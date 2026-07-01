// Rently API router — single Lambda handling all REST routes.
//
// Routes (see docs/AWS_BACKEND_CONTRACT.md):
//   GET    /{table}            list (with query filters)
//   GET    /{table}/{id}       get one
//   POST   /{table}            create
//   PUT    /{table}/{id}       upsert
//   DELETE /{table}/{id}       delete
//   POST   /storage/presign    → { uploadUrl, publicUrl }
//   DELETE /storage/{key+}     delete S3 object
//   POST   /3d/viewers         → create hosted viewer HTML for uploaded 3D assets
//
// Uses the AWS SDK v3 bundled in the Node.js 20 Lambda runtime (no node_modules).

import {
  DynamoDBClient,
} from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
  QueryCommand,
  ScanCommand,
} from '@aws-sdk/lib-dynamodb';
import { S3Client, DeleteObjectCommand, PutObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';
// Pure-JS zip reader (bundled in node_modules) — KIRI returns the finished model
// as a single ZIP, so we unzip it in-process to extract the .glb mesh / .ply splat.
import AdmZip from 'adm-zip';
// Node built-ins only — used to mint a Google OAuth token from the Firebase
// service account (sign a JWT with RS256) and to load that account off disk.
import crypto from 'node:crypto';
import { readFileSync } from 'node:fs';
import {
  rankWeightsFor, cohortPriceTarget, priceFitScore, neighborhoodFitScore,
} from './lib/ranking.mjs';

// ── Connectors (owned by the Connectors agent — we only IMPORT from them) ─────
// These modules live in ./lib and expose the Israeli-data spine used to enrich a
// listing on create: GovMap geocode (→ lat/lng + gush/helka), nadlan+CBS price
// badge (מעל/מתחת לשוק) and the neighbourhood score. They may not exist yet at
// deploy time, so we load them LAZILY via dynamic import wrapped in try/catch —
// a static top-level import of a missing file would crash the whole Lambda. Once
// the Connectors agent's files land in ./lib the calls below resolve for real;
// until then every enrichment step degrades to a no-op (fail-soft).
//   ./lib/govmap.mjs       → geocode(addressHe) -> { lat, lng, gush, helka }
//   ./lib/nadlan_cbs.mjs   → priceBadge({lat,lng,rooms,area,price}) -> { medianPpm, deltaPct, badge }
//   ./lib/neighborhood.mjs → neighborhoodScore({lat,lng}) -> { score, sub }
let _connectors = null;
async function connectors() {
  if (_connectors) return _connectors;
  const mod = {};
  // Loaded independently so one missing/broken module doesn't disable the others.
  try { mod.geocode = (await import('./lib/govmap.mjs')).geocode; }
  catch (e) { console.warn('connectors: govmap unavailable:', e.message); }
  try { mod.priceBadge = (await import('./lib/nadlan_cbs.mjs')).priceBadge; }
  catch (e) { console.warn('connectors: nadlan_cbs unavailable:', e.message); }
  try { mod.neighborhoodScore = (await import('./lib/neighborhood.mjs')).neighborhoodScore; }
  catch (e) { console.warn('connectors: neighborhood unavailable:', e.message); }
  _connectors = mod;
  return mod;
}

const REGION = process.env.AWS_REGION;
const S3_BUCKET = process.env.S3_BUCKET;
// Python OpenCV stitcher Lambda (container image) — invoked async to build a
// horizontal 360° panorama from the frames the user swept on the phone.
const PANO_STITCH_FN = process.env.PANO_STITCH_FN || '';
const lambda = new LambdaClient({ region: REGION });
const TABLE_PREFIX = process.env.TABLE_PREFIX || 'rently-';
const LUMA_API_KEY = process.env.LUMA_API_KEY || '';
// Luma Agents image API (uni-1) — virtual staging via image_edit.
const LUMA_BASE = 'https://agents.lumalabs.ai/v1';

// "Erik" — the voice/text personal assistant (Gemini). Key stays server-side
// ONLY; the client never sees it. Stateless: the conversation is passed in on
// every request and nothing about the user is stored server-side.
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || '';
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-2.5-flash';
// Fallback chain — a free-tier model is frequently overloaded (429/503). If the
// primary is busy we try the next one so the assistant keeps answering instead
// of telling the user "the server is busy".
// Order = fastest-first for low latency, then capable fallbacks for availability.
const GEMINI_MODELS = (process.env.GEMINI_MODELS
  || 'gemini-2.5-flash-lite,gemini-2.0-flash,gemini-2.5-flash,gemini-flash-latest')
  .split(',').map((s) => s.trim()).filter(Boolean);

// Gemini Live (real-time bidirectional audio). The client never gets the API
// key — the backend mints a short-lived ephemeral token, locked to Erik's model,
// persona and create_property tool, and the client connects directly to the
// Gemini Live WebSocket with that token. Falls back to GEMINI_API_KEY if a
// dedicated Live key isn't configured.
const GEMINI_LIVE_API_KEY = process.env.GEMINI_LIVE_API_KEY || GEMINI_API_KEY;
const GEMINI_LIVE_MODEL =
  process.env.GEMINI_LIVE_MODEL || 'models/gemini-2.5-flash-native-audio-latest';

// ── Listing embeddings (בינוני tier — DORMANT until provisioned) ──────────────
// Off by default. Flip ENABLE_EMBEDDINGS=1 only once a Gemini Embedding 2 quota
// AND an S3 Vectors index exist. While off, enrichListingOnCreate skips the embed
// step entirely, so this code ships completely inert (zero extra calls/cost).
// Set GEMINI_EMBED_MODEL to the Gemini Embedding 2 model id when provisioning.
const EMBEDDINGS_ENABLED = process.env.ENABLE_EMBEDDINGS === '1';
const GEMINI_EMBED_MODEL = process.env.GEMINI_EMBED_MODEL || 'gemini-embedding-001';
const EMBED_DIM = Number(process.env.EMBED_DIM) || 768;
// Step 3 stores the embedding directly on the property record and computes
// cosine similarity in-memory at search time — no external vector DB.

// Varjo Teleport — builds an interactive Gaussian-splat 3D walkthrough of an
// apartment from an mp4 (or zip of images). The client_secret stays server-side
// ONLY; the backend mints a short-lived token and hands the client just the
// presigned S3 upload URLs (so big videos upload straight to storage).
const TELEPORT_CLIENT_ID = process.env.TELEPORT_CLIENT_ID || '';
const TELEPORT_CLIENT_SECRET = process.env.TELEPORT_CLIENT_SECRET || '';
const TELEPORT_AUTH_URL = process.env.TELEPORT_AUTH_URL
  || 'https://signin.teleport.varjo.com/oauth2/token';
const TELEPORT_API_BASE = process.env.TELEPORT_API_BASE
  || 'https://teleport.varjo.com';

// KIRI Engine — textured photogrammetry mesh (Photo Scan) + 3D Gaussian
// Splatting (3DGS). The Bearer API key stays server-side ONLY: the client
// uploads its capture frames/video to S3 via presigned PUTs, then the backend
// streams those bytes to KIRI as multipart/form-data. We never hand the key out.
const KIRI_API_KEY = process.env.KIRI_API_KEY || '';
const KIRI_API_BASE = process.env.KIRI_API_BASE
  || 'https://api.kiriengine.app/api/v1/open';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});
const s3 = new S3Client({ region: REGION });

// Path segment → DynamoDB table name. Also defines the partition-key attribute
// and an optional GSI used for list queries.
const TABLES = {
  properties:      { name: `${TABLE_PREFIX}properties`,      gsi: { name: 'status-createdAt',     pk: 'status',         filterKey: 'status' }, ownerIndex: 'ownerUserId-createdAt' },
  messages:        { name: `${TABLE_PREFIX}messages`,        gsi: { name: 'matchId-createdAt',    pk: 'matchId',        filterKey: 'matchId' } },
  users:           { name: `${TABLE_PREFIX}users`,           gsi: { name: 'discoverable-updatedAt', pk: 'discoverable', filterKey: 'discoverable' } },
  // Behavioral events — query-able for research by userId (a user's full event
  // stream) via the userId-createdAt GSI, and by eventType (e.g. all swipeRight)
  // via the eventType-createdAt GSI. The default `gsi` (userId) backs
  // GET /events?userId=<uid>; eventType is exposed as an extra index below.
  events:          { name: `${TABLE_PREFIX}events`,          gsi: { name: 'userId-createdAt', pk: 'userId', filterKey: 'userId' }, indexes: { eventType: { name: 'eventType-createdAt', pk: 'eventType', filterKey: 'eventType' } } },
  reports:         { name: `${TABLE_PREFIX}reports`,         gsi: null },
  blocks:          { name: `${TABLE_PREFIX}blocks`,          gsi: null },
  reviews:         { name: `${TABLE_PREFIX}reviews`,         gsi: { name: 'targetKey-createdAt', pk: 'targetKey', filterKey: 'targetKey' } },
  property_views:  { name: `${TABLE_PREFIX}property-views`,  gsi: { name: 'propertyId-index', pk: 'propertyId', filterKey: 'propertyId' } },
  property_likes:  { name: `${TABLE_PREFIX}property-likes`,  gsi: { name: 'propertyId-index', pk: 'propertyId', filterKey: 'propertyId' } },
  app_state:       { name: `${TABLE_PREFIX}app-state`,       gsi: null },
};

// One row per user (pk: userId) holding the set of their FCM device tokens, so
// the scheduled tour-notifier Lambda can push "your 3D tour is ready" to every
// device a landlord owns. Created out-of-band (see deploy checklist).
const DEVICE_TOKENS_TABLE = `${TABLE_PREFIX}device-tokens`;

// Notification inbox — one row per delivered notification, keyed by
// userId (pk) + createdAt (sk, ms-epoch Number, newest = largest). Stores the
// same {title, body, data} that was pushed so the app can render an in-app
// inbox and an unread badge even if the device push was dropped. Created
// out-of-band (aws dynamodb create-table, on-demand). pk=userId(S) sk=createdAt(N).
const NOTIFICATIONS_TABLE = `${TABLE_PREFIX}notifications`;

// Company-broadcast history — one row per admin broadcast, keyed by id (S, a
// uuid). Stores the rich notification that was fanned out to every device plus
// the delivery tallies, so the admin console can render a "sent history" feed.
// Created out-of-band / by the deploy script (aws dynamodb create-table,
// on-demand). pk=id(S). Sorting newest-first is done in-Lambda after a SCAN.
const BROADCASTS_TABLE = `${TABLE_PREFIX}broadcasts`;

// Per-impression search-ranking log — the training set for the phase-2 LightGBM
// lambdarank ranker. One row per (search, listing) impression: the feature
// vector our transparent linear scorer saw + the outcome (click/like/none).
// pk=id(S, uuid). GSI userId-createdAt for per-user replay. PAY_PER_REQUEST,
// created out-of-band (aws dynamodb create-table). Append-only, never read on the
// hot path.
const SEARCH_LOG_TABLE = `${TABLE_PREFIX}search-log`;

// Tenant saved searches (server-side mirror of the on-device list). The client
// syncs each SavedSearch here so a NEW listing can be matched against every
// tenant's criteria the instant it's published — and fire an FCM alert with no
// polling. pk=userId(S) sk=id(S). Same field set as lib/data/models/saved_search
// (city, min/maxBudget, min/maxRooms, transactionType, requiredTags, alertsOn).
const SAVED_SEARCHES_TABLE = `${TABLE_PREFIX}saved-searches`;

// Admin gate. The API-Gateway authorizer (aws/lambda/authorizer/index.mjs)
// verifies the Firebase JWT but only forwards `uid` in its context — it does
// NOT pass the token's custom claims (e.g. notifAdmin) downstream. So we cannot
// read a notifAdmin claim from the event; instead we gate the admin broadcast
// routes by the known admin uid (notifi@notifi.com). See callerIsNotifAdmin().
const NOTIF_ADMIN_UID = process.env.NOTIF_ADMIN_UID
  || 'dR46Nv6L3mN1cyzXwxrubHpdqZi2';

// ── Firebase Cloud Messaging (HTTP v1) — SENDING ─────────────────────────────
// Push delivery using ONLY Node built-ins: we mint a Google OAuth access token
// by signing a JWT with the service account's RSA private key, cache it in
// module scope, and POST messages to the FCM v1 endpoint. Dead/unregistered
// tokens are pruned from the owning user's row. Everything fails soft: if the
// service account is missing or a send errors, the main request is never broken.
const FCM_PROJECT_ID = 'mydatingapp-4c043';
const FCM_SEND_URL = `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`;
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

// Load the service account JSON once (next to this file, bundled in the deploy
// zip). Absent/garbage → fcmSA stays null and all sends become no-ops.
let fcmSA = null;
try {
  fcmSA = JSON.parse(readFileSync(new URL('./fcm-service-account.json', import.meta.url), 'utf8'));
  if (!fcmSA.client_email || !fcmSA.private_key) {
    console.warn('FCM: service account JSON missing client_email/private_key — push disabled');
    fcmSA = null;
  }
} catch (e) {
  console.warn('FCM: no service account JSON — push disabled:', e.message);
  fcmSA = null;
}

// Cached OAuth token { value, exp(ms epoch) } and an in-flight promise so that
// concurrent sends don't each mint their own token.
let _fcmToken = null;
let _fcmTokenInflight = null;

const b64url = (buf) => Buffer.from(buf)
  .toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

// Mint (or reuse) a Google OAuth access token for FCM. Cached until ~5 min
// before expiry. Returns null if the service account is unavailable or the
// token exchange fails (caller treats null as "push disabled").
async function fcmAccessToken() {
  if (!fcmSA) return null;
  const now = Date.now();
  if (_fcmToken && _fcmToken.exp - 5 * 60 * 1000 > now) return _fcmToken.value;
  if (_fcmTokenInflight) return _fcmTokenInflight;

  _fcmTokenInflight = (async () => {
    try {
      const iat = Math.floor(Date.now() / 1000);
      const exp = iat + 3600;
      const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
      const claims = b64url(JSON.stringify({
        iss: fcmSA.client_email,
        scope: FCM_SCOPE,
        aud: GOOGLE_TOKEN_URL,
        iat,
        exp,
      }));
      const signingInput = `${header}.${claims}`;
      const signer = crypto.createSign('RSA-SHA256');
      signer.update(signingInput);
      signer.end();
      const signature = b64url(signer.sign(fcmSA.private_key));
      const assertion = `${signingInput}.${signature}`;

      const resp = await fetch(GOOGLE_TOKEN_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          assertion,
        }).toString(),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok || !data.access_token) {
        console.warn('FCM: token exchange failed', resp.status, JSON.stringify(data).slice(0, 300));
        return null;
      }
      const ttlMs = (Number(data.expires_in) || 3600) * 1000;
      _fcmToken = { value: data.access_token, exp: Date.now() + ttlMs };
      return _fcmToken.value;
    } catch (e) {
      console.warn('FCM: token exchange exception:', e.message);
      return null;
    } finally {
      _fcmTokenInflight = null;
    }
  })();
  return _fcmTokenInflight;
}

// Read a user's stored FCM device tokens (empty array on any miss).
async function getUserTokens(userId) {
  if (!userId) return [];
  try {
    const r = await ddb.send(new GetCommand({
      TableName: DEVICE_TOKENS_TABLE, Key: { userId },
    }));
    return (r.Item && Array.isArray(r.Item.tokens)) ? r.Item.tokens : [];
  } catch { return []; }
}

// Remove dead tokens from a user's row (best-effort; never throws).
async function pruneUserTokens(userId, deadSet) {
  if (!deadSet || deadSet.size === 0) return;
  try {
    const current = await getUserTokens(userId);
    const kept = current.filter((t) => !deadSet.has(t));
    if (kept.length === current.length) return;
    await ddb.send(new PutCommand({
      TableName: DEVICE_TOKENS_TABLE,
      Item: { userId, tokens: kept, updatedAt: new Date().toISOString() },
    }));
  } catch (e) {
    console.warn('FCM: prune failed for', userId, e.message);
  }
}

// Send a push to every device a user owns. notification = {title, body, data?}.
// `data` values are coerced to strings (FCM v1 requires string-only data maps).
// Prunes UNREGISTERED / invalid tokens. Returns the count that were accepted.
// Fully fail-soft: returns 0 rather than throwing.
async function sendPushToUser(userId, { title, body, data } = {}) {
  try {
    const token = await fcmAccessToken();
    if (!token) return 0;
    const tokens = await getUserTokens(userId);
    if (tokens.length === 0) return 0;

    const dataStr = {};
    if (data && typeof data === 'object') {
      for (const [k, v] of Object.entries(data)) {
        if (v === undefined || v === null) continue;
        dataStr[k] = typeof v === 'string' ? v : String(v);
      }
    }

    const dead = new Set();
    const results = await Promise.all(tokens.map(async (deviceToken) => {
      try {
        const message = {
          token: deviceToken,
          notification: { title: title || '', body: body || '' },
          data: dataStr,
          apns: { payload: { aps: { sound: 'default' } } },
          android: { priority: 'high' },
        };
        const resp = await fetch(FCM_SEND_URL, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ message }),
        });
        if (resp.ok) return true;

        const errBody = await resp.json().catch(() => ({}));
        const status = errBody?.error?.status || '';
        const fcmErr = errBody?.error?.details?.find?.(
          (d) => d['@type']?.includes('FcmError'))?.errorCode || '';
        // Dead token → prune it so we stop trying. 404 UNREGISTERED, or a 400
        // that flags the registration token itself as invalid.
        const isDead = resp.status === 404
          || status === 'UNREGISTERED' || status === 'NOT_FOUND'
          || fcmErr === 'UNREGISTERED' || fcmErr === 'INVALID_ARGUMENT'
          || (resp.status === 400 && /registration token|not a valid fcm/i
            .test(JSON.stringify(errBody)));
        if (isDead) dead.add(deviceToken);
        else {
          console.warn('FCM: send failed', resp.status,
            JSON.stringify(errBody).slice(0, 200));
        }
        return false;
      } catch (e) {
        console.warn('FCM: send exception:', e.message);
        return false;
      }
    }));

    if (dead.size > 0) await pruneUserTokens(userId, dead);
    return results.filter(Boolean).length;
  } catch (e) {
    console.warn('FCM: sendPushToUser failed:', e.message);
    return 0;
  }
}

// ── Notification inbox + unified delivery ────────────────────────────────────
// notify() is the ONE entry point every real notification goes through. It does
// two things, in order, and is fully fail-soft (never throws, never blocks the
// request that triggered it):
//   1. PERSIST a row in the notifications table so the app can show an inbox and
//      an unread badge — keyed by userId (pk) + createdAt (sk, ms-epoch), with
//      read:false. The row id (a uuid) is what mark-read targets.
//   2. PUSH the same title/body/data to all of that user's devices via FCM.
// `data` is the structured payload the app routes on (type, propertyId, …); the
// notification's own `type`/`id` are merged into it so a tapped push and an
// inbox row resolve to the exact same destination.
async function notify(userId, type, title, body, data = {}) {
  if (!userId) return;
  const createdAt = Date.now();
  const id = crypto.randomUUID();
  const payload = { ...data, type, notificationId: id };
  try {
    await ddb.send(new PutCommand({
      TableName: NOTIFICATIONS_TABLE,
      Item: {
        userId,
        createdAt,            // sk: ms-epoch Number, newest = largest
        id,
        type,
        title: title || '',
        body: body || '',
        data: payload,
        read: false,
      },
    }));
  } catch (e) {
    console.warn('notify: persist failed:', e.message);
  }
  try {
    await sendPushToUser(userId, { title, body, data: payload });
  } catch (e) {
    console.warn('notify: push failed:', e.message);
  }
}

// Translate a successful table write into the right push (Hebrew copy). Called
// fire-and-forget from the POST handler; fully fail-soft. Routed through
// notify() so every event is BOTH stored in the inbox AND pushed. Triggers:
//   • property_likes → a tenant liked a landlord's property (a new lead, not yet
//                      a mutual match) → push the property owner (landlord).
//   • messages       → a NEW CHAT MESSAGE → push the other party in the thread.
//   • reviews        → a NEW REVIEW → push the reviewee (or the property owner).
async function firePushForWrite(tableKey, body, senderUid) {
  try {
    if (tableKey === 'property_likes') {
      const propertyId = body.propertyId;
      if (!propertyId) return;
      let ownerUid = null;
      let propTitle = '';
      try {
        const prop = await ddb.send(new GetCommand({
          TableName: TABLES.properties.name, Key: { id: propertyId },
        }));
        ownerUid = prop.Item && prop.Item.ownerUserId;
        propTitle = (prop.Item && (prop.Item.street || prop.Item.city)) || '';
      } catch { /* ignore */ }
      if (!ownerUid || ownerUid === senderUid) return;
      const who = body.tenantName || 'מתעניין חדש';
      await notify(
        ownerUid,
        'property_like',
        'מתעניין חדש בנכס שלך 👀',
        propTitle ? `${who} התעניין/ה בדירה שלך ב${propTitle}`
          : `${who} התעניין/ה בדירה שלך`,
        { propertyId: String(propertyId) },
      );
      return;
    }

    if (tableKey === 'messages') {
      const matchId = body.matchId;
      if (!matchId) return;
      const recipient = await otherPartyOf(matchId, senderUid);
      if (!recipient || recipient === senderUid) return;
      const text = (body.text || body.body || '').toString();
      const preview = text.length > 80 ? `${text.slice(0, 79)}…` : (text || 'הודעה חדשה');
      await notify(
        recipient,
        'message',
        'הודעה חדשה 💬',
        preview,
        { matchId: String(matchId) },
      );
      return;
    }

    if (tableKey === 'reviews') {
      // A new review was written. Notify the reviewee — explicit revieweeUserId
      // if the client set one, otherwise (for a property review) the property's
      // owner (landlord). Never notify the author of their own review.
      let target = (body.revieweeUserId || '').toString();
      const propertyId = (body.propertyId || body.targetId || '').toString();
      if (!target && (body.targetType === 'property') && propertyId) {
        try {
          const prop = await ddb.send(new GetCommand({
            TableName: TABLES.properties.name, Key: { id: propertyId },
          }));
          target = (prop.Item && prop.Item.ownerUserId) || '';
        } catch { /* ignore */ }
      }
      if (!target || target === senderUid) return;
      const stars = Math.max(0, Math.min(5, Number(body.rating) || 0));
      const author = body.authorName || 'משתמש Rently';
      await notify(
        target,
        'review',
        'קיבלת ביקורת חדשה ⭐',
        stars ? `${author} השאיר/ה לך ביקורת (${stars}/5)`
          : `${author} השאיר/ה לך ביקורת`,
        { propertyId, rating: String(stars) },
      );
      return;
    }
  } catch (e) {
    console.warn('FCM: firePushForWrite failed:', e.message);
  }
}

// ── New-listing enrichment pipeline ──────────────────────────────────────────
// Runs once, synchronously, on a genuine listing INSERT. MUTATES `body` in place
// so the enriched fields are persisted by the very next putItem. Every step is
// independently fail-soft: a slow/broken Gemini call or a missing Connectors
// module degrades to "field simply absent", never an error to the client.
//   1. smartTags  — one cheap Gemini call over title+description(+image URLs).
//   2. geocode    — GovMap address → lat/lng + gush/helka.
//   3. priceBadge — nadlan comps + CBS trend → מעל/מתחת לשוק.
//   4. nbhdScore  — data.gov.il + OSM neighbourhood score.
async function enrichListingOnCreate(body) {
  // 1) Smart tags — independent, so do it in parallel with the geo chain.
  const tasks = [];
  tasks.push((async () => {
    try {
      const tags = await extractSmartTags(body);
      if (tags && tags.length) body.smartTags = tags;
    } catch (e) { console.warn('enrich: smartTags failed:', e.message); }
    // Embedding piggybacks on the same enrichment window (runs after tags so
    // they're in the embed text). Dormant unless ENABLE_EMBEDDINGS=1, and
    // fail-soft — a missing embedding never blocks the publish.
    if (EMBEDDINGS_ENABLED) {
      try {
        const vec = await geminiEmbed(listingEmbedText(body));
        if (vec) {
          // Stored directly on the record — this IS the vector store; search
          // reads it back and scores cosine in-memory (no external vector DB).
          body.embedding = vec;
          body.embeddingDim = EMBED_DIM;
          body.embeddingModel = GEMINI_EMBED_MODEL;
        }
      } catch (e) { console.warn('enrich: embedding failed:', e.message); }
    }
  })());

  // 2→4) Geo chain: geocode first (lat/lng feed the other two), then price badge
  // + neighbourhood score in parallel. Uses the lazily-loaded Connectors.
  tasks.push((async () => {
    let lat = typeof body.lat === 'number' ? body.lat : undefined;
    let lng = typeof body.lng === 'number' ? body.lng
      : (typeof body.lon === 'number' ? body.lon : undefined);
    try {
      const c = await connectors();
      if (c.geocode && (lat === undefined || lng === undefined)) {
        const addr = [body.street, body.streetNumber, body.city]
          .filter(Boolean).join(' ').trim();
        if (addr) {
          const g = await c.geocode(addr);
          if (g) {
            if (typeof g.lat === 'number') { lat = g.lat; body.lat = g.lat; }
            // The model stores longitude as `lon`; mirror to `lng` too so both
            // the client field and the connector convention are populated.
            if (typeof g.lng === 'number') { lng = g.lng; body.lon = g.lng; body.lng = g.lng; }
            if (g.gush) body.gush = String(g.gush);
            if (g.helka) body.helka = String(g.helka);
          }
        }
      }
    } catch (e) { console.warn('enrich: geocode failed:', e.message); }

    if (lat === undefined || lng === undefined) return; // no coords → skip geo-derived
    const c = await connectors().catch(() => ({}));
    await Promise.all([
      (async () => {
        try {
          if (!c.priceBadge) return;
          const badge = await c.priceBadge({
            lat, lng,
            rooms: Number(body.rooms) || undefined,
            area: Number(body.sizeM2) || undefined,
            price: Number(body.price) || undefined,
          });
          if (badge) body.priceBadge = badge; // { medianPpm, deltaPct, badge }
        } catch (e) { console.warn('enrich: priceBadge failed:', e.message); }
      })(),
      (async () => {
        try {
          if (!c.neighborhoodScore) return;
          const ns = await c.neighborhoodScore({ lat, lng, locality: body.city });
          if (ns) body.neighborhoodScore = ns; // { score, sub }
        } catch (e) { console.warn('enrich: neighborhoodScore failed:', e.message); }
      })(),
    ]);
  })());

  await Promise.all(tasks);
}

// One cheap, fail-soft Gemini call → a flat array of normalised Hebrew tags
// extracted from the listing's free text (+ up to 4 image URLs for multimodal
// signal). Returns [] on any problem so the publish never blocks.
async function extractSmartTags(body) {
  if (!GEMINI_API_KEY) return [];
  const title = (body.title || [body.street, body.city].filter(Boolean).join(' ') || '')
    .toString().slice(0, 200);
  const description = (body.description || '').toString().slice(0, 1500);
  const features = Array.isArray(body.featureLabels)
    ? body.featureLabels.slice(0, 30).join(', ') : '';
  if (!title && !description && !features) return [];

  const imageUrls = Array.isArray(body.imageUrls)
    ? body.imageUrls.filter((u) => typeof u === 'string' && /^https?:\/\//.test(u)).slice(0, 4)
    : [];

  const sys = 'אתה מחלץ תגיות חיפוש מובנות ממודעת דירה להשכרה. החזר אך ורק JSON תקין '
    + 'במבנה {"tags":["..."]}. כל תגית: מילה או צירוף קצר בעברית, בלי כפילויות, '
    + 'עד 12 תגיות. התמקד בתכונות שמחפשים לפיהן: מרפסת, מעלית, חניה, ממ"ד, משופצת, '
    + 'מרוהטת, מיזוג, סורגים, נוף, קומה גבוהה, פינוי מיידי, גינה, חיות מחמד, '
    + 'נגישות, סמוך לתחבורה, שקטה וכו׳. אל תמציא תכונות שלא נרמזו בטקסט או בתמונות.';

  const parts = [{
    text: `כותרת: ${title}\nתיאור: ${description}\nתכונות מסומנות: ${features}`,
  }];
  // Attach images as fetched inline data (best multimodal signal). Fail-soft per
  // image; cap total bytes so we stay cheap and within the request budget.
  for (const url of imageUrls) {
    try {
      const r = await fetch(url);
      if (!r.ok) continue;
      const ct = r.headers.get('content-type') || 'image/jpeg';
      if (!ct.startsWith('image/')) continue;
      const buf = Buffer.from(await r.arrayBuffer());
      if (buf.length > 1_500_000) continue; // skip oversized
      parts.push({ inlineData: { mimeType: ct, data: buf.toString('base64') } });
    } catch { /* skip this image */ }
  }

  const contents = [{ role: 'user', parts }];
  const data = await geminiGenerate(sys, contents, undefined, {
    temperature: 0.2,
    maxOutputTokens: 200,
    responseMimeType: 'application/json',
  });
  let text = (data?.candidates?.[0]?.content?.parts || [])
    .map((p) => p.text || '').join('');
  text = text.replace(/```(?:json)?/gi, '').replace(/```/g, '');
  const m = text.match(/\{[\s\S]*\}/);
  const parsed = m ? JSON.parse(m[0]) : {};
  const raw = Array.isArray(parsed.tags) ? parsed.tags : [];
  const seen = new Set();
  const tags = [];
  for (const t of raw) {
    const s = String(t || '').trim().slice(0, 40);
    const k = s.toLowerCase();
    if (s && !seen.has(k)) { seen.add(k); tags.push(s); }
    if (tags.length >= 12) break;
  }
  return tags;
}

// ── Instant saved-search alerts ──────────────────────────────────────────────
// On a NEW listing, scan every tenant's saved search and FCM-notify the ones it
// matches (same boolean predicate the on-device SavedSearch.matches uses). No
// polling — fired straight from the create path. Never notifies the landlord who
// posted it, never throws. Saved searches live in SAVED_SEARCHES_TABLE, synced
// from the client (SavedSearchesScreen → SavedSearchRepository).
async function fireSavedSearchAlerts(property, ownerUid) {
  try {
    // Pull all active saved searches (small table; Phase-1 scale). Bound the
    // fan-out so a flood of searches can't blow the request budget.
    let searches = [];
    let lastKey;
    do {
      const out = await ddb.send(new ScanCommand({
        TableName: SAVED_SEARCHES_TABLE,
        ExclusiveStartKey: lastKey,
      }));
      searches = searches.concat(out.Items || []);
      lastKey = out.LastEvaluatedKey;
    } while (lastKey && searches.length < 5000);

    const notified = new Set(); // one push per user even if several searches hit
    const addr = [property.street, property.streetNumber, property.city]
      .filter(Boolean).join(' ').trim();
    const propTitle = (property.city || addr || 'דירה חדשה');
    const propId = String(property.id || '');

    for (const s of searches) {
      const targetUid = String(s.userId || '');
      if (!targetUid || targetUid === ownerUid) continue;
      if (notified.has(targetUid)) continue;
      if (s.alertsOn === false) continue;
      if (!savedSearchMatches(s, property)) continue;
      notified.add(targetUid);
      const name = (s.name || 'החיפוש השמור שלך').toString().slice(0, 60);
      const price = Number(property.price) > 0 ? ` · ${Number(property.price)} ₪` : '';
      await notify(
        targetUid,
        'saved_search',
        'דירה חדשה שמתאימה לך 🔔',
        `${propTitle}${price} — תואם ל"${name}"`,
        { propertyId: propId, savedSearchId: String(s.id || ''), deepLink: `rently://property/${propId}` },
      );
      if (notified.size >= 300) break; // cap fan-out per create (anti-flood)
    }
  } catch (e) {
    console.warn('saved-search alerts failed:', e.message);
  }
}

// Boolean predicate mirroring lib/data/models/saved_search.dart `matches`:
// every criterion that was actually set must pass; unset criteria never exclude.
function savedSearchMatches(s, p) {
  const city = (s.city || '').toString().trim();
  if (city) {
    if (String(p.city || '').trim().toLowerCase() !== city.toLowerCase()) return false;
  }
  const price = Number(p.price);
  if (s.minBudget != null && price < Number(s.minBudget)) return false;
  if (s.maxBudget != null && price > Number(s.maxBudget)) return false;

  const rooms = Number(p.rooms);
  if (s.minRooms != null && rooms < Number(s.minRooms)) return false;
  if (s.maxRooms != null && rooms > Number(s.maxRooms)) return false;

  const txType = (s.transactionType || '').toString().trim();
  if (txType) {
    if (String(p.transactionType || '').trim() !== txType) return false;
  }

  const required = Array.isArray(s.requiredTags) ? s.requiredTags : [];
  if (required.length) {
    const haystack = [
      p.description, p.city, p.neighborhood, p.street, p.condition, p.propertyType,
      Array.isArray(p.featureLabels) ? p.featureLabels.join(' ') : '',
      Array.isArray(p.smartTags) ? p.smartTags.join(' ') : '',
    ].filter(Boolean).join(' ').toLowerCase();
    for (const t of required) {
      const needle = String(t || '').trim().toLowerCase();
      if (!needle) continue;
      if (!haystack.includes(needle)) return false;
    }
  }
  return true;
}

// Rental contracts (pk: id). Stores terms + each party's Ed25519 signature.
// Only the contract's landlord or tenant can read/sign it.
const CONTRACTS_TABLE = `${TABLE_PREFIX}contracts`;

// Profile-tag → cross-side compatibility key. Mirrors the client's
// ProfileTagCatalog so server-side lead ranking uses the exact same model.
const TENANT_TAG_KEYS = {
  'זוג': 'couples', 'משפחה עם ילדים': 'family', 'מחפש/ת שותפים': 'roommates',
  'סטודנט/ית': 'students', 'לא מעשן/ת': 'no_smoking', 'יש לי חיות מחמד': 'pets',
  'שקט/ה ומסודר/ת': 'quiet', 'חייב/ת חניה': 'parking', 'מרוהטת': 'furnished',
  'מעלית': 'elevator', 'מרפסת': 'balcony', 'ממ"ד / מקלט': 'shelter',
  'מיזוג אוויר': 'ac', 'נגישות לנכים': 'accessible',
  'מתאים לחיות מחמד': 'pets_allowed', 'אישור הכנסה מוכן': 'income_proof',
  'יש לי ערבים': 'guarantors', 'שכירות ארוכת טווח': 'long_term',
  'שכירות לטווח קצר': 'short_term', 'כניסה מיידית': 'immediate',
};
const LANDLORD_TAG_KEYS = {
  'הדירה מרוהטת': 'furnished', 'יש חניה': 'parking', 'יש מעלית': 'elevator',
  'יש מרפסת': 'balcony', 'ממ"ד / מקלט': 'shelter', 'מיזוג אוויר': 'ac',
  'דירה נגישה': 'accessible', 'מאפשר בעלי חיים': 'pets_allowed',
  'מתאים לזוגות': 'couples', 'מתאים למשפחות': 'family',
  'מתאים לשותפים': 'roommates', 'מתאים לסטודנטים': 'students',
  'מעדיף שוכרים לא מעשנים': 'no_smoking', 'מחפש שוכרים שקטים': 'quiet',
  'חוזה ארוך טווח': 'long_term', 'מאפשר טווח קצר': 'short_term',
  'כניסה מיידית': 'immediate', 'דורש אישור הכנסה': 'income_proof',
  'דורש ערבים': 'guarantors',
};
function keysFor(tags, map) {
  const out = new Set();
  for (const t of (tags || [])) { if (map[t]) out.add(map[t]); }
  return out;
}

// ── Authorization ─────────────────────────────────────────────────────────────
// The API Gateway authorizer verifies the Firebase JWT and passes the caller's
// uid via event.requestContext.authorizer.uid. Reads stay open (this is a public
// listings/discovery marketplace), but every WRITE stamps the owner field from
// the verified uid — so a caller can never create/overwrite a row owned by
// someone else — and DELETEs on owned tables are rejected unless the caller owns
// the row. Legitimate clients already send their own uid, so this is transparent
// for them; it only blocks forged cross-user writes/deletes.
//
// Only fields verified to exist in the data model are stamped, to avoid breaking
// GSI filters: properties.ownerUserId, messages.senderId, users.id (== uid).
const OWNED_TABLES = new Set(['properties', 'messages', 'users']);

function callerUidOf(event) {
  return event.requestContext?.authorizer?.uid || null;
}

// Gate for the admin-broadcast routes. The TOKEN authorizer only forwards the
// verified `uid` (not custom claims), so a `notifAdmin === true` claim never
// reaches this Lambda. We therefore gate by the verified admin uid as the
// fallback the task allows: the request is authenticated by API Gateway, and we
// additionally require that the caller IS the notif-admin user. If the
// authorizer is ever extended to forward claims, honor a notifAdmin claim too.
function callerIsNotifAdmin(event) {
  const ctx = event.requestContext?.authorizer || {};
  // Honor a forwarded custom claim if/when the authorizer starts passing it.
  // API-Gateway authorizer context values are stringified, so accept the
  // string 'true' as well as a boolean true.
  if (ctx.notifAdmin === true || ctx.notifAdmin === 'true') return true;
  return callerUidOf(event) === NOTIF_ADMIN_UID;
}

// Force the owner field to the authenticated uid before a write.
function stampOwner(tableKey, body, uid) {
  if (!uid) return;
  if (tableKey === 'properties') body.ownerUserId = uid;
  else if (tableKey === 'messages') body.senderId = uid;
  else if (tableKey === 'users') body.id = uid;
}

const json = (status, body) => ({
  statusCode: status,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization,Content-Type,x-api-key',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  },
  body: JSON.stringify(body),
});

export const handler = async (event) => {
  try {
    const method = event.httpMethod;
    const path = event.path || '';
    const segments = path.split('/').filter(Boolean);

    if (method === 'OPTIONS') return json(200, {});

    // ── Storage routes ──────────────────────────────────────────────────────
    if (segments[0] === 'storage') {
      return await handleStorage(method, segments, event);
    }

    // ── 3D viewer routes ────────────────────────────────────────────────────
    if (segments[0] === '3d' && segments[1] === 'viewers' && method === 'POST') {
      return await create3dViewer(event);
    }

    // ── Scan routes ─────────────────────────────────────────────────────────
    // Only GET /scans/:id remains in use (the refresh/poll fallback). Creation
    // and processing moved to the Teleport flow, so the legacy createScan /
    // processScan (Luma virtual-staging) endpoints were removed.
    if (segments[0] === 'scans') {
      const scanId = segments[1] ? decodeURIComponent(segments[1]) : null;
      // GET /scans/:id → return scan status + viewerUrl
      if (method === 'GET' && scanId) return await getScan(scanId);
      return json(404, { message: 'Unknown scan route' });
    }

    // ── Panorama stitch jobs (OpenCV horizontal 360°) ───────────────────────
    if (segments[0] === 'panorama') {
      const jobId = segments[1] ? decodeURIComponent(segments[1]) : null;
      // POST /panorama/pole-fill → composite real floor/ceiling caps (sync)
      if (method === 'POST' && segments[1] === 'pole-fill') return await poleFill(event);
      // POST /panorama → job + N presigned frame upload URLs
      if (method === 'POST' && !jobId) return await createPanorama(event);
      // POST /panorama/:id/stitch → async-invoke the stitcher
      if (method === 'POST' && jobId && segments[2] === 'stitch') {
        return await stitchPanorama(jobId, event);
      }
      // GET /panorama/:id → poll status → imageUrl + haov/vaov
      if (method === 'GET' && jobId) return await getPanorama(jobId);
      return json(404, { message: 'Unknown panorama route' });
    }

    // ── Varjo Teleport 3D captures ──────────────────────────────────────────
    if (segments[0] === 'teleport' && segments[1] === 'captures') {
      const eid = segments[2] ? decodeURIComponent(segments[2]) : null;
      // POST /teleport/captures → create a capture (returns eid + num_parts)
      if (method === 'POST' && !eid) return await teleportCreateCapture(event);
      // POST /teleport/captures/:eid/upload-url/:part → presigned S3 URL
      if (method === 'POST' && eid && segments[3] === 'upload-url') {
        return await teleportUploadUrl(event, eid, segments[4]);
      }
      // POST /teleport/captures/:eid/finalize → finalize the upload
      if (method === 'POST' && eid && segments[3] === 'finalize') {
        return await teleportFinalize(event, eid);
      }
      // GET /teleport/captures/:eid → status + viewer_url
      if (method === 'GET' && eid) return await teleportGetCapture(eid);
      return json(404, { message: 'Unknown teleport route' });
    }

    // ── KIRI Engine 3D reconstruction (Photo Scan + 3DGS) ───────────────────
    // The KIRI API key NEVER reaches the app — the client uploads frames to S3
    // via our presigned PUT urls, then we POST those bytes to KIRI server-side.
    if (segments[0] === 'scan3d') {
      const jobId = segments[1] ? decodeURIComponent(segments[1]) : null;
      // POST /scan3d → job + N presigned frame/video upload URLs
      if (method === 'POST' && !jobId) return await createScan3d(event);
      // POST /scan3d/:id/start → submit uploaded files to KIRI
      if (method === 'POST' && jobId && segments[2] === 'start') {
        return await startScan3d(event, jobId);
      }
      // GET /scan3d/:id → poll KIRI → {status, meshGlbUrl, splatUrl}
      if (method === 'GET' && jobId) return await getScan3d(event, jobId);
      return json(404, { message: 'Unknown scan3d route' });
    }

    // ── Push notification device tokens ─────────────────────────────────────
    if (segments[0] === 'notifications' && segments[1] === 'register-token'
        && method === 'POST') {
      return await handleRegisterToken(event);
    }
    // POST /notifications/mark-read → mark some/all of the caller's rows read.
    if (segments[0] === 'notifications' && segments[1] === 'mark-read'
        && method === 'POST') {
      return await handleMarkRead(event);
    }
    // GET /notifications → the caller's inbox, newest-first, + unread count.
    if (segments[0] === 'notifications' && !segments[1] && method === 'GET') {
      return await handleListNotifications(event);
    }

    // ── Two-sided match ranking (landlord's leads) ──────────────────────────
    if (segments[0] === 'match' && segments[1] === 'leads' && method === 'POST') {
      return await handleMatchLeads(event);
    }

    // ── Ranker impression log (LightGBM training data) ──────────────────────
    // POST /search/log → append per-impression feature vectors + outcomes.
    if (segments[0] === 'search' && segments[1] === 'log' && method === 'POST') {
      return await handleSearchLog(event);
    }

    // ── Semantic kNN candidate source (step 3) ──────────────────────────────
    // POST /search/knn → embed query text, kNN against S3 Vectors, return the
    // matching listings. Dormant → {results:[]} unless embeddings+index are on.
    if (segments[0] === 'search' && segments[1] === 'knn' && method === 'POST') {
      return await handleSearchKnn(event);
    }

    // ── Per-listing "Ask Rently" Q&A ────────────────────────────────────────
    // POST /listing/ask → answer a question about ONE listing, grounded strictly
    // in that listing + its enrichment. Auth-gated.
    if (segments[0] === 'listing' && segments[1] === 'ask' && method === 'POST') {
      return await handleListingAsk(event);
    }

    // GET /listing/enrichment?listingId=... → the stored enrichment for one
    // listing (priceBadge / neighborhoodScore / smartTags / gush-helka) so the
    // detail-screen badges can render. Fail-soft: returns {} when absent.
    if (segments[0] === 'listing' && segments[1] === 'enrichment' && method === 'GET') {
      const uid = callerUidOf(event);
      if (!uid) return json(401, { message: 'Authentication required.' });
      const lid = (event.queryStringParameters && event.queryStringParameters.listingId) || '';
      if (!lid) return json(400, { message: 'listingId is required' });
      try {
        const r = await ddb.send(new GetCommand({
          TableName: TABLES.properties.name, Key: { id: lid },
        }));
        const it = r.Item || {};
        return json(200, {
          listingId: lid,
          priceBadge: it.priceBadge || null,
          neighborhoodScore: it.neighborhoodScore || null,
          smartTags: it.smartTags || [],
          gush: it.gush || null,
          helka: it.helka || null,
        });
      } catch {
        return json(200, { listingId: lid }); // fail-soft
      }
    }

    // ── Rental contracts with e-signatures ──────────────────────────────────
    if (segments[0] === 'contracts') {
      const cid = segments[1] ? decodeURIComponent(segments[1]) : null;
      if (method === 'POST' && !cid) return await contractCreate(event);
      if (method === 'GET' && !cid) return await contractList(event);
      if (method === 'GET' && cid) return await contractGet(event, cid);
      if (method === 'POST' && cid && segments[2] === 'sign') {
        return await contractSign(event, cid);
      }
      if (method === 'POST' && cid && segments[2] === 'cancel') {
        return await contractCancel(event, cid);
      }
      return json(404, { message: 'Unknown contracts route' });
    }

    // ── Paid AI lease tailoring ───────────────────────────────────────────────
    // POST /contract/improve — takes the standard lease text + property/match
    // facts and returns an improved, tailored Hebrew draft (Gemini, key stays
    // server-side). The paywall (50₪) is enforced client-side as a stub; this
    // endpoint stays auth-gated and strictly grounded.
    if (segments[0] === 'contract' && segments[1] === 'improve' && method === 'POST') {
      return await handleContractImprove(event);
    }

    // ── Erik personal assistant ─────────────────────────────────────────────
    if (segments[0] === 'assistant' && method === 'POST') {
      // POST /assistant/tts → Gemini natural voice for a reply (audio bytes).
      if (segments[1] === 'tts') return await handleAssistantTts(event);
      // POST /assistant/live-token → ephemeral token for the real-time Live voice
      // session (the API key never leaves the backend).
      if (segments[1] === 'live-token') return await handleAssistantLiveToken(event);
      // POST /assistant/extract → the ONLY model call in the cost-optimised
      // listing flow: pull structured property fields out of a free-text
      // description + report which required fields are still missing.
      if (segments[1] === 'extract') return await handleAssistantExtract(event);
      // POST /assistant/explain → data-grounded explainer: takes the engine's
      // Scorecards + persona and writes a warm "how I chose" + per-property
      // "why this one, by the numbers", grounded strictly in the supplied figures.
      if (segments[1] === 'explain') return await handleAssistantExplain(event);
      return await handleAssistant(event);
    }

    // ── Admin company broadcast ─────────────────────────────────────────────
    // Both routes are gated to the notif-admin user (see callerIsNotifAdmin).
    if (segments[0] === 'admin' && segments[1] === 'broadcast'
        && !segments[2] && method === 'POST') {
      return await handleAdminBroadcast(event);
    }
    if (segments[0] === 'admin' && segments[1] === 'broadcasts'
        && !segments[2] && method === 'GET') {
      return await handleAdminListBroadcasts(event);
    }

    // ── Table CRUD ──────────────────────────────────────────────────────────
    const tableKey = segments[0];
    const table = TABLES[tableKey];
    if (!table) return json(404, { message: `Unknown resource: ${tableKey}` });

    const id = segments[1] ? decodeURIComponent(segments[1]) : null;
    const body = event.body ? JSON.parse(event.body) : {};
    const query = event.queryStringParameters || {};
    const callerUid = callerUidOf(event);

    // Writes/deletes on owner-scoped tables require a verified identity.
    const isMutation = method === 'POST' || method === 'PUT' || method === 'DELETE';
    if (isMutation && OWNED_TABLES.has(tableKey) && !callerUid) {
      return json(401, { message: 'Unauthorized' });
    }

    switch (method) {
      case 'GET':
        // Public aggregate counts (no row data leaked) — how many likes/views a
        // listing has. Enabled only for the analytics tables.
        if (id === 'count') {
          if (tableKey !== 'property_likes' && tableKey !== 'property_views') {
            return json(404, { message: 'Not found' });
          }
          return await countItems(table, query);
        }
        if (id) return await getOne(table, id);
        // Chat history is private: only the property owner (landlord) or someone
        // who has already posted in the thread may read it. Non-members get an
        // empty thread (not an error) so the UI degrades gracefully and a new
        // thread the tenant hasn't written to yet simply shows empty.
        if (tableKey === 'messages') {
          const matchId = query.matchId;
          if (!matchId) return json(400, { message: 'matchId required' });
          if (!(await isThreadMember(matchId, callerUid))) {
            return json(200, { items: [], hasMore: false, lastKey: null });
          }
        }
        // Who-liked-my-property is private: only the property's owner may read
        // the likes (and thus the interested tenants' identities).
        if (tableKey === 'property_likes') {
          const pid = query.propertyId;
          if (!pid) return json(400, { message: 'propertyId required' });
          if (!callerUid || !(await isOwnerOf(pid, callerUid))) {
            return json(200, { items: [], hasMore: false, lastKey: null });
          }
        }
        {
          const listed = await listItems(table, query);
          // Attach server-side ranking signals to each property so the client can
          // order/explain results with the same transparent scorer the future
          // LightGBM ranker will be trained against. Properties table only;
          // fail-soft (a signal failure just omits `rankSignals`).
          if (tableKey === 'properties' && listed.statusCode === 200) {
            // Cohort for the caller → cohort-aware weights/price-target/neighborhood.
            // Fail-soft: profile load errors → null cohort → default weights.
            const profile = callerUid ? await loadUserProfile(callerUid).catch(() => null) : null;
            return await attachRankSignals(listed, query, profileCohort(profile));
          }
          return listed;
        }
      case 'POST': {
        stampOwner(tableKey, body, callerUid);
        const writeId = tableKey === 'users'
          ? callerUid
          : (body.id || body.propertyId || body.userId);

        // ── New-listing pipeline (properties only) ──────────────────────────
        // Detect a genuine INSERT (not a re-PUT of an existing row) so the smart
        // tags + enrichment + instant saved-search alerts run exactly once. All
        // of this is fail-soft: an enrichment hiccup never blocks the publish.
        let isNewListing = false;
        if (tableKey === 'properties' && writeId) {
          try {
            const existing = await ddb.send(new GetCommand({
              TableName: table.name, Key: { id: writeId },
            }));
            isNewListing = !existing.Item;
          } catch { /* lookup failed → fail CLOSED (treat as existing) so a transient error can't re-enrich/re-alert an edit */ isNewListing = false; }
          if (isNewListing) {
            // Budget enrichment so a slow connector/Gemini fetch can't stall the
            // publish (the client blocks on this response). Fail-soft on timeout.
            await Promise.race([
              enrichListingOnCreate(body), // mutates body: smartTags, geo, badges
              new Promise((res) => setTimeout(res, 4000)),
            ]).catch(() => {});
          }
        }

        const written = await putItem(table, writeId, body);
        // Fire-and-forget push notifications on real events. Never block or fail
        // the write on a push problem — awaited so the Lambda doesn't get frozen
        // mid-send, but every error is swallowed inside the helpers.
        if (written.statusCode === 200) {
          await firePushForWrite(tableKey, body, callerUid);
          // New listing → run every tenant's saved search against it and push
          // an instant "new match" alert. No polling. Fail-soft.
          if (tableKey === 'properties' && isNewListing) {
            await fireSavedSearchAlerts({ ...body, id: writeId }, callerUid);
          }
        }
        return written;
      }
      case 'PUT': {
        stampOwner(tableKey, body, callerUid);
        // For the users table the row id IS the uid — never let a caller PUT to
        // another user's id.
        const writeId = tableKey === 'users' ? callerUid : id;
        return await putItem(table, writeId, body);
      }
      case 'DELETE':
        return await deleteItem(table, tableKey, id, callerUid);
      default:
        return json(405, { message: 'Method not allowed' });
    }
  } catch (e) {
    // Log the full error server-side; return a generic message so internal
    // details (stack, table names, SDK errors) never leak to clients.
    console.error('Router error:', e);
    return json(500, { message: 'Internal error' });
  }
};

// Rejects S3 keys that try to escape their folder via traversal or absolute
// paths. (Per-user key namespacing is a recommended follow-up — see audit.)
function isSafeStorageKey(key) {
  if (typeof key !== 'string' || key.length === 0 || key.length > 1024) return false;
  if (key.startsWith('/')) return false;
  if (key.split('/').some((seg) => seg === '..')) return false;
  return true;
}

// ── Chat membership ──────────────────────────────────────────────────────────
// matchId formats:
//   • New:    "match-<propertyId>~<tenantUid>"  → exact two-party membership:
//             the embedded tenant and the property owner (landlord), nobody else.
//             This gives each tenant interested in a property their own private
//             thread (no cross-tenant leakage).
//   • Legacy: "match-<propertyId>"  → owner, or anyone who already posted in the
//             thread (pre-migration data; kept readable for back-compat).
async function isOwnerOf(propertyId, uid) {
  try {
    const prop = await ddb.send(new GetCommand({
      TableName: TABLES.properties.name,
      Key: { id: propertyId },
    }));
    return !!(prop.Item && prop.Item.ownerUserId === uid);
  } catch (e) {
    console.error('isThreadMember property lookup failed:', e);
    return false;
  }
}

// Resolve the OTHER party of a chat thread, given the sender. matchId encodes
// the property + tenant; the two members are that tenant and the property's
// owner (landlord). Returns the recipient uid, or null if undeterminable.
async function otherPartyOf(matchId, senderUid) {
  if (!matchId || !senderUid) return null;
  const rest = matchId.startsWith('match-') ? matchId.slice(6) : matchId;
  const sep = rest.lastIndexOf('~');
  if (sep < 0) return null; // legacy threads: can't resolve a single counterpart
  const propertyId = rest.slice(0, sep);
  const tenantUid = rest.slice(sep + 1);
  try {
    const prop = await ddb.send(new GetCommand({
      TableName: TABLES.properties.name, Key: { id: propertyId },
    }));
    const ownerUid = prop.Item && prop.Item.ownerUserId;
    if (!ownerUid) return senderUid === tenantUid ? null : tenantUid;
    if (senderUid === tenantUid) return ownerUid;     // tenant → landlord
    if (senderUid === ownerUid) return tenantUid;     // landlord → tenant
    return tenantUid; // sender is neither (shouldn't happen) — default to tenant
  } catch {
    return senderUid === tenantUid ? null : tenantUid;
  }
}

async function isThreadMember(matchId, uid) {
  if (!uid || !matchId) return false;
  const rest = matchId.startsWith('match-') ? matchId.slice(6) : matchId;
  const sep = rest.lastIndexOf('~');

  if (sep >= 0) {
    const propertyId = rest.slice(0, sep);
    const tenantUid = rest.slice(sep + 1);
    if (uid === tenantUid) return true;
    return await isOwnerOf(propertyId, uid);
  }

  // Legacy: owner OR anyone who has already posted in the thread.
  if (await isOwnerOf(rest, uid)) return true;
  try {
    const msgs = await ddb.send(new QueryCommand({
      TableName: TABLES.messages.name,
      IndexName: TABLES.messages.gsi.name,
      KeyConditionExpression: 'matchId = :m',
      ExpressionAttributeValues: { ':m': matchId },
      Limit: 200,
    }));
    return (msgs.Items || []).some((m) => m.senderId === uid);
  } catch (e) {
    console.error('isThreadMember message lookup failed:', e);
    return false;
  }
}

// ── DynamoDB handlers ────────────────────────────────────────────────────────

async function getOne(table, id) {
  const r = await ddb.send(new GetCommand({ TableName: table.name, Key: { id } }));
  return r.Item ? json(200, r.Item) : json(404, {});
}

// Aggregate count of rows matching the GSI filter (e.g. all likes/views for a
// propertyId). Pages through with Select:COUNT so no row data is returned.
async function countItems(table, query) {
  const filterKey = table.gsi?.filterKey;
  const filterVal = filterKey ? query[filterKey] : undefined;
  if (!table.gsi || filterVal === undefined) {
    return json(400, { message: `${filterKey || 'filter'} required` });
  }
  let count = 0;
  let cursor;
  do {
    const out = await ddb.send(new QueryCommand({
      TableName: table.name,
      IndexName: table.gsi.name,
      KeyConditionExpression: '#pk = :v',
      ExpressionAttributeNames: { '#pk': table.gsi.pk },
      ExpressionAttributeValues: { ':v': castFilter(filterVal) },
      Select: 'COUNT',
      ExclusiveStartKey: cursor,
    }));
    count += out.Count || 0;
    cursor = out.LastEvaluatedKey;
  } while (cursor);
  return json(200, { count });
}

async function listItems(table, query) {
  const limit = Math.min(parseInt(query.limit || '150', 10), 500);
  const filterKey = table.gsi?.filterKey;
  const filterVal = filterKey ? query[filterKey] : undefined;
  const cursor = parseCursor(query.lastKey);

  // Per-owner query (e.g. GET /properties?ownerUserId=<uid>) — uses a dedicated
  // GSI so a user only ever reads their own rows, never a full-table scan.
  if (table.ownerIndex && query.ownerUserId) {
    const out = await ddb.send(new QueryCommand({
      TableName: table.name,
      IndexName: table.ownerIndex,
      KeyConditionExpression: '#o = :o',
      ExpressionAttributeNames: { '#o': 'ownerUserId' },
      ExpressionAttributeValues: { ':o': String(query.ownerUserId) },
      Limit: limit,
      ExclusiveStartKey: cursor,
      ScanIndexForward: query.order !== 'desc',
    }));
    return json(200, pageBody(out));
  }

  // Extra named GSIs (beyond the default one): query whichever filter is
  // supplied. Used by the events table so research can pull rows by eventType
  // (e.g. GET /events?eventType=swipeRight) as well as by userId.
  if (table.indexes) {
    for (const idx of Object.values(table.indexes)) {
      const v = query[idx.filterKey];
      if (v !== undefined) {
        const out = await ddb.send(new QueryCommand({
          TableName: table.name,
          IndexName: idx.name,
          KeyConditionExpression: '#pk = :v',
          ExpressionAttributeNames: { '#pk': idx.pk },
          ExpressionAttributeValues: { ':v': castFilter(v) },
          Limit: limit,
          ExclusiveStartKey: cursor,
          ScanIndexForward: query.order !== 'desc',
        }));
        return json(200, pageBody(out));
      }
    }
  }

  // Query the GSI when the matching filter is supplied (efficient path).
  if (table.gsi && filterVal !== undefined) {
    const out = await ddb.send(new QueryCommand({
      TableName: table.name,
      IndexName: table.gsi.name,
      KeyConditionExpression: '#pk = :v',
      ExpressionAttributeNames: { '#pk': table.gsi.pk },
      ExpressionAttributeValues: { ':v': castFilter(filterVal) },
      Limit: limit,
      ExclusiveStartKey: cursor,
      ScanIndexForward: query.order !== 'desc',
    }));
    return json(200, pageBody(out));
  }

  // Fallback: Scan with optional FilterExpression.
  const params = { TableName: table.name, Limit: limit, ExclusiveStartKey: cursor };
  if (filterKey && filterVal !== undefined) {
    params.FilterExpression = '#k = :v';
    params.ExpressionAttributeNames = { '#k': filterKey };
    params.ExpressionAttributeValues = { ':v': castFilter(filterVal) };
  }
  const out = await ddb.send(new ScanCommand(params));
  return json(200, pageBody(out));
}

// ── Transparent ranker — per-listing server signals ──────────────────────────
// Decorates a properties listItems() response with a `rankSignals` block per row
// (and a `rankScore`), so the client (and the future LightGBM ranker) sees the
// exact features the linear scorer used. Features:
//   freshness     — recency decay on createdAt (newer = higher, 14-day half-life)
//   popularity    — like-rate with Bayesian shrinkage toward the global prior
//                   (avoids a 1-view/1-like listing ranking above a proven one)
//   completeness  — fraction of the fields that make a listing browse-worthy
//   priceFit      — closeness of the listing price to the query's budget window
// All numbers are 0..1. `rankScore` is a transparent weighted sum — explainable,
// zero-infra, good for cold-start. Fail-soft: any error returns the list as-is.
// Bayesian shrinkage prior for like-rate: assume a modest baseline so listings
// with little traffic regress toward the mean instead of spiking on noise.
const LIKE_RATE_PRIOR = 0.12;   // assumed global like-per-view rate
const LIKE_RATE_STRENGTH = 8;   // pseudo-views of prior weight

// Cohort-aware main-feed scorer (Phase 0/1). Weights, price-target and the
// neighborhood sub-weights all vary by `cohort` (family|single|student|couple|
// null); neighborhood_fit (public data) and semantic_sim are now folded in.
async function attachRankSignals(listed, query, cohort = null) {
  try {
    const parsed = JSON.parse(listed.body);
    const items = Array.isArray(parsed.items) ? parsed.items : [];
    if (items.length === 0) return listed;

    const W = rankWeightsFor(cohort);
    const priceTarget = cohortPriceTarget(cohort);

    // Budget window for price-fit: explicit min/max, or ± a band around a target.
    const minBudget = num(query.minBudget) ?? num(query.minPrice);
    const maxBudget = num(query.maxBudget) ?? num(query.maxPrice);
    const targetPrice = num(query.price) ?? num(query.budget);

    // Pull popularity counts (views + likes) per listing in parallel, bounded.
    const ids = items.map((p) => String(p.id || '')).filter(Boolean).slice(0, 60);
    const counts = await loadPopularityCounts(ids);

    const now = Date.now();
    for (const p of items) {
      const id = String(p.id || '');
      const c = counts[id] || { views: 0, likes: 0 };
      const freshness = freshnessScore(p.createdAt, now);
      const popularity = shrinkLikeRate(c.likes, c.views);
      const completeness = completenessScore(p);
      const priceFit = priceFitScore(Number(p.price), { minBudget, maxBudget, targetPrice }, priceTarget);
      // neighborhood_fit: cohort-weighted public-data area sub-scores (0.5 when
      // the listing has no enriched neighborhood score).
      const neighborhood = neighborhoodFitScore(p.neighborhoodScore, cohort);
      // semantic_sim: present only on listings that came through /search/knn;
      // neutral 0.5 on the plain feed.
      const semRaw = Number(p.semanticSim);
      const semantic = Number.isFinite(semRaw) ? Math.max(0, Math.min(1, semRaw)) : 0.5;
      const rankScore =
        W.freshness * freshness +
        W.popularity * popularity +
        W.completeness * completeness +
        W.priceFit * priceFit +
        W.neighborhood * neighborhood +
        W.semantic * semantic;
      p.rankSignals = {
        freshness: round3(freshness),
        popularity: round3(popularity),
        completeness: round3(completeness),
        priceFit: round3(priceFit),
        neighborhood: round3(neighborhood),
        semantic: round3(semantic),
        cohort: cohort || 'default',
        views: c.views, likes: c.likes,
      };
      p.rankScore = round3(rankScore);
    }
    return json(200, parsed);
  } catch (e) {
    console.warn('attachRankSignals failed:', e.message);
    return listed;
  }
}

function num(v) {
  if (v === undefined || v === null || v === '') return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
}
const round3 = (n) => Math.round((Number(n) || 0) * 1000) / 1000;

// Exponential recency decay, 14-day half-life. Missing/garbage date → neutral 0.5.
function freshnessScore(createdAt, now) {
  const t = Date.parse(createdAt);
  if (!Number.isFinite(t)) return 0.5;
  const ageDays = Math.max(0, (now - t) / 86_400_000);
  return Math.exp(-Math.LN2 * ageDays / 14);
}

// Bayesian-shrunk like-rate, normalised so the prior maps to ~0.5.
function shrinkLikeRate(likes, views) {
  const l = Math.max(0, Number(likes) || 0);
  const v = Math.max(l, Number(views) || 0); // views can't be below likes
  const rate = (l + LIKE_RATE_PRIOR * LIKE_RATE_STRENGTH)
    / (v + LIKE_RATE_STRENGTH);
  // Map the like-rate onto 0..1 with the prior sitting at 0.5 (so an unproven
  // listing is neutral, above-prior is >0.5, below is <0.5).
  return Math.max(0, Math.min(1, 0.5 * (rate / LIKE_RATE_PRIOR)));
}

// Fraction of browse-critical fields present → a fuller listing ranks higher.
function completenessScore(p) {
  const checks = [
    Number(p.price) > 0,
    Number(p.rooms) > 0,
    !!p.city,
    !!p.street,
    Number(p.sizeM2) > 0,
    Array.isArray(p.imageUrls) && p.imageUrls.length > 0,
    !!(p.description && String(p.description).trim().length > 20),
    Array.isArray(p.smartTags) && p.smartTags.length > 0,
    !!p.neighborhood,
  ];
  const hit = checks.filter(Boolean).length;
  return hit / checks.length;
}

// Closeness of price to the requested budget. Inside [min,max] → 1.0; outside,
// decays with relative overshoot. No budget given → neutral 0.5.

// View + like counts per listing (the popularity signal source). Uses the
// propertyId-index COUNT query on the analytics tables. Bounded, fail-soft.
async function loadPopularityCounts(ids) {
  const out = {};
  await Promise.all(ids.map(async (id) => {
    const [views, likes] = await Promise.all([
      countByPropertyId(TABLES.property_views, id),
      countByPropertyId(TABLES.property_likes, id),
    ]);
    out[id] = { views, likes };
  }));
  return out;
}

async function countByPropertyId(table, propertyId) {
  try {
    const r = await ddb.send(new QueryCommand({
      TableName: table.name,
      IndexName: table.gsi.name,
      KeyConditionExpression: '#pk = :v',
      ExpressionAttributeNames: { '#pk': table.gsi.pk },
      ExpressionAttributeValues: { ':v': propertyId },
      Select: 'COUNT',
    }));
    return r.Count || 0;
  } catch {
    return 0;
  }
}

// POST /search/log — append one row per impression (the LightGBM training set).
// Body: { searchId?, query?, impressions: [{ propertyId, features:{...}, rank,
//         score, outcome }] }. outcome ∈ {impression, click, like, contact, none}.
// Auth-gated. Append-only, fully fail-soft. One Put per impression (capped).
async function handleSearchLog(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }

  const impressions = Array.isArray(body.impressions) ? body.impressions.slice(0, 100) : [];
  if (impressions.length === 0) return json(400, { message: 'impressions[] required' });

  const searchId = (body.searchId || crypto.randomUUID()).toString().slice(0, 64);
  const queryText = (body.query || '').toString().slice(0, 500);
  const queryCriteria = (body.criteria && typeof body.criteria === 'object')
    ? body.criteria : {};
  const now = Date.now();

  let written = 0;
  await Promise.all(impressions.map(async (imp, i) => {
    if (!imp || typeof imp !== 'object') return;
    // ponytail: outcomes are caller-asserted; sanity-check before training.
    const propertyId = (imp.propertyId || imp.id || imp.listingId || '').toString();
    if (!propertyId) return;
    try {
      await ddb.send(new PutCommand({
        TableName: SEARCH_LOG_TABLE,
        Item: {
          id: crypto.randomUUID(),
          userId: uid,
          createdAt: now + i,             // sk: keep stable per-impression ordering
          searchId,
          query: queryText,
          criteria: queryCriteria,
          propertyId,
          // The per-impression feature vector the ranker saw (training input).
          features: (imp.features && typeof imp.features === 'object') ? imp.features : {},
          rank: Number.isFinite(Number(imp.rank)) ? Number(imp.rank) : null,
          score: Number.isFinite(Number(imp.score)) ? Number(imp.score) : null,
          // The label the model learns to predict.
          outcome: (imp.outcome || 'impression').toString().slice(0, 24),
        },
      }));
      written += 1;
    } catch (e) {
      console.warn('search/log write failed:', e.message);
    }
  }));

  return json(200, { ok: true, logged: written, searchId });
}

// POST /search/knn — embed the query text, then score every active listing that
// carries an embedding by in-memory cosine similarity and return the top matches
// (each with a `semanticSim` signal for the client ranker). No external vector
// DB: the embedding lives on the property record. Fully fail-soft — any problem
// (embeddings off, embed failure, fetch failure) returns { results: [] } so the
// client's city query still stands.
// ponytail: brute-force cosine over the active set (status GSI, capped at 1000).
// Fine at Phase-1 scale; reinstate a vector index if the catalogue grows large.
async function handleSearchKnn(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }

  const text = typeof body.text === 'string' ? body.text.trim() : '';
  if (!EMBEDDINGS_ENABLED || !text) return json(200, { results: [] });

  try {
    const vec = await geminiEmbed(text);
    if (!vec) return json(200, { results: [] });
    const wantCity = typeof body.city === 'string' ? body.city.trim().toLowerCase() : '';
    const topK = Math.max(1, Math.min(200, Number(body.topK) || 50));

    // Pull the active listings (same status-GSI pattern as search_listings).
    let rows = [];
    for (const status of ['available', 'active']) {
      try {
        const out = await ddb.send(new QueryCommand({
          TableName: TABLES.properties.name,
          IndexName: TABLES.properties.gsi.name,
          KeyConditionExpression: '#s = :s',
          ExpressionAttributeNames: { '#s': TABLES.properties.gsi.pk },
          ExpressionAttributeValues: { ':s': status },
          Limit: 1000,
          ScanIndexForward: false,
        }));
        rows = rows.concat(out.Items || []);
      } catch { /* status value may not exist — ignore */ }
    }

    const seen = new Set();
    const scored = [];
    for (const p of rows) {
      if (!p || !p.id || seen.has(p.id)) continue;
      seen.add(p.id);
      if (p.isActive === false || p.status === 'inactive') continue;
      if (wantCity && String(p.city || '').toLowerCase() !== wantCity) continue;
      const emb = p.embedding;
      if (!Array.isArray(emb) || emb.length !== vec.length) continue;
      scored.push({ ...p, semanticSim: cosineSim(vec, emb) });
    }
    scored.sort((a, b) => b.semanticSim - a.semanticSim);
    return json(200, { results: scored.slice(0, topK) });
  } catch (e) {
    console.warn('search/knn failed:', e.message);
    return json(200, { results: [] });
  }
}

function pageBody(out) {
  return {
    items: out.Items || [],
    hasMore: !!out.LastEvaluatedKey,
    lastKey: out.LastEvaluatedKey
      ? encodeURIComponent(JSON.stringify(out.LastEvaluatedKey))
      : null,
  };
}

function parseCursor(cursor) {
  if (!cursor) return undefined;
  try {
    return JSON.parse(decodeURIComponent(cursor));
  } catch {
    return undefined;
  }
}

async function putItem(table, id, body) {
  if (!id) return json(400, { message: 'Missing id' });
  const item = { ...body, id };
  coerceGsiKeyTypes(table, item);
  await ddb.send(new PutCommand({ TableName: table.name, Item: item }));
  return json(200, item);
}

// DynamoDB GSI key attributes are strongly typed: a row whose GSI-key attribute
// has the wrong type is rejected (ValidationException: "Type mismatch for Index
// Key …"). The app writes some GSI keys with a JS type that doesn't match the
// table's declared key type — e.g. users.discoverable is declared S (String) on
// the `discoverable-updatedAt` index, but the client sends a BOOL, which threw
// on EVERY user write. Coerce known GSI-key attributes to the declared type
// before the put so the index always accepts the row.
//
// The discoverable-updatedAt index is only ever WRITTEN (the discovery read path
// scans without a discoverable filter), so stringifying here has no read impact.
function coerceGsiKeyTypes(table, item) {
  // users.discoverable → String ("true"/"false") to match the S-typed GSI key.
  if (table.name.endsWith('users') && item.discoverable !== undefined) {
    item.discoverable = String(item.discoverable);
  }
}

async function deleteItem(table, tableKey, id, callerUid) {
  if (!id) return json(400, { message: 'Missing id' });

  // Ownership enforcement: a caller may only delete rows they own.
  //  • users      — the row id IS the uid, so id must equal the caller.
  //  • properties — fetch the row and compare its ownerUserId.
  // Other tables have no verified owner field; they remain authenticated-only.
  if (tableKey === 'users') {
    if (id !== callerUid) return json(403, { message: 'Forbidden' });
  } else if (tableKey === 'properties') {
    const existing = await ddb.send(
      new GetCommand({ TableName: table.name, Key: { id } }),
    );
    const owner = existing.Item?.ownerUserId;
    if (owner && owner !== callerUid) return json(403, { message: 'Forbidden' });
  }

  await ddb.send(new DeleteCommand({ TableName: table.name, Key: { id } }));
  return json(200, { id, deleted: true });
}

function castFilter(v) {
  if (v === 'true') return true;
  if (v === 'false') return false;
  const n = Number(v);
  return Number.isFinite(n) && v.trim?.() !== '' ? v : v; // keep strings as-is
}

// ── S3 storage handlers ───────────────────────────────────────────────────────

async function handleStorage(method, segments, event) {
  // POST /storage/presign
  if (method === 'POST' && segments[1] === 'presign') {
    const body = event.body ? JSON.parse(event.body) : {};
    const key = body.key;
    const contentType = body.contentType || 'application/octet-stream';
    if (!key) return json(400, { message: 'Missing key' });
    if (!isSafeStorageKey(key)) return json(400, { message: 'Invalid key' });

    const uploadUrl = await getSignedUrl(
      s3,
      new PutObjectCommand({ Bucket: S3_BUCKET, Key: key, ContentType: contentType }),
      { expiresIn: 900 },
    );
    const publicUrl = `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${key}`;
    return json(200, { uploadUrl, publicUrl, key });
  }

  // DELETE /storage/{key+}
  if (method === 'DELETE') {
    const key = segments.slice(1).map(decodeURIComponent).join('/');
    if (!key) return json(400, { message: 'Missing key' });
    if (!isSafeStorageKey(key)) return json(400, { message: 'Invalid key' });
    await s3.send(new DeleteObjectCommand({ Bucket: S3_BUCKET, Key: key }));
    return json(200, { key, deleted: true });
  }

  return json(404, { message: 'Unknown storage route' });
}

async function create3dViewer(event) {
  const body = event.body ? JSON.parse(event.body) : {};
  const propertyId = sanitizeId(body.propertyId || body.id || 'property');
  const title = sanitizeText(body.title || 'Rently 3D Tour');
  const assets = normalizeAssets(body.assets);
  if (assets.length === 0) {
    return json(400, { message: 'At least one 3D asset URL is required.' });
  }

  const manifest = build3dManifest(assets);
  const html = renderViewerHtml({
    title,
    manifest,
    propertyId,
  });
  const key = `3d-viewers/${propertyId}/${Date.now()}-${Math.random().toString(36).slice(2, 10)}.html`;
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: key,
    Body: html,
    ContentType: 'text/html; charset=utf-8',
    CacheControl: 'public, max-age=300',
  }));

  const viewerUrl = `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${key}`;
  return json(200, {
    data: {
      scanId: `scan_${propertyId}_${Date.now()}`,
      viewerUrl,
      downloadUrl: manifest.downloadUrl,
      format: manifest.format,
      model3d: {
        viewerUrl,
        glbUrl: manifest.glbUrl,
        objUrl: manifest.objUrl,
        mtlUrl: manifest.mtlUrl,
        usdzUrl: manifest.usdzUrl,
        spzUrl: manifest.spzUrl,
        plyUrl: manifest.plyUrl,
        textureFolder: manifest.textureFolder,
        assets,
      },
    },
  });
}

// ── Pole-fill: composite real floor/ceiling caps into a phone panorama ────────
// POST /panorama/pole-fill {stripUrl, floorUrl?, ceilingUrl?, vaov} → {data:{imageUrl}}
// Invokes the Python Lambda synchronously (it carries the OpenCV/py360convert
// runtime). The app already falls back to the partial-FOV strip on any failure.
async function poleFill(event) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  if (!PANO_STITCH_FN) return json(503, { message: 'Pole-fill not configured.' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }

  const stripKey = keyFromS3Url(body.stripUrl);
  if (!stripKey) return json(400, { message: 'stripUrl required' });
  const floorKey = body.floorUrl ? keyFromS3Url(body.floorUrl) : null;
  const ceilingKey = body.ceilingUrl ? keyFromS3Url(body.ceilingUrl) : null;
  const vaov = Number(body.vaov) || 60;
  const resultKey =
    `panoramas/composited/${Date.now()}-${Math.random().toString(36).slice(2, 10)}.jpg`;

  try {
    const out = await lambda.send(new InvokeCommand({
      FunctionName: PANO_STITCH_FN,
      InvocationType: 'RequestResponse',
      Payload: Buffer.from(JSON.stringify({
        op: 'poleFill', bucket: S3_BUCKET, stripKey, floorKey, ceilingKey,
        vaov, resultKey,
      })),
    }));
    const res = JSON.parse(Buffer.from(out.Payload || '').toString() || '{}');
    if (res.status === 'ready' && res.imageUrl) {
      return json(200, { data: { imageUrl: res.imageUrl } });
    }
    return json(502, { message: res.error || 'pole-fill failed' });
  } catch (e) {
    console.error('poleFill error:', e);
    return json(502, { message: 'pole-fill failed' });
  }
}

// Extract the S3 object key from a public S3 URL (virtual-hosted or path style).
function keyFromS3Url(u) {
  if (typeof u !== 'string' || !u) return null;
  try {
    const url = new URL(u);
    let key = decodeURIComponent(url.pathname).replace(/^\/+/, '');
    if (S3_BUCKET && key.startsWith(`${S3_BUCKET}/`)) key = key.slice(S3_BUCKET.length + 1);
    return isSafeStorageKey(key) ? key : null;
  } catch {
    return null;
  }
}

function normalizeAssets(rawAssets) {
  if (!Array.isArray(rawAssets)) return [];
  return rawAssets
    .map((item) => {
      if (!item || typeof item !== 'object') return null;
      const url = typeof item.url === 'string' ? item.url.trim() : '';
      if (!isAllowedAssetUrl(url)) return null;
      const fileName = sanitizeText(item.fileName || fileNameFromUrl(url));
      const kind = sanitizeAssetKind(item.kind || inferAssetKind(fileName, url));
      const contentType = typeof item.contentType === 'string'
        ? item.contentType.trim()
        : '';
      const sizeBytes = Number.isFinite(Number(item.sizeBytes))
        ? Number(item.sizeBytes)
        : null;
      return {
        kind,
        url,
        fileName,
        contentType,
        sizeBytes,
      };
    })
    .filter(Boolean);
}

function build3dManifest(assets) {
  const byKind = (kind) => assets.find((item) => item.kind === kind)?.url || '';
  const textureAssets = assets.filter((item) => item.kind === 'texture');
  return {
    format: preferredFormat(assets),
    downloadUrl: preferredDownloadUrl(assets),
    glbUrl: byKind('glb'),
    objUrl: byKind('obj'),
    mtlUrl: byKind('mtl'),
    usdzUrl: byKind('usdz'),
    spzUrl: byKind('spz'),
    plyUrl: byKind('ply'),
    textureFolder: textureAssets.length > 0 ? commonPrefix(textureAssets.map((item) => item.url)) : '',
    assets,
  };
}

function preferredFormat(assets) {
  const order = ['glb', 'usdz', 'obj', 'spz', 'ply', 'sog'];
  for (const kind of order) {
    if (assets.some((item) => item.kind === kind)) return kind;
  }
  return assets[0]?.kind || '';
}

function preferredDownloadUrl(assets) {
  const order = ['glb', 'usdz', 'obj', 'spz', 'ply', 'sog'];
  for (const kind of order) {
    const match = assets.find((item) => item.kind === kind);
    if (match?.url) return match.url;
  }
  return assets[0]?.url || '';
}

function renderViewerHtml({ title, manifest, propertyId }) {
  const config = JSON.stringify(manifest);
  const safeTitle = escapeHtml(title);
  const safePropertyId = escapeHtml(propertyId);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${safeTitle}</title>
  <style>
    :root { color-scheme: dark; }
    html, body { margin: 0; height: 100%; background: #07111c; color: #f5f7fb; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { display: flex; flex-direction: column; }
    header { padding: 16px 18px 12px; border-bottom: 1px solid rgba(255,255,255,0.08); background: rgba(7,17,28,0.92); backdrop-filter: blur(12px); }
    h1 { margin: 0; font-size: 18px; line-height: 1.2; }
    p { margin: 6px 0 0; color: rgba(245,247,251,0.72); font-size: 13px; }
    #viewer { flex: 1; position: relative; min-height: 320px; }
    #fallback, #obj-container, model-viewer, iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
    #fallback { display: none; padding: 24px; overflow: auto; box-sizing: border-box; }
    ul { padding-left: 20px; }
    a { color: #9bd1ff; }
    canvas { display: block; width: 100%; height: 100%; }
  </style>
  <script type="module" src="https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js"></script>
</head>
<body>
  <header>
    <h1>${safeTitle}</h1>
    <p>Rently property ${safePropertyId}</p>
  </header>
  <div id="viewer">
    <model-viewer id="model-viewer" camera-controls touch-action="pan-y" interaction-prompt="auto" ar></model-viewer>
    <div id="obj-container" hidden></div>
    <iframe id="external-viewer" hidden allowfullscreen></iframe>
    <div id="fallback"></div>
  </div>
  <script type="module">
    const config = ${config};
    const modelViewer = document.getElementById('model-viewer');
    const objContainer = document.getElementById('obj-container');
    const externalViewer = document.getElementById('external-viewer');
    const fallback = document.getElementById('fallback');

    const renderFallback = (reason) => {
      modelViewer.hidden = true;
      objContainer.hidden = true;
      externalViewer.hidden = true;
      fallback.style.display = 'block';
      const links = (config.assets || []).map((asset) =>
        '<li><a href="' + asset.url + '" target="_blank" rel="noreferrer">' +
        (asset.fileName || asset.kind || asset.url) + '</a> (' + asset.kind + ')</li>'
      ).join('');
      fallback.innerHTML =
        '<h2 style="margin-top:0">Viewer unavailable</h2>' +
        '<p>' + reason + '</p>' +
        '<ul>' + links + '</ul>';
    };

    if (config.glbUrl || config.usdzUrl) {
      modelViewer.src = config.glbUrl || '';
      if (config.usdzUrl) modelViewer.setAttribute('ios-src', config.usdzUrl);
      modelViewer.hidden = false;
    } else if (config.objUrl) {
      modelViewer.hidden = true;
      objContainer.hidden = false;
      const THREE = await import('https://unpkg.com/three@0.166.1/build/three.module.js');
      const { OrbitControls } = await import('https://unpkg.com/three@0.166.1/examples/jsm/controls/OrbitControls.js');
      const { OBJLoader } = await import('https://unpkg.com/three@0.166.1/examples/jsm/loaders/OBJLoader.js');
      const { MTLLoader } = await import('https://unpkg.com/three@0.166.1/examples/jsm/loaders/MTLLoader.js');

      const scene = new THREE.Scene();
      scene.background = new THREE.Color(0x07111c);
      const camera = new THREE.PerspectiveCamera(60, objContainer.clientWidth / Math.max(objContainer.clientHeight, 1), 0.01, 1000);
      camera.position.set(0, 1.4, 3.8);

      const renderer = new THREE.WebGLRenderer({ antialias: true });
      renderer.setPixelRatio(window.devicePixelRatio || 1);
      renderer.setSize(objContainer.clientWidth, Math.max(objContainer.clientHeight, 1));
      objContainer.appendChild(renderer.domElement);

      scene.add(new THREE.AmbientLight(0xffffff, 1.2));
      const keyLight = new THREE.DirectionalLight(0xffffff, 1.4);
      keyLight.position.set(4, 8, 6);
      scene.add(keyLight);

      const controls = new OrbitControls(camera, renderer.domElement);
      controls.enableDamping = true;

      const fitCamera = (object) => {
        const box = new THREE.Box3().setFromObject(object);
        const size = box.getSize(new THREE.Vector3());
        const center = box.getCenter(new THREE.Vector3());
        controls.target.copy(center);
        const maxDim = Math.max(size.x, size.y, size.z, 1);
        camera.position.set(center.x, center.y + maxDim * 0.3, center.z + maxDim * 1.8);
        camera.near = maxDim / 100;
        camera.far = maxDim * 100;
        camera.updateProjectionMatrix();
      };

      const loader = new OBJLoader();
      if (config.mtlUrl) {
        const materials = await new MTLLoader().loadAsync(config.mtlUrl);
        materials.preload();
        loader.setMaterials(materials);
      }
      const object = await loader.loadAsync(config.objUrl);
      scene.add(object);
      fitCamera(object);

      const onResize = () => {
        const width = objContainer.clientWidth;
        const height = Math.max(objContainer.clientHeight, 1);
        camera.aspect = width / height;
        camera.updateProjectionMatrix();
        renderer.setSize(width, height);
      };
      window.addEventListener('resize', onResize);
      onResize();

      const tick = () => {
        controls.update();
        renderer.render(scene, camera);
        requestAnimationFrame(tick);
      };
      tick();
    } else if (config.viewerUrl) {
      modelViewer.hidden = true;
      externalViewer.hidden = false;
      externalViewer.src = config.viewerUrl;
    } else {
      renderFallback('No renderable GLB, USDZ, or OBJ asset was uploaded for this property.');
    }
  </script>
</body>
</html>`;
}

function isAllowedAssetUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:';
  } catch {
    return false;
  }
}

function inferAssetKind(fileName, url) {
  const source = (fileName || url || '').toLowerCase();
  if (source.endsWith('.glb') || source.endsWith('.gltf')) return 'glb';
  if (source.endsWith('.obj')) return 'obj';
  if (source.endsWith('.mtl')) return 'mtl';
  if (source.endsWith('.usdz')) return 'usdz';
  if (source.endsWith('.spz')) return 'spz';
  if (source.endsWith('.ply')) return 'ply';
  if (source.endsWith('.sog')) return 'sog';
  if (source.endsWith('.png') || source.endsWith('.jpg') || source.endsWith('.jpeg') || source.endsWith('.webp') || source.endsWith('.ktx2')) return 'texture';
  if (source.endsWith('.bin')) return 'buffer';
  return 'asset';
}

function sanitizeAssetKind(value) {
  const normalized = String(value || '').toLowerCase().replace(/[^a-z0-9_-]/g, '');
  return normalized || 'asset';
}

function sanitizeId(value) {
  return String(value || 'property').replace(/[^A-Za-z0-9._/-]/g, '_').slice(0, 120) || 'property';
}

function sanitizeText(value) {
  return String(value || '').replace(/[\u0000-\u001f]+/g, ' ').trim().slice(0, 180);
}

function fileNameFromUrl(value) {
  try {
    const url = new URL(value);
    return decodeURIComponent(url.pathname.split('/').pop() || '');
  } catch {
    return '';
  }
}

function commonPrefix(values) {
  if (values.length === 0) return '';
  let prefix = values[0];
  for (const value of values.slice(1)) {
    while (!value.startsWith(prefix) && prefix) {
      prefix = prefix.slice(0, -1);
    }
  }
  const slash = prefix.lastIndexOf('/');
  return slash >= 0 ? prefix.slice(0, slash + 1) : prefix;
}

// ── Scan handlers (video → virtual-tour viewer) ──────────────────────────────

// ── Virtual staging ("הדמיה") via Luma Agents uni-1 image_edit ───────────────
// The createScan / processScan endpoints (presign + kick off a Luma generation)
// were removed — staging creation moved to the Teleport flow. GET /scans/:id is
// kept as the poll/refresh fallback; it still polls Luma for any legacy job that
// already carries a generationId and re-hosts the staged result on S3.

// ── Varjo Teleport helpers ──────────────────────────────────────────────────

let _teleportToken = null;
let _teleportTokenExp = 0;

async function teleportAuthToken() {
  const now = Date.now();
  if (_teleportToken && now < _teleportTokenExp - 60000) return _teleportToken;
  const res = await fetch(TELEPORT_AUTH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: TELEPORT_CLIENT_ID,
      client_secret: TELEPORT_CLIENT_SECRET,
    }).toString(),
  });
  if (!res.ok) throw new Error(`teleport auth ${res.status}`);
  const data = await res.json();
  _teleportToken = data.access_token;
  // Tokens last ~1h; refresh a minute early. Default to 50 min if unsure.
  _teleportTokenExp = now + (data.expires_in ? data.expires_in * 1000 : 3000000);
  return _teleportToken;
}

async function teleportFetch(path, { method = 'GET', body } = {}) {
  const token = await teleportAuthToken();
  const res = await fetch(`${TELEPORT_API_BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  return { ok: res.ok, status: res.status, data };
}

function teleportConfigured() {
  return TELEPORT_CLIENT_ID && TELEPORT_CLIENT_SECRET;
}

// POST /teleport/captures {name, bytesize} → {eid, numParts, chunkSize}
async function teleportCreateCapture(event) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  if (!teleportConfigured()) return json(503, { message: '3D capture not configured.' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }
  const name = (typeof body.name === 'string' && body.name.trim())
    ? body.name.trim().slice(0, 120) : 'Rently apartment';
  const bytesize = Number(body.bytesize);
  if (!Number.isFinite(bytesize) || bytesize <= 0) {
    return json(400, { message: 'bytesize required' });
  }
  // Teleport REQUIRES input_data_format. Omitting it makes the pipeline treat
  // the upload as a bulk-images zip, so every mp4 video fails reconstruction
  // (state=ERROR). We always send "video"; the file name carries an .mp4 hint.
  const inputDataFormat = (body.inputDataFormat === 'bulk-images')
    ? 'bulk-images' : 'video';
  const capName = (inputDataFormat === 'video' && !/\.(mp4|mov)$/i.test(name))
    ? `${name}.mp4` : name;
  try {
    const r = await teleportFetch('/api/v1/captures', {
      method: 'POST',
      body: { name: capName, bytesize, input_data_format: inputDataFormat },
    });
    if (!r.ok) {
      console.warn('teleport create failed', r.status, JSON.stringify(r.data).slice(0, 200));
      return json(502, { message: 'Could not start 3D capture.' });
    }
    return json(200, {
      eid: r.data.eid,
      numParts: r.data.num_parts,
      chunkSize: r.data.chunk_size,
    });
  } catch (e) {
    console.warn('teleport create exception', e.message);
    return json(502, { message: 'Could not start 3D capture.' });
  }
}

// POST /teleport/captures/:eid/upload-url/:part {bytesize} → {uploadUrl}
async function teleportUploadUrl(event, eid, partStr) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  if (!teleportConfigured()) return json(503, { message: '3D capture not configured.' });
  const part = parseInt(partStr || '0', 10);
  if (!Number.isInteger(part) || part < 1) return json(400, { message: 'invalid part' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
  const bytesize = Number(body.bytesize) || undefined;
  try {
    const r = await teleportFetch(
      `/api/v1/captures/${encodeURIComponent(eid)}/create-upload-url/${part}`,
      { method: 'POST', body: { eid, bytesize } },
    );
    if (!r.ok) {
      console.warn('teleport upload-url failed', r.status);
      return json(502, { message: 'Could not get upload URL.' });
    }
    return json(200, { uploadUrl: r.data.upload_url, chunkSize: r.data.chunk_size });
  } catch (e) {
    console.warn('teleport upload-url exception', e.message);
    return json(502, { message: 'Could not get upload URL.' });
  }
}

// POST /teleport/captures/:eid/finalize {parts:[{number,etag}]} → status
async function teleportFinalize(event, eid) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  if (!teleportConfigured()) return json(503, { message: '3D capture not configured.' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }
  const parts = Array.isArray(body.parts) ? body.parts : [];
  if (parts.length === 0) return json(400, { message: 'parts required' });
  try {
    const r = await teleportFetch(
      `/api/v1/captures/${encodeURIComponent(eid)}/uploaded`,
      { method: 'POST', body: { eid, parts } },
    );
    if (!r.ok) {
      console.warn('teleport finalize failed', r.status, JSON.stringify(r.data).slice(0, 200));
      return json(502, { message: 'Could not finalize 3D capture.' });
    }
    return json(200, teleportCaptureView(r.data));
  } catch (e) {
    console.warn('teleport finalize exception', e.message);
    return json(502, { message: 'Could not finalize 3D capture.' });
  }
}

// GET /teleport/captures/:eid → {eid, state, viewerUrl, ...}
async function teleportGetCapture(eid) {
  if (!teleportConfigured()) return json(503, { message: '3D capture not configured.' });
  try {
    // The item GET is 405; the list endpoint carries state + viewer_url.
    const r = await teleportFetch('/api/v1/captures');
    if (!r.ok || !Array.isArray(r.data)) {
      return json(502, { message: 'Could not read 3D capture.' });
    }
    const cap = r.data.find((c) => c && c.eid === eid);
    if (!cap) return json(404, { message: 'Capture not found' });
    return json(200, teleportCaptureView(cap));
  } catch (e) {
    console.warn('teleport get exception', e.message);
    return json(502, { message: 'Could not read 3D capture.' });
  }
}

function teleportCaptureView(c) {
  return {
    eid: c.eid,
    sid: c.sid,
    state: c.state, // CREATED | PROCESSING | READY | ...
    stateDescription: c.state_description || null,
    errorReason: c.error_reason || null,
    viewerUrl: c.viewer_url || null,
    previewUrl: c.preview_url || null,
    videoUrl: c.video_url || null,
    shareUrl: c.share_url || null,
  };
}

async function getScanMeta(scanId) {
  try {
    const obj = await s3.send(new GetObjectCommand({
      Bucket: S3_BUCKET,
      Key: `3d-scans/meta/${scanId}.json`,
    }));
    return JSON.parse(await streamToString(obj.Body));
  } catch {
    return null;
  }
}

async function putScanMeta(scanId, meta) {
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: `3d-scans/meta/${scanId}.json`,
    Body: JSON.stringify(meta),
    ContentType: 'application/json',
  }));
}

function scanResponse(meta) {
  const url = meta.stagedUrl || meta.viewerUrl || '';
  const s = meta.status || 'pending';
  const processingStage = s === 'ready' ? 'complete'
    : s === 'failed' ? 'failed'
    : s === 'processing' ? 'staging'
    : 'pending';
  return json(200, {
    data: {
      id: meta.scanId,
      scanId: meta.scanId,
      status: s,
      viewerUrl: url,
      previewImageUrl: url,
      downloadUrl: url,
      processingError: meta.error || '',
      processingStage,
      format: meta.contentType?.startsWith('video/') ? 'video' : 'image',
    },
  });
}

// Download the Luma presigned result (expires in 1h) and re-host permanently on S3.
async function rehostImage(sourceUrl, key) {
  const res = await fetch(sourceUrl);
  if (!res.ok) throw new Error(`rehost download failed ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: key,
    Body: buf,
    ContentType: 'image/png',
    CacheControl: 'public, max-age=31536000',
  }));
  return `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${key}`;
}

// ── Panorama stitch jobs ────────────────────────────────────────────────────
// The phone uploads N overlapping frames; the Python OpenCV Lambda stitches them
// into a horizontal 360° strip. Job meta is a small S3 JSON the stitcher updates
// and the client polls (same store pattern as 3D scans — no extra table).

async function getPanoMeta(jobId) {
  try {
    const obj = await s3.send(new GetObjectCommand({
      Bucket: S3_BUCKET, Key: `panoramas/meta/${jobId}.json`,
    }));
    return JSON.parse(await streamToString(obj.Body));
  } catch {
    return null;
  }
}

async function putPanoMeta(jobId, meta) {
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET, Key: `panoramas/meta/${jobId}.json`,
    Body: JSON.stringify(meta), ContentType: 'application/json',
  }));
}

async function createPanorama(event) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  const body = event.body ? JSON.parse(event.body) : {};
  const propertyId = sanitizeId(body.propertyId || 'prop');
  const ts = Date.now();
  const rand = Math.random().toString(36).slice(2, 10);
  const jobId = `pano_${ts}_${rand}`;

  // ── Video capture mode ────────────────────────────────────────────────────
  // The app recorded one mp4 while rotating in place plus a gyro pose timeline
  // [{tMs, yaw, pitch}]. We presign ONE video PUT and stash the timeline + FOVs
  // in the job meta; the stitch Lambda extracts the sharpest keyframe per yaw
  // bucket, attaches the interpolated pose, and feeds the existing pose-assisted
  // projector. (Same contract the photo path uses, just a better frame source.)
  if (body.captureMode === 'video') {
    const videoKey = `panoramas/jobs/${jobId}/video.mp4`;
    const videoUploadUrl = await getSignedUrl(
      s3,
      new PutObjectCommand({ Bucket: S3_BUCKET, Key: videoKey, ContentType: 'video/mp4' }),
      { expiresIn: 21600 },
    );
    const resultKey = `panoramas/results/${jobId}.jpg`;
    await putPanoMeta(jobId, {
      jobId, propertyId, resultKey,
      captureMode: 'video',
      videoKey,
      poseTimeline: Array.isArray(body.poseTimeline) ? body.poseTimeline : [],
      hfov: Number(body.hfov) || 0,
      vfov: Number(body.vfov) || 0,
      status: 'pending', createdAt: ts,
    });
    return json(200, { data: { jobId, videoUploadUrl } });
  }

  // ── Arranged capture mode ─────────────────────────────────────────────────
  // The user shot N wide native panoramas and PLACED each at a known horizontal
  // position (startDeg + widthDeg) and a vertical row (horizontal/top/bottom).
  // No feature-matching: the stitcher composites by KNOWN position. We presign
  // ONE jpeg PUT per pano (SAME order the client sends), and stash the parallel
  // panoKeys[] + the panos[] placement array in the job meta.
  if (body.captureMode === 'arranged') {
    const panos = Array.isArray(body.panos) ? body.panos : [];
    if (panos.length < 1) return json(400, { message: 'panos required' });
    const panoKeys = [];
    const uploadUrls = [];
    for (let i = 0; i < panos.length; i++) {
      const key = `panoramas/jobs/${jobId}/p${i}.jpg`;
      panoKeys.push(key);
      uploadUrls.push(await getSignedUrl(
        s3,
        new PutObjectCommand({ Bucket: S3_BUCKET, Key: key, ContentType: 'image/jpeg' }),
        { expiresIn: 21600 },
      ));
    }
    const resultKey = `panoramas/results/${jobId}.jpg`;
    await putPanoMeta(jobId, {
      jobId, propertyId, resultKey,
      captureMode: 'arranged',
      panoKeys,
      // Keep only the placement fields we use (startDeg, widthDeg, row).
      panos: panos.map((p) => ({
        startDeg: Number(p.startDeg) || 0,
        widthDeg: Number(p.widthDeg) || 0,
        row: (p.row === 'top' || p.row === 'bottom') ? p.row : 'horizontal',
      })),
      status: 'pending', createdAt: ts,
    });
    return json(200, { data: { jobId, uploadUrls } });
  }

  // ── Photo capture mode (unchanged) ────────────────────────────────────────
  // Allocate exactly as many frame slots as the client will upload (cv2 needs ≥2).
  // Must NOT clamp up — extra unfilled slots become missing keys the stitcher 404s on.
  const frameCount = Math.max(2, Math.min(60, Number(body.frameCount) || 16));

  const frameKeys = [];
  const uploadUrls = [];
  for (let i = 0; i < frameCount; i++) {
    const key = `panoramas/jobs/${jobId}/f${i}.jpg`;
    frameKeys.push(key);
    uploadUrls.push(await getSignedUrl(
      s3,
      new PutObjectCommand({ Bucket: S3_BUCKET, Key: key, ContentType: 'image/jpeg' }),
      { expiresIn: 21600 },
    ));
  }
  const resultKey = `panoramas/results/${jobId}.jpg`;
  await putPanoMeta(jobId, {
    jobId, propertyId, frameKeys, resultKey,
    // pose-assisted stitching: persist the per-frame poses sent at create so the
    // stitch step (a separate request) can use them (bridged via meta).
    ...(Array.isArray(body.poses) && body.poses.length ? { poses: body.poses } : {}),
    status: 'pending', createdAt: ts,
  });
  return json(200, { data: { jobId, uploadUrls } });
}

async function stitchPanorama(jobId, event) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  const meta = await getPanoMeta(jobId);
  if (!meta) return json(404, { message: 'Panorama job not found' });
  if (meta.status === 'ready' || meta.status === 'failed') {
    return json(200, { data: panoData(meta) });
  }
  if (!PANO_STITCH_FN) {
    const failed = { ...meta, status: 'failed', error: 'Stitcher not configured (no PANO_STITCH_FN).' };
    await putPanoMeta(jobId, failed);
    return json(200, { data: panoData(failed) });
  }
  await putPanoMeta(jobId, { ...meta, status: 'processing', processedAt: Date.now() });

  // ── Video capture mode ────────────────────────────────────────────────────
  // Hand the stitcher the recorded video + pose timeline; it picks the sharpest
  // keyframe per yaw bucket, attaches each frame's interpolated pose, and runs
  // the same pose-assisted projector the photo path uses.
  if (meta.captureMode === 'video') {
    await lambda.send(new InvokeCommand({
      FunctionName: PANO_STITCH_FN,
      InvocationType: 'Event',
      Payload: Buffer.from(JSON.stringify({
        bucket: S3_BUCKET,
        metaKey: `panoramas/meta/${jobId}.json`,
        videoKey: meta.videoKey,
        resultKey: meta.resultKey,
        captureMode: 'video',
        poseTimeline: meta.poseTimeline || [],
        hfov: meta.hfov,
        vfov: meta.vfov,
        meta: {
          jobId, propertyId: meta.propertyId, videoKey: meta.videoKey,
          resultKey: meta.resultKey, createdAt: meta.createdAt,
        },
      })),
    }));
    return json(200, { data: { jobId, status: 'processing' } });
  }

  // ── Arranged capture mode ─────────────────────────────────────────────────
  // Deterministic composite by KNOWN position: hand the stitcher the per-pano
  // S3 keys and their {startDeg, widthDeg, row} placements; it bilinear-resizes
  // each native pano into its lon/lat rectangle on a 360×180 equirect canvas and
  // feather-blends overlaps. No feature-matching.
  if (meta.captureMode === 'arranged') {
    await lambda.send(new InvokeCommand({
      FunctionName: PANO_STITCH_FN,
      InvocationType: 'Event',
      Payload: Buffer.from(JSON.stringify({
        bucket: S3_BUCKET,
        metaKey: `panoramas/meta/${jobId}.json`,
        resultKey: meta.resultKey,
        captureMode: 'arranged',
        panoKeys: meta.panoKeys,
        panos: meta.panos,
        meta: {
          jobId, propertyId: meta.propertyId,
          resultKey: meta.resultKey, createdAt: meta.createdAt,
        },
      })),
    }));
    return json(200, { data: { jobId, status: 'processing' } });
  }

  // Pose-assisted stitching: the app may send a top-level `poses` array on the
  // stitch request, parallel to the frames (poses[i] ↔ frame f{i}), each
  // {yaw, pitch, hfov, vfov} in DEGREES. When present and aligned with the
  // frames, the stitch Lambda projects each frame onto an equirectangular canvas
  // by its KNOWN pose (deterministic) instead of fragile feature-matching — the
  // real fix for failed stitches on blank walls. We forward it untouched and let
  // the stitcher validate alignment; if it's absent/mismatched the stitcher
  // falls back to cv2.Stitcher (backward-compatible).
  // Prefer poses persisted at create (the app sends them on POST /panorama);
  // fall back to poses on the stitch request body for flexibility.
  const poses = validatePoses(meta.poses, meta.frameKeys.length)
    ?? sanitizePoses(event, meta.frameKeys.length);

  // Stitching exceeds the API Gateway 29s limit, so invoke async (Event) and let
  // the client poll GET /panorama/:id.
  await lambda.send(new InvokeCommand({
    FunctionName: PANO_STITCH_FN,
    InvocationType: 'Event',
    Payload: Buffer.from(JSON.stringify({
      bucket: S3_BUCKET,
      metaKey: `panoramas/meta/${jobId}.json`,
      frameKeys: meta.frameKeys,
      resultKey: meta.resultKey,
      ...(poses ? { poses } : {}),
      meta: {
        jobId, propertyId: meta.propertyId, frameKeys: meta.frameKeys,
        resultKey: meta.resultKey, createdAt: meta.createdAt,
      },
    })),
  }));
  return json(200, { data: { jobId, status: 'processing' } });
}

// Parse + validate the optional `poses` array off the stitch request body.
// Returns a clean array of {yaw,pitch,hfov,vfov} numbers (in degrees) only when
// it's a non-empty array aligned 1:1 with the frames; otherwise null so the
// stitcher takes its existing feature-matching path. Stays backward-compatible:
// a request with no poses behaves exactly as before.
function sanitizePoses(event, frameCount) {
  let body = {};
  try { body = event?.body ? JSON.parse(event.body) : {}; }
  catch { return null; }
  return validatePoses(body.poses, frameCount);
}

// Validate a raw poses array (from the stitch request OR the persisted job meta).
function validatePoses(raw, frameCount) {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  // Must be parallel to the frames — a mismatch means we can't trust the mapping.
  if (raw.length !== frameCount) return null;
  const out = [];
  for (const p of raw) {
    if (!p || typeof p !== 'object') return null;
    const yaw = Number(p.yaw);
    const pitch = Number(p.pitch);
    const hfov = Number(p.hfov);
    const vfov = Number(p.vfov);
    if (![yaw, pitch, hfov, vfov].every(Number.isFinite)) return null;
    if (hfov <= 0 || vfov <= 0) return null;
    out.push({ yaw, pitch, hfov, vfov });
  }
  return out;
}

async function getPanorama(jobId) {
  const meta = await getPanoMeta(jobId);
  if (!meta) return json(404, { message: 'Panorama job not found' });
  return json(200, { data: panoData(meta) });
}

function panoData(meta) {
  return {
    jobId: meta.jobId,
    status: meta.status || 'pending',
    imageUrl: meta.imageUrl || '',
    haov: meta.haov ?? 360,
    vaov: meta.vaov ?? 60,
    error: meta.error || '',
  };
}

// ── KIRI Engine 3D reconstruction ────────────────────────────────────────────
// Job meta is a small S3 JSON (same store pattern as scans/panoramas — no extra
// DynamoDB table). Lifecycle:
//   POST /scan3d            → allocate S3 keys + presigned PUTs (client uploads)
//   POST /scan3d/:id/start  → stream the uploaded bytes to KIRI as multipart;
//                             store KIRI's `serialize` (its job id)
//   GET  /scan3d/:id        → poll KIRI getStatus; when Successful, fetch the
//                             zip download link → {status:'ready', meshGlbUrl, splatUrl}

const KIRI_MAX_FRAMES = 300; // KIRI accepts 20–300 images per project.

async function getScan3dMeta(jobId) {
  try {
    const obj = await s3.send(new GetObjectCommand({
      Bucket: S3_BUCKET, Key: `scan3d/meta/${jobId}.json`,
    }));
    return JSON.parse(await streamToString(obj.Body));
  } catch {
    return null;
  }
}

async function putScan3dMeta(jobId, meta) {
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET, Key: `scan3d/meta/${jobId}.json`,
    Body: JSON.stringify(meta), ContentType: 'application/json',
  }));
}

// POST /scan3d {propertyId, captureType:'photos'|'video', frameCount}
//   → {jobId, uploadUrls:[presigned S3 PUT urls]}
async function createScan3d(event) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }

  const propertyId = sanitizeId(body.propertyId || 'prop');
  const captureType = body.captureType === 'video' ? 'video' : 'photos';
  // 3DGS by default (walkable splat for apartments); allow photo mesh too.
  const scanType = body.scanType === 'photo' ? 'photo' : '3dgs';
  const ts = Date.now();
  const rand = Math.random().toString(36).slice(2, 10);
  const jobId = `k3d_${ts}_${rand}`;

  const fileKeys = [];
  const uploadUrls = [];
  if (captureType === 'video') {
    const key = `scan3d/jobs/${jobId}/video.mp4`;
    fileKeys.push(key);
    uploadUrls.push(await getSignedUrl(
      s3,
      new PutObjectCommand({ Bucket: S3_BUCKET, Key: key, ContentType: 'video/mp4' }),
      // 6h: a slow mobile video upload (tens of MB on cellular) must not 403 mid-flight.
      { expiresIn: 21600 },
    ));
  } else {
    // KIRI needs 20–300 images. Trust the client's count but clamp to the API range.
    const frameCount = Math.max(20, Math.min(KIRI_MAX_FRAMES, Number(body.frameCount) || 20));
    for (let i = 0; i < frameCount; i++) {
      const key = `scan3d/jobs/${jobId}/f${i}.jpg`;
      fileKeys.push(key);
      uploadUrls.push(await getSignedUrl(
        s3,
        new PutObjectCommand({ Bucket: S3_BUCKET, Key: key, ContentType: 'image/jpeg' }),
        // 6h: keep parity with video so a slow multi-image upload can't expire.
        { expiresIn: 21600 },
      ));
    }
  }

  // Fast mode (splat-only, KIRI isMesh=0) → quicker reconstruction; the Gaussian
  // splat already serves both 360 and the 3D walkthrough, so the mesh bake is skippable.
  const fast = body.fast === true;
  await putScan3dMeta(jobId, {
    jobId, propertyId, captureType, scanType, fileKeys, fast,
    status: 'pending', createdAt: ts,
  });
  return json(200, { data: { jobId, uploadUrls } });
}

// POST /scan3d/:id/start → submit the uploaded S3 files to KIRI (create job).
async function startScan3d(event, jobId) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  if (!KIRI_API_KEY) return json(503, { message: '3D reconstruction not configured.' });

  const meta = await getScan3dMeta(jobId);
  if (!meta) return json(404, { message: 'Scan job not found' });
  // Idempotent: if already submitted, just report current status.
  if (meta.serialize) return json(200, { ok: true, status: meta.status || 'processing' });

  const isVideo = meta.captureType === 'video';
  // Endpoint per scan + capture type (3DGS by default; photo = textured mesh).
  // For 3DGS we set isMesh=1 so KIRI also bakes a GLB mesh alongside the .ply.
  const path = meta.scanType === 'photo'
    ? (isVideo ? '/photo/video' : '/photo/image')
    : (isVideo ? '/3dgs/video' : '/3dgs/image');

  try {
    const parts = [];
    for (const key of meta.fileKeys) {
      const obj = await s3.send(new GetObjectCommand({ Bucket: S3_BUCKET, Key: key }));
      const bytes = await streamToBuffer(obj.Body);
      const fileName = key.split('/').pop();
      if (isVideo) {
        parts.push({ name: 'videoFile', filename: fileName, contentType: 'video/mp4', data: bytes });
      } else {
        // KIRI expects the array field name `imagesFiles` for every image.
        parts.push({ name: 'imagesFiles', filename: fileName, contentType: 'image/jpeg', data: bytes });
      }
    }
    if (meta.scanType === 'photo') {
      parts.push({ name: 'fileFormat', data: 'glb' });
      parts.push({ name: 'modelQuality', data: '0' });
      parts.push({ name: 'textureQuality', data: '0' });
    } else {
      // Fast mode = splat only (isMesh=0) → KIRI skips the slow mesh bake.
      // Quality mode (default) = also emit a GLB mesh (isMesh=1).
      parts.push({ name: 'isMesh', data: meta.fast ? '0' : '1' });
      parts.push({ name: 'isMask', data: '0' });
      parts.push({ name: 'fileFormat', data: 'glb' });
    }

    const { body: mpBody, contentType } = buildMultipart(parts);
    const res = await fetch(`${KIRI_API_BASE}${path}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${KIRI_API_KEY}`, 'Content-Type': contentType },
      body: mpBody,
      signal: AbortSignal.timeout(REMOTE_FETCH_TIMEOUT_MS),
    });
    const data = await res.json().catch(() => ({}));
    const serialize = data?.data?.serialize;
    if (!res.ok || !serialize) {
      console.warn('KIRI submit failed', res.status, JSON.stringify(data).slice(0, 200));
      const failed = { ...meta, status: 'failed', error: data?.msg || `KIRI error ${res.status}` };
      await putScan3dMeta(jobId, failed);
      return json(502, { message: 'Could not start 3D reconstruction.' });
    }
    await putScan3dMeta(jobId, {
      ...meta, serialize, calculateType: data.data.calculateType,
      status: 'processing', submittedAt: Date.now(),
    });
    return json(200, { ok: true });
  } catch (e) {
    console.warn('KIRI submit exception', e.message);
    return json(502, { message: 'Could not start 3D reconstruction.' });
  }
}

// GET /scan3d/:id → poll KIRI; on success return rehosted asset urls.
async function getScan3d(event, jobId) {
  const meta = await getScan3dMeta(jobId);
  if (!meta) return json(404, { message: 'Scan job not found' });

  if (meta.status === 'ready') {
    return json(200, {
      status: 'ready',
      meshGlbUrl: meta.meshGlbUrl || '',
      splatUrl: meta.splatUrl || '',
      plyUrl: meta.plyUrl || '',
    });
  }
  if (meta.status === 'failed') {
    return json(200, { status: 'failed', error: meta.error || 'reconstruction failed' });
  }
  if (!KIRI_API_KEY || !meta.serialize) {
    return json(200, { status: 'processing' });
  }

  try {
    const sr = await fetch(
      `${KIRI_API_BASE}/model/getStatus?serialize=${encodeURIComponent(meta.serialize)}`,
      { headers: { Authorization: `Bearer ${KIRI_API_KEY}` }, signal: AbortSignal.timeout(REMOTE_FETCH_TIMEOUT_MS) },
    );
    const sd = await sr.json().catch(() => ({}));
    // KIRI status: -1 Uploading, 0 Processing, 1 Failed, 2 Successful, 3 Queuing, 4 Exported.
    const status = sd?.data?.status;
    if (status === 1) {
      await putScan3dMeta(jobId, { ...meta, status: 'failed', error: 'KIRI reconstruction failed' });
      return json(200, { status: 'failed', error: 'KIRI reconstruction failed' });
    }
    if (status !== 2 && status !== 4) {
      return json(200, { status: 'processing' });
    }

    // Successful → fetch the zip download link, re-host permanently on S3.
    const dr = await fetch(
      `${KIRI_API_BASE}/model/getModelZip?serialize=${encodeURIComponent(meta.serialize)}`,
      { headers: { Authorization: `Bearer ${KIRI_API_KEY}` }, signal: AbortSignal.timeout(REMOTE_FETCH_TIMEOUT_MS) },
    );
    const dd = await dr.json().catch(() => ({}));
    const modelUrl = dd?.data?.modelUrl;
    if (!dr.ok || !modelUrl) {
      return json(200, { status: 'processing' });
    }
    // KIRI returns ONE zip bundle (link valid ~60 min). Download it, unzip in
    // memory, and pull out the real renderable assets: the textured mesh
    // (.glb/.gltf) and — for 3DGS scans — the gaussian splat (.ply). Re-host each
    // extracted file permanently on S3 so the client gets directly-loadable urls.
    const zipRes = await fetchToBuffer(modelUrl, { maxBytes: MAX_KIRI_ZIP_BYTES });
    if (!zipRes.ok) {
      console.warn('KIRI zip download failed', zipRes.status, zipRes.tooLarge ? '(over size cap)' : '');
      return json(200, { status: 'processing' });
    }
    const zipBuf = zipRes.buffer;

    let entries;
    try {
      entries = new AdmZip(zipBuf).getEntries();
    } catch (e) {
      console.warn('KIRI zip unpack failed', e.message);
      return json(200, { status: 'processing' });
    }

    // Pick the largest matching file per kind (the model, not a stray sample).
    let meshEntry = null;   // .glb preferred, else .gltf
    let splatEntry = null;  // .ply
    for (const entry of entries) {
      if (entry.isDirectory) continue;
      const name = entry.entryName.toLowerCase();
      const size = entry.header?.size || 0;
      if (name.endsWith('.glb')) {
        if (!meshEntry || meshEntry._ext !== 'glb' || size > meshEntry._size) {
          meshEntry = { entry, _ext: 'glb', _size: size };
        }
      } else if (name.endsWith('.gltf')) {
        // Only take a .gltf if we haven't found a (self-contained) .glb.
        if (!meshEntry) meshEntry = { entry, _ext: 'gltf', _size: size };
      } else if (name.endsWith('.ply')) {
        if (!splatEntry || size > splatEntry._size) {
          splatEntry = { entry, _size: size };
        }
      }
    }

    const base = `scan3d/results/${jobId}`;
    let meshGlbUrl = '';
    let splatUrl = '';   // COMPACT .splat the app loads (primary)
    let plyUrl = '';     // raw KIRI .ply kept for archival / debugging

    if (meshEntry) {
      const ext = meshEntry._ext;
      const key = `${base}/model.${ext}`;
      const ctype = ext === 'glb' ? 'model/gltf-binary' : 'model/gltf+json';
      meshGlbUrl = await putExtractedFile(meshEntry.entry.getData(), key, ctype);
    }
    if (splatEntry) {
      const plyBuf = splatEntry.entry.getData();
      // Keep the raw .ply (archival), but the app's splat viewer must receive the
      // COMPACT .splat — the 95 MB .ply is too slow to stream + parse on-device.
      plyUrl = await putExtractedFile(plyBuf, `${base}/splat.ply`, 'application/octet-stream');
      try {
        const splatBuf = plyToSplat(plyBuf);
        splatUrl = await putExtractedFile(
          splatBuf, `${base}/${jobId}.splat`, 'application/octet-stream',
        );
        console.log(`plyToSplat ${jobId}: ${plyBuf.length}B ply → ${splatBuf.length}B splat (${splatBuf.length / 32} splats)`);
      } catch (e) {
        // Conversion failed (unexpected PLY layout) — fall back to the raw .ply so
        // the viewer at least has something to load; the URL still ends .ply, which
        // the viewer's sceneFormat() detects correctly.
        console.warn('plyToSplat failed, serving raw .ply', e.message);
        splatUrl = plyUrl;
      }
    }

    if (!meshGlbUrl && !splatUrl) {
      // Nothing renderable found in the bundle — keep the raw zip as a fallback.
      console.warn('KIRI zip had no .glb/.gltf/.ply', entries.map((e) => e.entryName).slice(0, 40));
      meshGlbUrl = await rehostFile(modelUrl, `${base}/model.zip`, 'application/zip');
    }

    const updated = {
      ...meta, status: 'ready',
      meshGlbUrl,                 // extracted textured GLB/GLTF mesh
      splatUrl,                   // COMPACT .splat (gaussian splat) — what the app loads
      plyUrl,                     // raw KIRI .ply (archival), if present
      completedAt: Date.now(),
    };
    await putScan3dMeta(jobId, updated);

    // 3D/tour just became READY (one-time transition: meta was 'processing'
    // until this write). Push the property's owner. Fire-and-forget; swallow.
    if (meta.propertyId) {
      try {
        const prop = await ddb.send(new GetCommand({
          TableName: TABLES.properties.name, Key: { id: meta.propertyId },
        }));
        const ownerUid = prop.Item && prop.Item.ownerUserId;
        if (ownerUid) {
          const where = (prop.Item.street || prop.Item.city) || '';
          await notify(
            ownerUid,
            'tour_ready',
            'הסיור התלת-ממדי מוכן! 🏠',
            where ? `הסיור התלת-ממדי של הדירה ב${where} מוכן לצפייה`
              : 'הסיור התלת-ממדי של הדירה שלך מוכן לצפייה',
            { propertyId: String(meta.propertyId), jobId: String(jobId) },
          );
        }
      } catch (e) { console.warn('FCM: tour-ready push failed:', e.message); }
    }

    return json(200, { status: 'ready', meshGlbUrl, splatUrl, plyUrl });
  } catch (e) {
    console.warn('KIRI poll exception', e.message);
    return json(200, { status: 'processing' });
  }
}

// ── 3DGS .ply → compact .splat converter ────────────────────────────────────
// KIRI returns a HEAVY raw gaussian-splat .ply (~95 MB, full spherical-harmonics
// SH) that is far too slow to stream + parse in the in-app WebView splat viewer.
// We convert it server-side to the compact antimatter15 .splat format (32 bytes
// per splat → ~5-8x smaller, ~13-25 MB), which the GaussianSplats3D viewer loads
// natively and fast on-device.
//
// Per-splat .splat record (32 bytes):
//   • position  : 3 × float32  (x, y, z)                          (12B)
//   • scale     : 3 × float32  = exp(scale_i)                     (12B)
//   • color RGBA: 4 × uint8     rgb = 0.5 + C0·f_dc_i ; a=sigmoid (4B)
//   • rotation  : 4 × uint8     normalized quaternion ·128+128    (4B)
//
// Parses the PLY HEADER to find each property's byte offset (order varies between
// exporters: x,y,z; maybe nx,ny,nz; f_dc_0..2 = DC SH color; f_rest_* = higher SH
// which we IGNORE; opacity; scale_0..2; rot_0..3). One pass over the buffer with a
// DataView, writing straight into the output — bounded memory (a ~95 MB ply fits
// the 3008 MB Lambda with headroom). Splats are emitted in descending
// scale-volume × opacity order for better front-to-back blending.
const SH_C0 = 0.28209479177387814;

function plyToSplat(plyBuffer) {
  const headerEnd = plyHeaderEnd(plyBuffer);
  if (headerEnd < 0) throw new Error('plyToSplat: no end_header found');
  const headerText = plyBuffer.toString('latin1', 0, headerEnd);
  const lines = headerText.split(/\r?\n/);
  if (!lines.some((l) => l.trim() === 'ply')) {
    throw new Error('plyToSplat: not a PLY file');
  }
  const fmtLine = lines.find((l) => l.startsWith('format'));
  if (!fmtLine || !fmtLine.includes('binary_little_endian')) {
    throw new Error(`plyToSplat: unsupported format "${(fmtLine || '').trim()}"`);
  }

  // Parse the vertex element + its properties in declared (= on-disk) order.
  let vertexCount = 0;
  let inVertex = false;
  const props = [];
  for (const raw of lines) {
    const line = raw.trim();
    if (line.startsWith('element ')) {
      const [, name, count] = line.split(/\s+/);
      inVertex = name === 'vertex';
      if (inVertex) vertexCount = parseInt(count, 10) || 0;
    } else if (inVertex && line.startsWith('property ')) {
      const parts = line.split(/\s+/);
      props.push({ name: parts[2], size: plyTypeSize(parts[1]) });
    }
  }
  if (vertexCount <= 0) throw new Error('plyToSplat: zero vertices');

  let stride = 0;
  const offsetOf = {};
  for (const p of props) { offsetOf[p.name] = stride; stride += p.size; }

  const need = (n) => {
    if (!(n in offsetOf)) throw new Error(`plyToSplat: missing property "${n}"`);
    return offsetOf[n];
  };
  const oX = need('x'), oY = need('y'), oZ = need('z');
  const oFdc0 = need('f_dc_0'), oFdc1 = need('f_dc_1'), oFdc2 = need('f_dc_2');
  const oOpacity = need('opacity');
  const oS0 = need('scale_0'), oS1 = need('scale_1'), oS2 = need('scale_2');
  const oR0 = need('rot_0'), oR1 = need('rot_1'), oR2 = need('rot_2'), oR3 = need('rot_3');

  const bodyStart = headerEnd;
  if (bodyStart + vertexCount * stride > plyBuffer.length) {
    // Truncated file — clamp to the vertices actually present.
    vertexCount = Math.floor((plyBuffer.length - bodyStart) / stride);
  }
  if (vertexCount <= 0) throw new Error('plyToSplat: no vertex data');

  const view = new DataView(
    plyBuffer.buffer, plyBuffer.byteOffset + bodyStart, vertexCount * stride,
  );
  const sigmoid = (x) => 1 / (1 + Math.exp(-x));

  // Importance order = scale-volume × opacity, descending.
  const sortKey = new Float32Array(vertexCount);
  for (let i = 0; i < vertexCount; i++) {
    const base = i * stride;
    const sx = Math.exp(view.getFloat32(base + oS0, true));
    const sy = Math.exp(view.getFloat32(base + oS1, true));
    const sz = Math.exp(view.getFloat32(base + oS2, true));
    sortKey[i] = sx * sy * sz * sigmoid(view.getFloat32(base + oOpacity, true));
  }
  const order = new Uint32Array(vertexCount);
  for (let i = 0; i < vertexCount; i++) order[i] = i;
  order.sort((a, b) => sortKey[b] - sortKey[a]);

  const out = Buffer.allocUnsafe(vertexCount * 32);
  const clampByte = (v) => (v < 0 ? 0 : v > 255 ? 255 : v);

  for (let n = 0; n < vertexCount; n++) {
    const i = order[n];
    const base = i * stride;
    const o = n * 32;

    out.writeFloatLE(view.getFloat32(base + oX, true), o);
    out.writeFloatLE(view.getFloat32(base + oY, true), o + 4);
    out.writeFloatLE(view.getFloat32(base + oZ, true), o + 8);

    out.writeFloatLE(Math.exp(view.getFloat32(base + oS0, true)), o + 12);
    out.writeFloatLE(Math.exp(view.getFloat32(base + oS1, true)), o + 16);
    out.writeFloatLE(Math.exp(view.getFloat32(base + oS2, true)), o + 20);

    const r = Math.round((0.5 + SH_C0 * view.getFloat32(base + oFdc0, true)) * 255);
    const g = Math.round((0.5 + SH_C0 * view.getFloat32(base + oFdc1, true)) * 255);
    const b = Math.round((0.5 + SH_C0 * view.getFloat32(base + oFdc2, true)) * 255);
    const al = Math.round(sigmoid(view.getFloat32(base + oOpacity, true)) * 255);
    out[o + 24] = clampByte(r);
    out[o + 25] = clampByte(g);
    out[o + 26] = clampByte(b);
    out[o + 27] = clampByte(al);

    let q0 = view.getFloat32(base + oR0, true);
    let q1 = view.getFloat32(base + oR1, true);
    let q2 = view.getFloat32(base + oR2, true);
    let q3 = view.getFloat32(base + oR3, true);
    let len = Math.hypot(q0, q1, q2, q3);
    if (len === 0) { q0 = 1; len = 1; }
    q0 /= len; q1 /= len; q2 /= len; q3 /= len;
    out[o + 28] = clampByte(Math.round(q0 * 128 + 128));
    out[o + 29] = clampByte(Math.round(q1 * 128 + 128));
    out[o + 30] = clampByte(Math.round(q2 * 128 + 128));
    out[o + 31] = clampByte(Math.round(q3 * 128 + 128));
  }
  return out;
}

// Byte index just past the "end_header" line (start of the binary body).
function plyHeaderEnd(buf) {
  const idx = buf.indexOf(Buffer.from('end_header'));
  if (idx < 0) return -1;
  let i = idx + 'end_header'.length;
  if (buf[i] === 0x0d) i++; // \r
  if (buf[i] === 0x0a) i++; // \n
  return i;
}

function plyTypeSize(type) {
  switch (type) {
    case 'char': case 'uchar': case 'int8': case 'uint8': return 1;
    case 'short': case 'ushort': case 'int16': case 'uint16': return 2;
    case 'int': case 'uint': case 'int32': case 'uint32':
    case 'float': case 'float32': return 4;
    case 'double': case 'float64': case 'int64': case 'uint64': return 8;
    default: throw new Error(`plyToSplat: unknown property type "${type}"`);
  }
}

// Build a multipart/form-data body from {name, data, filename?, contentType?}
// parts. `data` is a Buffer (file) or string (field). Returns a single Buffer.
function buildMultipart(parts) {
  const boundary = `----rentlyKiri${Date.now().toString(16)}${Math.random().toString(16).slice(2)}`;
  const chunks = [];
  for (const p of parts) {
    let header = `--${boundary}\r\nContent-Disposition: form-data; name="${p.name}"`;
    if (p.filename) header += `; filename="${p.filename}"`;
    header += '\r\n';
    if (p.contentType) header += `Content-Type: ${p.contentType}\r\n`;
    header += '\r\n';
    chunks.push(Buffer.from(header, 'utf-8'));
    chunks.push(Buffer.isBuffer(p.data) ? p.data : Buffer.from(String(p.data), 'utf-8'));
    chunks.push(Buffer.from('\r\n', 'utf-8'));
  }
  chunks.push(Buffer.from(`--${boundary}--\r\n`, 'utf-8'));
  return { body: Buffer.concat(chunks), contentType: `multipart/form-data; boundary=${boundary}` };
}

// Per-source-file cap when buffering an uploaded scan frame/video from S3 before
// re-POSTing it to KIRI. Bounds Lambda memory: a malicious/oversized upload can't
// balloon the function past this. 600 MB comfortably covers a long video capture.
const MAX_SCAN_FILE_BYTES = 600 * 1024 * 1024;
// Cap + wall-clock timeout for the KIRI result zip download (the link is remote
// and untrusted). Bounds both memory (no unbounded buffering) and hang time.
const MAX_KIRI_ZIP_BYTES = 800 * 1024 * 1024;
const REMOTE_FETCH_TIMEOUT_MS = 120000;

async function streamToBuffer(stream, maxBytes = MAX_SCAN_FILE_BYTES) {
  const chunks = [];
  let total = 0;
  for await (const chunk of stream) {
    const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += buf.length;
    if (total > maxBytes) {
      throw new Error(`stream exceeds ${maxBytes} byte cap`);
    }
    chunks.push(buf);
  }
  return Buffer.concat(chunks);
}

// Download a remote URL into a Buffer with a wall-clock timeout AND a hard size
// cap, streaming the body so an oversized/slow response is aborted instead of
// being fully buffered into Lambda memory.
async function fetchToBuffer(url, { timeoutMs = REMOTE_FETCH_TIMEOUT_MS, maxBytes } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) return { ok: false, status: res.status };
    // Reject early if the server advertises an over-cap length.
    const declared = Number(res.headers.get('content-length') || 0);
    if (maxBytes && declared && declared > maxBytes) {
      controller.abort();
      return { ok: false, status: res.status, tooLarge: true };
    }
    const chunks = [];
    let total = 0;
    for await (const chunk of res.body) {
      const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      total += buf.length;
      if (maxBytes && total > maxBytes) {
        controller.abort();
        return { ok: false, status: res.status, tooLarge: true };
      }
      chunks.push(buf);
    }
    return { ok: true, status: res.status, buffer: Buffer.concat(chunks) };
  } finally {
    clearTimeout(timer);
  }
}

// Persist an already-in-memory buffer (e.g. a file extracted from a zip) to S3
// and return its public url. Mirrors rehostFile's caching/headers.
async function putExtractedFile(buf, key, contentType) {
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET, Key: key, Body: buf,
    ContentType: contentType || 'application/octet-stream',
    CacheControl: 'public, max-age=31536000',
  }));
  return `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${key}`;
}

// Download a (short-lived) remote file and re-host it permanently on S3.
async function rehostFile(sourceUrl, key, contentType) {
  const res = await fetch(sourceUrl);
  if (!res.ok) throw new Error(`rehost download failed ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET, Key: key, Body: buf,
    ContentType: contentType || 'application/octet-stream',
    CacheControl: 'public, max-age=31536000',
  }));
  return `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${key}`;
}

async function getScan(scanId) {
  const meta = await getScanMeta(scanId);
  if (!meta) return json(404, { message: 'Scan not found' });

  if (meta.status === 'ready' || meta.status === 'failed') {
    return scanResponse(meta);
  }

  if (meta.generationId && LUMA_API_KEY) {
    try {
      const res = await fetch(`${LUMA_BASE}/generations/${meta.generationId}`, {
        headers: { 'Authorization': `Bearer ${LUMA_API_KEY}` },
      });
      if (res.ok) {
        const data = await res.json();
        const state = (data.state || '').toLowerCase();
        if (state === 'completed') {
          const outUrl = data.output && data.output[0] && data.output[0].url;
          if (outUrl) {
            const stagedKey = `staged/${meta.propertyId}/${scanId}.png`;
            const stagedUrl = await rehostImage(outUrl, stagedKey);
            const updated = { ...meta, status: 'ready', viewerUrl: stagedUrl, stagedUrl, completedAt: Date.now() };
            await putScanMeta(scanId, updated);
            return scanResponse(updated);
          }
          const updated = { ...meta, status: 'failed', error: 'Luma completed with no image output' };
          await putScanMeta(scanId, updated);
          return scanResponse(updated);
        }
        if (state === 'failed') {
          const updated = { ...meta, status: 'failed', error: data.failure_reason || 'Luma generation failed' };
          await putScanMeta(scanId, updated);
          return scanResponse(updated);
        }
        // queued / processing
        return json(200, { data: { id: scanId, scanId, status: 'processing', viewerUrl: '', previewImageUrl: '', format: 'image', processingStage: 'staging' } });
      }
      console.warn('Luma getScan poll HTTP', res.status);
    } catch (e) {
      console.warn('Luma getScan poll failed:', e.message);
    }
  }

  return scanResponse(meta);
}

async function streamToString(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf-8');
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ── Erik — personal assistant (Gemini) ───────────────────────────────────────

const ASSISTANT_TOOL = {
  functionDeclarations: [
    {
      name: 'create_property',
      description:
        'יוצר טיוטת מודעת דירה להשכרה — רק לאחר שנאספו כל הפרטים החיוניים מהמשתמש ולאחר שהמשתמש אישר במפורש שהפרטים נכונים. אין להמציא פרטים שלא נמסרו.',
      parameters: {
        type: 'object',
        properties: {
          city: { type: 'string', description: 'עיר' },
          neighborhood: { type: 'string', description: 'שכונה (אופציונלי)' },
          street: { type: 'string', description: 'שם הרחוב' },
          streetNumber: { type: 'string', description: 'מספר הבית' },
          rooms: { type: 'number', description: 'מספר חדרים (אפשר חצי, למשל 3.5)' },
          price: { type: 'integer', description: 'מחיר חודשי בשקלים' },
          sizeM2: { type: 'integer', description: 'גודל במ"ר (אם ידוע)' },
          floor: { type: 'integer', description: 'קומה' },
          totalFloors: { type: 'integer', description: 'כמה קומות בבניין (אם ידוע)' },
          condition: { type: 'string', description: 'מצב הדירה: משופצת / חדשה / טובה / דורשת שיפוץ' },
          entryDate: { type: 'string', description: 'תאריך כניסה בטקסט חופשי, למשל "מיידי" או "בעוד חודש"' },
          description: { type: 'string', description: 'תיאור קצר ונעים של הדירה' },
        },
        // Only the three fields actually needed to publish are required, so the
        // model reliably emits create_property as soon as it has them (street,
        // floor etc. are collected when given but never block the call).
        required: ['city', 'rooms', 'price'],
      },
    },
  ],
};

// Erik's full tool surface for the function-calling loop: create_property (the
// landlord publish path) PLUS search_listings (the real DB query). Built lazily
// (SEARCH_LISTINGS_TOOL is a const declared later → avoid the temporal-dead-zone
// crash at module init) so the chat handler can hand the model both tools and run
// the request→functionCall→execute→feed loop.
function assistantToolsFull() {
  return {
    functionDeclarations: [
      ASSISTANT_TOOL.functionDeclarations[0], // create_property
      SEARCH_LISTINGS_TOOL,
      UPDATE_USER_PROFILE_TOOL,
    ],
  };
}

// Required fields to publish a listing. Everything else is optional polish.
const LISTING_REQUIRED = ['price', 'rooms', 'city'];

// Closed enum for the responseSchema extraction (matches the app's catalogue).
const EXTRACT_PROPERTY_TYPE_ENUM = [
  'דירה', 'דירת גן', 'דירת גג', 'פנטהאוז', 'מיני פנטהאוז', 'דופלקס', 'טריפלקס',
  'סטודיו', 'יחידת דיור', 'בית פרטי', 'קוטג', 'מרתף',
];

function missingRequired(fields) {
  return LISTING_REQUIRED.filter((k) => {
    const v = fields[k];
    return v === null || v === undefined || v === '' ||
      (typeof v === 'number' && !(v > 0));
  });
}

async function handleAssistantExtract(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
  const description = (body.description || '').toString().slice(0, 2000);
  const current = (body.currentFields && typeof body.currentFields === 'object')
    ? body.currentFields : {};

  if (!GEMINI_API_KEY) {
    return json(200, { fields: current, missing: missingRequired(current) });
  }

  const sys = 'אתה מחלץ פרטי דירה להשכרה מטקסט חופשי בעברית. price=שכר דירה חודשי '
    + 'בשקלים. אל תמציא ערכים — מה שלא מופיע בטקסט החזר null. description = תקציר '
    + 'נקי וקצר של הדירה. propertyType מתוך הרשימה הסגורה בלבד.';
  const contents = [{
    role: 'user',
    parts: [{ text: `תיאור הדירה: ${description}\nשדות ידועים כבר: ${JSON.stringify(current)}` }],
  }];

  // Controlled generation: a full JSON Schema (with enums for city/propertyType)
  // forces bulletproof structured Hebrew extraction — no fence-stripping, no
  // "almost-JSON" parse failures.
  const responseSchema = {
    type: 'object',
    properties: {
      fields: {
        type: 'object',
        properties: {
          price: { type: 'integer', nullable: true },
          rooms: { type: 'number', nullable: true },
          sizeM2: { type: 'integer', nullable: true },
          city: { type: 'string', nullable: true },
          neighborhood: { type: 'string', nullable: true },
          street: { type: 'string', nullable: true },
          propertyType: { type: 'string', nullable: true, enum: EXTRACT_PROPERTY_TYPE_ENUM },
          entryDate: { type: 'string', nullable: true },
          description: { type: 'string' },
        },
      },
      suggestedTitle: { type: 'string' },
    },
    required: ['fields'],
  };

  try {
    const data = await geminiGenerate(sys, contents, undefined, {
      responseMimeType: 'application/json',
      responseSchema,
      temperature: 0.2,
    });
    const text = (data?.candidates?.[0]?.content?.parts || [])
      .map((p) => p.text || '').join('');
    const parsed = text ? JSON.parse(text) : {};
    const ex = (parsed.fields && typeof parsed.fields === 'object') ? parsed.fields : {};
    // Merge: keep already-known values, fill from extraction (non-null only).
    const fields = { ...current };
    for (const [k, v] of Object.entries(ex)) {
      if (v !== null && v !== undefined && v !== '') fields[k] = v;
    }
    return json(200, {
      fields,
      missing: missingRequired(fields),
      suggestedTitle: (parsed.suggestedTitle || '').toString().slice(0, 80),
    });
  } catch (e) {
    console.warn('assistant/extract', e.message);
    return json(200, { fields: current, missing: missingRequired(current), busy: true });
  }
}

// POST /assistant/explain — the LLM as a data-grounded EXPLAINER.
// The deterministic engine already CHOSE the apartments and produced a Scorecard
// each (fit, dimension breakdown, REAL stats, persona reasons, concerns). Here we
// feed those Scorecards + the persona to Gemini and get back a warm persona-level
// "how I chose these" plus a per-property one-line "why this one, by the numbers".
// HARD RULE enforced via the prompt: ground every claim in the supplied figures,
// NEVER invent prices/stats. We also only return reasons for ids we were given.
async function handleAssistantExplain(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }

  const persona = Array.isArray(body.persona)
    ? body.persona.map((s) => String(s || '').slice(0, 200)).filter(Boolean).slice(0, 20)
    : [];
  const query = (body.query || '').toString().slice(0, 500);

  // Validate + clamp the scorecards. Cap to ~8 to bound the prompt size, drop any
  // without a usable propertyId, and clamp the free-text fields the engine fills.
  const clampStr = (v, n) => (v === null || v === undefined) ? undefined : String(v).slice(0, n);
  const rawCards = Array.isArray(body.scorecards) ? body.scorecards.slice(0, 8) : [];
  const cards = [];
  const ids = [];
  for (const c of rawCards) {
    if (!c || typeof c !== 'object') continue;
    const propertyId = (c.propertyId || '').toString().trim();
    if (!propertyId) continue;
    const dims = Array.isArray(c.dimensions) ? c.dimensions.slice(0, 8).map((d) => ({
      key: clampStr(d?.key, 40),
      label: clampStr(d?.label, 60),
      weightPct: typeof d?.weightPct === 'number' ? d.weightPct : undefined,
      contributionPct: typeof d?.contributionPct === 'number' ? d.contributionPct : undefined,
      stat: clampStr(d?.stat, 160),
      positive: d?.positive !== false,
    })) : [];
    cards.push({
      propertyId,
      fitPct: typeof c.fitPct === 'number' ? c.fitPct : undefined,
      tier: clampStr(c.tier, 60),
      confidence: typeof c.confidence === 'number' ? c.confidence : undefined,
      explanation: clampStr(c.explanation, 300),
      highlights: Array.isArray(c.highlights)
        ? c.highlights.slice(0, 6).map((h) => clampStr(h, 120)).filter(Boolean) : [],
      dimensions: dims,
      personaReasons: Array.isArray(c.personaReasons)
        ? c.personaReasons.slice(0, 6).map((p) => clampStr(p, 160)).filter(Boolean) : [],
      concerns: Array.isArray(c.concerns)
        ? c.concerns.slice(0, 6).map((p) => clampStr(p, 160)).filter(Boolean) : [],
    });
    ids.push(propertyId);
  }

  // Nothing usable, or no model key → degrade to empty (the UI keeps engine reasons).
  if (cards.length === 0 || !GEMINI_API_KEY) {
    return json(200, { howIChose: '', reasons: {} });
  }

  const sys = 'אתה אתי, עוזר חכם. קיבלת את הדירות שכבר נבחרו ע״י מנוע דירוג, כל אחת '
    + 'עם ציון התאמה, פירוק לממדים, וסטטיסטיקות אמת, וגם הפרסונה של המשתמש. כתוב: '
    + '(1) howIChose — פסקה חמה קצרה שמסבירה איך שקללת את הנתונים והפרסונה כדי לבחור '
    + 'את אלו, תוך ציון הממדים/מספרים האמיתיים שהיו מכריעים; (2) reasons — לכל '
    + 'propertyId משפט קצר אחד למה היא מתאימה, מצטט נתון אמיתי מה-scorecard שלה. '
    + 'חוקים: השתמש רק במספרים שמופיעים בקלט; אל תמציא מחירים/סטטיסטיקות; אם נתון '
    + 'חסר — דבר איכותית. החזר JSON תקין בלבד: {"howIChose":"...","reasons":{"id":"..."}}.';

  const contents = [{
    role: 'user',
    parts: [{
      text: `הפרסונה של המשתמש: ${JSON.stringify(persona)}\n`
        + `החיפוש: ${query}\n`
        + `הדירות שנבחרו (Scorecards): ${JSON.stringify(cards)}`,
    }],
  }];

  try {
    const data = await geminiGenerate(sys, contents);
    let text = (data?.candidates?.[0]?.content?.parts || [])
      .map((p) => p.text || '').join('');
    // The model sometimes wraps JSON in ```json fences — strip them, then grab
    // the first JSON object.
    text = text.replace(/```(?:json)?/gi, '').replace(/```/g, '');
    const m = text.match(/\{[\s\S]*\}/);
    const parsed = m ? JSON.parse(m[0]) : {};
    const howIChose = (parsed.howIChose || '').toString().slice(0, 800);
    // Only surface reasons for ids we were actually given (ignore any invented).
    const reasonsIn = (parsed.reasons && typeof parsed.reasons === 'object') ? parsed.reasons : {};
    const reasons = {};
    for (const id of ids) {
      const r = reasonsIn[id];
      if (r !== null && r !== undefined && String(r).trim() !== '') {
        reasons[id] = String(r).slice(0, 300);
      }
    }
    return json(200, { howIChose, reasons });
  } catch (e) {
    console.warn('assistant/explain', e.message);
    return json(200, { howIChose: '', reasons: {} });
  }
}

// The text a listing is embedded from — title + description + tags. The backfill
// script mirrors this so create-path and backfilled rows embed identically.
function listingEmbedText(body) {
  const title = (body.title || [body.street, body.city].filter(Boolean).join(' ') || '')
    .toString();
  const description = (body.description || '').toString();
  const tags = Array.isArray(body.smartTags) && body.smartTags.length
    ? body.smartTags.join(', ')
    : (Array.isArray(body.featureLabels) ? body.featureLabels.join(', ') : '');
  return [title, description, tags].filter(Boolean).join('\n').trim();
}

// One embedding via Gemini's embedContent endpoint. Fail-soft: returns null on
// any problem (quota/network/bad shape) so callers degrade to no-embedding.
// ponytail: text-only — the embedContent contract is unambiguous. Multimodal
// image embedding is a later refinement; images already inform smartTags.
async function geminiEmbed(text) {
  if (!GEMINI_API_KEY || !text) return null;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_EMBED_MODEL}:embedContent?key=${GEMINI_API_KEY}`;
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: `models/${GEMINI_EMBED_MODEL}`,
        content: { parts: [{ text: String(text).slice(0, 8000) }] },
        outputDimensionality: EMBED_DIM,
      }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    const vec = data?.embedding?.values;
    return Array.isArray(vec) && vec.length ? vec : null;
  } catch {
    return null;
  }
}

// Cosine similarity of two equal-length vectors, mapped from [-1,1] to a [0,1]
// score so 0.5 == orthogonal — matching the scorer's neutral-0.5 convention for
// candidates that carry no semantic signal.
function cosineSim(a, b) {
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    const x = a[i];
    const y = b[i];
    dot += x * y;
    na += x * x;
    nb += y * y;
  }
  if (na === 0 || nb === 0) return 0.5;
  const s = dot / (Math.sqrt(na) * Math.sqrt(nb));
  return Math.max(0, Math.min(1, (s + 1) / 2));
}

async function geminiGenerate(systemText, contents, tools, genOverrides) {
  let lastStatus = '';
  for (const model of GEMINI_MODELS) {
    const reqBody = {
      systemInstruction: { parts: [{ text: systemText }] },
      contents,
      generationConfig: {
        temperature: 0.6,
        maxOutputTokens: 480,
        ...(genOverrides || {}),
      },
    };
    // "thinking" config only applies to the 2.5 thinking models; sending it to
    // others can be rejected. Disable it where supported for low latency.
    if (model.includes('2.5')) {
      reqBody.generationConfig.thinkingConfig = { thinkingBudget: 0 };
    }
    if (tools) reqBody.tools = tools;
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`;
    for (let attempt = 0; attempt < 2; attempt++) {
      let res;
      try {
        res = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(reqBody),
        });
      } catch {
        lastStatus = `${model}=net`;
        break; // network error — try the next model
      }
      if (res.ok) return await res.json();
      lastStatus = `${model}=${res.status}`;
      // Overloaded/throttled — one quick retry, then move to the next model.
      if (res.status === 429 || res.status === 500 || res.status === 503) {
        if (attempt === 0) {
          await new Promise((r) => setTimeout(r, 500));
          continue;
        }
        break;
      }
      // Other errors (e.g. 400/404) — this model won't work; try the next.
      break;
    }
  }
  throw new Error(`Gemini busy (${lastStatus})`);
}

async function loadOwnerProperties(uid) {
  try {
    const res = await ddb.send(new QueryCommand({
      TableName: TABLES.properties.name,
      IndexName: TABLES.properties.ownerIndex,
      KeyConditionExpression: '#o = :o',
      ExpressionAttributeNames: { '#o': 'ownerUserId' },
      ExpressionAttributeValues: { ':o': String(uid) },
      Limit: 50,
    }));
    return res.Items || [];
  } catch (e) {
    console.warn('loadOwnerProperties failed:', e.message);
    return [];
  }
}

async function loadUserProfile(uid) {
  try {
    const res = await ddb.send(new GetCommand({ TableName: TABLES.users.name, Key: { id: uid } }));
    return res.Item || null;
  } catch {
    return null;
  }
}

// ── Live user profile (מהיר tier) ────────────────────────────────────────────
// A learned search-preference profile, kept as a nested `searchProfile` map on
// the existing users record (no new table to provision). Written by the
// update_user_profile tool from any assistant touchpoint (Erik / נועה), read
// back into the system prompt so the next turn is personalized.
//
// Allowlist is the trust boundary: the model may ONLY write these keys, so a
// hallucinated field name can't pollute the user record.
const PROFILE_WRITABLE_FIELDS = new Set([
  'household',    // 'family' | 'single' | 'student' | 'couple' — cohort hint
  'cityPref',
  'priceMin',
  'priceMax',
  'vibePref',     // שקט / תוסס / משפחתי / סטודנטיאלי
  'hasPets',
  'hasChildren',
  'wfh',
]);

// Reads the cohort for per-cohort ranking. Prefers an explicit household, else
// infers from vibePref. Returns null when unknown (scorer falls back to global).
function profileCohort(profile) {
  const sp = profile && profile.searchProfile;
  const hh = sp && sp.household && sp.household.value;
  if (hh === 'family' || hh === 'single' || hh === 'student' || hh === 'couple') return hh;
  const vibe = sp && sp.vibePref && sp.vibePref.value;
  if (typeof vibe === 'string') {
    if (vibe.includes('משפח')) return 'family';
    if (vibe.includes('סטודנט')) return 'student';
  }
  return null;
}

// Merge-writes one profile field. Read-modify-write on the whole searchProfile
// map so a missing parent isn't a problem and the field key can be dynamic.
// ponytail: last-writer-wins under concurrent writes — fine, a user's assistant
// turns are serialized; upgrade to a nested UpdateExpression if that changes.
async function saveUserProfileField(uid, field, value, confidence, source) {
  if (!uid || !PROFILE_WRITABLE_FIELDS.has(field)) return false;
  try {
    const current = await loadUserProfile(uid);
    const sp = (current && current.searchProfile) || {};
    sp[field] = {
      value,
      confidence: typeof confidence === 'number' ? Math.max(0, Math.min(1, confidence)) : 0.6,
      source: typeof source === 'string' ? source.slice(0, 40) : 'assistant',
      updatedAt: new Date().toISOString(),
    };
    await ddb.send(new UpdateCommand({
      TableName: TABLES.users.name,
      Key: { id: uid },
      UpdateExpression: 'SET searchProfile = :sp',
      ExpressionAttributeValues: { ':sp': sp },
    }));
    return true;
  } catch (e) {
    console.warn('saveUserProfileField failed:', e.message);
    return false;
  }
}

const UPDATE_USER_PROFILE_TOOL = {
  name: 'update_user_profile',
  description:
    'שמור העדפה קבועה שהמשתמש חשף על עצמו (לא חד-פעמית לשיחה) כדי לשפר חיפושים עתידיים. '
    + 'קרא רק כשהמשתמש מגלה משהו יציב: תקציב, עיר מועדפת, אורח חיים (חיות/ילדים/עבודה מהבית), '
    + 'או סוג משק בית. אל תשאל שאלות רק כדי למלא — שמור מה שנאמר באופן טבעי.',
  parameters: {
    type: 'object',
    properties: {
      field: {
        type: 'string',
        enum: Array.from(PROFILE_WRITABLE_FIELDS),
        description: 'שם ההעדפה',
      },
      value: { description: 'הערך (מחרוזת/מספר/בוליאני)' },
      confidence: { type: 'number', description: 'ביטחון 0..1' },
      source: { type: 'string', description: 'מאיפה נלמד, למשל erik/search' },
    },
    required: ['field', 'value'],
  },
};

// ── search_listings tool — the real DB query behind Erik's function-calling ───
// Shared by the assistant tool-loop. Runs an actual catalogue query against the
// properties table (status='available' GSI) and filters in-Lambda by the model's
// extracted criteria, returning a small set of REAL listings the model is then
// instructed to answer strictly from.
const SEARCH_LISTINGS_TOOL = {
  name: 'search_listings',
  description:
    'מחפש דירות אמיתיות בקטלוג של Rently לפי קריטריונים. החזר תוצאות אמת בלבד — '
    + 'אל תמציא דירות. קרא לפונקציה כשהמשתמש מחפש דירה (עיר/חדרים/תקציב/שכונה).',
  parameters: {
    type: 'object',
    properties: {
      city: { type: 'string', description: 'עיר' },
      neighborhood: { type: 'string', description: 'שכונה' },
      minRooms: { type: 'number', description: 'מינימום חדרים' },
      maxRooms: { type: 'number', description: 'מקסימום חדרים' },
      minPrice: { type: 'integer', description: 'מחיר חודשי מינימלי בשקלים' },
      maxPrice: { type: 'integer', description: 'מחיר חודשי מקסימלי בשקלים' },
      pets: { type: 'boolean', description: 'מתיר חיות מחמד' },
      limit: { type: 'integer', description: 'כמה תוצאות להחזיר (ברירת מחדל 6)' },
    },
  },
};

// Execute the search_listings tool. Returns a compact array of real listings
// (id + the fields the model needs to describe them honestly). Fail-soft → [].
async function runSearchListings(args = {}) {
  const limit = Math.min(Math.max(Number(args.limit) || 6, 1), 12);
  const wantCity = (args.city || '').toString().trim().toLowerCase();
  const wantHood = (args.neighborhood || '').toString().trim().toLowerCase();
  const minRooms = num(args.minRooms);
  const maxRooms = num(args.maxRooms);
  const minPrice = num(args.minPrice);
  const maxPrice = num(args.maxPrice);
  const pets = args.pets === true;

  // Scan the active listings (Phase-1 scale). Query the status GSI for the
  // common active states, then filter in-Lambda by the soft criteria.
  let rows = [];
  for (const status of ['available', 'active']) {
    try {
      const out = await ddb.send(new QueryCommand({
        TableName: TABLES.properties.name,
        IndexName: TABLES.properties.gsi.name,
        KeyConditionExpression: '#s = :s',
        ExpressionAttributeNames: { '#s': TABLES.properties.gsi.pk },
        ExpressionAttributeValues: { ':s': status },
        Limit: 200,
        ScanIndexForward: false,
      }));
      rows = rows.concat(out.Items || []);
    } catch { /* status value may not exist — ignore */ }
  }
  // De-dup by id (a listing could match both status reads in theory).
  const byId = new Map();
  for (const r of rows) if (r && r.id && !byId.has(r.id)) byId.set(r.id, r);
  rows = [...byId.values()];

  const matched = rows.filter((p) => {
    if (p.isActive === false || p.status === 'inactive') return false;
    if (wantCity && String(p.city || '').toLowerCase() !== wantCity) return false;
    if (wantHood && !String(p.neighborhood || '').toLowerCase().includes(wantHood)) return false;
    const rooms = Number(p.rooms);
    if (minRooms !== undefined && rooms < minRooms) return false;
    if (maxRooms !== undefined && rooms > maxRooms) return false;
    const price = Number(p.price);
    if (minPrice !== undefined && price < minPrice) return false;
    if (maxPrice !== undefined && price > maxPrice) return false;
    if (pets) {
      const hay = [
        Array.isArray(p.featureLabels) ? p.featureLabels.join(' ') : '',
        Array.isArray(p.smartTags) ? p.smartTags.join(' ') : '',
        p.description || '',
      ].join(' ').toLowerCase();
      const petFlag = p.features && (p.features.pets === true || p.features.petsAllowed === true);
      if (!petFlag && !/חיות|חיית מחמד|כלב|חתול|pets?/.test(hay)) return false;
    }
    return true;
  }).slice(0, limit);

  return matched.map((p) => ({
    id: String(p.id || ''),
    city: p.city || '',
    neighborhood: p.neighborhood || '',
    address: [p.street, p.streetNumber].filter(Boolean).join(' '),
    rooms: Number(p.rooms) || null,
    price: Number(p.price) || null,
    sizeM2: Number(p.sizeM2) || null,
    floor: p.floor ?? null,
    condition: p.condition || '',
    smartTags: Array.isArray(p.smartTags) ? p.smartTags.slice(0, 10) : [],
    priceBadge: p.priceBadge?.badge || null,
    description: (p.description || '').toString().slice(0, 240),
  }));
}

// POST /listing/ask — per-listing "Ask Rently" Q&A. Given a listingId + question,
// assemble the listing + its enrichment (neighbourhood score, price badge, POIs)
// as the ONLY context, then answer in Hebrew strictly from it. Auth-gated.
async function handleListingAsk(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
  const listingId = (body.listingId || body.propertyId || '').toString().trim();
  const question = (body.question || '').toString().trim().slice(0, 500);
  if (!listingId) return json(400, { message: 'listingId required' });
  if (!question) return json(400, { message: 'question required' });

  let prop = null;
  try {
    const r = await ddb.send(new GetCommand({
      TableName: TABLES.properties.name, Key: { id: listingId },
    }));
    prop = r.Item || null;
  } catch (e) { console.warn('listing/ask get failed:', e.message); }
  if (!prop) return json(404, { message: 'Listing not found' });

  if (!GEMINI_API_KEY) {
    return json(200, { answer: 'העוזר אינו זמין כרגע. נסו שוב מאוחר יותר.', grounded: false });
  }

  // Build a compact, grounded context object — only honest facts about THIS
  // listing + its enrichment. The model is told to answer ONLY from this.
  const context = {
    כתובת: [prop.street, prop.streetNumber, prop.neighborhood, prop.city].filter(Boolean).join(', '),
    עיר: prop.city || null,
    שכונה: prop.neighborhood || null,
    חדרים: Number(prop.rooms) || null,
    מחיר_חודשי: Number(prop.price) || null,
    גודל_מר: Number(prop.sizeM2) || null,
    קומה: prop.floor ?? null,
    סהכ_קומות: prop.totalFloors ?? null,
    מצב: prop.condition || null,
    תאריך_כניסה: prop.entryDate || null,
    סוג_עסקה: prop.transactionType || null,
    תיאור: (prop.description || '').toString().slice(0, 1200),
    תכונות: Array.isArray(prop.featureLabels) ? prop.featureLabels.slice(0, 40) : [],
    תגיות: Array.isArray(prop.smartTags) ? prop.smartTags.slice(0, 20) : [],
    תג_מחיר: prop.priceBadge || null,           // { medianPpm, deltaPct, badge }
    ציון_שכונה: prop.neighborhoodScore || null, // { score, sub }
    גוש: prop.gush || null,
    חלקה: prop.helka || null,
  };

  const sys = 'אתה "Rently" — עוזר שעונה על שאלות לגבי דירה ספציפית אחת בלבד. '
    + 'ענה בעברית, חם ותכליתי. חוק ברזל: השתמש אך ורק במידע שמופיע בהקשר הנתון על '
    + 'הדירה. אסור בהחלט להמציא עובדות, מחירים, מרחקים או פרטים שלא מופיעים בהקשר. '
    + 'אם המידע לא נמצא בהקשר — אמור בכנות שאין לך את המידע הזה על הדירה והצע לפנות '
    + 'לבעל הדירה. אל תשתמש ב-markdown או כוכביות. תשובות קצרות וברורות.';

  const contents = [{
    role: 'user',
    parts: [{
      text: `הקשר הדירה (המקור היחיד למידע):\n${JSON.stringify(context, null, 0)}\n\n`
        + `שאלת המשתמש: ${question}`,
    }],
  }];

  try {
    const data = await geminiGenerate(sys, contents, undefined, {
      temperature: 0.3, maxOutputTokens: 400,
    });
    let answer = (data?.candidates?.[0]?.content?.parts || [])
      .map((p) => p.text || '').join('');
    answer = stripMarkup(answer);
    if (!answer) answer = 'אין לי את המידע הזה על הדירה. כדאי לפנות לבעל הדירה.';
    return json(200, { answer, listingId, grounded: true });
  } catch (e) {
    console.warn('listing/ask error:', e.message);
    return json(200, {
      answer: 'יש עומס קטן כרגע, אפשר לנסות שוב בעוד רגע?',
      listingId, grounded: false,
    });
  }
}

function buildErikSystemPrompt(profile, properties) {
  const name = profile && (profile.name || profile.ownerName)
    ? String(profile.name || profile.ownerName).trim()
    : '';
  const isActive = (p) => p.isActive !== false && p.status !== 'inactive';
  const active = properties.filter(isActive);
  const lines = properties.slice(0, 10).map((p, i) => {
    const addr = [p.street, p.streetNumber, p.city].filter(Boolean).join(' ');
    const price = p.price ? `${p.price} ₪ לחודש` : 'ללא מחיר';
    const st = isActive(p) ? 'פעילה' : 'לא פעילה';
    return `  ${i + 1}. ${addr || 'דירה'} — ${p.rooms || '?'} חדרים, ${price} (${st})`;
  });
  const snapshot = properties.length === 0
    ? 'למשתמש אין עדיין דירות מפורסמות.'
    : `למשתמש ${properties.length} דירות (${active.length} פעילות):\n${lines.join('\n')}`;

  // Learned preferences (written by update_user_profile across sessions), folded
  // back in so the assistant remembers between conversations.
  const sp = profile && profile.searchProfile;
  const profileLine = sp
    ? 'מה שכבר ידוע על המשתמש מהעבר (אל תשאל שוב על אלה): '
        + Object.entries(sp)
            .map(([k, v]) => `${k}=${v && v.value}`)
            .join(', ')
    : '';

  return [
    'אתה "אריק" — אדם אמיתי, חם ונחמד, שעוזר לבעלי דירות לפרסם דירה להשכרה באפליקציית Rently. אתה לא בוט ולא תוכנה — אתה פשוט אריק.',
    'חוק ברזל בסגנון: כתוב עברית טבעית ואנושית לחלוטין, כמו בן אדם שמדבר בטלפון בנעימות. אסור להשתמש בכוכביות (* או **), בסימני עיצוב markdown, בכותרות, ברשימות עם מקפים או נקודות, או באימוג׳ים. לעולם אל תזכיר שאתה בינה מלאכותית, מודל, עוזר ממוחשב או תוכנה. רק טקסט רגיל, חם ואישי.',
    'הקהל שלך הוא בעלי דירות מבוגרים (גיל 65 ומעלה) שאינם בקיאים בטכנולוגיה. דבר עברית פשוטה, ברורה ונעימה, במשפטים קצרים. בלי מילים באנגלית ובלי ז׳רגון.',
    name ? `שם המשתמש הוא ${name}. אפשר לפנות אליו בשמו מדי פעם, בנימוס.` : '',
    'פתיחת השיחה: בקש מבעל הדירה, בחום ובקצרה, לספר בכמה מילים על הדירה — איפה היא, כמה חדרים, וכל מה שירצה. הקשב היטב, וחלץ מהתיאור החופשי כמה שיותר פרטים בעצמך.',
    'אחרי התיאור — שאל רק על הפרטים החיוניים שחסרים, ואחד 2-3 פרטים קצרים בשאלה אחת ידידותית (למשל: "מצוין! נשאר רק לדעת את הקומה והמחיר החודשי — מה הם?"). אל תשאל על מה שכבר נאמר, ואל תמתח את זה לשאלה-אחר-שאלה אם אפשר לקצר.',
    'חשוב מאוד: הקלט מגיע מהמרת דיבור-לטקסט ולעיתים יש בו שגיאות, במיוחד במספרים בעברית. פרש בהיגיון רב: "ארבע 1000" או "ארבע אלף" פירושו 4000; "שלושת אלפים וחמש מאות" פירושו 3500; "אלפיים" פירושו 2000. אם מספר או פרט נשמע לא הגיוני או לא ברור — חזור עליו בעדינות לאישור ("רק לוודא — המחיר הוא ארבעת אלפים שקלים בחודש?") לפני שתמשיך.',
    'מה אתה יכול לעשות: לעזור לפרסם דירה חדשה (לאסוף את הפרטים בשיחה), לתת תמונת מצב על הדירות הקיימות, ולהסביר בפשטות איך האפליקציה עובדת.',
    'שלושת הפרטים שחובה כדי לפרסם: עיר, מספר חדרים, ומחיר חודשי. רחוב ומספר בית, קומה, גודל במ"ר, מצב הדירה ותאריך כניסה משפרים את המודעה אך אינם חוסמים פרסום — אם בעל הדירה מסר אותם קח אותם, אחרת אל תעכב בשבילם. אם לא נמסר תאריך כניסה — הנח "מיידי". כדאי לשאול גם על רחוב וקומה בנימוס, אבל אם המשתמש לא יודע או רוצה לדלג — המשך בלעדיהם.',
    'המטרה החשובה ביותר: לסיים את כל התהליך מהר ובנעימים, תוך דקה עד שתיים. היה תכליתי, חם ומקצועי כמו סוכן שירות מעולה. תשובות קצרות מאוד — משפט אחד או שניים, בלי חזרות מיותרות. ברגע שיש לפחות עיר, מספר חדרים ומחיר, אשר אותם במשפט קצר אחד, ואם המשתמש מאשר — קרא מיד ל-create_property. אל תיתקע בלולאת שאלות: אם נאספו שלושת הפרטים החיוניים, התקדם לפרסום.',
    'כפתורי בחירה (חשוב לחוויית המשתמש!): כשאתה שואל שאלה שיש לה כמה תשובות נפוצות וקצרות — מצב הדירה, תאריך כניסה, מספר חדרים, או אישור כן/לא — הוסף בסוף ההודעה שורה נפרדת בדיוק בפורמט הזה: [[CHOICES: אפשרות1 | אפשרות2 | אפשרות3]] (בין 2 ל-5 אפשרויות קצרות מאוד, מילה-שתיים כל אחת). דוגמאות: למצב הדירה [[CHOICES: משופצת | חדשה | במצב טוב | דורשת שיפוץ]]; לתאריך כניסה [[CHOICES: מיידי | בעוד חודש | גמיש]]; לאישור פרטים [[CHOICES: כן, הכל נכון | יש טעות]]. אל תוסיף שורה כזו כשאין תשובות נפוצות (כתובת, מחיר חופשי). הכפתורים הם תוספת — תמיד כתוב גם את השאלה במילים.',
    'רק כשיש לפחות עיר, מספר חדרים ומחיר — ולאחר שחזרת על הפרטים והמשתמש אישר שהכל נכון — קרא לפונקציה create_property עם כל מה שנמסר (כולל רחוב/קומה אם ידועים). אל תמציא נתונים שלא נמסרו.',
    'חשוב לגבי תמונות: ברגע שהפרטים אושרו — קרא מיד ל-create_property (אל תחכה לתמונה). מיד אחרי הקריאה האפליקציה תציג למשתמש כפתורים להוספת תמונה, ותדרוש לפחות תמונה אחת לפני הפרסום. אתה יכול להזכיר בעדינות "נוסיף תמונה אחת ונפרסם", אבל את התמונה המשתמש מוסיף באפליקציה, לא דרכך.',
    'אם המשתמש מבקש "תמונת מצב" או "מה קורה עם הדירות שלי" — תן סיכום קצר וברור: כמה דירות יש, כמה פעילות.',
    'אל תבטיח דברים שאינך יכול לבצע. אם משהו לא ברור — שאל שוב בעדינות. שמור על תשובות קצרות שקל להקשיב להן.',
    'נתוני המשתמש הנוכחיים (לשימושך בלבד, אל תקריא את כל הרשימה אלא אם ביקשו):',
    snapshot,
    profileLine,
    'כשהמשתמש חושף העדפה קבועה (תקציב, עיר, אורח חיים, סוג משק בית) — קרא ל-update_user_profile כדי לזכור אותה לפעם הבאה.',
  ].filter(Boolean).join('\n');
}

// Strip anything that looks like AI / markdown formatting so Erik reads like a
// person — no asterisks (which TTS would read aloud), code ticks, headings, etc.
function stripMarkup(s) {
  return String(s || '')
    .replace(/\*+/g, '')        // * and ** (bold/italic/bullets)
    .replace(/`+/g, '')          // code ticks
    .replace(/_{2,}/g, '')       // __underline__
    .replace(/^#{1,6}\s*/gm, '') // markdown headings
    .replace(/^\s*[-•]\s+/gm, '')// bullet markers
    .replace(/[ \t]{2,}/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// POST /notifications/register-token → store the caller's FCM device token.
// Keyed by the verified uid so a caller can only register tokens to themselves.
async function handleRegisterToken(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
  const token = (body.token || '').toString().trim();
  if (!token) return json(400, { message: 'token is required' });
  const platform = (body.platform || '').toString().trim() || 'unknown';
  const now = new Date().toISOString();

  let tokens = [];
  try {
    const existing = await ddb.send(new GetCommand({
      TableName: DEVICE_TOKENS_TABLE, Key: { userId: uid },
    }));
    if (existing.Item && Array.isArray(existing.Item.tokens)) {
      tokens = existing.Item.tokens;
    }
  } catch (e) { /* table may not exist yet — first write creates the row */ }

  if (!tokens.includes(token)) tokens.push(token);
  if (tokens.length > 10) tokens = tokens.slice(tokens.length - 10); // bound row size

  await ddb.send(new PutCommand({
    TableName: DEVICE_TOKENS_TABLE,
    Item: { userId: uid, tokens, platform, updatedAt: now },
  }));
  return json(200, { ok: true, count: tokens.length });
}

// GET /notifications → the authenticated caller's notification inbox, newest
// first, plus the count still unread. Query the notifications table by userId
// (pk) with ScanIndexForward=false so the largest createdAt (newest) comes back
// first. Optional ?limit (default 50, max 200). Returns flat, app-ready rows.
async function handleListNotifications(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  const q = event.queryStringParameters || {};
  const limit = Math.min(Math.max(parseInt(q.limit, 10) || 50, 1), 200);

  let items = [];
  try {
    const out = await ddb.send(new QueryCommand({
      TableName: NOTIFICATIONS_TABLE,
      KeyConditionExpression: 'userId = :u',
      ExpressionAttributeValues: { ':u': uid },
      ScanIndexForward: false, // newest (largest createdAt) first
      Limit: limit,
    }));
    items = out.Items || [];
  } catch (e) {
    console.warn('notifications list failed:', e.message);
  }

  const notifications = items.map((it) => ({
    id: it.id,
    type: it.type || '',
    title: it.title || '',
    body: it.body || '',
    data: it.data || {},
    read: it.read === true,
    createdAt: Number(it.createdAt) || 0,
  }));
  const unreadCount = notifications.filter((n) => !n.read).length;
  return json(200, { notifications, unreadCount, count: notifications.length });
}

// POST /notifications/mark-read → mark the caller's notifications read.
// Body: { ids: [...] } marks those ids, or { all: true } marks every unread row.
// Only ever touches rows under the caller's own userId partition. Returns the
// number of rows updated.
async function handleMarkRead(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
  const all = body.all === true;
  const ids = Array.isArray(body.ids) ? body.ids.map((x) => String(x)) : [];
  if (!all && ids.length === 0) {
    return json(400, { message: 'ids[] or all:true required' });
  }

  // Pull the caller's rows so we can map ids → sort keys (createdAt) and skip
  // rows already read. The table is keyed by userId+createdAt, so a write needs
  // the createdAt; we never trust a client-supplied key.
  let rows = [];
  try {
    let lastKey;
    do {
      const out = await ddb.send(new QueryCommand({
        TableName: NOTIFICATIONS_TABLE,
        KeyConditionExpression: 'userId = :u',
        ExpressionAttributeValues: { ':u': uid },
        ExclusiveStartKey: lastKey,
      }));
      rows = rows.concat(out.Items || []);
      lastKey = out.LastEvaluatedKey;
    } while (lastKey && rows.length < 1000);
  } catch (e) {
    console.warn('mark-read query failed:', e.message);
    return json(200, { ok: true, updated: 0 });
  }

  const idSet = new Set(ids);
  const targets = rows.filter((r) =>
    r.read !== true && (all || idSet.has(String(r.id))));

  let updated = 0;
  await Promise.all(targets.map(async (r) => {
    try {
      await ddb.send(new PutCommand({
        TableName: NOTIFICATIONS_TABLE,
        Item: { ...r, read: true },
      }));
      updated += 1;
    } catch (e) {
      console.warn('mark-read write failed:', e.message);
    }
  }));

  return json(200, { ok: true, updated });
}

// POST /match/leads → rank the tenants who liked the caller's properties by the
// same two-sided model the client uses (landlord→tenant fit: affordability +
// shared preferences + deal-breaker gates). Landlord-only.
async function handleMatchLeads(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });

  // 1. Landlord profile (their offer + requirements).
  let landlordProfile = {};
  try {
    const r = await ddb.send(new GetCommand({
      TableName: TABLES.users.name, Key: { id: uid },
    }));
    landlordProfile = r.Item || {};
  } catch { /* no profile yet */ }
  const landlordKeys = keysFor(landlordProfile.importantDetails, LANDLORD_TAG_KEYS);
  const landlordDealKeys = keysFor(landlordProfile.dealBreakers, LANDLORD_TAG_KEYS);

  // Bound the per-property × per-like fan-out so one landlord with many listings
  // and many likes can't fan out into thousands of DynamoDB reads + scored pairs
  // in a single request. Caps: properties scanned, likes pulled per property, and
  // total (tenant, property) pairs scored.
  const MAX_LEAD_PROPERTIES = 50;
  const MAX_LIKES_PER_PROPERTY = 100;
  const MAX_LEAD_PAIRS = 500;

  // 2. The landlord's properties.
  const props = [];
  try {
    const out = await ddb.send(new QueryCommand({
      TableName: TABLES.properties.name,
      IndexName: TABLES.properties.ownerIndex,
      KeyConditionExpression: 'ownerUserId = :o',
      ExpressionAttributeValues: { ':o': uid },
      Limit: MAX_LEAD_PROPERTIES,
    }));
    for (const p of out.Items || []) props.push(p);
  } catch (e) { console.warn('match/leads props', e.message); }
  const cappedProps = props.slice(0, MAX_LEAD_PROPERTIES);

  // 3. For each property, the tenants who liked it (capped at MAX_LEAD_PAIRS total).
  const likeRows = [];
  for (const p of cappedProps) {
    if (likeRows.length >= MAX_LEAD_PAIRS) break;
    try {
      const out = await ddb.send(new QueryCommand({
        TableName: TABLES.property_likes.name,
        IndexName: TABLES.property_likes.gsi.name,
        KeyConditionExpression: 'propertyId = :p',
        ExpressionAttributeValues: { ':p': p.id },
        Limit: MAX_LIKES_PER_PROPERTY,
      }));
      for (const l of out.Items || []) {
        likeRows.push({ like: l, property: p });
        if (likeRows.length >= MAX_LEAD_PAIRS) break;
      }
    } catch { /* skip */ }
  }

  // 4. Score each (tenant, property) pair.
  const profileCache = {};
  const leads = [];
  for (const { like, property } of likeRows) {
    const tenantId = like.tenantId;
    if (!tenantId) continue;
    if (!(tenantId in profileCache)) {
      try {
        const r = await ddb.send(new GetCommand({
          TableName: TABLES.users.name, Key: { id: tenantId },
        }));
        profileCache[tenantId] = r.Item || {};
      } catch { profileCache[tenantId] = {}; }
    }
    const tp = profileCache[tenantId];
    const tenantKeys = keysFor(tp.importantDetails, TENANT_TAG_KEYS);
    const tenantDealKeys = keysFor(tp.dealBreakers, TENANT_TAG_KEYS);

    const { score, reasons, conflicts } = scoreLandlordToTenant({
      budgetMax: Number(tp.budgetMax) || 0,
      price: Number(property.price) || 0,
      tenantKeys, tenantDealKeys, landlordKeys, landlordDealKeys,
    });

    leads.push({
      tenantId,
      tenantName: like.tenantName || tp.name || 'מתעניין',
      propertyId: property.id,
      propertyTitle: property.street || property.city || '',
      score,
      excluded: conflicts.length > 0,
      reasons,
      conflicts,
      likedAt: like.createdAt || null,
    });
  }

  leads.sort((a, b) => b.score - a.score);
  return json(200, { leads, count: leads.length });
}

function scoreLandlordToTenant({ budgetMax, price, tenantKeys, tenantDealKeys, landlordKeys, landlordDealKeys }) {
  let fit = 60;
  const reasons = [];
  const conflicts = [];

  if (budgetMax > 0 && price > 0) {
    const ratio = budgetMax / price;
    if (ratio >= 1.15) { fit += 10; reasons.push('תקציב נוח לשכר הדירה'); }
    else if (ratio >= 1.0) { fit += 5; }
    else { fit -= 18; conflicts.push('התקציב נמוך משכר הדירה'); }
  }
  for (const k of landlordDealKeys) {
    if (tenantKeys.has(k)) fit += 6; else conflicts.push(`חסר: ${k}`);
  }
  for (const k of tenantDealKeys) {
    if (!landlordKeys.has(k)) conflicts.push(`השוכר דורש: ${k}`);
  }
  const shared = [...tenantKeys].filter((k) => landlordKeys.has(k));
  fit += shared.length * 4;
  for (const k of shared) reasons.push(k);

  fit -= conflicts.length * 28;
  return { score: Math.max(0, Math.min(100, Math.round(fit))), reasons, conflicts };
}

// ── Rental contract handlers ───────────────────────────────────────────────
function isContractParty(item, uid) {
  return !!item && (item.landlordUserId === uid || item.tenantUserId === uid);
}

async function contractCreate(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }
  const id = (body.id || '').toString();
  if (!id) return json(400, { message: 'id required' });
  // The creator must be a party; default the landlord to the caller.
  if (body.landlordUserId !== uid && body.tenantUserId !== uid) {
    body.landlordUserId = uid;
  }
  const now = new Date().toISOString();
  const item = { ...body, id, createdAt: body.createdAt || now, updatedAt: now };
  await ddb.send(new PutCommand({ TableName: CONTRACTS_TABLE, Item: item }));

  // Contract sent → notify the OTHER party that a contract awaits their
  // signature. Only when the status is actually 'sent' (a draft saved by the
  // creator shouldn't ping the counterpart). Fire-and-forget; never blocks.
  if ((item.status || '') === 'sent') {
    const other = item.landlordUserId === uid ? item.tenantUserId : item.landlordUserId;
    const fromName = item.landlordUserId === uid
      ? (item.landlordName || 'המשכיר') : (item.tenantName || 'השוכר');
    if (other && other !== uid) {
      await notify(
        other,
        'contract_sent',
        'נשלח אליך חוזה לחתימה 📄',
        `${fromName} שלח/ה אליך הסכם שכירות לעיון וחתימה`,
        { contractId: String(id) },
      );
    }
  }
  return json(200, { item });
}

async function contractGet(event, cid) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  const r = await ddb.send(new GetCommand({
    TableName: CONTRACTS_TABLE, Key: { id: cid },
  }));
  if (!r.Item || !isContractParty(r.Item, uid)) {
    return json(404, { message: 'Not found' });
  }
  return json(200, { item: r.Item });
}

async function contractList(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  const query = event.queryStringParameters || {};
  const MAX_CONTRACT_ITEMS = 200;
  const items = [];
  // Resume from the caller's cursor if provided; otherwise start a fresh sweep.
  let lastKey = parseCursor(query.cursor);
  do {
    const out = await ddb.send(new ScanCommand({
      TableName: CONTRACTS_TABLE,
      FilterExpression: 'landlordUserId = :u OR tenantUserId = :u',
      ExpressionAttributeValues: { ':u': uid },
      ExclusiveStartKey: lastKey,
    }));
    for (const it of out.Items || []) items.push(it);
    lastKey = out.LastEvaluatedKey;
  } while (lastKey && items.length < MAX_CONTRACT_ITEMS);
  items.sort((a, b) => (b.updatedAt || '').localeCompare(a.updatedAt || ''));
  // Hand back a cursor so a caller with >MAX_CONTRACT_ITEMS contracts can page on.
  return json(200, {
    items,
    hasMore: !!lastKey,
    lastKey: lastKey ? encodeURIComponent(JSON.stringify(lastKey)) : null,
  });
}

async function contractSign(event, cid) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  let sig = {};
  try { sig = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }
  const role = (sig.role || '').toString();
  if (role !== 'landlord' && role !== 'tenant') {
    return json(400, { message: 'invalid role' });
  }
  const r = await ddb.send(new GetCommand({
    TableName: CONTRACTS_TABLE, Key: { id: cid },
  }));
  const item = r.Item;
  if (!item || !isContractParty(item, uid)) {
    return json(404, { message: 'Not found' });
  }
  // The caller may only sign the role they actually are.
  if (role === 'landlord' && item.landlordUserId !== uid) {
    return json(403, { message: 'not the landlord of this contract' });
  }
  if (role === 'tenant' && item.tenantUserId !== uid) {
    return json(403, { message: 'not the tenant of this contract' });
  }
  sig.signerUserId = uid; // the backend records who actually signed
  if (role === 'landlord') item.landlordSignature = sig;
  else item.tenantSignature = sig;
  if (item.landlordSignature && item.tenantSignature) item.status = 'signed';
  item.updatedAt = new Date().toISOString();
  await ddb.send(new PutCommand({ TableName: CONTRACTS_TABLE, Item: item }));

  // Contract signed → tell the OTHER party that this signer just signed.
  // Fire-and-forget; never blocks the response. The body distinguishes a
  // fully-signed contract from one still awaiting the counterpart's signature.
  const other = role === 'landlord' ? item.tenantUserId : item.landlordUserId;
  const signerName = (sig.signerName
    || (role === 'landlord' ? item.landlordName : item.tenantName) || 'הצד השני');
  if (other && other !== uid) {
    const fullySigned = item.status === 'signed';
    await notify(
      other,
      'contract_signed',
      'החוזה נחתם ✅',
      fullySigned
        ? `${signerName} חתם/ה — ההסכם נחתם על ידי שני הצדדים`
        : `${signerName} חתם/ה על ההסכם — נותרה חתימתך`,
      { contractId: String(cid) },
    );
  }
  return json(200, { item });
}

async function contractCancel(event, cid) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  const r = await ddb.send(new GetCommand({
    TableName: CONTRACTS_TABLE, Key: { id: cid },
  }));
  const item = r.Item;
  if (!item || item.landlordUserId !== uid) {
    return json(403, { message: 'forbidden' });
  }
  item.status = 'cancelled';
  item.updatedAt = new Date().toISOString();
  await ddb.send(new PutCommand({ TableName: CONTRACTS_TABLE, Item: item }));
  return json(200, { item });
}

// The disclaimer the AI draft must always preserve. Kept here so the server can
// re-append it even if the model drops it.
const LEASE_DISCLAIMER =
  'מסמך זה הוא תבנית כללית מטעם עורכי הדין של Rently ואינו תחליף לייעוץ ' +
  'משפטי. מומלץ להיוועץ בעורך/ת דין לפני חתימה.';

// The standard residential-lease boilerplate the app offers when the client did
// not send its own draft text. Plain Hebrew, NOT legal advice; placeholders are
// filled from the request facts.
const STANDARD_LEASE_TEMPLATE =
  'הסכם שכירות למגורים — מטעם עורכי הדין של Rently. הצדדים: {{landlordName}} ' +
  '("המשכיר") ו-{{tenantName}} ("השוכר"). הנכס: {{propertyTitle}}, למגורים בלבד. ' +
  'תקופה: {{durationMonths}} חודשים. דמי שכירות חודשיים: {{monthlyRent}} ש"ח, מראש ' +
  'עד ה-10 בכל חודש. פיקדון: {{deposit}} ש"ח. השוכר ישמור על הנכס וישא בתשלומי ' +
  'השוטפים; המשכיר ימסור נכס ראוי למגורים ויתקן ליקויים מהותיים. הפרה יסודית שלא ' +
  'תוקנה תוך 14 יום תזכה בביטול וסעדים על פי דין. כפוף לדיני מדינת ישראל. ' + LEASE_DISCLAIMER;

// POST /contract/improve — the LLM as a careful lease EDITOR. It takes the draft
// lease text + the property/match facts and returns an improved, tailored Hebrew
// draft. HARD RULES (enforced via the prompt): edit/clarify only, never invent
// figures or legal nonsense, keep it a residential lease, and keep the disclaimer.
async function handleContractImprove(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }

  const str = (v, n) => (v === null || v === undefined ? '' : String(v).slice(0, n));
  const num = (v) => (typeof v === 'number' && isFinite(v) ? Math.round(v) : 0);

  const facts = {
    landlordName: str(body.landlordName, 120) || 'המשכיר',
    tenantName: str(body.tenantName, 120) || 'השוכר',
    propertyTitle: str(body.propertyTitle, 200) || 'הנכס נשוא ההסכם',
    monthlyRent: num(body.monthlyRent),
    deposit: num(body.deposit),
    durationMonths: num(body.durationMonths) || 12,
  };

  let draft = str(body.contractText, 8000).trim();
  if (!draft) {
    draft = STANDARD_LEASE_TEMPLATE
      .replaceAll('{{landlordName}}', facts.landlordName)
      .replaceAll('{{tenantName}}', facts.tenantName)
      .replaceAll('{{propertyTitle}}', facts.propertyTitle)
      .replaceAll('{{durationMonths}}', String(facts.durationMonths))
      .replaceAll('{{monthlyRent}}', String(facts.monthlyRent))
      .replaceAll('{{deposit}}', String(facts.deposit));
  }

  // No model key → degrade to returning the draft unchanged (the UI keeps it).
  if (!GEMINI_API_KEY) return json(200, { improved: draft });

  const sys =
    'אתה עורך חוזים זהיר. קיבלת טיוטת הסכם שכירות למגורים בעברית ועובדות אמת על ' +
    'הנכס והעסקה. שפר ונסח מחדש את ההסכם כך שיהיה ברור, מסודר וערוך בסעיפים ' +
    'ממוספרים, ומותאם לנתונים שניתנו. ' +
    'חוקים נוקשים: (1) השתמש אך ורק בעובדות שסופקו — אל תמציא מחירים, תאריכים, ' +
    'שמות, סכומים או צדדים; (2) אל תמציא "סעיפים משפטיים" מופרכים; הישאר בגדר ' +
    'הסכם שכירות למגורים סטנדרטי וסביר; (3) כתוב בעברית בלבד; (4) שמור בסוף את ' +
    'משפט ההסתייגות במדויק: "' + LEASE_DISCLAIMER + '". ' +
    'החזר את טקסט ההסכם המשופר בלבד, ללא הקדמות וללא הסברים.';

  const contents = [{
    role: 'user',
    parts: [{
      text:
        'עובדות אמת (אין לסטות מהן):\n' + JSON.stringify(facts) +
        '\n\nטיוטת ההסכם לשיפור:\n' + draft,
    }],
  }];

  try {
    const data = await geminiGenerate(sys, contents, undefined, {
      temperature: 0.3, // low — fidelity to the supplied facts over creativity
      maxOutputTokens: 2048, // a full lease is longer than the default cap
    });
    let text = (data?.candidates?.[0]?.content?.parts || [])
      .map((p) => p.text || '').join('').trim();
    text = text.replace(/```(?:\w+)?/g, '').replace(/```/g, '').trim();
    if (!text) text = draft; // empty model output → keep the draft
    // Belt-and-braces: guarantee the disclaimer survived.
    if (!text.includes('אינו תחליף לייעוץ')) {
      text = `${text}\n\n${LEASE_DISCLAIMER}`;
    }
    return json(200, { improved: text.slice(0, 12000) });
  } catch (e) {
    console.warn('contract/improve', e.message);
    return json(200, { improved: draft });
  }
}

async function handleAssistant(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  if (!GEMINI_API_KEY) {
    return json(200, { reply: 'העוזר האישי אינו זמין כרגע. אנא נסו שוב מאוחר יותר.', propertyDraft: null });
  }

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }

  const messages = Array.isArray(body.messages) ? body.messages.slice(-20) : [];
  if (messages.length === 0) return json(400, { message: 'messages required' });

  // נועה — the tenant apartment-search assistant. Separate warm persona, no
  // owner-property load and no listing-creation tool. Additive: the landlord
  // "Erik" flow below is untouched.
  if (body.mode === 'tenant_search') {
    return await handleTenantSearchChat(messages, uid);
  }

  const [properties, profile] = await Promise.all([
    loadOwnerProperties(uid),
    loadUserProfile(uid),
  ]);
  const systemText = buildErikSystemPrompt(profile, properties) + '\n' + GROUNDING_RULE;
  const contents = messages
    .filter((m) => m && typeof m.text === 'string' && m.text.trim())
    .map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: String(m.text).slice(0, 2000) }],
    }));

  try {
    const result = await runAssistantToolLoop(systemText, contents, assistantToolsFull(), uid);
    let reply = stripMarkup(result.reply);
    let suggestions = [];
    const cm = /\[\[\s*CHOICES?\s*:\s*([^\]]+)\]\]/i.exec(reply);
    if (cm) {
      suggestions = cm[1].split('|').map((s) => s.trim()).filter(Boolean).slice(0, 5);
      reply = reply.replace(cm[0], '').trim();
    }
    if (!reply && result.propertyDraft) {
      reply = 'הכנתי טיוטה של הדירה! עכשיו רק צריך להוסיף תמונה אחת של הדירה — '
        + 'אפשר לצלם עכשיו או לבחור תמונה מהטלפון, ואז נפרסם.';
    }
    if (!reply) reply = 'סליחה, לא הבנתי. אפשר לחזור על זה שוב?';
    return json(200, {
      reply,
      propertyDraft: result.propertyDraft,
      suggestions,
      listings: result.listings,
    });
  } catch (e) {
    console.warn('assistant error:', e.message);
    return json(200, {
      reply: 'סליחה, יש כרגע עומס קטן על העוזר. אפשר לנסות שוב בעוד רגע?',
      propertyDraft: null,
    });
  }
}

// Strict grounding instruction shared by the tool-using chats: the model must
// answer ONLY from search_listings results — never invent listings/prices.
const GROUNDING_RULE =
  'חוק ברזל לגבי דירות: כשמדובר בדירות זמינות לחיפוש — ענה אך ורק על סמך התוצאות '
  + 'שמחזירה הפונקציה search_listings. אסור בהחלט להמציא דירות, כתובות, מחירים או '
  + 'פרטים. אם אין תוצאות — אמור בכנות שלא נמצאו דירות מתאימות כרגע. כשהמשתמש מחפש '
  + 'דירה (עיר/חדרים/תקציב/שכונה/חיות) — קרא ל-search_listings לפני שאתה עונה.';

// ── Gemini function-calling loop ─────────────────────────────────────────────
// Runs the request → functionCall → execute → feed-result loop (ReAct). Executes
// search_listings against the real DB and feeds results back; create_property is
// terminal (returned as a draft for the app to publish). Capped at MAX_HOPS so a
// misbehaving model can't loop forever. Returns { reply, propertyDraft, listings }.
const MAX_TOOL_HOPS = 5;
async function runAssistantToolLoop(systemText, contents, tools, uid = null) {
  const convo = contents.slice();
  let propertyDraft = null;
  let listings = [];

  for (let hop = 0; hop < MAX_TOOL_HOPS; hop++) {
    const data = await geminiGenerate(systemText, convo, [tools]);
    const cand = data.candidates && data.candidates[0];
    const parts = (cand && cand.content && cand.content.parts) || [];

    let textOut = '';
    const calls = [];
    for (const p of parts) {
      if (p.text) textOut += p.text;
      if (p.functionCall && p.functionCall.name) calls.push(p.functionCall);
    }

    // create_property is terminal — capture the draft and stop the loop.
    const createCall = calls.find((c) => c.name === 'create_property');
    if (createCall) {
      propertyDraft = createCall.args || {};
      return { reply: textOut, propertyDraft, listings };
    }

    // Non-terminal tools: search_listings (feeds real listings back) and
    // update_user_profile (persists a revealed preference). Both get a
    // functionResponse so the model continues grounded.
    const toolCalls = calls.filter(
      (c) => c.name === 'search_listings' || c.name === 'update_user_profile',
    );
    if (toolCalls.length === 0) {
      // No tool call → the model answered directly. Done.
      return { reply: textOut, propertyDraft, listings };
    }

    convo.push({ role: 'model', parts: parts.filter((p) => p.functionCall) });
    const responseParts = [];
    for (const call of toolCalls) {
      if (call.name === 'update_user_profile') {
        const a = call.args || {};
        const saved = await saveUserProfileField(
          uid, a.field, a.value, a.confidence, a.source,
        );
        responseParts.push({
          functionResponse: {
            name: 'update_user_profile',
            response: { saved },
          },
        });
        continue;
      }
      const results = await runSearchListings(call.args || {});
      listings = results; // expose the latest tool result to the app
      responseParts.push({
        functionResponse: {
          name: 'search_listings',
          response: { results, count: results.length },
        },
      });
    }
    convo.push({ role: 'user', parts: responseParts });
  }

  // Hit the hop cap — make a final no-tools pass so the model summarises what it
  // already found instead of returning empty.
  try {
    const data = await geminiGenerate(systemText, convo);
    const cand = data.candidates && data.candidates[0];
    const parts = (cand && cand.content && cand.content.parts) || [];
    const reply = parts.map((p) => p.text || '').join('');
    return { reply, propertyDraft, listings };
  } catch {
    return { reply: '', propertyDraft, listings };
  }
}

// ── נועה — tenant apartment-search chat (warm, separate from Erik) ────────────
// Conversational layer only: helps a renter describe what they want; the app
// runs the actual catalogue search and shows result cards. No listing tool.
async function handleTenantSearchChat(messages, uid = null) {
  const systemText = buildTenantSearchSystemPrompt() + '\n' + GROUNDING_RULE;
  const contents = messages
    .filter((m) => m && typeof m.text === 'string' && m.text.trim())
    .map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: String(m.text).slice(0, 2000) }],
    }));
  // Search + profile-write tool surface (no create_property for tenants). Sharing
  // update_user_profile with Erik is what connects the touchpoints to one store.
  const tools = { functionDeclarations: [SEARCH_LISTINGS_TOOL, UPDATE_USER_PROFILE_TOOL] };
  try {
    const result = await runAssistantToolLoop(systemText, contents, tools, uid);
    let reply = stripMarkup(result.reply);
    let suggestions = [];
    const cm = /\[\[\s*CHOICES?\s*:\s*([^\]]+)\]\]/i.exec(reply);
    if (cm) {
      suggestions = cm[1].split('|').map((s) => s.trim()).filter(Boolean).slice(0, 5);
      reply = reply.replace(cm[0], '').trim();
    }
    if (!reply) reply = 'ספר לי עוד קצת על מה שאתה מחפש, ואני כבר אדאג לדייק 🙂';
    return json(200, {
      reply, suggestions, propertyDraft: null, listings: result.listings,
    });
  } catch (e) {
    console.warn('tenant assistant error:', e.message);
    return json(200, {
      reply: 'יש עומס קטן כרגע על העוזר, ננסה שוב בעוד רגע?',
      suggestions: [],
      propertyDraft: null,
    });
  }
}

function buildTenantSearchSystemPrompt() {
  return [
    'את "אתי" — בן אדם אמיתי, חמה ונחמדה, שעוזרת לאנשים למצוא דירה להשכרה באפליקציית Rently. את לא בוט ולא תוכנה — את פשוט אתי. לעולם אל תזכירי שאת בינה מלאכותית, מודל או תוכנה.',
    'סגנון: עברית טבעית, חמה ומשוחררת, כמו חברה שמבינה עניין. משפטים קצרים (שורה־שתיים), בלי רובוטיות, בלי ז׳רגון, בלי כוכביות או markdown. מותר אימוג׳י אחד פה ושם, בטעם.',
    'המטרה: להבין מה האדם באמת מחפש ולגרום לו להרגיש שמקשיבים לו. תני לו לספר על עצמו במילים שלו — אזור, תקציב, כמה חדרים, אורח חיים, חיות מחמד, קרבה לעבודה או לתחבורה, ומה חשוב לו.',
    'אל תרוצי ישר להציע — קודם שקפי בחום מה הבנת, ושאלי שאלה אחת קצרה ועדינה כדי להכיר אותו יותר (לא חקירה, שאלה אחת בכל פעם). כשכבר יש מספיק מידע (אזור או תקציב או חדרים, או בקשה ברורה) — אמרי בחום שאת בודקת מה הכי מתאים, כי האפליקציה תציג לו את הדירות. אל תמציאי דירות, כתובות או מחירים ספציפיים בעצמך.',
    'הקלט עלול להיות מסורבל או לא ברור — פרשי בהיגיון, וכשמשהו לא ברור שאלי בעדינות.',
    'כפתורי בחירה: כשיש שאלה עם כמה תשובות נפוצות קצרות (תקציב, מספר חדרים, אווירת שכונה, כן/לא) — הוסיפי בסוף שורה נפרדת בדיוק בפורמט: [[CHOICES: אפשרות1 | אפשרות2 | אפשרות3]] (2 עד 5 אפשרויות קצרות מאוד). תמיד כתבי גם את השאלה במילים. אל תוסיפי שורה כזו כשאין תשובות נפוצות.',
    'תשובות קצרות מאוד, חמות ולעניין. בלי הבטחות שאי אפשר לקיים.',
  ].join('\n');
}

// Mints a short-lived Gemini Live ephemeral token for a real-time voice session.
// The token is locked server-side to Erik's model + persona + create_property
// tool, so the client connects straight to the Live WebSocket without ever
// seeing the API key and can't repurpose the session. Single use, valid 30 min,
// must connect within 1 min. Stateless — nothing about the user is stored.
async function handleAssistantLiveToken(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  if (!GEMINI_LIVE_API_KEY) {
    return json(503, { message: 'Live assistant not configured.' });
  }

  let properties = [];
  let profile = null;
  try {
    [properties, profile] = await Promise.all([
      loadOwnerProperties(uid),
      loadUserProfile(uid),
    ]);
  } catch { /* context is best-effort */ }
  const systemText = buildErikSystemPrompt(profile, properties);

  const now = Date.now();
  const expireTime = new Date(now + 30 * 60 * 1000).toISOString();
  const newSessionExpireTime = new Date(now + 60 * 1000).toISOString();

  const reqBody = {
    uses: 1,
    expireTime,
    newSessionExpireTime,
    bidiGenerateContentSetup: {
      model: GEMINI_LIVE_MODEL,
      generationConfig: { responseModalities: ['AUDIO'] },
      systemInstruction: { parts: [{ text: systemText }] },
      tools: [ASSISTANT_TOOL],
      inputAudioTranscription: {},
      outputAudioTranscription: {},
    },
  };

  try {
    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1alpha/auth_tokens?key=${GEMINI_LIVE_API_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(reqBody),
      },
    );
    const data = await r.json().catch(() => ({}));
    if (!r.ok) {
      console.warn('live-token error:', r.status, JSON.stringify(data).slice(0, 300));
      return json(502, { message: 'Could not start live session.' });
    }
    const name = data.name || '';
    return json(200, {
      token: name,
      model: GEMINI_LIVE_MODEL,
      expireTime,
    });
  } catch (e) {
    console.warn('live-token exception:', e.message);
    return json(502, { message: 'Could not start live session.' });
  }
}

// Gemini natural voice for Erik's reply. Returns base64 PCM (L16 mono) + the
// sample rate; the client wraps it in a WAV header and plays it.
const TTS_MODEL = process.env.GEMINI_TTS_MODEL || 'gemini-2.5-flash-preview-tts';
// "Kore" is the verified-working warm voice for Hebrew on this API key.
const TTS_VOICE = process.env.GEMINI_TTS_VOICE || 'Kore';

async function handleAssistantTts(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  if (!GEMINI_API_KEY) return json(200, { audio: null });

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON.' }); }
  const text = stripMarkup((body.text || '').toString()).slice(0, 1200);
  if (!text) return json(400, { message: 'text required' });
  const voice = (body.voice || TTS_VOICE).toString();

  const reqBody = {
    contents: [{ parts: [{ text }] }],
    generationConfig: {
      responseModalities: ['AUDIO'],
      speechConfig: {
        voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } },
      },
    },
  };
  try {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${TTS_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
    let res;
    for (let attempt = 0; attempt < 2; attempt++) {
      res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(reqBody),
      });
      if (res.ok) break;
      if (res.status === 429 || res.status === 500 || res.status === 503) {
        await new Promise((r) => setTimeout(r, 600 * (attempt + 1)));
        continue;
      }
      break;
    }
    if (!res || !res.ok) return json(200, { audio: null });
    const data = await res.json();
    const part = data.candidates?.[0]?.content?.parts?.[0];
    const inline = part && part.inlineData;
    if (!inline || !inline.data) return json(200, { audio: null });
    let sampleRate = 24000;
    const m = /rate=(\d+)/.exec(inline.mimeType || '');
    if (m) sampleRate = parseInt(m[1], 10);
    return json(200, { audio: inline.data, sampleRate });
  } catch (e) {
    console.warn('tts error:', e.message);
    return json(200, { audio: null });
  }
}

// ── Admin company broadcast ──────────────────────────────────────────────────
// POST /admin/broadcast — fan a single rich push out to EVERY user's devices.
//   Gate: caller must be the notif-admin (callerIsNotifAdmin) → else 403.
//   Body: { title, body, imageUrl?, template?, data? }.
//   Action: SCAN rently-device-tokens for every user's tokens, then send via
//   FCM v1 one message per token (chunked into batches so a huge user base
//   doesn't fire tens of thousands of requests at once). The message carries a
//   rich notification (image, high-priority Android channel, iOS mutable-content
//   so the Notification Service Extension can attach the image). Dead tokens
//   (UNREGISTERED / invalid) are pruned from their owning user's row. Persists
//   one history row to rently-broadcasts. Returns { sent, failed }.

// Read every user's device tokens (full-table SCAN, paginated). Returns
// [{ userId, tokens:[...] }, ...]. Best-effort: returns what it gathered.
async function scanAllDeviceTokens() {
  const rows = [];
  let lastKey;
  do {
    const out = await ddb.send(new ScanCommand({
      TableName: DEVICE_TOKENS_TABLE,
      ProjectionExpression: 'userId, tokens',
      ExclusiveStartKey: lastKey,
    }));
    for (const it of (out.Items || [])) {
      if (it && it.userId && Array.isArray(it.tokens) && it.tokens.length) {
        rows.push({ userId: it.userId, tokens: it.tokens });
      }
    }
    lastKey = out.LastEvaluatedKey;
  } while (lastKey);
  return rows;
}

async function handleAdminBroadcast(event) {
  if (!callerIsNotifAdmin(event)) return json(403, { message: 'Forbidden' });

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }

  const title = (body.title || '').toString().trim();
  const bodyText = (body.body || '').toString().trim();
  const imageUrl = body.imageUrl ? String(body.imageUrl) : undefined;
  const template = body.template ? String(body.template) : undefined;
  if (!title && !bodyText) {
    return json(400, { message: 'title or body is required' });
  }
  // Bound payload so a too-large title/body/data doesn't silently fail EVERY
  // per-token send (FCM rejects >4KB). And only allow https images (no SSRF/junk).
  if (title.length > 120 || bodyText.length > 300) {
    return json(400, { message: 'title (≤120) or body (≤300) too long' });
  }
  if (imageUrl && !/^https:\/\//i.test(imageUrl)) {
    return json(400, { message: 'imageUrl must be an https URL' });
  }
  if (body.data && JSON.stringify(body.data).length > 2048) {
    return json(400, { message: 'data payload too large' });
  }

  const token = await fcmAccessToken();
  if (!token) return json(503, { message: 'Push is not configured.' });

  // Build the FCM v1 data map (strings only). template is folded in so a tapped
  // push routes the same way the app expects.
  const dataStr = {};
  if (body.data && typeof body.data === 'object') {
    for (const [k, v] of Object.entries(body.data)) {
      if (v === undefined || v === null) continue;
      dataStr[k] = typeof v === 'string' ? v : String(v);
    }
  }
  if (template) dataStr.template = template;
  dataStr.type = 'broadcast'; // always — never let client data override tap-routing

  // The rich Android/iOS envelope shared by every token's message.
  const androidNotification = {
    channel_id: 'rently_default',
    notification_priority: 'PRIORITY_MAX',
    default_sound: true,
  };
  if (imageUrl) androidNotification.image = imageUrl;
  const baseMessage = {
    notification: { title: title || '', body: bodyText || '' },
    data: dataStr,
    android: { priority: 'high', notification: androidNotification },
    apns: {
      payload: { aps: { 'mutable-content': 1, sound: 'default' } },
      ...(imageUrl ? { fcm_options: { image: imageUrl } } : {}),
    },
  };

  // Gather all tokens, remembering which user each belongs to so we can prune
  // dead ones from the right row.
  let userRows = [];
  try {
    userRows = await scanAllDeviceTokens();
  } catch (e) {
    console.warn('broadcast: token scan failed:', e.message);
    return json(500, { message: 'Could not load recipients.' });
  }
  const targets = []; // { userId, deviceToken }
  for (const r of userRows) {
    for (const t of r.tokens) targets.push({ userId: r.userId, deviceToken: t });
  }

  let sent = 0;
  let failed = 0;
  const deadByUser = new Map(); // userId → Set(deadToken)

  // Chunk so we never open more than CHUNK concurrent FCM connections at once
  // (handles >500 tokens / huge user bases without a thundering herd).
  const CHUNK = 500;
  for (let i = 0; i < targets.length; i += CHUNK) {
    const slice = targets.slice(i, i + CHUNK);
    const results = await Promise.all(slice.map(async ({ userId, deviceToken }) => {
      try {
        const resp = await fetch(FCM_SEND_URL, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ message: { ...baseMessage, token: deviceToken } }),
        });
        if (resp.ok) return true;

        const errBody = await resp.json().catch(() => ({}));
        const status = errBody?.error?.status || '';
        const fcmErr = errBody?.error?.details?.find?.(
          (d) => d['@type']?.includes('FcmError'))?.errorCode || '';
        const isDead = resp.status === 404
          || status === 'UNREGISTERED' || status === 'NOT_FOUND'
          || fcmErr === 'UNREGISTERED' || fcmErr === 'INVALID_ARGUMENT'
          || (resp.status === 400 && /registration token|not a valid fcm/i
            .test(JSON.stringify(errBody)));
        if (isDead) {
          if (!deadByUser.has(userId)) deadByUser.set(userId, new Set());
          deadByUser.get(userId).add(deviceToken);
        } else {
          console.warn('broadcast: send failed', resp.status,
            JSON.stringify(errBody).slice(0, 200));
        }
        return false;
      } catch (e) {
        console.warn('broadcast: send exception:', e.message);
        return false;
      }
    }));
    for (const ok of results) { if (ok) sent += 1; else failed += 1; }
  }

  // Prune dead tokens from each affected user's row (best-effort).
  await Promise.all([...deadByUser.entries()].map(([userId, set]) =>
    pruneUserTokens(userId, set)));

  // Persist the broadcast to history (best-effort; never fail the send on this).
  const id = crypto.randomUUID();
  const createdAt = Date.now();
  try {
    await ddb.send(new PutCommand({
      TableName: BROADCASTS_TABLE,
      Item: {
        id,
        title,
        body: bodyText,
        imageUrl: imageUrl || '',
        template: template || '',
        sentCount: sent,
        failedCount: failed,
        createdAt,
        createdBy: callerUidOf(event) || '',
      },
    }));
  } catch (e) {
    console.warn('broadcast: history persist failed:', e.message);
  }

  return json(200, { sent, failed });
}

// GET /admin/broadcasts — recent broadcast history, newest-first, for the admin
// console. Gated to the notif-admin. The table is keyed only by id, so we SCAN
// and sort by createdAt in-Lambda (the volume is tiny: one row per broadcast).
async function handleAdminListBroadcasts(event) {
  if (!callerIsNotifAdmin(event)) return json(403, { message: 'Forbidden' });
  const q = event.queryStringParameters || {};
  const limit = Math.min(Math.max(parseInt(q.limit, 10) || 50, 1), 200);

  let items = [];
  try {
    let lastKey;
    do {
      const out = await ddb.send(new ScanCommand({
        TableName: BROADCASTS_TABLE,
        ExclusiveStartKey: lastKey,
      }));
      items = items.concat(out.Items || []);
      lastKey = out.LastEvaluatedKey;
    } while (lastKey && items.length < 2000);
  } catch (e) {
    console.warn('broadcasts list failed:', e.message);
  }

  const broadcasts = items
    .map((it) => ({
      id: it.id,
      title: it.title || '',
      body: it.body || '',
      imageUrl: it.imageUrl || '',
      template: it.template || '',
      sentCount: Number(it.sentCount) || 0,
      failedCount: Number(it.failedCount) || 0,
      createdAt: Number(it.createdAt) || 0,
      createdBy: it.createdBy || '',
    }))
    .sort((a, b) => b.createdAt - a.createdAt)
    .slice(0, limit);

  return json(200, { broadcasts, count: broadcasts.length });
}
