// Authorization + chat-privacy regression suite for the Rentch API router.
//
// Drives the REAL aws/lambda/router/index.mjs handler with a fake DynamoDB
// (installed on globalThis.__ddb) so the actual production authz code runs — no
// AWS account, no SDK install. Run from the aws/ directory:
//
//     node --test test/
//
// These tests lock in the guarantees added when the IDOR + chat-eavesdropping
// holes were closed: every write is stamped with the caller's verified uid, only
// owners may delete owned rows, and message threads are readable only by their
// two parties.
// Register the AWS-SDK stub loader before importing the router so its
// @aws-sdk/* imports resolve to stubs. Runs in-process (the "test" script names
// this file explicitly), so this register() completes before the dynamic import.
import { register } from 'node:module';
register('../test-loader.mjs', import.meta.url);

import test from 'node:test';
import assert from 'node:assert/strict';

const { handler } = await import('../lambda/router/index.mjs');

// ── Test doubles ──────────────────────────────────────────────────────────────

// Installs a fake DynamoDB that records every command and serves the given rows
// (by table-agnostic id) and messages (by matchId). Returns the call log.
function installDdb({ rows = {}, messages = {} } = {}) {
  const calls = [];
  globalThis.__ddb = {
    send(cmd) {
      const type = cmd.constructor.name;
      calls.push({ type, input: cmd.input });
      switch (type) {
        case 'GetCommand':
          return Promise.resolve({ Item: rows[cmd.input.Key.id] });
        case 'PutCommand':
        case 'DeleteCommand':
          return Promise.resolve({});
        case 'QueryCommand': {
          const v = cmd.input.ExpressionAttributeValues || {};
          const matchId = v[':m'] ?? v[':v'];
          return Promise.resolve({ Items: messages[matchId] ?? [] });
        }
        case 'ScanCommand':
          return Promise.resolve({ Items: [] });
        default:
          return Promise.resolve({});
      }
    },
  };
  return calls;
}

// Builds an API-Gateway-proxy event. `uid` becomes the authorizer-verified id.
function event({ method, path, uid = null, body = null, query = null }) {
  return {
    httpMethod: method,
    path,
    body: body ? JSON.stringify(body) : null,
    queryStringParameters: query,
    requestContext: { authorizer: uid ? { uid } : {} },
  };
}

const lastOf = (calls, type) => [...calls].reverse().find((c) => c.type === type);
const bodyOf = (res) => JSON.parse(res.body);

// ── Ownership / IDOR ─────────────────────────────────────────────────────────

test('PUT property stamps ownerUserId with the caller uid, ignoring a forged value', async () => {
  const calls = installDdb();
  const res = await handler(event({
    method: 'PUT', path: '/properties/p1', uid: 'alice',
    body: { ownerUserId: 'mallory', price: 5000 },
  }));
  assert.equal(res.statusCode, 200);
  assert.equal(lastOf(calls, 'PutCommand').input.Item.ownerUserId, 'alice');
});

test('DELETE on a property owned by someone else is rejected with 403 and performs no delete', async () => {
  const calls = installDdb({ rows: { p2: { id: 'p2', ownerUserId: 'bob' } } });
  const res = await handler(event({ method: 'DELETE', path: '/properties/p2', uid: 'alice' }));
  assert.equal(res.statusCode, 403);
  assert.equal(lastOf(calls, 'DeleteCommand'), undefined);
});

test('DELETE on a property the caller owns succeeds and deletes the correct id', async () => {
  const calls = installDdb({ rows: { p3: { id: 'p3', ownerUserId: 'alice' } } });
  const res = await handler(event({ method: 'DELETE', path: '/properties/p3', uid: 'alice' }));
  assert.equal(res.statusCode, 200);
  assert.equal(lastOf(calls, 'DeleteCommand').input.Key.id, 'p3');
});

test("DELETE on another user's profile is rejected with 403", async () => {
  installDdb();
  const res = await handler(event({ method: 'DELETE', path: '/users/bob', uid: 'alice' }));
  assert.equal(res.statusCode, 403);
});

test("PUT to another user's id writes the row under the caller's uid, never the target", async () => {
  const calls = installDdb();
  const res = await handler(event({
    method: 'PUT', path: '/users/bob', uid: 'alice', body: { id: 'bob', name: 'spoof' },
  }));
  assert.equal(res.statusCode, 200);
  assert.equal(lastOf(calls, 'PutCommand').input.Item.id, 'alice');
});

test('POST message stamps senderId with the caller uid, ignoring a forged sender', async () => {
  const calls = installDdb();
  const res = await handler(event({
    method: 'POST', path: '/messages', uid: 'alice',
    body: { id: 'm1', matchId: 'match-pX~alice', senderId: 'bob', text: 'hi' },
  }));
  assert.equal(res.statusCode, 200);
  assert.equal(lastOf(calls, 'PutCommand').input.Item.senderId, 'alice');
});

test('a mutation on an owner-scoped table without a verified uid is rejected with 401', async () => {
  installDdb();
  const res = await handler(event({ method: 'PUT', path: '/properties/p9', uid: null, body: { price: 1 } }));
  assert.equal(res.statusCode, 401);
});

test('public catalog reads stay open (no uid required)', async () => {
  installDdb();
  const res = await handler(event({ method: 'GET', path: '/properties', query: { status: 'active' } }));
  assert.equal(res.statusCode, 200);
});

test('a presign request with a path-traversal key is rejected with 400', async () => {
  installDdb();
  const res = await handler(event({
    method: 'POST', path: '/storage/presign', uid: 'alice',
    body: { key: '../../etc/passwd', contentType: 'image/png' },
  }));
  assert.equal(res.statusCode, 400);
});

// ── Chat membership (GET /messages) ──────────────────────────────────────────

const THREAD = {
  rows: { pX: { id: 'pX', ownerUserId: 'landlord' } },
  messages: {
    'match-pX': [{ id: 'm0', matchId: 'match-pX', senderId: 'tenant', text: 'legacy' }],
    'match-pX~tenant': [{ id: 'm1', matchId: 'match-pX~tenant', senderId: 'tenant', text: 'hi' }],
  },
};

test('GET /messages requires a matchId (400 when missing)', async () => {
  installDdb(THREAD);
  const res = await handler(event({ method: 'GET', path: '/messages', uid: 'landlord', query: {} }));
  assert.equal(res.statusCode, 400);
});

test('new-format thread: the embedded tenant can read their own thread', async () => {
  installDdb(THREAD);
  const res = await handler(event({ method: 'GET', path: '/messages', uid: 'tenant', query: { matchId: 'match-pX~tenant' } }));
  assert.equal(res.statusCode, 200);
  assert.equal(bodyOf(res).items.length, 1);
});

test('new-format thread: the property owner (landlord) can read the thread', async () => {
  installDdb(THREAD);
  const res = await handler(event({ method: 'GET', path: '/messages', uid: 'landlord', query: { matchId: 'match-pX~tenant' } }));
  assert.equal(res.statusCode, 200);
  assert.equal(bodyOf(res).items.length, 1);
});

test('new-format thread: a different tenant CANNOT read another tenant thread (returns empty, not data)', async () => {
  installDdb(THREAD);
  const res = await handler(event({ method: 'GET', path: '/messages', uid: 'tenant2', query: { matchId: 'match-pX~tenant' } }));
  assert.equal(res.statusCode, 200);
  assert.equal(bodyOf(res).items.length, 0);
});

test('legacy thread (no ~): owner and a prior poster are members; an outsider is blocked', async () => {
  installDdb(THREAD);
  const owner = await handler(event({ method: 'GET', path: '/messages', uid: 'landlord', query: { matchId: 'match-pX' } }));
  const poster = await handler(event({ method: 'GET', path: '/messages', uid: 'tenant', query: { matchId: 'match-pX' } }));
  const outsider = await handler(event({ method: 'GET', path: '/messages', uid: 'stranger', query: { matchId: 'match-pX' } }));
  assert.equal(bodyOf(owner).items.length, 1, 'owner sees legacy thread');
  assert.equal(bodyOf(poster).items.length, 1, 'prior poster sees legacy thread');
  assert.equal(bodyOf(outsider).items.length, 0, 'outsider is blocked');
});
