// rently-tour-notifier — scheduled (EventBridge, e.g. every 10 min) Lambda that
// detects when a property's Varjo Teleport 3D tour finishes processing and
// pushes "הסיור התלת-ממדי שלך מוכן" to the owner's devices via FCM.
//
// Why a poller: Teleport has no completion webhook and processing takes ~1–2h,
// by which time the app is closed — so a true push is the only way to reach the
// landlord. The router Lambda stores device tokens (POST /notifications/
// register-token); this Lambda reads them and calls FCM HTTP v1.
//
// Required env:
//   TABLE_PREFIX            (default "rently-")
//   TELEPORT_CLIENT_ID / TELEPORT_CLIENT_SECRET
//   TELEPORT_AUTH_URL       (default https://signin.teleport.varjo.com/oauth2/token)
//   TELEPORT_API_BASE       (default https://teleport.varjo.com)
//   FCM_SERVICE_ACCOUNT     (the Firebase service-account JSON, as a string)

import {
  DynamoDBClient,
} from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  ScanCommand,
  GetCommand,
  UpdateCommand,
} from '@aws-sdk/lib-dynamodb';
import crypto from 'node:crypto';

const REGION = process.env.AWS_REGION || 'us-east-1';
const TABLE_PREFIX = process.env.TABLE_PREFIX || 'rently-';
const PROPERTIES_TABLE = `${TABLE_PREFIX}properties`;
const DEVICE_TOKENS_TABLE = `${TABLE_PREFIX}device-tokens`;

const TELEPORT_AUTH_URL = process.env.TELEPORT_AUTH_URL
  || 'https://signin.teleport.varjo.com/oauth2/token';
const TELEPORT_API_BASE = process.env.TELEPORT_API_BASE
  || 'https://teleport.varjo.com';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

const PENDING_STATES = new Set(['processing', 'queued', 'uploading', 'captured']);
const READY_STATES = new Set(['READY', 'DONE', 'COMPLETE', 'COMPLETED']);

// ── Teleport auth + status ────────────────────────────────────────────────
let _teleportToken = null;
let _teleportTokenExp = 0;

async function teleportToken() {
  const now = Date.now();
  if (_teleportToken && now < _teleportTokenExp) return _teleportToken;
  const resp = await fetch(TELEPORT_AUTH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: process.env.TELEPORT_CLIENT_ID || '',
      client_secret: process.env.TELEPORT_CLIENT_SECRET || '',
    }),
  });
  if (!resp.ok) throw new Error(`Teleport auth failed: ${resp.status}`);
  const data = await resp.json();
  _teleportToken = data.access_token;
  _teleportTokenExp = now + 50 * 60 * 1000; // ~50 min
  return _teleportToken;
}

async function teleportCaptureState(eid) {
  const token = await teleportToken();
  const resp = await fetch(`${TELEPORT_API_BASE}/api/v1/captures`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!resp.ok) throw new Error(`Teleport list failed: ${resp.status}`);
  const list = await resp.json();
  const match = Array.isArray(list)
    ? list.find((c) => c.eid === eid || c.sid === eid)
    : null;
  if (!match) return null;
  return {
    state: (match.state || '').toUpperCase(),
    viewerUrl: match.viewer_url || '',
    previewUrl: match.preview_url || (match.preview_urls && match.preview_urls[0]) || '',
  };
}

// ── FCM HTTP v1 ───────────────────────────────────────────────────────────
let _fcmAccessToken = null;
let _fcmAccessExp = 0;

function serviceAccount() {
  const raw = process.env.FCM_SERVICE_ACCOUNT;
  if (!raw) throw new Error('FCM_SERVICE_ACCOUNT not set');
  return JSON.parse(raw);
}

function base64url(input) {
  return Buffer.from(input).toString('base64')
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

// Mint a Google OAuth2 access token from the service account (RS256 JWT grant).
async function fcmAccessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (_fcmAccessToken && now < _fcmAccessExp - 60) return _fcmAccessToken;

  const sa = serviceAccount();
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(`${header}.${claims}`);
  const signature = signer.sign(sa.private_key, 'base64')
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  const assertion = `${header}.${claims}.${signature}`;

  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!resp.ok) throw new Error(`FCM token failed: ${resp.status} ${await resp.text()}`);
  const data = await resp.json();
  _fcmAccessToken = data.access_token;
  _fcmAccessExp = now + (data.expires_in || 3600);
  return _fcmAccessToken;
}

async function sendFcm(token, title, bodyText, dataPayload) {
  const sa = serviceAccount();
  const accessToken = await fcmAccessToken();
  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body: bodyText },
          data: dataPayload || {},
          apns: { payload: { aps: { sound: 'default' } } },
          android: { priority: 'high' },
        },
      }),
    },
  );
  // 404 / UNREGISTERED → stale token; caller can prune. We just report.
  return { ok: resp.ok, status: resp.status };
}

async function tokensForUser(userId) {
  if (!userId) return [];
  try {
    const out = await ddb.send(new GetCommand({
      TableName: DEVICE_TOKENS_TABLE, Key: { userId },
    }));
    return (out.Item && Array.isArray(out.Item.tokens)) ? out.Item.tokens : [];
  } catch {
    return [];
  }
}

// ── Property scan ─────────────────────────────────────────────────────────
function tourOf(item) {
  const tour = item.virtualTour && typeof item.virtualTour === 'object'
    ? item.virtualTour
    : null;
  const status = (tour?.status || item.tourStatus || '').toString().toLowerCase();
  const eid = (tour?.id || item.tourEid || '').toString();
  const provider = (tour?.provider || 'teleport').toString();
  return { tour, status, eid, provider };
}

export const handler = async () => {
  let scanned = 0, ready = 0, notified = 0;

  let lastKey;
  do {
    const out = await ddb.send(new ScanCommand({
      TableName: PROPERTIES_TABLE,
      ExclusiveStartKey: lastKey,
    }));
    lastKey = out.LastEvaluatedKey;

    for (const item of out.Items || []) {
      const { status, eid, provider } = tourOf(item);
      if (provider !== 'teleport') continue;
      if (!eid || item.tourNotified === true) continue;
      if (!PENDING_STATES.has(status)) continue;
      scanned++;

      let state;
      try {
        state = await teleportCaptureState(eid);
      } catch (e) {
        console.error(`teleport status ${eid}:`, e.message);
        continue;
      }
      if (!state || !READY_STATES.has(state.state)) continue;
      ready++;

      // Mark the property ready + notified so we never push twice.
      try {
        await ddb.send(new UpdateCommand({
          TableName: PROPERTIES_TABLE,
          Key: { id: item.id },
          UpdateExpression:
            'SET tourStatus = :s, tourViewerUrl = :v, tourNotified = :n',
          ExpressionAttributeValues: {
            ':s': 'ready',
            ':v': state.viewerUrl || '',
            ':n': true,
          },
        }));
      } catch (e) {
        console.error(`update property ${item.id}:`, e.message);
      }

      const tokens = await tokensForUser(item.ownerUserId);
      if (tokens.length === 0) continue;
      const title = 'הסיור התלת-ממדי מוכן! 🏠';
      const bodyText = `הסיור הווירטואלי של "${item.title || item.city || 'הנכס שלך'}" מוכן לצפייה.`;
      for (const t of tokens) {
        try {
          const r = await sendFcm(t, title, bodyText, {
            type: 'tour_ready',
            propertyId: (item.id || '').toString(),
            viewerUrl: state.viewerUrl || '',
          });
          if (r.ok) notified++;
        } catch (e) {
          console.error('fcm send:', e.message);
        }
      }
    }
  } while (lastKey);

  console.log(`tour-notifier: scanned=${scanned} ready=${ready} notified=${notified}`);
  return { scanned, ready, notified };
};
