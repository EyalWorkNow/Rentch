// Self-check for morning.mjs — run: `node lib/morning.selfcheck.mjs`
// Zero network: fetch is stubbed. Verifies token caching, auth header + 401
// retry, VAT-inclusive payment-form body, webhook HMAC (constant-time), parse.
import assert from 'node:assert';
import crypto from 'node:crypto';
import {
  getToken, setFetch, _resetTokenCache, createPaymentForm, chargeToken,
  verifyWebhook, parseWebhook,
} from './morning.mjs';

process.env.MORNING_API_KEY = 'test-id';
process.env.MORNING_API_SECRET = 'test-secret';
process.env.MORNING_WEBHOOK_SECRET = 'whsec_123';
process.env.MORNING_PLUGIN_ID = 'plugin-9';

const plan = { id: 'monthly', priceAgorot: 3500, months: 1, label: 'חודשי' };

function mockFetch(routes) {
  const calls = [];
  setFetch(async (url, opts = {}) => {
    calls.push({ url, opts, body: opts.body ? JSON.parse(opts.body) : null });
    for (const [frag, handler] of routes) {
      if (url.includes(frag)) return handler(url, opts);
    }
    throw new Error('no mock for ' + url);
  });
  return calls;
}
const ok = (obj) => ({ ok: true, status: 200, json: async () => obj, text: async () => JSON.stringify(obj) });

// ── getToken caches + only calls /account/token once ─────────────────────────
_resetTokenCache();
let tokenHits = 0;
mockFetch([['/account/token', () => { tokenHits++; return ok({ token: 'JWT-1' }); }]]);
const t1 = await getToken();
const t2 = await getToken();
assert.equal(t1, 'JWT-1');
assert.equal(t2, 'JWT-1');
assert.equal(tokenHits, 1, 'token cached — one auth call for two getToken()');

// ── concurrent cold-cache getToken → a single mint (in-flight de-dup) ─────────
_resetTokenCache();
let concurHits = 0;
mockFetch([['/account/token', async () => {
  concurHits++;
  await new Promise((r) => setTimeout(r, 5));
  return ok({ token: 'JWT-c' });
}]]);
const [ca, cb, cc] = await Promise.all([getToken(), getToken(), getToken()]);
assert.equal(ca, 'JWT-c'); assert.equal(cb, 'JWT-c'); assert.equal(cc, 'JWT-c');
assert.equal(concurHits, 1, 'concurrent cold getToken → one mint (in-flight de-dup)');

// ── createPaymentForm sends VAT-inclusive price + addToken + auth header ──────
_resetTokenCache();
let calls = mockFetch([
  ['/account/token', () => ok({ token: 'JWT-2' })],
  ['/payments/form', () => ok({ url: 'https://pay.example/abc' })],
]);
const form = await createPaymentForm({
  plan, clientName: 'דנה', clientEmail: 'd@x.com',
  successUrl: 'rently://ok', failureUrl: 'rently://no', notifyUrl: 'https://api/webhook',
  subscriptionId: 'sub_42',
});
assert.equal(form.url, 'https://pay.example/abc');
const formCall = calls.find((c) => c.url.includes('/payments/form'));
assert.equal(formCall.opts.headers.Authorization, 'Bearer JWT-2', 'bearer token attached');
assert.equal(formCall.body.amount, 35, 'amount is ₪35 (VAT-inclusive, verified field)');
assert.equal(formCall.body.addToken, true, 'requests a saved token');
assert.equal(formCall.body.custom, 'sub_42', 'round-trips our sub id');
assert.equal(formCall.body.income, undefined, 'NO income array (verified: amount-only, else 2417/2422)');

// ── 401 → refresh token → retry once ─────────────────────────────────────────
_resetTokenCache();
let formTries = 0;
calls = mockFetch([
  ['/account/token', () => ok({ token: 'JWT-fresh' })],
  ['/payments', () => {
    formTries++;
    if (formTries === 1) return { ok: false, status: 401, json: async () => ({}), text: async () => '{}' };
    return ok({ success: true, id: 'pay_1', documentId: 'doc_1' });
  }],
]);
const charge = await chargeToken({ plan, token: 'tok_x', clientName: 'דנה' });
assert.equal(charge.ok, true, 'charge succeeds after 401 retry');
assert.equal(charge.docId, 'doc_1');
assert.equal(formTries, 2, 'retried once after 401');

// ── a DECLINED charge that still carries a reference id is NOT a success ──────
_resetTokenCache();
mockFetch([
  ['/account/token', () => ok({ token: 'JWT-d' })],
  ['/payments', () => ok({ id: 'ref_9', status: 0, errorCode: 5, message: 'declined' })],
]);
const declined = await chargeToken({ plan, token: 'tok_bad', clientName: 'דנה' });
assert.equal(declined.ok, false, 'declined charge with an id must not false-positive');

// ── idempotency key is sent (body + header) so a re-charge is deduped ─────────
_resetTokenCache();
calls = mockFetch([
  ['/account/token', () => ok({ token: 'JWT-i' })],
  ['/payments', () => ok({ success: true, id: 'pay_i' })],
]);
await chargeToken({ plan, token: 'tok_i', idempotencyKey: 'uid7:2026-09-01' });
const chargeCall = calls.find((c) => c.url.includes('/payments'));
assert.equal(chargeCall.body.idempotencyKey, 'uid7:2026-09-01', 'idempotency key in body');
assert.equal(chargeCall.opts.headers['Idempotency-Key'], 'uid7:2026-09-01', 'idempotency key header');

// ── verifyWebhook: HMAC-SHA256 constant-time ─────────────────────────────────
const raw = JSON.stringify({ status: 1, custom: 'sub_42', token: 'tok_z' });
const good = crypto.createHmac('sha256', 'whsec_123').update(raw, 'utf8').digest('hex');
assert.equal(verifyWebhook({ 'x-morning-signature': good }, raw), true, 'valid signature accepted');
// REST API v1 delivers headers in Title-Case — must still verify.
assert.equal(verifyWebhook({ 'X-Morning-Signature': good }, raw), true, 'Title-Case header accepted');
assert.equal(verifyWebhook({ 'X-MORNING-SIGNATURE': good }, raw), true, 'upper header accepted');
assert.equal(verifyWebhook({ 'x-morning-signature': 'deadbeef' }, raw), false, 'bad signature rejected');
assert.equal(verifyWebhook({}, raw), false, 'missing signature rejected');
// fail-closed when no secret configured
const savedSecret = process.env.MORNING_WEBHOOK_SECRET;
delete process.env.MORNING_WEBHOOK_SECRET;
assert.equal(verifyWebhook({ 'x-morning-signature': good }, raw), false, 'no secret → fail closed');
process.env.MORNING_WEBHOOK_SECRET = savedSecret;

// ── parseWebhook normalises fields + binds plan via composite custom ─────────
const parsed = parseWebhook({ status: 1, custom: 'sub_42', token: 'tok_z', cardSuffix: '4242', cardBrand: 'visa', transactionId: 'tx9' });
assert.equal(parsed.subscriptionId, 'sub_42');
assert.equal(parsed.planId, null, 'legacy custom w/o :: → no plan');
assert.equal(parsed.success, true);
assert.equal(parsed.token, 'tok_z');
assert.equal(parsed.cardLast4, '4242');
assert.equal(parsed.transactionId, 'tx9');
// composite "<uid>::<plan>" binds the granted plan to the paid link
const comp = parseWebhook({ status: 1, custom: 'uid123::annual', transactionId: 'tx1', sum: 350 });
assert.equal(comp.subscriptionId, 'uid123');
assert.equal(comp.planId, 'annual');
assert.equal(comp.amountAgorot, 35000, 'charged ₪350 → 35000 agorot for cross-check');
const compM = parseWebhook({ status: 1, custom: 'uid9::monthly', amount: 35 });
assert.equal(compM.planId, 'monthly');
assert.equal(compM.amountAgorot, 3500);

console.log('morning.selfcheck: ALL PASS ✓');
