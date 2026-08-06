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
  BatchGetCommand,
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
import { scoreListings, round3 } from './lib/ranking.mjs';
import {
  querySignals, cohortFromSignals, resolveCohortFrom,
  COHORT_KEYS, COHORT_DEFS, isListingVisibleToCohort,
} from './lib/cohort.mjs';
import { passesEligibility } from './lib/eligibility.mjs';
// Consumption / personalisation layer — pure helpers for the interaction store
// (implicit-feedback score), item-item collaborative filtering, and the LightGBM
// training-data join. DB reads stay here; the math lives in ./lib/cf.mjs.
import { implicitScore, cfRecommend, trainingRowsFrom } from './lib/cf.mjs';
// Phase-1 learned-ranker serving hook (DORMANT until a model is provisioned) +
// Phase-0 deterministic A/B bucketing. RANK_FEATURE_ORDER is the canonical
// feature-key list the client, trainer and scorer all agree on.
import {
  RANK_FEATURE_ORDER, loadModel, scoreWithModel, blendScore, modelAlpha,
  rankFeaturesFrom,
} from './lib/model_scorer.mjs';
import { userEmbeddingFrom, cosine01 } from './lib/user_embedding.mjs';
import { variantFor } from './lib/ab.mjs';
// Landlord subscription paywall — the shared, unit-tested engine + its DynamoDB
// store adapter. All lifecycle logic lives in the engine; the router only wires
// it to DynamoDB (ddb) + Morning + HTTP (see the billing section below).
import { createEngine } from './lib/subscription_engine.mjs';
import { createDdbStore } from './lib/ddb_store.mjs';
// Morning (Green Invoice) / Grow API client — hosted payment, token charge,
// document creation, webhook verification.
import * as morning from './lib/morning.mjs';
// Ranking A/B: control (variant 0) always sees the pure linear score; treatment
// (variant 1) gets the model blend WHEN a model is loaded. With no model both
// variants are identical (pure linear) — the experiment is a no-op until then.
const RANK_EXPERIMENT = 'rank_model_v1';

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
// Node Lambda that turns a Gaussian-splat .ply/.spz upload into a compact .ksplat
// the in-app viewer streams fast (defaults to the deployed function name).
const SPLAT_CONVERT_FN = process.env.SPLAT_CONVERT_FN || 'rentch-splat-convert';
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

// OpenAI Realtime — powers אתי's live voice conversation. The key stays here; the
// client only ever gets a short-lived ephemeral token (see createRealtimeSession).
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || '';
const OPENAI_REALTIME_MODEL =
  process.env.OPENAI_REALTIME_MODEL || 'gpt-realtime-mini';
// 'marin' — one of the two newest realtime voices, deliberately NOT alloy/echo/
// verse (the voices ChatGPT users instantly recognize). Warm, female-leaning.
const OPENAI_REALTIME_VOICE = process.env.OPENAI_REALTIME_VOICE || 'marin';
// Text chat model for אתי (tenant search). Runs on OpenAI so the warm reply is
// isolated from the shared Gemini free-tier quota. Falls back to Gemini when the
// OpenAI account is unfunded/over-quota (see handleTenantSearchChat).
const OPENAI_CHAT_MODEL = process.env.OPENAI_CHAT_MODEL || 'gpt-5.4-mini';
// Natural human text-to-speech for אתי + עזרא (real voice, not robotic device TTS).
const OPENAI_TTS_MODEL = process.env.OPENAI_TTS_MODEL || 'gpt-4o-mini-tts-2025-12-15';
const OPENAI_STT_MODEL = process.env.OPENAI_STT_MODEL || 'gpt-4o-transcribe';
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
  // Mutual matches — created by the landlord on accept, SYNCED so the tenant sees
  // the chat. Query by tenantUid (tenant's list) or landlordUid (landlord's list).
  matches:         { name: `${TABLE_PREFIX}matches`,         gsi: { name: 'tenantUid-createdAt', pk: 'tenantUid', filterKey: 'tenantUid' }, indexes: { landlord: { name: 'landlordUid-createdAt', pk: 'landlordUid', filterKey: 'landlordUid' } } },
  app_state:       { name: `${TABLE_PREFIX}app-state`,       gsi: null },
  // Broker tools cloud store — one row per (broker, data-type), id = `{uid}:{name}`.
  // Owner-scoped via the dedicated /broker_data route (never the generic handler).
  broker_data:     { name: `${TABLE_PREFIX}broker-data`,     gsi: null },
  // Per-user accumulated persona (pk: id == uid). One row per user, upserted by
  // the client with confidence-scored facts for personalisation + targeting.
  // Owner-scoped: a caller may only read/write their own row (see below).
  persona:         { name: `${TABLE_PREFIX}persona`,         gsi: null },
  // Consumption layer — one accumulated row per (user,property) engagement.
  // Base key: pk userId(S) + sk propertyId(S). GSI propertyId-userId (pk
  // propertyId, sk userId, projection ALL) backs item-item CF: given a property,
  // find every OTHER user who engaged it. Not exposed via the generic handler —
  // written/read only by the owner-scoped /interactions + /reco/cf routes.
  interactions:    { name: `${TABLE_PREFIX}interactions`,    gsi: { name: 'propertyId-userId', pk: 'propertyId', filterKey: 'propertyId' } },
};

// One row per user (pk: userId) holding the set of their FCM device tokens, so
// the scheduled tour-notifier Lambda can push "your 3D tour is ready" to every
// device a landlord owns. Created out-of-band (see deploy checklist).
const DEVICE_TOKENS_TABLE = `${TABLE_PREFIX}device-tokens`;

// Landlord subscriptions — one row per landlord, pk id = Firebase uid. Owner-
// scoped: only reachable via the dedicated /billing/* routes (NEVER the generic
// table handler), so it isn't in TABLES. Created out-of-band by
// aws/billing-setup.sh. Holds status/plan/period/token/card/dunning fields.
const SUBSCRIPTIONS_TABLE = `${TABLE_PREFIX}subscriptions`;
// Issued invoices (Morning documents), pk id = invoiceId, GSI ownerUserId-
// issuedAt so a landlord can list their own. Also out-of-band.
const INVOICES_TABLE = `${TABLE_PREFIX}invoices`;
const INVOICES_OWNER_INDEX = 'ownerUserId-issuedAt';

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

// Load the service account JSON once. Prefer the FCM_SERVICE_ACCOUNT_JSON env
// var (a secret lives in Lambda env, and survives code-only deploys that would
// otherwise drop a bundled file from the zip — the exact failure that silently
// disabled all push). Fall back to a bundled file next to this module.
// Absent/garbage → fcmSA stays null and all sends become no-ops.
let fcmSA = null;
try {
  const raw = process.env.FCM_SERVICE_ACCOUNT_JSON
    || readFileSync(new URL('./fcm-service-account.json', import.meta.url), 'utf8');
  fcmSA = JSON.parse(raw);
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
          // Explicit iOS alert + high-priority immediate delivery (don't rely on
          // FCM's implicit fill): a backgrounded/closed app renders the banner.
          apns: {
            headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
            payload: {
              aps: {
                alert: { title: title || '', body: body || '' },
                sound: 'default',
                badge: 1,
              },
            },
          },
          android: {
            priority: 'high',
            // Pin the channel explicitly (matches the app's rently_default channel)
            // so a backgrounded push always displays, even if the manifest default-
            // channel meta-data is missing on some build.
            notification: { channel_id: 'rently_alerts', sound: 'default' },
          },
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

    if (tableKey === 'matches') {
      // A mutual match was created (landlord accepted). Push the TENANT so they
      // know a chat is now open — the #1 gap: they used to only hear about it once
      // the landlord actually messaged.
      const tenant = (body.tenantUid || '').toString();
      if (!tenant || tenant === senderUid) return;
      let propTitle = '';
      try {
        const prop = await ddb.send(new GetCommand({
          TableName: TABLES.properties.name, Key: { id: body.propertyId },
        }));
        propTitle = (prop.Item && (prop.Item.street || prop.Item.city)) || '';
      } catch { /* ignore */ }
      await notify(
        tenant,
        'match',
        'יש לך התאמה! 🎉',
        propTitle
            ? `בעל הדירה ב${propTitle} אישר — אפשר להתחיל לשוחח`
            : 'בעל הדירה אישר — אפשר להתחיל לשוחח',
        { matchId: String(body.id || ''), propertyId: String(body.propertyId || '') },
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

  // 1b) Audience suggestions — best-effort, only when the landlord gave us
  // something to reason from (a note and/or declared cohorts) and the client
  // didn't already supply suggestions. Fail-soft: a missing field just stays out.
  tasks.push((async () => {
    try {
      if (Array.isArray(body.audienceSuggested)) return; // client already populated
      const declaredCohorts = Array.isArray(body.audienceCohorts) ? body.audienceCohorts : [];
      const note = (body.audienceNote || '').toString();
      if (!declaredCohorts.length && !note.trim()) return; // nothing to reason from
      const sug = await suggestAudienceCohorts({ listing: body, declaredCohorts, note });
      if (sug && sug.length) body.audienceSuggested = sug;
    } catch (e) { console.warn('enrich: audienceSuggested failed:', e.message); }
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

// ── Audience cohort suggestion ───────────────────────────────────────────────
// Reasons over the 14-cohort taxonomy + the listing's own data + the cohorts the
// landlord already declared + their free-text note, and proposes ADDITIONAL
// relevant cohorts (never repeating a declared one), each with a 0-1 confidence
// and a one-line Hebrew reason. Pure best-effort: returns [] on any GPT/parse
// error or a missing key, so it NEVER blocks a publish or 500s a request.
// Runs on OpenAI (GPT) — same model as אתי — NOT Gemini.
// Shared by POST /audience/suggest and enrichListingOnCreate.
async function suggestAudienceCohorts({ listing, declaredCohorts, note }) {
  if (!OPENAI_API_KEY) return [];
  const l = (listing && typeof listing === 'object') ? listing : {};
  const declared = (Array.isArray(declaredCohorts) ? declaredCohorts : [])
    .filter((c) => COHORT_KEYS.includes(c));
  const declaredSet = new Set(declared);
  const noteText = (note || '').toString().slice(0, 500);

  // Compact listing summary for the model (only the fields that inform targeting).
  const feats = Array.isArray(l.featureLabels) ? l.featureLabels
    : (Array.isArray(l.features) ? l.features
      : (Array.isArray(l.smartTags) ? l.smartTags : (Array.isArray(l.tags) ? l.tags : [])));
  const summary = {
    price: num(l.price), rooms: num(l.rooms), sizeM2: num(l.sizeM2),
    city: (l.city || '').toString().slice(0, 60),
    neighborhood: (l.neighborhood || '').toString().slice(0, 60),
    propertyType: (l.propertyType || '').toString().slice(0, 40),
    condition: (l.condition || '').toString().slice(0, 40),
    features: (Array.isArray(feats) ? feats : []).slice(0, 30)
      .map((x) => String(x).slice(0, 40)),
  };

  // The taxonomy, with a short Hebrew definition per key, so the model reasons
  // over a closed, well-defined set (the enum then hard-limits the output keys).
  const taxonomy = COHORT_KEYS.map((k) => `- ${k}: ${COHORT_DEFS[k]}`).join('\n');
  const sys =
    'אתה יועץ שיווק לדירות להשכרה בישראל. יש לך טקסונומיה סגורה של 14 קהלי יעד. '
    + 'בהינתן נתוני דירה, הקהלים שבעל הדירה כבר בחר, והערה חופשית שלו — הצע קהלים '
    + 'נוספים ורלוונטיים שהוא לא בחר. אל תחזור על קהל שכבר נבחר. השתמש אך ורק '
    + 'במפתחות מהרשימה (בשדה cohort). לכל הצעה: confidence בין 0 ל-1 ו-reason משפט '
    + 'קצר אחד בעברית המנמק מדוע הדירה מתאימה לקהל הזה, מבוסס על הנתונים בלבד. אל '
    + 'תמציא עובדות. החזר עד 5 הצעות, מהחזק לחלש. '
    + 'החזר אך ורק אובייקט JSON תקין בפורמט '
    + '{"suggestions":[{"cohort":"<key>","confidence":<0-1>,"reason":"<טקסט>"}]} '
    + 'ללא טקסט נוסף וללא סימוני markdown.'
    + `\n\nהקהלים:\n${taxonomy}`;
  const userMsg =
    `נתוני הדירה: ${JSON.stringify(summary)}\n`
    + `קהלים שבעל הדירה כבר בחר: ${JSON.stringify(declared)}\n`
    + `הערה חופשית של בעל הדירה: ${noteText || '(אין)'}`;

  try {
    const text = await openaiChat(sys, [{ role: 'user', text: userMsg }]);
    // Strip an accidental ```json fence the model might add, then parse.
    const clean = (text || '')
      .replace(/^\s*```(?:json)?/i, '').replace(/```\s*$/, '').trim();
    const parsed = clean ? JSON.parse(clean) : {};
    const raw = Array.isArray(parsed.suggestions) ? parsed.suggestions : [];
    const seen = new Set();
    const out = [];
    for (const s of raw) {
      const cohort = String(s?.cohort || '');
      if (!COHORT_KEYS.includes(cohort)) continue; // only valid keys
      if (declaredSet.has(cohort) || seen.has(cohort)) continue; // ADDITIONAL only, dedupe
      let confidence = Number(s?.confidence);
      if (!Number.isFinite(confidence)) confidence = 0.5;
      confidence = Math.max(0, Math.min(1, confidence)); // clamp 0-1
      const reason = String(s?.reason || '').trim().slice(0, 200);
      seen.add(cohort);
      out.push({ cohort, confidence, reason });
    }
    out.sort((a, b) => b.confidence - a.confidence); // strongest first
    return out.slice(0, 5); // cap
  } catch (e) {
    console.warn('suggestAudienceCohorts failed:', e.message);
    return [];
  }
}

// POST /audience/suggest — auth-gated wrapper around suggestAudienceCohorts.
// Never 500s the client: a Gemini/parse failure degrades to { suggestions: [] }.
async function handleAudienceSuggest(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
  const listing = (body.listing && typeof body.listing === 'object') ? body.listing : {};
  const declaredCohorts = Array.isArray(body.declaredCohorts) ? body.declaredCohorts : [];
  const note = (body.note || '').toString();
  const suggestions = await suggestAudienceCohorts({ listing, declaredCohorts, note });
  return json(200, { suggestions });
}

// POST /profile/fields — a direct client→searchProfile write, so a real tenant
// who never chats with the assistant can still populate the profile the
// per-listing eligibility gate reads. Body: { fields: { <field>: <value>, ... } }.
// Only allowlisted (PROFILE_WRITABLE_FIELDS) keys are written; the rest are
// silently ignored. Confidence 0.9 / source 'profile'. Never 500s: fail-soft to
// { saved: 0 } on any error.
async function handleProfileFields(event) {
  try {
    const uid = callerUidOf(event);
    if (!uid) return json(401, { message: 'Authentication required.' });
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
    const fields = (body.fields && typeof body.fields === 'object') ? body.fields : {};
    // Optional provenance: declared syncs stay source='profile' (default, and the
    // only source a `must` rule may hide on); inferred syncs pass source='search'.
    const source = (typeof body.source === 'string' && body.source) ? body.source : 'profile';
    const confidence = Number.isFinite(Number(body.confidence)) ? Number(body.confidence) : 0.9;
    const saved = await saveUserProfileFields(uid, fields, confidence, source);
    return json(200, { saved });
  } catch (e) {
    console.warn('handleProfileFields failed:', e.message);
    return json(200, { saved: 0 });
  }
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

    // SCALE: send in PARALLEL, not one-await-at-a-time. 300 sequential FCM sends
    // (~100ms each) were ~30s — blowing the 20s Lambda timeout and blocking the
    // publish response. Promise.all collapses that to ~one round-trip. (Proper
    // fix is async off the request path via a stream/queue — infra follow-up.)
    const sends = [];
    for (const s of searches) {
      const targetUid = String(s.userId || '');
      if (!targetUid || targetUid === ownerUid) continue;
      if (notified.has(targetUid)) continue;
      if (s.alertsOn === false) continue;
      if (!savedSearchMatches(s, property)) continue;
      notified.add(targetUid);
      const name = (s.name || 'החיפוש השמור שלך').toString().slice(0, 60);
      const price = Number(property.price) > 0 ? ` · ${Number(property.price)} ₪` : '';
      sends.push(notify(
        targetUid,
        'saved_search',
        'דירה חדשה שמתאימה לך 🔔',
        `${propTitle}${price} — תואם ל"${name}"`,
        { propertyId: propId, savedSearchId: String(s.id || ''), deepLink: `rently://property/${propId}` },
      ));
      if (notified.size >= 300) break; // cap fan-out per create (anti-flood)
    }
    await Promise.all(sends);
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
const OWNED_TABLES = new Set([
  'properties', 'messages', 'users', 'persona',
  // Likes/matches carry tenant PII and drive push — writes must be authenticated
  // and identity-stamped so a caller can't forge a lead or spoof a match.
  'property_likes', 'matches',
]);

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
  // The liker IS the caller; the landlord accepting IS the caller.
  else if (tableKey === 'property_likes') body.tenantId = uid;
  // 'matches' is NOT stamped here — unlike every other table, the caller
  // isn't always the same party (a tenant self-creating a request thread
  // names a landlordUid that ISN'T them). See the POST handler: it stamps
  // landlordUid = uid itself, but only once it has verified which of the
  // two creation paths this actually is.
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

const html = (status, body) => ({
  statusCode: status,
  headers: {
    'Content-Type': 'text/html; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'public, max-age=300',
  },
  body,
});

const _esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const SHARE_BASE = process.env.SHARE_BASE ||
  'https://g7b9nx11sk.execute-api.us-east-1.amazonaws.com/prod';
const APP_STORE_URL = process.env.APP_STORE_URL ||
  'https://apps.apple.com/il/app/rently/id6773088152';

// Public share page: rich OpenGraph tags so WhatsApp/Telegram/social render a
// banner (photo + title + price) when the listing link is sent.
// Social link-preview crawlers that need the OG tags (all anonymous).
const _OG_CRAWLERS =
  /facebookexternalhit|whatsapp|twitterbot|telegrambot|slackbot|linkedinbot|discordbot|pinterest|redditbot|embedly|skypeuripreview|googlebot|bingbot|opengraph|vkshare|whatsapp\/|line-podcast/i;

async function propertyOgPage(id, ua = '') {
  // ANTI-SCRAPE: the rich card is served ONLY to link-preview crawlers. A real
  // person (or a scraper) that opens the URL is bounced straight into the app,
  // so the page can't be used to harvest listings. Combined with the random,
  // unguessable 8-char ids (≈2.8e12 space → no enumeration), the endpoint leaks
  // nothing beyond the single card the sharer chose to send.
  // A real person (not a link-preview crawler) opened the URL.
  const isPerson = ua && !_OG_CRAWLERS.test(ua);
  // The app is published on the App Store only (iOS). iOS visitors get the
  // app-open interstitial with an App Store fallback; everyone else (Android /
  // desktop) falls through to the rich card below — never a broken store redirect.
  const isIOS = /iphone|ipad|ipod/i.test(ua);
  if (isPerson && isIOS) {
    // Try to open the APP at this apartment (rently://property/:id). If the app
    // is installed the page is backgrounded → we CANCEL the fallback (via the
    // visibility/pagehide events, far more reliable than a timer delta). If it
    // isn't installed the page stays visible → after ~1.2s we send them to the
    // App Store product page. A manual button covers browsers that block the
    // auto-launch.
    const jid = JSON.stringify(String(id));
    const store = JSON.stringify(APP_STORE_URL);
    const page = `<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>פתיחת הדירה ב-Rently…</title>
<style>body{font-family:-apple-system,system-ui,Arial,sans-serif;margin:0;background:#0f1220;color:#fff;display:flex;min-height:100vh;align-items:center;justify-content:center;text-align:center}
.b{max-width:420px;padding:24px}h1{font-size:21px;margin:0 0 6px}
a.btn{display:inline-block;background:#14D3DC;color:#04222b;font-weight:800;text-decoration:none;padding:14px 30px;border-radius:999px;margin-top:16px}
a.lnk{display:block;color:#8b93a7;font-size:13px;margin-top:16px;text-decoration:underline}</style>
</head><body><div class="b"><h1>פותחים את הדירה באפליקציה…</h1>
<p style="color:#c9cfe0">אם לא נפתח אוטומטית, לחצו:</p>
<a class="btn" href="rently://property/${_esc(id)}" onclick="return go(event)">פתח ב-Rently</a>
<a class="lnk" href="${_esc(APP_STORE_URL)}">אין לכם את האפליקציה? התקינו מ-App Store</a>
<script>
var ID=${jid},STORE=${store},DEEP='rently://property/'+ID,t;
function toStore(){if(!document.hidden)window.location=STORE;}
function go(e){if(e&&e.preventDefault)e.preventDefault();clearTimeout(t);t=setTimeout(toStore,1200);window.location=DEEP;return false;}
document.addEventListener('visibilitychange',function(){if(document.hidden)clearTimeout(t);});
window.addEventListener('pagehide',function(){clearTimeout(t);});
go();
</script></div></body></html>`;
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
      body: page,
    };
  }

  let p = null;
  try {
    const r = await ddb.send(new GetCommand({
      TableName: TABLES.properties.name, Key: { id },
    }));
    p = r.Item || null;
  } catch { /* fall through to a generic card */ }

  const shareUrl = `${SHARE_BASE}/p/${encodeURIComponent(id)}`;
  const img = p
    ? ((Array.isArray(p.imageUrls) && p.imageUrls[0]) ||
       (Array.isArray(p.media) && p.media[0] && p.media[0].url) || '')
    : '';
  const isSale = p && p.transactionType === 'sale';
  const priceTxt = p && p.price
    ? `₪${Number(p.price).toLocaleString('en-US')}${isSale ? '' : ' לחודש'}`
    : '';
  const title = p
    ? `${p.address || p.city || 'דירה'}${priceTxt ? ' · ' + priceTxt : ''}`
    : 'Rently';
  const parts = [];
  if (p) {
    if (p.rooms) parts.push(`${p.rooms} חדרים`);
    if (p.sizeM2) parts.push(`${p.sizeM2} מ"ר`);
    if (p.city) parts.push(p.city);
  }
  const desc = parts.join(' · ') || 'דירות להשכרה ולמכירה ב-Rently';

  const t = _esc(title), d = _esc(desc), i = _esc(img), u = _esc(shareUrl);
  const body = `<!doctype html><html lang="he" dir="rtl"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${t}</title>
<meta property="og:type" content="website">
<meta property="og:site_name" content="Rently">
<meta property="og:title" content="${t}">
<meta property="og:description" content="${d}">
${i ? `<meta property="og:image" content="${i}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">` : ''}
<meta property="og:url" content="${u}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${t}">
<meta name="twitter:description" content="${d}">
${i ? `<meta name="twitter:image" content="${i}">` : ''}
<style>body{font-family:-apple-system,system-ui,Arial,sans-serif;margin:0;background:#0f1220;color:#fff;text-align:center}
.card{max-width:520px;margin:0 auto;padding:22px}
.card img.hero{width:100%;aspect-ratio:16/10;object-fit:cover;border-radius:18px;display:block}
h1{font-size:20px;margin:18px 12px 6px}p{color:#c9cfe0;margin:0 12px 22px}
a.btn{display:inline-block;background:#14D3DC;color:#04222b;font-weight:800;text-decoration:none;padding:14px 30px;border-radius:999px}</style>
</head><body><div class="card">
${i ? `<img class="hero" src="${i}" alt="">` : ''}
<h1>${t}</h1><p>${d}</p>
<a class="btn" href="${_esc(APP_STORE_URL)}">פתח ב-Rently</a>
</div></body></html>`;
  return html(200, body);
}

export const handler = async (event) => {
  try {
    // Internal async worker: the AI-360 generation (gpt-image-2) takes ~50s —
    // over the API-Gateway limit — so POST /panorama/:id/ai-generate self-invokes
    // this function as an async Event that does the slow work + writes the result.
    if (event && event.op === 'aiGenerate' && event.jobId) {
      return await runAiGenerate(event.jobId);
    }

    // Lambda Function URL (public, no authorizer) → ONLY the public OpenGraph
    // share page is served here; every other route still requires the
    // authenticated API Gateway. This keeps the Function URL from exposing any
    // data/mutations.
    if (!event.httpMethod && event.requestContext?.http) {
      const segs = (event.rawPath || '/').split('/').filter(Boolean);
      if (event.requestContext.http.method === 'GET' &&
          segs[0] === 'p' && segs[1]) {
        const ua = event.headers?.['user-agent'] ||
          event.headers?.['User-Agent'] || '';
        return await propertyOgPage(decodeURIComponent(segs[1]), ua);
      }
      return json(404, { message: 'Not found' });
    }

    const method = event.httpMethod;
    const path = event.path || '';
    const segments = path.split('/').filter(Boolean);

    if (method === 'OPTIONS') return json(200, {});

    // ── Public share page (OpenGraph banner for WhatsApp/social) ────────────
    // GET /p/:id → HTML with og:image/title/description. No auth (the WhatsApp
    // crawler is anonymous).
    if (segments[0] === 'p' && segments[1] && method === 'GET') {
      // Pass the UA so a real person gets the app-open interstitial (crawlers get
      // the OG card). API-GW header keys can be any case.
      const ua = event.headers?.['user-agent'] || event.headers?.['User-Agent'] || '';
      return await propertyOgPage(decodeURIComponent(segments[1]), ua);
    }

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
      // POST /panorama/:id/ai-generate → async gpt-image-2 → generated 360
      if (method === 'POST' && jobId && segments[2] === 'ai-generate') {
        return await aiGeneratePanorama(jobId, event);
      }
      // POST /panorama/:id/enhance → async pole-fill + 360-wrap on an existing pano
      if (method === 'POST' && jobId && segments[2] === 'enhance') {
        return await enhancePanorama(jobId, event);
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
    // POST /notifications/test → push a real test notification to the CALLER's own
    // device (self-serve "am I actually getting phone pushes?" check).
    if (segments[0] === 'notifications' && segments[1] === 'test'
        && method === 'POST') {
      const uid = callerUidOf(event);
      if (!uid) return json(401, { message: 'auth required' });
      const tokens = await getUserTokens(uid);
      const sent = await sendPushToUser(uid, {
        title: 'בדיקת התראה 🔔 Rently',
        body: 'ההתראות עובדות! זו התראת אמת מהשרת ✅',
        data: { type: 'test' },
      });
      // Also drop it in the inbox.
      await notify(uid, 'test', 'בדיקת התראה 🔔 Rently',
          'ההתראות עובדות! זו התראת אמת מהשרת ✅', { type: 'test' });
      // Diagnostics so the client can tell the user exactly what happened.
      return json(200, { ok: true, tokensRegistered: tokens.length, pushed: sent });
    }

    // ── Broker tools cloud sync ─────────────────────────────────────────────
    // GET/PUT /broker_data/{name} — a broker's clients/leads/deals/viewings/
    // exclusivity/branding blob. The row id is ALWAYS `{callerUid}:{name}`,
    // derived server-side from the verified identity — a caller can NEVER read
    // or write another broker's data. Fully private CRM in the cloud.
    if (segments[0] === 'broker_data') {
      const uid = callerUidOf(event);
      if (!uid) return json(401, { message: 'Unauthorized' });
      const name = (segments[1] || '').replace(/[^a-zA-Z0-9_]/g, '');
      if (!name) return json(400, { message: 'name required' });
      const rowId = `${uid}:${name}`;
      const T = TABLES.broker_data.name;
      if (method === 'GET') {
        const out = await ddb.send(new GetCommand({ TableName: T, Key: { id: rowId } }));
        return json(200, out.Item || { id: rowId, data: null, updatedAt: null });
      }
      if (method === 'PUT' || method === 'POST') {
        const body = event.body ? JSON.parse(event.body) : {};
        await ddb.send(new PutCommand({ TableName: T, Item: {
          id: rowId, uid, data: body.data ?? null, updatedAt: body.updatedAt || '',
        }}));
        return json(200, { ok: true });
      }
      return json(405, { message: 'Method not allowed' });
    }

    // ── Two-sided match ranking (landlord's leads) ──────────────────────────
    if (segments[0] === 'match' && segments[1] === 'leads' && method === 'POST') {
      return await handleMatchLeads(event);
    }

    // ── Audience cohort suggestion (landlord targeting) ─────────────────────
    // POST /audience/suggest → given a draft listing + the cohorts the landlord
    // already picked + a free-text note, Gemini proposes ADDITIONAL relevant
    // cohorts (each with confidence + one-line Hebrew reason). Fail-soft → [].
    if (segments[0] === 'audience' && segments[1] === 'suggest' && method === 'POST') {
      return await handleAudienceSuggest(event);
    }

    // ── Direct tenant profile write (feeds the eligibility gate) ─────────────
    // POST /profile/fields → { fields: {<field>:<value>,...} }. Writes allowlisted
    // keys to the caller's users.searchProfile (conf 0.9, source 'profile') so
    // non-chatting tenants aren't hidden from gated listings. Returns { saved:n }.
    if (segments[0] === 'profile' && segments[1] === 'fields' && method === 'POST') {
      return await handleProfileFields(event);
    }

    // ── Ranker impression log (LightGBM training data) ──────────────────────
    // POST /search/log → append per-impression feature vectors + outcomes.
    if (segments[0] === 'search' && segments[1] === 'log' && method === 'POST') {
      return await handleSearchLog(event);
    }

    // POST /search/outcome → append ONE labeled row (click/like/…/skip) that a
    // later join pairs with its impression row by (searchId, propertyId).
    if (segments[0] === 'search' && segments[1] === 'outcome' && method === 'POST') {
      return await handleSearchOutcome(event);
    }

    // ── Semantic kNN candidate source (step 3) ──────────────────────────────
    // POST /search/knn → embed query text, kNN against S3 Vectors, return the
    // matching listings. Dormant → {results:[]} unless embeddings+index are on.
    if (segments[0] === 'search' && segments[1] === 'knn' && method === 'POST') {
      return await handleSearchKnn(event);
    }

    // ── Consumption layer: interaction store + CF + ML export ────────────────
    // POST /interactions → record/accumulate a per-(user,property) interaction
    // and recompute its implicit score. → { ok, score }. Fail-soft.
    if (segments[0] === 'interactions' && !segments[1] && method === 'POST') {
      return await handleInteraction(event);
    }
    // POST /reco/cf → item-item co-engagement recommendations. → { items:[...] }.
    if (segments[0] === 'reco' && segments[1] === 'cf' && method === 'POST') {
      return await handleRecoCf(event);
    }
    // POST /user/embedding → (re)compute + store the caller's user vector (the
    // action-weighted mean of the embeddings of listings they engaged with).
    if (segments[0] === 'user' && segments[1] === 'embedding' && method === 'POST') {
      return await handleUserEmbedding(event);
    }
    // POST /listing/audience → LOOK-ALIKE tenants for a landlord's own listing.
    if (segments[0] === 'listing' && segments[1] === 'audience' && method === 'POST') {
      return await handleListingAudience(event);
    }
    // GET /ml/export → LightGBM training set (admin-only). → { rows, count }.
    if (segments[0] === 'ml' && segments[1] === 'export' && method === 'GET') {
      return await handleMlExport(event);
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
    // ── Landlord subscription billing (Morning/Green Invoice + Grow) ─────────
    // JWT-gated app routes: /billing/subscription, /billing/checkout.
    if (segments[0] === 'billing') {
      return await handleBilling(event, segments, method);
    }
    // NO-AUTH provider callbacks, isolated on their own path so they never touch
    // the JWT /billing proxy: POST /hooks/morning (IPN, HMAC-verified) and
    // GET /hooks/return (post-payment redirect page).
    if (segments[0] === 'hooks') {
      return await handleHooks(event, segments, method);
    }

    if (segments[0] === 'contract' && segments[1] === 'improve' && method === 'POST') {
      return await handleContractImprove(event);
    }

    // ── Erik personal assistant ─────────────────────────────────────────────
    if (segments[0] === 'assistant' && method === 'POST') {
      // POST /assistant/tts → Gemini natural voice for a reply (audio bytes).
      if (segments[1] === 'tts') return await handleAssistantTts(event);
      // POST /assistant/transcribe → Whisper STT: base64 audio → Hebrew text.
      // Far more accurate than the device recogniser AND silent (no beeps).
      if (segments[1] === 'transcribe') return await handleTranscribe(event);
      // POST /assistant/extract → Etti intent-extraction engine: free text →
      // { hard_constraints, soft_weights, inferred_persona } for the ranking.
      if (segments[1] === 'extract') return await handleEttiExtract(event);
      // POST /assistant/live-token → ephemeral token for the real-time Live voice
      // session (the API key never leaves the backend).
      if (segments[1] === 'live-token') return await handleAssistantLiveToken(event);
      // POST /assistant/realtime/session → ephemeral OpenAI Realtime session for
      // אתי's live GPT voice. The OpenAI key stays server-side; the client gets a
      // short-lived client_secret only.
      if (segments[1] === 'realtime' && segments[2] === 'session') {
        return await createRealtimeSession(event);
      }
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
        // Persona is private: a user may only read THEIR OWN row, never list.
        if (tableKey === 'persona') {
          if (!callerUid || id !== callerUid) {
            return json(id ? 403 : 401, { message: 'Forbidden' });
          }
          return await getOne(table, id);
        }
        // Public aggregate counts (no row data leaked) — how many likes/views a
        // listing has. Enabled only for the analytics tables.
        if (id === 'count') {
          if (tableKey !== 'property_likes' && tableKey !== 'property_views') {
            return json(404, { message: 'Not found' });
          }
          return await countItems(table, query);
        }
        if (id) {
          // Likes/matches have GUESSABLE ids (like_<pid>_<tenant>,
          // match-<pid>~<tenant>). getOne would otherwise hand the full row —
          // tenant income/age/work-coords for a like, the match graph for a
          // match — to anyone who can construct the id. Gate to members; return
          // 404 (not 403) so existence itself isn't confirmed.
          if (tableKey === 'matches') {
            if (!(await isThreadMember(id, callerUid))) return json(404, {});
          }
          if (tableKey === 'property_likes') {
            const r = await ddb.send(
              new GetCommand({ TableName: table.name, Key: { id } }));
            const it = r.Item;
            if (!it) return json(404, {});
            const ok = !!callerUid && (
              it.tenantId === callerUid ||
              (it.ownerUserId && it.ownerUserId === callerUid) ||
              (await isOwnerOf(it.propertyId, callerUid)));
            return ok ? json(200, it) : json(404, {});
          }
          return await getOne(table, id);
        }
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
        // The match list is private: a caller may only read matches where they
        // are a party (?tenantUid=me or ?landlordUid=me). Without this, either
        // filter enumerates the entire two-sided match graph for any uid.
        if (tableKey === 'matches') {
          const t = query.tenantUid;
          const l = query.landlordUid;
          const mine =
            (t && callerUid && String(t) === String(callerUid)) ||
            (l && callerUid && String(l) === String(callerUid));
          if (!mine) {
            return json(200, { items: [], hasMore: false, lastKey: null });
          }
        }
        // IDOR guard: a per-owner listing query (?ownerUserId=…) exposes that
        // landlord's FULL portfolio incl. draft/removed rows. Only the owner
        // themselves may read it — otherwise anyone could enumerate a
        // competitor's unpublished listings. (The public feed uses ?status=…,
        // never ?ownerUserId=…, so this doesn't touch tenant browsing.)
        if (tableKey === 'properties' && query.ownerUserId) {
          if (!callerUid || String(query.ownerUserId) !== String(callerUid)) {
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
            // Query params are checked first; the profile is loaded only if they
            // don't already determine the cohort. Fail-soft → null → default.
            const cohort = await resolveCohort(query, callerUid).catch(() => null);
            // FAIL-OPEN audience gate: drop listings a landlord marked exclusive to
            // cohorts this caller isn't in — but never hide a landlord's own rows,
            // and never hide anything when the cohort/audience signal is missing.
            const gated = applyAudienceGate(listed, cohort, callerUid);
            // Per-listing eligibility gate: hide listings whose landlord-defined
            // tenant criteria this caller fails (never the caller's own rows).
            const eligible = await applyEligibilityGate(gated, callerUid);
            // OPT-OUT (?rank=0): skip the per-listing rank decoration for callers
            // that rank locally — the website runs the ported on-device
            // SmartSearch, so the ~15ms/row of server scoring (≈2s on a 136-row
            // feed) is pure latency there. STRICTLY opt-in: the app never sends
            // `rank`, so its responses are byte-identical to before. The privacy
            // and audience/eligibility gates above ALWAYS run — only the scoring
            // decoration is skipped.
            if (String(query.rank) === '0') return eligible;
            return await attachRankSignals(eligible, query, cohort, callerUid);
          }
          return listed;
        }
      case 'POST': {
        stampOwner(tableKey, body, callerUid);
        // A match row is created two ways: (1) the landlord accepting a liker
        // — the caller must own the property; or (2) a tenant self-creating a
        // one-sided "request to message" thread for THEMSELVES (no mutual
        // like yet) — the caller must be exactly the tenantUid they're
        // claiming (no creating threads for someone else), and the
        // landlordUid they name must be the property's REAL owner (verified,
        // not fail-open — a tenant is asserting a fact about someone else).
        // Block anything that's neither: a definite ownership mismatch
        // (spoofed match / forged "you have a match" push to a victim).
        if (tableKey === 'matches' && callerUid && body.propertyId) {
          const ownsProperty = await ownsOrUnknown(body.propertyId, callerUid);
          const isTenantSelfRequest =
            !ownsProperty &&
            body.tenantUid === callerUid &&
            body.landlordUid &&
            body.landlordUid !== callerUid &&
            (await isRealOwnerOf(body.propertyId, body.landlordUid));
          if (!ownsProperty && !isTenantSelfRequest) {
            return json(403, { message: 'Forbidden' });
          }
          // Landlord path: landlordUid is always the caller, never the
          // client's word for it. Tenant-self path: landlordUid/tenantUid
          // were already verified above — pass through as sent.
          if (ownsProperty) body.landlordUid = callerUid;
        } else if (tableKey === 'matches' && callerUid) {
          body.landlordUid = callerUid;
        }
        // A message write must be by a MEMBER of the thread. Without this any
        // authenticated user could inject a message into any matchId (the stream
        // then delivers + pushes it to the real participants), and on a legacy
        // thread that single post also passes the read gate → history leak.
        if (tableKey === 'messages') {
          if (!callerUid || !(await isThreadMember(body.matchId, callerUid))) {
            return json(403, { message: 'Forbidden' });
          }
          // Server-authoritative timestamp so cross-device clock skew can't
          // reorder messages (createdAt is the GSI sort key). The client value
          // is only used for its own optimistic bubble until the echo returns.
          body.createdAt = new Date().toISOString();
        }
        const writeId = (tableKey === 'users' || tableKey === 'persona')
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
          } catch { /* lookup failed → treat as existing/edit: fail CLOSED for enrichment (don't re-enrich/re-alert an edit) AND fail OPEN for the paywall (never block a legit edit or 500 a publish — the Phase-3 cron reconciles any listing that slips through) */ isNewListing = false; }
          if (isNewListing) {
            // PAYWALL: a landlord may keep 3 active properties free; the 4th
            // needs an active subscription. Authoritative server-side gate (the
            // client hint can be bypassed, this cannot). Gated on a CONFIRMED
            // new listing only — on a lookup error above we deliberately skip
            // this (fail open) rather than risk blocking an edit. Runs BEFORE
            // the costly enrichment so a blocked publish wastes nothing.
            const gate = await enforcePropertyQuota(callerUid);
            if (gate) return gate; // 402 subscription_required
            // Budget enrichment so a slow connector/Gemini fetch can't stall the
            // publish (the client blocks on this response). Fail-soft on timeout.
            await Promise.race([
              enrichListingOnCreate(body), // mutates body: smartTags, geo, badges
              new Promise((res) => setTimeout(res, 4000)),
            ]).catch(() => {});
          }
        }

        const written = await putItem(table, writeId, body);
        // SCALE: keep the denormalized popularity counter on the property row
        // current with an atomic ADD, so the feed never has to COUNT-query.
        if (written.statusCode === 200 &&
            (tableKey === 'property_views' || tableKey === 'property_likes')) {
          await incrementPropertyCounter(tableKey, body);
        }
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
        // For users & persona the row id IS the uid — never let a caller PUT to
        // another user's id.
        const writeId =
          (tableKey === 'users' || tableKey === 'persona') ? callerUid : id;
        // Persona writes are version-guarded so a slow/out-of-order request can
        // never clobber a newer persona already stored.
        if (tableKey === 'persona') {
          return await putPersonaVersioned(table, writeId, body);
        }
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

// Best-effort ownership check for match creation: block a DEFINITE mismatch
// (property exists and is owned by someone else) but allow when the property
// row can't be found/read, so legit flows (e.g. demo/seeded listings) aren't
// blocked by a lookup miss.
async function ownsOrUnknown(propertyId, uid) {
  try {
    const prop = await ddb.send(new GetCommand({
      TableName: TABLES.properties.name,
      Key: { id: propertyId },
    }));
    if (!prop.Item) return true;
    return prop.Item.ownerUserId === uid;
  } catch {
    return true;
  }
}

// STRICT counterpart to ownsOrUnknown — no fail-open on a lookup miss. Used to
// verify a tenant's claimed landlordUid on a self-created match/request row
// (see the POST /matches gate below): unlike the landlord-approves flow, a
// tenant is asserting a fact about someone ELSE, so an unverifiable claim
// must be rejected, not waved through.
async function isRealOwnerOf(propertyId, uid) {
  try {
    const prop = await ddb.send(new GetCommand({
      TableName: TABLES.properties.name,
      Key: { id: propertyId },
    }));
    return !!prop.Item && prop.Item.ownerUserId === uid;
  } catch {
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
  } else if (table.name === TABLES.properties.name) {
    // Defense-in-depth: an UNFILTERED properties scan (no status, no owner) must
    // not leak removed/paused/draft listings to a tenant. Default to only rows
    // that are active or have no status at all. (The app always sends
    // ?status=active, so this only guards a stray unfiltered caller.)
    params.FilterExpression = '#s = :active OR attribute_not_exists(#s)';
    params.ExpressionAttributeNames = { '#s': 'status' };
    params.ExpressionAttributeValues = { ':active': 'active' };
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
// Cohort-aware main-feed scorer. Loads popularity counts from DynamoDB, then
// delegates the (pure, unit-tested) scoring to ranking.scoreListings. Community
// affinity is a SOFT signal there — no listing is excluded. Fail-soft.
async function attachRankSignals(listed, query, cohort = null, callerUid = null) {
  try {
    const parsed = JSON.parse(listed.body);
    const items = Array.isArray(parsed.items) ? parsed.items : [];
    if (items.length === 0) {
      // Still stamp the A/B variant so an empty page logs consistently.
      parsed.abVariant = variantFor(callerUid, RANK_EXPERIMENT, 2);
      return json(200, parsed);
    }

    const ctx = {
      cohort,
      minBudget: num(query.minBudget) ?? num(query.minPrice),
      maxBudget: num(query.maxBudget) ?? num(query.maxPrice),
      targetPrice: num(query.price) ?? num(query.budget),
    };
    // SCALE: read DENORMALIZED counts off the property rows we already loaded —
    // no per-listing COUNT queries (was up to 120 DDB reads for one feed load,
    // each COUNT billing every row of a popular listing's GSI partition). The
    // counts are kept current by an atomic ADD on every view/like write (see
    // incrementPropertyCounter). Only pre-denormalization listings fall back.
    const counts = {};
    const missing = [];
    for (const p of items.slice(0, 60)) {
      const id = String(p.id || '');
      if (!id) continue;
      if (p.viewCount !== undefined || p.likeCount !== undefined) {
        counts[id] = {
          views: Number(p.viewCount) || 0,
          likes: Number(p.likeCount) || 0,
        };
      } else {
        missing.push(id);
      }
    }
    if (missing.length) Object.assign(counts, await loadPopularityCounts(missing));

    // ── Phase-2: personalised semantic signal ────────────────────────────────
    // If the caller has a stored user vector, set each listing's semanticSim to
    // cosine(userVec, listingVec) BEFORE scoring — scoreListings reads
    // p.semanticSim as the `semantic` component (else it stays a neutral 0.5, so
    // no regression for users without a vector or listings without an embedding).
    if (EMBEDDINGS_ENABLED && callerUid) {
      const userVec = await loadUserEmbedding(callerUid);
      if (userVec) {
        for (const p of items) {
          if (Array.isArray(p.embedding) && p.embedding.length === userVec.length) {
            p.semanticSim = cosine01(userVec, p.embedding);
          }
        }
      }
    }

    // Pure linear scoring (unchanged): sets p.rankSignals + p.rankScore.
    scoreListings(items, ctx, counts, Date.now());

    // ── Feature parity (landmine #1) ──────────────────────────────────────────
    // Surface the EXACT feature vector the server scored on as `rankFeatures` on
    // every listing — a stable, ordered object keyed by RANK_FEATURE_ORDER (+
    // cohort). This is the canonical vector the client logs back verbatim on
    // /search/log and the trainer/scorer index into. No training/serving skew.
    for (const p of items) {
      p.rankFeatures = rankFeaturesFrom(p.rankSignals);
      // Strip the 768-float embedding from the response — it's a large payload
      // (~6KB/listing) only needed server-side for the cosine above.
      if (p.embedding !== undefined) delete p.embedding;
    }

    // ── A/B (Phase 0) ─────────────────────────────────────────────────────────
    const abVariant = variantFor(callerUid, RANK_EXPERIMENT, 2);
    parsed.abVariant = abVariant;
    parsed.rankExperiment = RANK_EXPERIMENT;
    // Also stamp per-listing (same user-level value) so the client can log it on
    // each impression row verbatim alongside rankFeatures — parity with the client
    // reader that threads abVariant off the listing item.
    for (const p of items) p.abVariant = abVariant;

    // ── Model serving hook (Phase 1, dormant-ready) ──────────────────────────
    // When a model is loaded AND the caller is in the treatment bucket, blend
    // finalScore = α·linear + (1−α)·model (α = RANK_MODEL_ALPHA, default 0.7).
    // With NO model loaded — the default — behavior is EXACTLY today's pure
    // linear score for BOTH buckets. Fail-soft: any model error → pure linear.
    let modelApplied = false;
    if (abVariant === 1) {
      try {
        const model = await loadModel({ s3Get: rankModelS3Get });
        if (model) {
          const alpha = modelAlpha();
          for (const p of items) {
            const modelScore = scoreWithModel(model, p.rankFeatures);
            const blended = round3(blendScore(p.rankScore, modelScore, alpha));
            if (p.rankSignals) {
              p.rankSignals.linearRankScore = p.rankScore; // keep the transparent baseline
              p.rankSignals.modelScore = round3(modelScore);
            }
            p.rankScore = blended;
          }
          modelApplied = true;
        }
      } catch (e) {
        console.warn('model blend failed → pure linear:', e.message);
      }
    }
    parsed.rankModel = modelApplied; // client can log whether the model was live

    return json(200, parsed);
  } catch (e) {
    console.warn('attachRankSignals failed:', e.message);
    return listed;
  }
}

// S3 getter injected into loadModel so the model_scorer reuses this Lambda's
// existing S3 client + stream helper instead of importing its own.
async function rankModelS3Get(ref) {
  let r = String(ref).trim();
  if (r.startsWith('s3://')) r = r.slice(5);
  const slash = r.indexOf('/');
  const Bucket = slash > 0 ? r.slice(0, slash) : S3_BUCKET;
  const Key = slash > 0 ? r.slice(slash + 1) : r;
  const obj = await s3.send(new GetObjectCommand({ Bucket, Key }));
  return await streamToString(obj.Body);
}

// Fail-open audience gate over a catalog page. Filters OUT listings the pure
// isListingVisibleToCohort helper deems hidden for this caller; any parse hiccup
// or missing signal returns the page untouched (never hides more than intended).
// Pagination fields (hasMore/lastKey) are preserved as-is — a short page after
// filtering is acceptable and the cursor still advances correctly.
function applyAudienceGate(listed, cohort, callerUid) {
  try {
    const parsed = JSON.parse(listed.body);
    if (!Array.isArray(parsed.items)) return listed;
    parsed.items = parsed.items.filter(
      (l) => isListingVisibleToCohort(l, cohort, callerUid));
    return json(200, parsed);
  } catch (e) {
    console.warn('applyAudienceGate failed:', e.message);
    return listed;
  }
}

// FAIL-OPEN eligibility gate: a landlord can attach precise tenant criteria
// (listing.eligibility) so only matching tenants see the listing. We need the
// caller's FULL searchProfile to evaluate rules, so — only when some candidate
// listing actually has eligibility enabled — load the profile ONCE and reuse it
// across the page. The pure per-listing decision lives in lib/eligibility.mjs.
// Owner-visibility and disabled/empty rules are handled inside passesEligibility.
async function applyEligibilityGate(listed, callerUid) {
  try {
    const parsed = JSON.parse(listed.body);
    if (!Array.isArray(parsed.items)) return listed;
    const anyEnabled = parsed.items.some(
      (l) => l && l.eligibility && l.eligibility.enabled === true);
    if (!anyEnabled) return listed; // no gated listings → no profile read needed
    // Single profile read for the whole page (fail-soft → null → gate treats
    // every tenant field as unknown, i.e. must-rules hide, important-rules open).
    const profile = callerUid ? await loadUserProfile(callerUid).catch(() => null) : null;
    parsed.items = parsed.items.filter(
      (l) => passesEligibility(l, profile, callerUid));
    return json(200, parsed);
  } catch (e) {
    console.warn('applyEligibilityGate failed:', e.message);
    return listed;
  }
}

function num(v) {
  if (v === undefined || v === null || v === '') return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
}

// View + like counts per listing (the popularity signal source). Uses the
// propertyId-index COUNT query on the analytics tables. Bounded, fail-soft.
//
// Each id was costing 2 COUNT queries, so a 40-listing search fired ~80 DDB
// round-trips and the slowest gated the whole GET /properties response (~3-4s).
// Popularity is approximate and slow-moving, so cache it in the warm Lambda for
// POP_TTL_MS: repeat/overlapping searches (the common case) then hit memory and
// skip the queries entirely. ponytail: module Map + TTL, bounded at 5000 ids —
// swap for a denormalised count on the property row if the catalogue explodes.
const _popCache = new Map(); // id → { views, likes, exp }
const POP_TTL_MS = 90 * 1000;

// SCALE: maintain a denormalized counter on the property row via an atomic ADD,
// so reads are O(1) off the row instead of O(views+likes) COUNT queries. Guarded
// by attribute_exists so a like/view on a missing listing can't create a phantom
// property. Fully fail-soft — a counter hiccup never fails the underlying write.
async function incrementPropertyCounter(tableKey, body) {
  const pid = body && (body.propertyId || body.property_id);
  if (!pid) return;
  const attr = tableKey === 'property_likes' ? 'likeCount' : 'viewCount';
  try {
    await ddb.send(new UpdateCommand({
      TableName: TABLES.properties.name,
      Key: { id: String(pid) },
      UpdateExpression: 'ADD #c :one',
      ExpressionAttributeNames: { '#c': attr },
      ExpressionAttributeValues: { ':one': 1 },
      ConditionExpression: 'attribute_exists(id)',
    }));
  } catch (e) {
    if (e && e.name !== 'ConditionalCheckFailedException') {
      console.warn('incrementPropertyCounter', attr, e.message);
    }
  }
}

async function loadPopularityCounts(ids) {
  const out = {};
  const now = Date.now();
  const misses = [];
  for (const id of ids) {
    const c = _popCache.get(id);
    if (c && c.exp > now) out[id] = { views: c.views, likes: c.likes };
    else misses.push(id);
  }
  await Promise.all(misses.map(async (id) => {
    const [views, likes] = await Promise.all([
      countByPropertyId(TABLES.property_views, id),
      countByPropertyId(TABLES.property_likes, id),
    ]);
    out[id] = { views, likes };
    _popCache.set(id, { views, likes, exp: now + POP_TTL_MS });
  }));
  if (_popCache.size > 5000) {
    for (const k of [..._popCache.keys()].slice(0, _popCache.size - 5000)) {
      _popCache.delete(k);
    }
  }
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
  // Search-level context the ranker used: keep it on EVERY impression row so a
  // training join never has to look up the parent search. Fail-soft defaults.
  const weights = (body.weights && typeof body.weights === 'object') ? body.weights : {};
  const cohort = (body.cohort === null || body.cohort === undefined) ? null : body.cohort;
  const clientTs = Number.isFinite(Number(body.ts)) ? Number(body.ts) : null;
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
          // Search-level context (same on every impression of this search).
          weights,
          cohort,
          ts: clientTs,                   // client-asserted search timestamp
          kind: 'impression',             // pairs with 'outcome' rows via searchId
          propertyId,
          // The per-impression feature vector the ranker saw (training input).
          // CRITICAL (Phase-1): store the SERVER-canonical `rankFeatures`
          // (RANK_FEATURE_ORDER keys: freshness/popularity/…), NOT the client's
          // `features` (tag_overlap/price_fit/recency/…). The trainer vectorises
          // by RANK_FEATURE_ORDER, so storing the client vector = a train/serve
          // feature SKEW that trains the model on ~all-zeros. Fall back to the
          // client vector only when rankFeatures is absent (older clients).
          features: (imp.rankFeatures &&
                  typeof imp.rankFeatures === 'object' &&
                  Object.keys(imp.rankFeatures).length > 0)
              ? imp.rankFeatures
              : ((imp.features && typeof imp.features === 'object')
                  ? imp.features
                  : {}),
          // Keep the client's own vector too (future features / debugging).
          clientFeatures:
              (imp.features && typeof imp.features === 'object') ? imp.features : {},
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

// POST /search/outcome — append ONE labeled row (the real training label).
// Body: { searchId, propertyId, outcome, dwellMs? } with
//   outcome ∈ {click, like, superlike, contact, skip}.
// Auth-gated. A future join groups impression + outcome rows by (searchId,
// propertyId) via the `kind` marker. Fully fail-soft — never 500.
const OUTCOME_LABELS = new Set(['click', 'like', 'superlike', 'contact', 'skip']);
async function handleSearchOutcome(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  try {
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }

    const searchId = (body.searchId || '').toString().slice(0, 64);
    const propertyId = (body.propertyId || '').toString();
    const outcome = (body.outcome || '').toString().slice(0, 24);
    const dwellMs = Number.isFinite(Number(body.dwellMs)) ? Number(body.dwellMs) : null;

    // Sanity-check before persisting; still 200 (fail-soft) so the client's
    // fire-and-forget beacon never blocks the UI.
    if (searchId && propertyId && OUTCOME_LABELS.has(outcome)) {
      await ddb.send(new PutCommand({
        TableName: SEARCH_LOG_TABLE,
        Item: {
          id: crypto.randomUUID(),
          userId: uid,
          createdAt: Date.now(),
          searchId,
          propertyId,
          outcome,
          dwellMs,
          kind: 'outcome',              // pairs with 'impression' rows via searchId
        },
      }));
    }
  } catch (e) {
    console.warn('search/outcome write failed:', e.message);
  }
  return json(200, { ok: true });
}

// ── Consumption layer handlers (interaction store + CF + ML export) ──────────
// The pure math lives in ./lib/cf.mjs; these functions only do the (bounded)
// DynamoDB I/O around it. All three fail SOFT — they never 500 the client.

// Merge one incoming interaction event into the stored (user,property) row.
// Pure: MAX for accumulators (dwellMs/photosViewed/scrollDepth), OR for media
// flags, latest-wins for entrySource/entryRank, and per-action booleans/counter.
const INTERACTION_ACTIONS = new Set(['view', 'like', 'superlike', 'pass', 'contact', 'bounce']);
function mergeInteraction(cur, body) {
  const r = { ...(cur || {}) };
  const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : null);
  const d = num(body.dwellMs);
  if (d != null) r.dwellMs = Math.max(Number(r.dwellMs) || 0, d);          // keep max total
  if (body.opened360) r.opened360 = true;                                  // OR media flags
  if (body.opened3d) r.opened3d = true;
  if (body.openedVideo) r.openedVideo = true;
  const pv = num(body.photosViewed);
  if (pv != null) r.photosViewed = Math.max(Number(r.photosViewed) || 0, pv);
  const sd = num(body.scrollDepth);
  if (sd != null) r.scrollDepth = Math.max(Number(r.scrollDepth) || 0, sd);
  // Listing "size" for dwell length-normalization (landmine #3). Stable per
  // listing; latest-wins. The handler backfills these from the property row when
  // the client omits them, so a media-heavy listing doesn't auto-score on dwell.
  const mc = num(body.mediaCount);
  if (mc != null) r.mediaCount = mc;
  const dl = num(body.descLen);
  if (dl != null) r.descLen = dl;
  if (body.entrySource != null) r.entrySource = String(body.entrySource).slice(0, 40); // latest wins
  const er = num(body.entryRank);
  if (er != null) r.entryRank = er;
  const action = (body.action || '').toString();
  if (INTERACTION_ACTIONS.has(action)) {
    if (action === 'view') r.viewCount = (Number(r.viewCount) || 0) + 1;
    else if (action === 'like') r.liked = true;
    else if (action === 'superlike') r.superliked = true;
    else if (action === 'pass') r.passed = true;
    else if (action === 'contact') r.contacted = true;
    else if (action === 'bounce') r.bounced = true;
  }
  return r;
}

// POST /interactions — read-modify-write the caller's (user,property) row, merge
// the incoming signal, recompute the implicit score, persist. → { ok, score }.
async function handleInteraction(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  try {
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
    const propertyId = (body.propertyId || '').toString();
    if (!propertyId) return json(200, { ok: false, score: 0 });
    const T = TABLES.interactions.name;
    const cur = (await ddb.send(new GetCommand({
      TableName: T, Key: { userId: uid, propertyId },
    }))).Item || {};
    const rec = mergeInteraction(cur, body);
    rec.userId = uid;
    rec.propertyId = propertyId;
    // Dwell length-normalization needs the listing's "size". Prefer client-sent
    // mediaCount/descLen (already merged above); otherwise derive them ONCE from
    // the property row so a photo-heavy / long-copy listing doesn't over-score on
    // raw dwell. Fail-soft: on a lookup miss the score just uses the base expected
    // dwell (mediaCount/descLen default to 0 inside implicitScore).
    if (rec.mediaCount === undefined || rec.descLen === undefined) {
      const size = await deriveListingSize(propertyId).catch(() => null);
      if (size) {
        if (rec.mediaCount === undefined) rec.mediaCount = size.mediaCount;
        if (rec.descLen === undefined) rec.descLen = size.descLen;
      }
    }
    rec.score = implicitScore(rec);
    rec.updatedAt = Date.now();
    await ddb.send(new PutCommand({ TableName: T, Item: rec }));
    return json(200, { ok: true, score: rec.score });
  } catch (e) {
    console.warn('interactions write failed:', e.message);
    return json(200, { ok: false, score: 0 });   // fail-soft: never 500
  }
}

// Count a property's "media" for dwell length-normalization: photos + video +
// 360/3d. Defensive over the various shapes a listing row can carry.
function mediaCountOf(p) {
  if (!p || typeof p !== 'object') return 0;
  let n = 0;
  if (Array.isArray(p.imageUrls)) n += p.imageUrls.length;
  if (p.videoUrl || (Array.isArray(p.videoUrls) && p.videoUrls.length)) n += 1;
  // 360 panorama and/or a 3D splat model each count as one rich-media asset.
  if (p.panoramaUrl || p.panoUrl || (Array.isArray(p.panoramas) && p.panoramas.length)) n += 1;
  if (p.model3d && (p.model3d.ksplatUrl || p.model3d.meshGlbUrl || p.model3d.splatUrl)) n += 1;
  return n;
}

// GetItem the property row and return { mediaCount, descLen } for dwell
// normalization. Fail-soft → null (caller falls back to the base expected dwell).
async function deriveListingSize(propertyId) {
  const out = await ddb.send(new GetCommand({
    TableName: TABLES.properties.name, Key: { id: propertyId },
  }));
  const p = out.Item;
  if (!p) return null;
  return {
    mediaCount: mediaCountOf(p),
    descLen: p.description ? String(p.description).length : 0,
  };
}

// ── Phase-2: the USER TOWER (content-based user embedding) ───────────────────
// POST /user/embedding — the client sends the property ids it engaged with; we
// fetch those listings' embeddings, action-weight + mean-pool them into a user
// vector (lib/user_embedding.mjs), and store it on the persona row so the feed
// ranker can score cosine(userVec, listingVec) as a personalised semantic
// signal. Fully fail-soft. Body: { liked:[id], contacted:[id]?, superliked:[id]? }.
async function handleUserEmbedding(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  if (!EMBEDDINGS_ENABLED) return json(200, { ok: false, reason: 'embeddings_off' });
  try {
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
    const liked = Array.isArray(body.liked) ? body.liked : [];
    const contacted = new Set((Array.isArray(body.contacted) ? body.contacted : []).map(String));
    const superliked = new Set((Array.isArray(body.superliked) ? body.superliked : []).map(String));
    const ids = [...new Set(liked.map(String).filter(Boolean))].slice(0, 300);
    if (ids.length === 0) return json(200, { ok: false, reason: 'no_ids' });

    const engaged = [];
    for (let i = 0; i < ids.length; i += 100) {
      const chunk = ids.slice(i, i + 100);
      const res = await ddb.send(new BatchGetCommand({
        RequestItems: {
          [TABLES.properties.name]: {
            Keys: chunk.map((id) => ({ id })),
            ProjectionExpression: 'id, embedding',
          },
        },
      }));
      const rows = res.Responses?.[TABLES.properties.name] || [];
      for (const r of rows) {
        if (!Array.isArray(r.embedding) || !r.embedding.length) continue;
        const action = contacted.has(r.id) ? 'contact'
          : superliked.has(r.id) ? 'superlike' : 'like';
        engaged.push({ embedding: r.embedding, action });
      }
    }

    const vec = userEmbeddingFrom(engaged);
    if (!vec) return json(200, { ok: false, reason: 'no_embedded_likes', count: 0 });

    await ddb.send(new UpdateCommand({
      TableName: TABLES.persona.name,
      Key: { id: uid },
      UpdateExpression:
        'SET userEmbedding = :v, userEmbeddingDim = :d, userEmbeddingUpdatedAt = :t',
      ExpressionAttributeValues: {
        ':v': vec, ':d': vec.length, ':t': new Date().toISOString(),
      },
    }));
    return json(200, { ok: true, dim: vec.length, count: engaged.length });
  } catch (e) {
    console.warn('user/embedding failed:', e.message);
    return json(200, { ok: false, reason: 'error' });
  }
}

// ── Phase-3: LOOK-ALIKE AUDIENCES ────────────────────────────────────────────
// POST /listing/audience — for a landlord's OWN listing, rank the tenant
// population by how close their user vector sits to the listing's embedding
// ("tenants who'd love this apartment"), excluding tenants who already engaged.
// This is targeting over the REAL population (vs an LLM cohort guess on a draft).
// Body: { propertyId, topK? }. Fail-soft; dormant (empty) until user vectors
// accumulate. Brute-force cosine over the persona table — fine at Phase-3 scale.
async function handleListingAudience(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  if (!EMBEDDINGS_ENABLED) return json(200, { ok: false, reason: 'embeddings_off', audience: [] });
  try {
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
    const propertyId = String(body.propertyId || '');
    if (!propertyId) return json(400, { message: 'propertyId required' });

    const prop = (await ddb.send(new GetCommand({
      TableName: TABLES.properties.name, Key: { id: propertyId },
    }))).Item;
    if (!prop) return json(404, { message: 'Not found' });
    if (prop.ownerUserId !== uid) return json(403, { message: 'Forbidden' });
    const listingVec = Array.isArray(prop.embedding) && prop.embedding.length
      ? prop.embedding : null;
    if (!listingVec) return json(200, { ok: false, reason: 'listing_not_embedded', audience: [] });

    // Tenants already interested → excluded from the "new audience".
    const engaged = new Set();
    try {
      const likes = await ddb.send(new QueryCommand({
        TableName: TABLES.property_likes.name,
        IndexName: TABLES.property_likes.gsi.name,
        KeyConditionExpression: 'propertyId = :p',
        ExpressionAttributeValues: { ':p': propertyId },
        Limit: 500,
      }));
      for (const l of likes.Items || []) if (l.tenantId) engaged.add(String(l.tenantId));
    } catch { /* no likes / GSI hiccup — audience just includes everyone */ }

    // Scan the persona table for stored user vectors (bounded).
    const candidates = [];
    let lastKey;
    do {
      const page = await ddb.send(new ScanCommand({
        TableName: TABLES.persona.name,
        ExclusiveStartKey: lastKey,
        ProjectionExpression: 'id, userEmbedding',
        Limit: 1000,
      }));
      for (const it of page.Items || []) {
        if (Array.isArray(it.userEmbedding) && it.userEmbedding.length) {
          candidates.push({ id: String(it.id), userEmbedding: it.userEmbedding });
        }
      }
      lastKey = page.LastEvaluatedKey;
    } while (lastKey && candidates.length < 5000);

    const topK = Math.max(1, Math.min(100, Number(body.topK) || 25));
    const audience = topKBySimilarity(listingVec, candidates, topK, engaged)
      .map((a) => ({ tenantId: a.id, score: Math.round(a.score * 100) }));

    return json(200, {
      ok: true,
      propertyId,
      candidatesScanned: candidates.length,
      alreadyEngaged: engaged.size,
      audienceCount: audience.length,
      audience,
    });
  } catch (e) {
    console.warn('listing/audience failed:', e.message);
    return json(200, { ok: false, reason: 'error', audience: [] });
  }
}

// The caller's stored user vector (or null). Fail-soft — a miss/absence just
// means the feed's semantic signal stays neutral for this user.
async function loadUserEmbedding(uid) {
  try {
    const res = await ddb.send(new GetCommand({
      TableName: TABLES.persona.name,
      Key: { id: uid },
      ProjectionExpression: 'userEmbedding',
    }));
    const v = res.Item?.userEmbedding;
    return Array.isArray(v) && v.length ? v : null;
  } catch { return null; }
}

// POST /reco/cf — item-item co-engagement collaborative filtering. Reads are
// hard-capped so a heavy user can't blow the request budget. → { items:[...] }.
async function handleRecoCf(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  try {
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
    const limit = Math.max(1, Math.min(100, Number(body.limit) || 20));
    const T = TABLES.interactions.name;
    const GSI = TABLES.interactions.gsi.name; // propertyId-userId

    // Read caps keep the fan-out bounded no matter how active anyone is.
    const SEED_CAP = 40;    // seeds we branch out from
    const PER_SEED = 50;    // co-users pulled per seed property
    const USER_CAP = 400;   // distinct co-users total
    const MINE_CAP = 500;   // caller's own rows read
    const COUSER_CAP = 200; // rows read per co-user

    // a. the caller's interactions; seeds = positively-scored properties.
    const mine = (await ddb.send(new QueryCommand({
      TableName: T,
      KeyConditionExpression: 'userId = :u',
      ExpressionAttributeValues: { ':u': uid },
      Limit: MINE_CAP,
    }))).Items || [];
    const seeds = mine.filter((r) => Number(r.score) > 0);
    if (seeds.length === 0) return json(200, { items: [] });

    // b. OTHER users who engaged each seed (GSI query, capped).
    const coUserIds = new Set();
    for (const s of seeds.slice(0, SEED_CAP)) {
      if (coUserIds.size >= USER_CAP) break;
      try {
        const out = await ddb.send(new QueryCommand({
          TableName: T, IndexName: GSI,
          KeyConditionExpression: 'propertyId = :p',
          ExpressionAttributeValues: { ':p': String(s.propertyId) },
          Limit: PER_SEED,
        }));
        for (const row of (out.Items || [])) {
          if (row.userId && row.userId !== uid) coUserIds.add(row.userId);
          if (coUserIds.size >= USER_CAP) break;
        }
      } catch { /* one bad seed shouldn't sink the recommendation */ }
    }
    if (coUserIds.size === 0) return json(200, { items: [] });

    // c. each co-user's positively-scored properties (base-table query, capped).
    const ids = [...coUserIds].slice(0, USER_CAP);
    const results = await Promise.all(ids.map(async (cuid) => {
      try {
        const out = await ddb.send(new QueryCommand({
          TableName: T,
          KeyConditionExpression: 'userId = :u',
          ExpressionAttributeValues: { ':u': cuid },
          Limit: COUSER_CAP,
        }));
        return {
          userId: cuid,
          interactions: (out.Items || []).map((r) => ({
            propertyId: String(r.propertyId), score: Number(r.score) || 0,
          })),
        };
      } catch { return { userId: cuid, interactions: [] }; }
    }));
    const coUsers = results.filter((r) => r.interactions.length);

    const items = cfRecommend(
      mine.map((r) => ({ propertyId: String(r.propertyId), score: Number(r.score) || 0 })),
      coUsers, { limit },
    );
    return json(200, { items });
  } catch (e) {
    console.warn('reco/cf failed:', e.message);
    return json(200, { items: [] });   // fail-soft on any error / too-little data
  }
}

// GET /ml/export — LightGBM training-data export. Admin-only (notif-admin uid).
// Joins impression rows (feature vectors) with outcome rows by (searchId,
// propertyId) into labeled rows. Bounded scan; capped at 2000 rows. Fail-soft.
async function handleMlExport(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  if (!callerIsNotifAdmin(event)) return json(403, { message: 'Forbidden' });
  try {
    let items = [];
    let lastKey;
    do {
      const out = await ddb.send(new ScanCommand({
        TableName: SEARCH_LOG_TABLE,
        ExclusiveStartKey: lastKey,
        Limit: 1000,
      }));
      items = items.concat(out.Items || []);
      lastKey = out.LastEvaluatedKey;
    } while (lastKey && items.length < 8000);   // bounded sample

    const impressions = items.filter((r) => r && r.kind === 'impression');
    const outcomes = items.filter((r) => r && r.kind === 'outcome');
    const rows = trainingRowsFrom(impressions, outcomes).slice(0, 2000);
    return json(200, { rows, count: rows.length });
  } catch (e) {
    console.warn('ml/export failed:', e.message);
    return json(200, { rows: [], count: 0 });
  }
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

// Internal-only fields the client never consumes. The 768-float `embedding`
// vector especially: it bloats every list response ~10× AND is what pushes a
// property Scan past the 1MB page limit at ~140 rows, silently truncating the
// catalogue. Stripping it is safe (no client reads it) and lets more rows fit
// per page. (ownerUserId is KEPT — the client uses it for dedup/ownership.)
const _STRIP_LIST_FIELDS = ['embedding', 'embeddingDim', 'embeddingModel'];
function stripInternal(item) {
  if (!item || typeof item !== 'object') return item;
  for (const k of _STRIP_LIST_FIELDS) {
    if (k in item) delete item[k];
  }
  return item;
}

function pageBody(out) {
  return {
    items: (out.Items || []).map(stripInternal),
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

// ─────────────────────────────────────────────────────────────────────────────
// Landlord subscription billing — the router's thin adapter over the shared,
// unit-tested subscription engine (lib/subscription_engine.mjs). All lifecycle
// logic lives in the engine; here we only wire it to DynamoDB + Morning + HTTP.
// ─────────────────────────────────────────────────────────────────────────────

const billingStore = createDdbStore({
  ddb,
  tables: {
    subscriptions: SUBSCRIPTIONS_TABLE,
    invoices: INVOICES_TABLE,
    invoicesOwnerIndex: INVOICES_OWNER_INDEX,
    properties: TABLES.properties.name,
    propertiesOwnerIndex: TABLES.properties.ownerIndex,
  },
});
const billingProvider = {
  upsertClient: (o) => morning.upsertClient(o),
  createPaymentForm: (o) => morning.createPaymentForm(o),
  createPaymentFormOneOff: (o) => morning.createPaymentFormOneOff(o),
  chargeToken: (o) => morning.chargeToken(o),
  findRecentPaidDocument: (o) => morning.findRecentPaidDocument(o),
  findCardToken: (o) => morning.findCardToken(o),
};
const billingEngine = createEngine({
  store: billingStore,
  provider: billingProvider,
  now: () => Date.now(),
  log: (...a) => console.error('billing:', ...a),
});

// Build the provider return/notify URLs. Prefer explicit env; else derive the
// public API base from the incoming request (Host + stage).
function billingUrls(event) {
  const host = event.headers?.Host || event.headers?.host || '';
  const stage = event.requestContext?.stage || 'prod';
  const apiBase = process.env.MORNING_API_PUBLIC_BASE
    || (host ? `https://${host}/${stage}` : '');
  const returnBase = process.env.MORNING_RETURN_BASE || apiBase;
  return {
    notifyUrl: process.env.MORNING_NOTIFY_URL || `${apiBase}/hooks/morning`,
    successUrl: `${returnBase}/hooks/return?status=success`,
    failureUrl: `${returnBase}/hooks/return?status=failure`,
  };
}

// Server-side paywall gate for a NEW listing. Enforces ONLY when
// BILLING_ENFORCE=1 (deploy dormant, activate after the grandfather backfill).
// Returns a 402 response object when blocked, else null (allow).
async function enforcePropertyQuota(uid) {
  if (process.env.BILLING_ENFORCE !== '1') return null;
  const block = await billingEngine.enforceQuota(uid);
  if (!block) return null;
  return json(402, {
    ...block,
    message: 'מכסת הדירות החינמית מוצתה — נדרש מנוי כדי לפרסם דירה נוספת.',
  });
}

// GET  /billing/subscription · POST /billing/checkout · POST /billing/cancel ·
// POST /billing/resume · GET /billing/invoices  (all JWT-gated).
async function handleBilling(event, segments, method) {
  const uid = callerUidOf(event);
  const action = segments[1];
  if (!uid) return json(401, { message: 'Unauthorized' });

  if (action === 'subscription' && method === 'GET') {
    return json(200, await billingEngine.getEntitlement(uid));
  }

  if (action === 'checkout' && method === 'POST') {
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
    try {
      const r = await billingEngine.checkout(uid, {
        plan: body.plan, email: body.email, name: body.name, coupon: body.coupon,
        group: body.group, // chosen payment method (card/Bit/Apple/Google)
        ...billingUrls(event),
      });
      if (r.error === 'bad_plan') return json(400, { error: 'bad_plan', message: 'מסלול לא תקין.' });
      return json(200, { url: r.url, plan: r.plan, coupon: r.coupon ?? null, priceAgorot: r.priceAgorot ?? null });
    } catch (e) {
      console.error('checkout failed:', e?.status, e?.message, JSON.stringify(e?.data || {}));
      return json(502, { error: 'checkout_failed', message: 'יצירת התשלום נכשלה, נסה שוב.' });
    }
  }

  // One-off payment (e.g. the 50₪ AI-contract unlock). Body: {amountAgorot, description?, product?}
  if (action === 'checkout-oneoff' && method === 'POST') {
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
    try {
      const r = await billingEngine.checkoutOneOff(uid, {
        // NOTE: no client amount — the server prices the product (anti-tamper).
        description: body.description,
        product: body.product,
        propertyId: body.propertyId, // for a paid boost: which listing to boost
        group: body.group,           // chosen payment method
        email: body.email,
        name: body.name,
        ...billingUrls(event),
      });
      if (r.error === 'bad_product') return json(400, { error: 'bad_product', message: 'מוצר לא תקין.' });
      if (r.error === 'bad_amount') return json(400, { error: 'bad_amount', message: 'סכום לא תקין.' });
      if (r.error === 'missing_property') return json(400, { error: 'missing_property', message: 'חסר מזהה נכס.' });
      return json(200, { url: r.url });
    } catch (e) {
      console.error('checkout-oneoff failed:', e?.status, e?.message, JSON.stringify(e?.data || {}));
      return json(502, { error: 'checkout_failed', message: 'יצירת התשלום נכשלה, נסה שוב.' });
    }
  }

  // Verify-on-return: the app calls this when the hosted page redirects back
  // with success. Confirms the payment via Morning and activates — reliable
  // even if the IPN never arrives.
  if (action === 'confirm' && method === 'POST') {
    try {
      const r = await billingEngine.confirm(uid);
      return json(200, { ...r, entitlement: await billingEngine.getEntitlement(uid) });
    } catch (e) {
      console.error('confirm failed:', e?.status, e?.message);
      return json(200, { confirmed: false, reason: 'error', entitlement: await billingEngine.getEntitlement(uid) });
    }
  }

  // Verify-on-return for a PAID one-off boost. Body: {product, propertyId}.
  // Confirms the ₪10/₪50 payment via Morning, then stamps the boost tier.
  if (action === 'confirm-oneoff' && method === 'POST') {
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
    try {
      const r = await billingEngine.confirmOneOff(uid, { product: body.product, propertyId: body.propertyId });
      return json(200, r);
    } catch (e) {
      console.error('confirm-oneoff failed:', e?.status, e?.message);
      return json(200, { ok: false, reason: 'error' });
    }
  }

  // Boost a listing ("הקפצת מודעה"). Body: {propertyId}. Entitlement + quota gated.
  if (action === 'boost' && method === 'POST') {
    let body = {};
    try { body = event.body ? JSON.parse(event.body) : {}; } catch { body = {}; }
    const r = await billingEngine.boost(uid, body.propertyId);
    if (r.error === 'not_entitled') return json(402, { error: 'not_entitled', message: 'נדרש מנוי פעיל כדי להקפיץ מודעה.' });
    if (r.error === 'quota_exceeded') return json(409, { error: 'quota_exceeded', message: 'ניצלת את מכסת ההקפצות החודשית.', quota: r.quota, used: r.used });
    if (r.error === 'not_owner') return json(404, { error: 'not_owner', message: 'הנכס לא נמצא.' });
    if (r.error) return json(400, { error: r.error, message: 'בקשה לא תקינה.' });
    return json(200, r);
  }

  if (action === 'cancel' && method === 'POST') {
    const r = await billingEngine.cancel(uid);
    if (r.error) return json(404, { error: 'no_subscription', message: 'אין מנוי פעיל לביטול.' });
    return json(200, await billingEngine.getEntitlement(uid));
  }

  if (action === 'resume' && method === 'POST') {
    const r = await billingEngine.resume(uid);
    if (r.error) return json(404, { error: 'no_subscription', message: 'אין מנוי לחידוש.' });
    return json(200, await billingEngine.getEntitlement(uid));
  }

  if (action === 'invoices' && method === 'GET') {
    return json(200, { items: await billingEngine.listInvoices(uid) });
  }

  return json(404, { message: 'Not found' });
}

// NO-AUTH provider callbacks (API Gateway resource with AuthorizationType NONE).
//   GET  /hooks/return  — post-payment redirect fallback page.
//   POST /hooks/morning — Green Invoice/Grow IPN → verify + engine.applyPayment.
async function handleHooks(event, segments, method) {
  const action = segments[1];

  if (action === 'return' && method === 'GET') {
    const okStatus = event.queryStringParameters?.status === 'success';
    // Deep-link back into the app (Path A: external-browser wallet checkout).
    // The in-app WebView never renders this page — it intercepts /hooks/return
    // by URL — so this only fires for the system-browser (Apple/Google Pay) flow.
    const appLink = `rently://billing/return?status=${okStatus ? 'success' : 'failure'}`;
    return html(200, `<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Rently</title>
<style>body{font-family:-apple-system,Arial,sans-serif;background:#f4f6fa;color:#0b2540;display:grid;place-items:center;height:100vh;margin:0;text-align:center}
.c{background:#fff;padding:32px 28px;border-radius:18px;box-shadow:0 10px 30px rgba(11,37,64,.1);max-width:340px}
.i{font-size:44px}h1{font-size:20px;margin:12px 0 6px}p{color:#5b7a99;margin:0 0 18px}
a.b{display:inline-block;background:#4f46e5;color:#fff;text-decoration:none;font-weight:800;padding:13px 22px;border-radius:14px}</style>
<script>setTimeout(function(){location.href=${JSON.stringify(appLink)}},400);</script></head>
<body><div class="c"><div class="i">${okStatus ? '✅' : '⚠️'}</div>
<h1>${okStatus ? 'התשלום התקבל' : 'התשלום לא הושלם'}</h1>
<p>מעבירים אתכם חזרה לאפליקציה…</p>
<a class="b" href="${appLink}">חזרה לאפליקציית Rently</a></div></body></html>`);
  }

  if (action === 'morning' && method === 'POST') {
    const rawBody = event.isBase64Encoded && event.body
      ? Buffer.from(event.body, 'base64').toString('utf8')
      : (event.body || '');
    // DIAGNOSTIC CAPTURE: log the full raw IPN so the first real payment reveals
    // the exact Meshulam/Green-Invoice format to finalise verify/parse.
    console.log('IPN_CAPTURE headers:', JSON.stringify(event.headers || {}));
    console.log('IPN_CAPTURE body:', rawBody);
    if (!morning.verifyWebhook(event.headers || {}, rawBody)) {
      console.warn('billing webhook: signature verification failed (see IPN_CAPTURE above)');
      return json(401, { message: 'bad signature' });
    }
    let payload = {};
    try { payload = rawBody ? JSON.parse(rawBody) : {}; } catch { payload = {}; }
    const ev = morning.parseWebhook(payload);
    try {
      // A one-off boost IPN carries product+propertyId in `custom`; route it to
      // the boost apply path (applyPayment only handles subscriptions).
      const r = ev.oneOff
        ? await billingEngine.applyOneOffBoost({
            uid: ev.subscriptionId, product: ev.product, propertyId: ev.propertyId,
            amountAgorot: ev.amountAgorot, transactionId: ev.transactionId,
            docId: ev.docId, docUrl: ev.docUrl, success: ev.success,
          })
        : await billingEngine.applyPayment(ev);
      return json(200, { ok: true, ...r });
    } catch (e) {
      console.error('webhook apply failed:', e?.message || e);
      return json(500, { message: 'activation error' });
    }
  }

  return json(404, { message: 'Not found' });
}

// Persona upsert with a monotonic-version guard: the write is applied only when
// there's no existing row OR the incoming version is >= the stored one. This
// makes out-of-order / retried writes safe — a stale snapshot can never
// overwrite a fresher persona (matches the client's version-based restore).
async function putPersonaVersioned(table, id, body) {
  if (!id) return json(400, { message: 'Missing id' });
  const incoming = Number(body.version) || 0;
  const item = { ...body, id, version: incoming };
  try {
    await ddb.send(new PutCommand({
      TableName: table.name,
      Item: item,
      ConditionExpression: 'attribute_not_exists(id) OR #v <= :v',
      ExpressionAttributeNames: { '#v': 'version' },
      ExpressionAttributeValues: { ':v': incoming },
    }));
    return json(200, item);
  } catch (e) {
    if (e && e.name === 'ConditionalCheckFailedException') {
      // A newer persona is already stored — ignore this stale write, don't error.
      return json(200, { ignored: true, reason: 'stale_version' });
    }
    throw e;
  }
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
  if (tableKey === 'users' || tableKey === 'persona') {
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

  // Kick off async .ply/.spz → .ksplat conversion so the viewer streams a compact,
  // fast splat instead of a 200-400 MB raw .ply. We do NOT return a predicted URL
  // (it would 404 during the ~30s conversion) — the converter writes the real
  // ksplatUrl back onto the property (model3d.ksplatUrl) in DynamoDB when done, so
  // a seeker fetching the listing later gets the fast splat; owner preview mean-
  // while falls back to plyUrl. Fully fail-soft.
  const splatSourceUrl = manifest.plyUrl || manifest.spzUrl;
  const srcKey = splatSourceUrl ? keyFromS3Url(splatSourceUrl) : null;
  if (srcKey && SPLAT_CONVERT_FN) {
    try {
      await lambda.send(new InvokeCommand({
        FunctionName: SPLAT_CONVERT_FN,
        InvocationType: 'Event', // async — never block the /3d/viewers response
        Payload: Buffer.from(JSON.stringify({
          bucket: S3_BUCKET,
          key: srcKey,
          propertyId,
          tableName: TABLES.properties.name,
        })),
      }));
    } catch (e) {
      console.warn('splat-convert invoke failed:', e.message);
    }
  }

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
        ksplatUrl: '', // populated async by rentch-splat-convert (read from DDB later)
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

  // ── AI generate mode (gpt-image-2) ────────────────────────────────────────
  // The user uploads up to 6 real photos of the room (more angles = less the
  // model has to invent); gpt-image-2 merges them into ONE seamless
  // equirectangular 360. Presign a PUT per input image.
  if (body.captureMode === 'ai') {
    const resultKey = `panoramas/results/${jobId}.png`;
    const variant = String(body.variant || '').slice(0, 24);
    // Variant mode: generate a lighting/tidy alternative FROM an existing full
    // 360 already in our bucket — reference it by key, no re-upload, no slots.
    if (body.srcUrl) {
      // Use keyFromS3Url so a path-style URL's bucket prefix is stripped AND the
      // key is validated (isSafeStorageKey) — the raw pathname let a caller point
      // srcKey at an arbitrary/other-bucket object.
      const srcKey = keyFromS3Url(body.srcUrl);
      if (srcKey) {
        await putPanoMeta(jobId, {
          jobId, propertyId, inputKeys: [srcKey], resultKey, captureMode: 'ai',
          variant, status: 'pending', createdAt: ts,
        });
        return json(200, { data: { jobId } }); // src already in bucket → no uploads
      }
    }
    const n = Math.max(1, Math.min(6, Number(body.imageCount) || 1));
    const inputKeys = [];
    const uploadUrls = [];
    for (let i = 0; i < n; i++) {
      const key = `panoramas/jobs/${jobId}/ai${i}.jpg`;
      inputKeys.push(key);
      uploadUrls.push(await getSignedUrl(
        s3,
        new PutObjectCommand({ Bucket: S3_BUCKET, Key: key, ContentType: 'image/jpeg' }),
        { expiresIn: 21600 },
      ));
    }
    await putPanoMeta(jobId, {
      jobId, propertyId, inputKeys, resultKey, captureMode: 'ai',
      variant, status: 'pending', createdAt: ts,
    });
    return json(200, { data: { jobId, uploadUrls } });
  }

  // ── Enhance mode (AI pole-fill + 360 wrap on an EXISTING pano) ─────────────
  // The client uploads the pano to improve to the single presigned URL, then
  // POSTs /panorama/:id/enhance. gpt-image-2 fills the missing ceiling/floor and
  // closes the 360 wrap on the undistorted cube faces (pano-stitch enhance op).
  if (body.captureMode === 'enhance') {
    const resultKey = `panoramas/results/${jobId}.jpg`;
    // An existing pano (already in our bucket) is used in place — no re-upload.
    // Otherwise presign one upload for the source pano.
    let uploadUrls = [];
    // keyFromS3Url strips the bucket prefix + validates the key (isSafeStorageKey).
    let srcKey = body.srcUrl ? keyFromS3Url(body.srcUrl) : null;
    if (!srcKey) {
      srcKey = `panoramas/jobs/${jobId}/src.jpg`;
      uploadUrls = [await getSignedUrl(
        s3,
        new PutObjectCommand({ Bucket: S3_BUCKET, Key: srcKey, ContentType: 'image/jpeg' }),
        { expiresIn: 21600 },
      )];
    }
    await putPanoMeta(jobId, {
      jobId, propertyId, srcKey, resultKey, captureMode: 'enhance',
      wrap: body.wrap !== false, poles: body.poles !== false,
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
    // Reject non-physical FOVs: at/above 180° the projector's tan(fov/2) blows up
    // (→∞) or sign-flips, mirroring/collapsing the frame into garbage.
    if (hfov <= 0 || vfov <= 0 || hfov >= 180 || vfov >= 180) return null;
    out.push({ yaw, pitch, hfov, vfov });
  }
  return out;
}

// Hardened super-prompt for gpt-image-2: a viewer-ready, seamless, faithful 360.
// Priority #1 is FAITHFULNESS — the model must reproduce only what the photos
// show and never invent furniture/rooms, because that is the landlord's main
// complaint. Feeding MORE photos (up to 6) shrinks the unseen area it has to fill.
const AI_PANO_PROMPT = [
  'You are given one or more images — photos or WIDE PANORAMAS — of the SAME real',
  'room/apartment. Merge them into ONE photorealistic monoscopic 360°×180°',
  'EQUIRECTANGULAR panorama of THIS EXACT space, to be mapped onto a full sphere in',
  'a VR/360 viewer where the user turns a complete circle and looks straight up and',
  'straight down.',
  '',
  'OUTPUT FORMAT (non-negotiable):',
  '• A SINGLE equirectangular (spherical / lat-long) image whose content is laid out',
  '  for a 2:1 sphere: the full horizontal width spans exactly 360° of longitude,',
  '  the full height spans 180° of latitude (zenith at the very top row, nadir at',
  '  the very bottom row).',
  '• This is NOT a fisheye, NOT a "tiny planet", NOT a stereographic or circular',
  '  crop, NOT a flat wide photo. No circular frame, no black border, no vignette.',
  '',
  'FAITHFULNESS — THE MOST IMPORTANT RULE:',
  '• Reproduce ONLY what is actually visible in the photos. Keep the EXACT same',
  '  furniture, wall colors, flooring, windows, doors, fixtures, materials and',
  '  layout — same positions, same proportions.',
  '• Do NOT invent, add, remove, move, or restyle ANY object. No new furniture,',
  '  windows, doors, artwork, plants, lamps, rugs, or decorations that are not in',
  '  the photos. No extra rooms, hallways, or fantasy elements.',
  '• CRITICAL: never add WINDOWS, doors, openings, skylights or glass to a wall',
  '  that is solid in the photos — keep every solid wall solid. Do NOT relight or',
  '  change the time of day; reproduce the SAME lighting that is in the photos.',
  '• For directions the photos do NOT cover, do NOT guess objects. Simply CONTINUE',
  '  the adjacent real wall / floor / ceiling with the same plain color and texture',
  '  — an empty neutral surface is CORRECT; inventing furniture there is WRONG.',
  '• If unsure whether something exists, leave it OUT. Under-fill, never fabricate.',
  '',
  'EQUIRECTANGULAR GEOMETRY (all mandatory):',
  '1) The HORIZON is a single straight horizontal line across the vertical middle',
  '   of the image. Eye-level walls sit in the middle band.',
  '2) POLES: the ceiling converges smoothly to the TOP edge and the floor to the',
  '   BOTTOM edge. Content stretches horizontally toward both poles (as real',
  '   equirectangular projection does) and meets each pole as one consistent',
  '   surface — no black cap, no swirl, no pinch artifact at top or bottom.',
  '3) Vertical structures (wall corners, door frames, window edges) are STRAIGHT',
  '   and vertical when near the horizontal center, and bow naturally only as they',
  '   approach the poles. No wavy or melting walls.',
  '',
  'SEAMLESS 360° WRAP (critical for the viewer):',
  '4) The far-LEFT column and the far-RIGHT column are the SAME physical direction,',
  '   so they must be pixel-continuous: matching geometry, color AND brightness, so',
  '   there is NO visible seam or line when the view wraps past 360°.',
  '5) Keep EXPOSURE and WHITE BALANCE consistent all the way around the circle — no',
  '   bright or dark vertical band, no color shift from one side to the other. One',
  '   even, natural real-estate interior exposure across the whole panorama.',
  '',
  'COVERAGE & INTEGRITY:',
  '6) FULL coverage — no black bars, no blank wedges, no missing ceiling or floor.',
  '7) Each real object appears EXACTLY ONCE. Do NOT duplicate, tile, mirror or',
  '   repeat furniture, windows or wall sections around the circle to fill space.',
  '8) HIGH quality: sharp focus, clean edges, realistic interior lighting, natural',
  '   white balance, no text, watermark, logo, or people.',
].join('\n');

// Variant generation: take an EXISTING full 360 and produce a lighting/tidy
// alternative of the SAME space. Shared "keep everything, change only X" guard
// so the model never re-invents the room or (the landlord's nightmare) adds a
// window to a solid wall — the exact failure that burned us before.
const _PANO_KEEP = [
  'You are given ONE equirectangular 360°×180° panorama of a real room. Return the',
  'SAME room as ONE equirectangular (2:1 lat-long) panorama: identical layout,',
  'walls, windows, doors, furniture, objects and proportions, all in the same',
  'places. Preserve the equirectangular projection and the seamless left↔right',
  '360° wrap (the far-left and far-right columns stay pixel-continuous). Do NOT',
  'add, remove, move or restyle ANY object, and NEVER add a window, door, opening',
  'or skylight to a wall that is solid. No text, watermark, logo or people.',
].join('\n');
const VARIANT_PROMPTS = {
  tidy: `${_PANO_KEEP}\nONLY change: TIDY the room. Straighten and organize what is already there — square up the books already on the shelves (keep the books), align cushions, fold throws, coil loose cables, clear litter/clutter from the surfaces and the floor. Keep it lived-in and homey, just neat and clean. Keep the SAME lighting and time of day.`,
  day: `${_PANO_KEEP}\nONLY change: the LIGHTING to bright natural midday daylight — soft even sunlight, neutral white balance, gentle realistic shadows. Keep every object and every window exactly as they are.`,
  evening: `${_PANO_KEEP}\nONLY change: the LIGHTING to a warm early-evening mood — soft golden interior light, the existing lamps glowing warmly, gentle warm tones. Keep every object and every window exactly as they are.`,
  night: `${_PANO_KEEP}\nONLY change: the LIGHTING to night — dark outside the existing windows, warm interior lamplight as the main light source, a cozy low-key mood. Keep every object and every window exactly as they are.`,
};
function promptForVariant(v) {
  return (v && VARIANT_PROMPTS[v]) || AI_PANO_PROMPT;
}

// POST /panorama/:id/ai-generate → kick off the gpt-image-2 generation. Because
// it takes ~50s (over the API-Gateway limit) we self-invoke this function as an
// async Event (see the `op:'aiGenerate'` hook at the top of the handler) and the
// client polls GET /panorama/:id as usual.
async function aiGeneratePanorama(jobId, event) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  const meta = await getPanoMeta(jobId);
  if (!meta) return json(404, { message: 'Panorama job not found' });
  if (meta.status === 'ready' || meta.status === 'failed') {
    return json(200, { data: panoData(meta) });
  }
  if (!OPENAI_API_KEY) {
    const failed = { ...meta, status: 'failed', error: 'AI generation not configured.' };
    await putPanoMeta(jobId, failed);
    return json(200, { data: panoData(failed) });
  }
  await putPanoMeta(jobId, { ...meta, status: 'processing', processedAt: Date.now() });
  await lambda.send(new InvokeCommand({
    FunctionName: process.env.AWS_LAMBDA_FUNCTION_NAME,
    InvocationType: 'Event',
    Payload: Buffer.from(JSON.stringify({ op: 'aiGenerate', jobId })),
  }));
  return json(200, { data: { jobId, status: 'processing' } });
}

// The async worker (self-invoked). Downloads the input images (up to 6), asks
// gpt-image-2 to merge them into one seamless equirectangular 360, uploads the
// PNG, and marks the job ready. Fail-soft: any error → status 'failed' + message.
async function runAiGenerate(jobId) {
  const meta = await getPanoMeta(jobId);
  if (!meta) return json(404, { message: 'not found' });
  try {
    const inputKeys = Array.isArray(meta.inputKeys) ? meta.inputKeys : [];
    if (inputKeys.length === 0) throw new Error('no input images');
    // Download the input image(s) once.
    const imgs = [];
    for (const key of inputKeys) {
      const obj = await s3.send(new GetObjectCommand({ Bucket: S3_BUCKET, Key: key }));
      imgs.push(await streamToBuffer(obj.Body));
    }
    // Try quality:high first; if OpenAI returns a 5xx / non-JSON gateway blip
    // (the slow high-quality call can hit an 'upstream connect error'), retry
    // once at default quality (faster + more reliable) so the job still succeeds.
    let out = null, lastErr = 'unknown';
    // COST: single default-quality attempt (variants are lighting shifts — 'high'
    // isn't needed and doubled the price), plus ONE retry only on a TRANSIENT 5xx.
    // A fatal 4xx (bad request / content policy) must not trigger a second paid
    // image generation.
    for (let attempt = 0; attempt < 2 && !out; attempt++) {
      try {
        const form = new FormData();
        form.append('model', 'gpt-image-2');
        form.append('size', '1536x1024');
        form.append('prompt', promptForVariant(meta.variant));
        for (const bytes of imgs) {
          form.append('image[]', new Blob([bytes], { type: 'image/jpeg' }), 'pano.jpg');
        }
        const r = await fetch('https://api.openai.com/v1/images/edits', {
          method: 'POST',
          headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
          body: form,
        });
        const text = await r.text();
        if (!r.ok) {
          lastErr = `HTTP ${r.status}: ${text.slice(0, 140)}`;
          if (r.status < 500) break; // fatal → no retry, no double charge
          continue;                  // transient 5xx → one retry
        }
        let j;
        try { j = JSON.parse(text); }
        catch { lastErr = 'non-JSON: ' + text.slice(0, 140); continue; }
        const b64 = j?.data?.[0]?.b64_json;
        if (!b64) { lastErr = 'no image: ' + text.slice(0, 140); break; }
        out = Buffer.from(b64, 'base64');
      } catch (e) {
        lastErr = String(e && e.message ? e.message : e);
      }
    }
    if (!out) throw new Error('gpt-image-2 failed: ' + lastErr);
    await s3.send(new PutObjectCommand({
      Bucket: S3_BUCKET, Key: meta.resultKey, Body: out,
      ContentType: 'image/png', CacheControl: 'public, max-age=31536000',
    }));
    // gpt-image-2 outputs 3:2, but a 360 viewer expects a 2:1 equirectangular.
    // The model already maps content equirectangularly, so pano-stitch just
    // stretches it to 2:1 in place (OpenCV). Best-effort — the 3:2 still loads if
    // the stitcher is unavailable.
    if (PANO_STITCH_FN) {
      try {
        await lambda.send(new InvokeCommand({
          FunctionName: PANO_STITCH_FN,
          InvocationType: 'RequestResponse',
          Payload: Buffer.from(JSON.stringify({
            op: 'resize2to1', bucket: S3_BUCKET, key: meta.resultKey,
          })),
        }));
      } catch (e) { console.error('resize2to1 skipped:', e); }
    }
    const imageUrl =
      `https://${S3_BUCKET}.s3.${process.env.AWS_REGION}.amazonaws.com/${meta.resultKey}`;
    await putPanoMeta(jobId, {
      ...meta, status: 'ready', imageUrl, haov: 360, vaov: 180,
      aiGenerated: true, finishedAt: Date.now(),
    });
  } catch (e) {
    await putPanoMeta(jobId, {
      ...meta, status: 'failed', error: String(e && e.message ? e.message : e).slice(0, 300),
    });
  }
  return json(200, { ok: true });
}

// POST /panorama/:id/enhance → async pole-fill + 360-wrap on the uploaded pano.
// Runs in PANO_STITCH_FN (OpenCV + the enhance pipeline); client polls GET.
async function enhancePanorama(jobId, event) {
  if (!callerUidOf(event)) return json(401, { message: 'Authentication required.' });
  const meta = await getPanoMeta(jobId);
  if (!meta) return json(404, { message: 'Panorama job not found' });
  if (meta.status === 'ready' || meta.status === 'failed') {
    return json(200, { data: panoData(meta) });
  }
  if (!PANO_STITCH_FN) {
    const failed = { ...meta, status: 'failed', error: 'Enhancer not configured (no PANO_STITCH_FN).' };
    await putPanoMeta(jobId, failed);
    return json(200, { data: panoData(failed) });
  }
  await putPanoMeta(jobId, { ...meta, status: 'processing', processedAt: Date.now() });
  await lambda.send(new InvokeCommand({
    FunctionName: PANO_STITCH_FN,
    InvocationType: 'Event',
    Payload: Buffer.from(JSON.stringify({
      op: 'enhance',
      bucket: S3_BUCKET,
      metaKey: `panoramas/meta/${jobId}.json`,
      srcKey: meta.srcKey,
      resultKey: meta.resultKey,
      wrap: meta.wrap !== false,
      poles: meta.poles !== false,
    })),
  }));
  return json(200, { data: { jobId, status: 'processing' } });
}

// A stitch/AI worker is invoked async (Event); if it's OOM/timeout-killed no
// Python exception fires, so no terminal 'failed' is ever written and the client
// would poll 'processing' forever. Past this age we report a terminal 'failed'
// so the client stops spinning and can retry. (Mirrors SCAN3D_MAX_AGE_MS.)
const PANO_MAX_AGE_MS = 15 * 60 * 1000;

async function getPanorama(jobId) {
  const meta = await getPanoMeta(jobId);
  if (!meta) return json(404, { message: 'Panorama job not found' });
  const nonTerminal = meta.status !== 'ready' && meta.status !== 'failed';
  if (nonTerminal && meta.createdAt &&
      Date.now() - meta.createdAt > PANO_MAX_AGE_MS) {
    return json(200, { data: { ...panoData(meta), status: 'failed',
      error: meta.error || 'timeout' } });
  }
  return json(200, { data: panoData(meta) });
}

function panoData(meta) {
  return {
    jobId: meta.jobId,
    status: meta.status || 'pending',
    imageUrl: meta.imageUrl || '',
    haov: meta.haov ?? 360,
    // Full-sphere default (matches haov=360); 60 mislabeled full spheres narrow.
    vaov: meta.vaov ?? 180,
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
// A KIRI reconstruction finishes well within an hour. Past this we stop masking
// a stuck/failed job as 'processing' forever and report a terminal 'failed', so
// the client can surface an error and stop polling.
const SCAN3D_MAX_AGE_MS = 90 * 60 * 1000;

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
  // Fail early (before the client records/uploads anything) when 3D
  // reconstruction isn't configured — the same 503 startScan3d returns, but at
  // job-creation so the app can gate the whole flow up front.
  if (!KIRI_API_KEY) return json(503, { message: '3D reconstruction not configured.' });
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
  // Age failsafe: never leave a job masked as 'processing' indefinitely. This
  // is the catch-all for a KIRI job stuck Uploading/Queuing, a persistently
  // oversized/corrupt result zip, or an expired download link that never
  // resolves — all of which otherwise loop as 'processing' forever.
  if (meta.createdAt && Date.now() - meta.createdAt > SCAN3D_MAX_AGE_MS) {
    const failed = { ...meta, status: 'failed', error: 'Reconstruction timed out' };
    await putScan3dMeta(jobId, failed);
    return json(200, { status: 'failed', error: failed.error });
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
      // An over-size result is PERMANENT (it will be too big on every retry) —
      // fail terminally instead of looping 'processing'. A plain download blip
      // stays 'processing' (transient; the age failsafe bounds it).
      if (zipRes.tooLarge) {
        await putScan3dMeta(jobId, { ...meta, status: 'failed', error: 'Model too large to process' });
        return json(200, { status: 'failed', error: 'Model too large to process' });
      }
      return json(200, { status: 'processing' });
    }
    const zipBuf = zipRes.buffer;

    let entries;
    try {
      entries = new AdmZip(zipBuf).getEntries();
    } catch (e) {
      // A corrupt/unreadable zip won't fix itself — terminal failure.
      console.warn('KIRI zip unpack failed', e.message);
      await putScan3dMeta(jobId, { ...meta, status: 'failed', error: 'Corrupt reconstruction bundle' });
      return json(200, { status: 'failed', error: 'Corrupt reconstruction bundle' });
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
        'יוצר טיוטת מודעת דירה — להשכרה או למכירה, לפי סוג העסקה שהמשתמש ביקש (transactionType). רק לאחר שנאספו כל הפרטים החיוניים מהמשתמש ולאחר שהמשתמש אישר במפורש שהפרטים נכונים. אין להמציא פרטים שלא נמסרו.',
      parameters: {
        type: 'object',
        properties: {
          transactionType: {
            type: 'string',
            enum: ['rent', 'sale'],
            description:
              'סוג העסקה: rent=להשכרה, sale=למכירה. זהה מדברי המשתמש ("להשכרה"/"להשכיר" → rent, "למכירה"/"למכור" → sale). אם לא ברור — שאל במפורש לפני היצירה. ברירת מחדל: rent.',
          },
          city: { type: 'string', description: 'עיר' },
          neighborhood: { type: 'string', description: 'שכונה (אופציונלי)' },
          street: { type: 'string', description: 'שם הרחוב' },
          streetNumber: { type: 'string', description: 'מספר הבית' },
          rooms: { type: 'number', description: 'מספר חדרים (אפשר חצי, למשל 3.5)' },
          price: {
            type: 'integer',
            description:
              'המחיר בשקלים: אם transactionType=rent → שכר דירה חודשי; אם transactionType=sale → מחיר המכירה הכולל.',
          },
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
  // Phase 2 — cohort taxonomy signals.
  'sector',           // 'jewish-secular' | 'jewish-religious' | 'arab'
  'isReligious',
  'religiousStream',  // 'dati_leumi' | 'charedi'
  'isOleh',
  'langPref',         // 'he' | 'en' | 'fr' ...
  'lifeStage',        // 'student' | 'young-professional' | 'family' | 'senior'
  'age',
  'carFree',
  'isInvestor',
  'intent',           // 'residence' | 'investment'
  'expecting',
  'numChildren',
  'childAge',
  'accessibilityNeed',
  'isSolo',
  'leaseFlex',
  'occupation',       // tenant job/occupation — read by the per-listing eligibility gate
  'minRooms',         // tenant's desired room count — read by the eligibility gate (minRooms criterion)
  'maxRooms',         // tenant's max desired room count (kept for completeness)
  'moveInBucket',     // 'immediate' | 'month' | 'quarter' | 'flexible' — read by the moveInWithin criterion
]);

// Resolve the searcher's cohort for main-feed ranking, cheapest-first: the GET
// query params alone often determine it (no DB read); only if they don't do we
// pay for one loadUserProfile. The pure resolution logic lives in
// resolveCohortFrom (unit-tested); here we only add the conditional DB load.
async function resolveCohort(query, callerUid) {
  const fromQuery = cohortFromSignals(querySignals(query));
  if (fromQuery || !callerUid) return fromQuery || null;
  const profile = await loadUserProfile(callerUid).catch(() => null);
  return resolveCohortFrom(query, profile);
}

// Pure merge: fold a {field:value} batch into an existing searchProfile map,
// keeping ONLY allowlisted keys (the trust boundary) and wrapping each in the
// {value, confidence, source, updatedAt} envelope. Returns { sp, written } where
// `sp` is the new map to persist and `written` is how many keys were accepted.
// Extracted so both the single- and batch-writers share one code path and so it
// can be unit-tested without DynamoDB (see profile_fields.selfcheck.mjs).
function mergeProfileFields(current, fields, confidence, source) {
  const sp = (current && current.searchProfile) || {};
  const conf = typeof confidence === 'number' ? Math.max(0, Math.min(1, confidence)) : 0.6;
  const src = typeof source === 'string' ? source.slice(0, 40) : 'assistant';
  const now = new Date().toISOString();
  let written = 0;
  for (const [field, value] of Object.entries(fields || {})) {
    if (!PROFILE_WRITABLE_FIELDS.has(field)) continue; // drop non-allowlisted
    sp[field] = { value, confidence: conf, source: src, updatedAt: now };
    written += 1;
  }
  return { sp, written };
}

// Merge-writes a BATCH of profile fields in ONE read-modify-write of the whole
// searchProfile map (vs. one round-trip per field). Read-modify-write so a
// missing parent isn't a problem and field keys can be dynamic. Returns the
// count of allowlisted keys actually written (0 if uid missing / all dropped).
// ponytail: last-writer-wins under concurrent writes — fine, a user's assistant
// turns are serialized; upgrade to a nested UpdateExpression if that changes.
async function saveUserProfileFields(uid, fields, confidence, source) {
  if (!uid) return 0;
  try {
    const current = await loadUserProfile(uid);
    const { sp, written } = mergeProfileFields(current, fields, confidence, source);
    if (written === 0) return 0; // nothing allowlisted → skip the write entirely
    await ddb.send(new UpdateCommand({
      TableName: TABLES.users.name,
      Key: { id: uid },
      UpdateExpression: 'SET searchProfile = :sp',
      ExpressionAttributeValues: { ':sp': sp },
    }));
    return written;
  } catch (e) {
    console.warn('saveUserProfileFields failed:', e.message);
    return 0;
  }
}

// Merge-writes one profile field. Thin wrapper over the batch writer.
async function saveUserProfileField(uid, field, value, confidence, source) {
  if (!uid || !PROFILE_WRITABLE_FIELDS.has(field)) return false;
  const written = await saveUserProfileFields(uid, { [field]: value }, confidence, source);
  return written > 0;
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
      rooms: {
        type: 'number',
        description:
          'מספר חדרים מבוקש כשהמשתמש נוקב במספר יחיד ("דירת 3 חדרים", "3 חדרים", '
          + '"שלושה חדרים"). זהו המקרה הנפוץ — השתמש בו תמיד למספר בודד. אפשר חצי (3.5).',
      },
      minRooms: {
        type: 'number',
        description: 'מינימום חדרים — רק לטווח מפורש ("לפחות 3", "3 עד 4", "מ-3").',
      },
      maxRooms: {
        type: 'number',
        description: 'מקסימום חדרים — רק לטווח מפורש ("עד 4", "3 עד 4", "לא יותר מ-4").',
      },
      minPrice: { type: 'integer', description: 'מחיר חודשי מינימלי בשקלים' },
      maxPrice: { type: 'integer', description: 'מחיר חודשי מקסימלי בשקלים' },
      pets: { type: 'boolean', description: 'מתיר חיות מחמד' },
      // ── the intent CONTRACT (mirrors client SearchIntent keys) ───────────────
      // The assistant distils the conversation into these; the ranking engine
      // consumes them directly (gates + intent-weighted scoring). Keep in sync
      // with lib/core/search/search_intent.dart.
      transactionType: {
        type: 'string', enum: ['rent', 'sale'],
        description: 'שכירות או מכירה (השקעה⇒sale)',
      },
      intents: {
        type: 'array',
        description: 'תגי אורח-חיים/מרחב שהמשתמש ביקש (בחר רק מה שנאמר במפורש)',
        items: {
          type: 'string',
          enum: [
            'near_sea', 'nightlife', 'quiet', 'central', 'spacious',
            'accessible', 'luxury', 'view', 'student', 'near_university',
            'investment', 'roommates', 'wfh', 'good_schools', 'quality_area',
          ],
        },
      },
      features: {
        type: 'array',
        description: 'מאפיינים נדרשים (feat_parking, feat_elevator, feat_pets, ...)',
        items: { type: 'string' },
      },
      // ── THE BRAIN: you decide WHAT matters and HOW MUCH ──────────────────────
      // After you understood the user, assign an importance 0..1 to ONLY the
      // factors that matter to THEM right now. Omit anything irrelevant — the
      // engine will not consider it. Always include `budget` and `size` when the
      // user gave a budget / room need. You understand the person better than a
      // fixed formula — this is where that understanding enters the math.
      weights: {
        type: 'object',
        description:
          'חשיבות 0..1 לכל גורם שחשוב למשתמש עכשיו (השמט גורמים לא-רלוונטיים). '
          + 'גורמים אפשריים: budget, location, area_quality, safety, value, size, '
          + 'amenities, transit, condition, schools, family, near_sea, yield, '
          + 'university, nightlife, quiet, luxury, view, spacious, accessible',
        additionalProperties: { type: 'number' },
      },
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
  // A single stated room count ("דירת 3 חדרים") is the common case: treat it as a
  // tight band [n, n+0.5] so a 3-room search matches 3 and 3.5 (the real near-
  // substitute) but never 2 or 4. An explicit min/max range wins if the model set it.
  const exactRooms = num(args.rooms);
  const minRooms = num(args.minRooms) ?? exactRooms;
  const maxRooms = num(args.maxRooms)
    ?? (exactRooms !== undefined ? exactRooms + 0.5 : undefined);
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

  console.log('search_listings', JSON.stringify({
    in: { rooms: args.rooms ?? null, minRooms: args.minRooms ?? null, maxRooms: args.maxRooms ?? null, city: wantCity || null },
    band: { minRooms: minRooms ?? null, maxRooms: maxRooms ?? null },
    scanned: rows.length, matched: matched.length,
    roomsOut: matched.map((p) => Number(p.rooms)),
  }));

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
    'אתה "עזרא" — אדם אמיתי, שעוזר לבעלי דירות לפרסם דירה באפליקציית Rently (להשכרה או למכירה). אתה לא בוט ולא תוכנה — אתה פשוט עזרא.',
    'התנהל כמו סוכן נדל"ן מקצועי ורציני — אמין, בטוח בעצמו, מכובד ומדויק, שמנהל שיחה חיה וזורמת ומוביל אותה ביעילות עד לפרסום. מקצועיות ורצינות קודם כול, אך עדיין חם, סבלני ונגיש.',
    'חוק ברזל בסגנון: כתוב עברית טבעית ואנושית לחלוטין, כמו בן אדם שמדבר בטלפון בנעימות. אסור להשתמש בכוכביות (* או **), בסימני עיצוב markdown, בכותרות, ברשימות עם מקפים או נקודות, או באימוג׳ים. לעולם אל תזכיר שאתה בינה מלאכותית, מודל, עוזר ממוחשב או תוכנה. רק טקסט רגיל, חם ואישי.',
    'הקהל שלך הוא בעלי דירות מבוגרים (גיל 65 ומעלה) שאינם בקיאים בטכנולוגיה. דבר עברית פשוטה, ברורה ונעימה, במשפטים קצרים. בלי מילים באנגלית ובלי ז׳רגון.',
    name ? `שם המשתמש הוא ${name}. אפשר לפנות אליו בשמו מדי פעם, בנימוס.` : '',
    'פתיחת השיחה: בקש מבעל הדירה, בחום ובקצרה, לספר בכמה מילים על הדירה — איפה היא, כמה חדרים, וכל מה שירצה. הקשב היטב, וחלץ מהתיאור החופשי כמה שיותר פרטים בעצמך.',
    'עסקה — להשכרה או למכירה: זהה מוקדם מה בעל הדירה רוצה. אם אמר "למכירה"/"למכור" זו עסקת מכירה (transactionType=sale) והמחיר הוא מחיר המכירה הכולל (למשל 1,800,000 ₪), לא שכר חודשי. אם אמר "להשכרה"/"להשכיר" זו השכרה (rent) והמחיר הוא שכר דירה חודשי. אם זה לא נאמר במפורש — שאל בפשטות "הדירה להשכרה או למכירה?" לפני שתמשיך. אל תניח אוטומטית השכרה כשמדובר במכירה.',
    'אחרי התיאור — שאל רק על הפרטים החיוניים שחסרים, ואחד 2-3 פרטים קצרים בשאלה אחת ידידותית (למשל: "מצוין! נשאר רק לדעת את הקומה והמחיר החודשי — מה הם?"). אל תשאל על מה שכבר נאמר, ואל תמתח את זה לשאלה-אחר-שאלה אם אפשר לקצר.',
    'חשוב מאוד: הקלט מגיע מהמרת דיבור-לטקסט ולעיתים יש בו שגיאות, במיוחד במספרים בעברית. פרש בהיגיון רב: "ארבע 1000" או "ארבע אלף" פירושו 4000; "שלושת אלפים וחמש מאות" פירושו 3500; "אלפיים" פירושו 2000. אם מספר או פרט נשמע לא הגיוני או לא ברור — חזור עליו בעדינות לאישור ("רק לוודא — המחיר הוא ארבעת אלפים שקלים בחודש?") לפני שתמשיך.',
    'מה אתה יכול לעשות: לעזור לפרסם דירה חדשה (לאסוף את הפרטים בשיחה), לתת תמונת מצב על הדירות הקיימות, ולהסביר בפשטות איך האפליקציה עובדת.',
    'שלושת הפרטים שחובה כדי לפרסם: עיר, מספר חדרים, ומחיר חודשי. רחוב ומספר בית, קומה, גודל במ"ר, מצב הדירה ותאריך כניסה משפרים את המודעה אך אינם חוסמים פרסום — אם בעל הדירה מסר אותם קח אותם, אחרת אל תעכב בשבילם. אם לא נמסר תאריך כניסה — הנח "מיידי". כדאי לשאול גם על רחוב וקומה בנימוס, אבל אם המשתמש לא יודע או רוצה לדלג — המשך בלעדיהם.',
    'המטרה החשובה ביותר: לסיים את כל התהליך מהר ובנעימים, תוך דקה עד שתיים. היה תכליתי, חם ומקצועי כמו סוכן שירות מעולה. תשובות קצרות מאוד — משפט אחד או שניים, בלי חזרות מיותרות. ברגע שיש לפחות עיר, מספר חדרים ומחיר, אשר אותם במשפט קצר אחד, ואם המשתמש מאשר — קרא מיד ל-create_property. אל תיתקע בלולאת שאלות: אם נאספו שלושת הפרטים החיוניים, התקדם לפרסום.',
    'כפתורי בחירה (חשוב לחוויית המשתמש!): כשאתה שואל שאלה שיש לה כמה תשובות נפוצות וקצרות — מצב הדירה, תאריך כניסה, מספר חדרים, או אישור כן/לא — הוסף בסוף ההודעה שורה נפרדת בדיוק בפורמט הזה: [[CHOICES: אפשרות1 | אפשרות2 | אפשרות3]] (בין 2 ל-5 אפשרויות קצרות מאוד, מילה-שתיים כל אחת). דוגמאות: למצב הדירה [[CHOICES: משופצת | חדשה | במצב טוב | דורשת שיפוץ]]; לתאריך כניסה [[CHOICES: מיידי | בעוד חודש | גמיש]]; לאישור פרטים [[CHOICES: כן, הכל נכון | יש טעות]]. אל תוסיף שורה כזו כשאין תשובות נפוצות (כתובת, מחיר חופשי). הכפתורים הם תוספת — תמיד כתוב גם את השאלה במילים.',
    'רק כשיש לפחות עיר, מספר חדרים ומחיר — ולאחר שחזרת על הפרטים והמשתמש אישר שהכל נכון — קרא לפונקציה create_property עם כל מה שנמסר, כולל transactionType (rent או sale) לפי סוג העסקה שזוהה, וכולל רחוב/קומה אם ידועים. אל תמציא נתונים שלא נמסרו.',
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

// CANONICAL two-sided weights — MUST mirror the Dart MatchWeights
// (lib/core/matching/match_engine.dart:6-31). Kept in sync by
// test/match_weights_canonical_test.dart. Any change here needs the same change
// there (and vice-versa) or the drift guard fails.
const MATCH_W = {
  budgetHeadroomBonus: 10, // afford ratio >= 1.15
  budgetOkBonus: 5,        // ratio >= 1.0  (headroom * 0.5)
  budgetShortPenalty: 18,  // ratio <  1.0
  requirementBonus: 6,     // landlord requirement the tenant satisfies
  sharedTagBonus: 6,       // shared non-required preference key (was 4 — drift)
  conflictPenalty: 28,     // per unmet deal-breaker on the standalone fit
};

function scoreLandlordToTenant({ budgetMax, price, tenantKeys, tenantDealKeys, landlordKeys, landlordDealKeys }) {
  let fit = 60;
  const reasons = [];
  const conflicts = [];

  if (budgetMax > 0 && price > 0) {
    const ratio = budgetMax / price;
    if (ratio >= 1.15) { fit += MATCH_W.budgetHeadroomBonus; reasons.push('תקציב נוח לשכר הדירה'); }
    else if (ratio >= 1.0) { fit += MATCH_W.budgetOkBonus; }
    else { fit -= MATCH_W.budgetShortPenalty; conflicts.push('התקציב נמוך משכר הדירה'); }
  }
  for (const k of landlordDealKeys) {
    if (tenantKeys.has(k)) fit += MATCH_W.requirementBonus; else conflicts.push(`חסר: ${k}`);
  }
  for (const k of tenantDealKeys) {
    if (!landlordKeys.has(k)) conflicts.push(`השוכר דורש: ${k}`);
  }
  const shared = [...tenantKeys].filter((k) => landlordKeys.has(k));
  fit += shared.length * MATCH_W.sharedTagBonus;
  for (const k of shared) reasons.push(k);

  fit -= conflicts.length * MATCH_W.conflictPenalty;
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

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON body.' }); }

  const messages = Array.isArray(body.messages) ? body.messages.slice(-20) : [];
  if (messages.length === 0) return json(400, { message: 'messages required' });

  // אתי — the tenant apartment-search assistant, runs on OpenAI (GPT). No Gemini
  // dependency, so she stays up even if the Gemini key is missing/over-quota.
  if (body.mode === 'tenant_search') {
    return await handleTenantSearchChat(messages, uid);
  }

  const [properties, profile] = await Promise.all([
    loadOwnerProperties(uid),
    loadUserProfile(uid),
  ]);
  const systemText = buildErikSystemPrompt(profile, properties) + '\n' + GROUNDING_RULE;

  try {
    // Primary: OpenAI function-calling → Erik is LIVE + professional off the
    // dropped Gemini. Fallback: the Gemini tool loop if a Gemini key is set.
    let result = await openaiToolLoop(systemText, messages, uid);
    if (!result) {
      if (!GEMINI_API_KEY) {
        return json(200, { reply: 'העוזר האישי אינו זמין כרגע. אנא נסו שוב מאוחר יותר.', propertyDraft: null });
      }
      const contents = messages
        .filter((m) => m && typeof m.text === 'string' && m.text.trim())
        .map((m) => ({
          role: m.role === 'assistant' ? 'model' : 'user',
          parts: [{ text: String(m.text).slice(0, 2000) }],
        }));
      result = await runAssistantToolLoop(systemText, contents, assistantToolsFull(), uid);
    }
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
// COST: 3 hops covers the real publish/search flows (each hop re-sends the long
// system prompt as billed input); 5 was rarely reached and just added spend.
const MAX_TOOL_HOPS = 3;
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

// Erik's tool loop on OpenAI function-calling — so his conversation is LIVE and
// professional off the (dropped) Gemini quota. Mirrors runAssistantToolLoop:
// search_listings / update_user_profile feed back, create_property is terminal.
// Returns { reply, propertyDraft, listings } or null so the caller can fall back.
async function openaiToolLoop(systemText, messages, uid = null) {
  if (!OPENAI_API_KEY) return null;
  const tools = assistantToolsFull().functionDeclarations.map((d) => ({
    type: 'function',
    function: { name: d.name, description: d.description, parameters: d.parameters },
  }));
  const convo = [
    { role: 'system', content: systemText },
    ...messages
      .filter((m) => m && typeof m.text === 'string' && m.text.trim())
      .map((m) => ({
        role: m.role === 'assistant' ? 'assistant' : 'user',
        content: String(m.text).slice(0, 2000),
      })),
  ];
  let propertyDraft = null;
  let listings = [];
  const call = async (body) => {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({ model: OPENAI_CHAT_MODEL, ...body }),
    });
    if (!res.ok) { console.warn('erik openai', res.status); return null; }
    return res.json();
  };

  for (let hop = 0; hop < MAX_TOOL_HOPS; hop++) {
    const data = await call({ messages: convo, tools, tool_choice: 'auto', max_completion_tokens: 500 });
    if (!data) return null;
    const msg = data.choices?.[0]?.message;
    if (!msg) return null;
    const calls = msg.tool_calls || [];
    if (calls.length === 0) {
      return { reply: (msg.content || '').trim(), propertyDraft, listings };
    }
    const createCall = calls.find((c) => c.function?.name === 'create_property');
    if (createCall) {
      try { propertyDraft = JSON.parse(createCall.function.arguments || '{}'); }
      catch { propertyDraft = {}; }
      return { reply: (msg.content || '').trim(), propertyDraft, listings };
    }
    convo.push(msg); // assistant message carrying the tool_calls
    for (const c of calls) {
      let args = {};
      try { args = JSON.parse(c.function.arguments || '{}'); } catch {}
      let result = {};
      if (c.function?.name === 'update_user_profile') {
        result = { saved: await saveUserProfileField(uid, args.field, args.value, args.confidence, args.source) };
      } else if (c.function?.name === 'search_listings') {
        listings = await runSearchListings(args);
        result = { results: listings, count: listings.length };
      }
      convo.push({ role: 'tool', tool_call_id: c.id, content: JSON.stringify(result) });
    }
  }
  // hop cap → one final no-tools pass to summarise.
  const data = await call({ messages: convo, max_completion_tokens: 400 });
  return { reply: (data?.choices?.[0]?.message?.content || '').trim(), propertyDraft, listings };
}

// ── נועה — tenant apartment-search chat (warm, separate from Erik) ────────────
// Conversational layer only: helps a renter describe what they want; the app
// runs the actual catalogue search and shows result cards. No listing tool.
// OpenAI chat-completion for אתי's warm reply. Plain text, NO tools. Returns the
// reply string, or null on any failure (unfunded/over-quota/network) so the caller
// can fall back to Gemini. Isolated from the shared Gemini quota by design.
async function openaiChat(systemText, messages) {
  if (!OPENAI_API_KEY) return null;
  const chat = messages
    .filter((m) => m && typeof m.text === 'string' && m.text.trim())
    .map((m) => ({
      role: m.role === 'assistant' ? 'assistant' : 'user',
      content: String(m.text).slice(0, 2000),
    }));
  try {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: OPENAI_CHAT_MODEL,
        messages: [{ role: 'system', content: systemText }, ...chat],
        // gpt-5.x chat models: max_completion_tokens (not max_tokens) and only
        // the default temperature — sending the old params returns HTTP 400.
        max_completion_tokens: 400,
      }),
    });
    if (!res.ok) { console.warn('openai chat', res.status); return null; }
    const data = await res.json();
    return (data?.choices?.[0]?.message?.content || '').trim() || null;
  } catch (e) {
    console.warn('openai chat', e.message);
    return null;
  }
}

// ── ETTI — intent-extraction engine ─────────────────────────────────────────
// Reads a free-text query, reasons about Israeli housing culture, and emits a
// strict JSON plan: hard_constraints (gating), soft_weights (1.0 neutral, up to
// 2.0), inferred_persona. The client maps it (EttiPlan) into the ranking engine.
const ETTI_EXTRACT_PROMPT = [
  '"Etti", an advanced Real Estate Intent Extraction Engine specialized in the',
  'Israeli housing market. Read BETWEEN THE LINES: infer implicit needs, weighted',
  'preferences and hard constraints from deep knowledge of Israeli culture & real',
  'estate dynamics.',
  '',
  'SUPER-RULES:',
  '1. Tight budget ⇒ reliance on transit, periphery, or roommates. High weight for',
  '   transit, value; flexible on size/location.',
  '2. Family/kids expansion (baby, "upgrading to 4 rooms", "near parents") ⇒ safety,',
  '   schools, stroller accessibility (ground_floor/elevator).',
  '3. Investor/short-term (near universities/hospitals/bases, high budget, "sale") ⇒',
  '   ignore personal lifestyle fit; focus yield, high_demand_areas, low_vacancy.',
  '4. Specific community/religious needs (synagogue, Shabbat, Olim communities,',
  '   Haredi cities, mamad in the South) ⇒ turn location & specific amenities into',
  '   STRICT HARD CONSTRAINTS that override general preferences.',
  '',
  'OUTPUT strictly valid JSON ONLY (no prose), with:',
  '- "hard_constraints": absolute deal-breakers, e.g. {"city":"תל אביב-יפו","mamad":true,"max_price":6000}',
  '- "soft_weights": inferred factors → float −1.0..2.0 (1.0 neutral, 2.0 highly desired).',
  '  Use factor names: budget, value, size, transit, location/central_location, near_sea,',
  '  nightlife, quiet_neighborhood, safety/security, schools_nearby, family_friendly,',
  '  accessibility_stroller/ground_floor, luxury, view, yield, university, spacious.',
  '- "inferred_persona": one short sentence of your reasoning.',
  '',
  'EXAMPLES:',
  'Q: "מחפשים לשדרג ל-4 חדרים, באזור שקט, שיהיה קרוב להורים בפתח תקווה."',
  'A: {"hard_constraints":{"city":"פתח תקווה"},"soft_weights":{"family_friendly":1.8,"schools_nearby":1.5,"accessibility_stroller":1.5,"quiet_neighborhood":1.5},"inferred_persona":"Young family expanding, needs support from parents, prioritizes safety and child accessibility over nightlife."}',
  'Q: "סטודיו או חדר במרכז תל אביב, לא אכפת לי הגודל, רק שיהיה קרוב לים."',
  'A: {"hard_constraints":{"city":"תל אביב-יפו"},"soft_weights":{"near_sea":2.0,"central_location":1.8,"nightlife":1.5,"size":-1.0,"transit":1.2},"inferred_persona":"Single professional/student, willing to sacrifice size and budget for prime location and lifestyle."}',
  'Q: "דירה באשקלון, חובה ממ\\"ד תקני, עדיפות לקומת קרקע."',
  'A: {"hard_constraints":{"city":"אשקלון","mamad":true},"soft_weights":{"ground_floor":1.5,"security":2.0,"accessibility":1.2},"inferred_persona":"Security-driven search in the South, prioritizing safety and quick access to shelter."}',
].join('\n');

// JSON-mode chat: returns a parsed object (or null). Uses OpenAI structured output.
async function openaiExtractJson(systemText, userText) {
  if (!OPENAI_API_KEY) return null;
  try {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${OPENAI_API_KEY}` },
      body: JSON.stringify({
        model: OPENAI_CHAT_MODEL,
        messages: [
          { role: 'system', content: systemText },
          { role: 'user', content: String(userText || '').slice(0, 1500) },
        ],
        max_completion_tokens: 500,
        response_format: { type: 'json_object' },
      }),
    });
    if (!res.ok) { console.warn('etti extract', res.status); return null; }
    const data = await res.json();
    const txt = (data?.choices?.[0]?.message?.content || '').trim();
    try { return JSON.parse(txt); } catch { return null; }
  } catch (e) { console.warn('etti extract', e.message); return null; }
}

// Whisper STT — base64 audio (m4a/aac/wav/webm) → transcript. Runs OpenAI's
// audio transcription (much better Hebrew than the device recogniser). The key
// stays server-side; the client just uploads the recorded clip.
async function handleTranscribe(event) {
  let body = {};
  try { body = JSON.parse(event.body || '{}'); } catch {}
  const b64 = (body.audio || '').toString();
  if (!b64) return json(400, { error: 'missing audio' });
  const bytes = Buffer.from(b64, 'base64');
  if (!bytes.length) return json(400, { error: 'empty audio' });
  const mime = (body.mime || 'audio/m4a').toString();
  const lang = (body.language || 'he').toString();

  // Primary: OpenAI Whisper family (best quality) — used only if the project has
  // access. Secondary: Gemini multimodal transcription (this project's key does).
  const viaOpenAi = await openaiTranscribe(bytes, mime, lang);
  if (viaOpenAi != null) return json(200, { text: viaOpenAi, engine: 'openai' });
  const viaGemini = await geminiTranscribe(bytes, mime);
  if (viaGemini != null) return json(200, { text: viaGemini, engine: 'gemini' });
  return json(502, { error: 'stt failed' });
}

async function openaiTranscribe(bytes, mime, lang) {
  if (!OPENAI_API_KEY) return null;
  const ext = mime.includes('wav') ? 'wav'
    : mime.includes('webm') ? 'webm'
    : mime.includes('mpeg') || mime.includes('mp3') ? 'mp3'
    : mime.includes('ogg') ? 'ogg' : 'm4a';
  try {
    const form = new FormData();
    form.append('file', new Blob([bytes], { type: mime }), `audio.${ext}`);
    form.append('model', OPENAI_STT_MODEL);
    form.append('language', lang);
    form.append('temperature', '0');
    const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
      body: form,
    });
    if (!res.ok) return null; // model not enabled → fall through to Gemini
    const data = await res.json();
    return (data.text || '').toString().trim();
  } catch { return null; }
}

async function geminiTranscribe(bytes, mime) {
  if (!GEMINI_API_KEY) return null;
  const gmime = mime.includes('wav') ? 'audio/wav'
    : mime.includes('webm') ? 'audio/webm'
    : mime.includes('ogg') ? 'audio/ogg'
    : mime.includes('mp3') || mime.includes('mpeg') ? 'audio/mp3'
    : 'audio/aac'; // m4a/aacLc from the recorder
  const reqBody = {
    contents: [{
      parts: [
        { text: 'תמלל במדויק את האודיו הבא לעברית. החזר אך ורק את הטקסט המדובר — בלי הקדמות, בלי מרכאות, בלי הסברים. אם אין דיבור, החזר מחרוזת ריקה.' },
        { inlineData: { mimeType: gmime, data: bytes.toString('base64') } },
      ],
    }],
    generationConfig: { temperature: 0 },
  };
  for (const model of ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-flash-latest']) {
    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`;
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(reqBody),
      });
      if (!res.ok) continue;
      const data = await res.json();
      const text = (data?.candidates?.[0]?.content?.parts || [])
        .map((p) => p.text || '').join('').trim();
      return text.replace(/^["'״]+|["'״]+$/g, '').trim();
    } catch { /* next model */ }
  }
  return null;
}

async function handleEttiExtract(event) {
  let query = '';
  try { query = (JSON.parse(event.body || '{}').query || '').toString(); } catch {}
  if (!query.trim()) return json(400, { error: 'missing query' });
  const plan = await openaiExtractJson(ETTI_EXTRACT_PROMPT, query);
  return json(200, plan || { hard_constraints: {}, soft_weights: {}, inferred_persona: '' });
}

// אתי's warm reply. NO server tool loop: the CLIENT renders listings from its own
// on-device search, so the server only needs to write the warm conversational
// text. Primary = OpenAI (off the Gemini quota); fallback = a SINGLE tool-less
// Gemini call (vs the old MAX_TOOL_HOPS×models fan-out that saturated the quota).
// Tenant-specific grounding — the app does the search, so אתי must NOT call any
// tool (the shared GROUNDING_RULE tells the model to call search_listings, which
// the tenant chat has no tools for → it leaks fake tool-call JSON + spam tokens).
const TENANT_GROUNDING =
  'אל תמציאי דירות, כתובות, מחירים או פרטים ספציפיים — האפליקציה עצמה מציגה למשתמש '
  + 'את הדירות האמיתיות שמתאימות. לעולם אל תכתבי JSON, קוד, שמות פונקציות, קריאות '
  + 'לכלים (כמו search_listings) או טקסט בשפה זרה — אך ורק עברית טבעית, חמה וקצרה.';

// Detect the language of the user's last message so we can HARD-force the reply
// language — a Hebrew-heavy system prompt otherwise drags every answer to Hebrew.
function detectLang(text) {
  const t = String(text || '');
  if (/[؀-ۿ]/.test(t)) return 'Arabic (العربية)';
  if (/[Ѐ-ӿ]/.test(t)) return 'Russian (Русский)';
  if (/[֐-׿]/.test(t)) return 'Hebrew (עברית)';
  if (/[a-zA-Z]/.test(t)) {
    return /\b(je|une?|les?|des|du|bonjour|cherche|pièces?|proche|appartement|quartier|budget)\b/i.test(t)
      ? 'French (Français)' : 'English';
  }
  return 'Hebrew (עברית)';
}

async function handleTenantSearchChat(messages, uid = null) {
  const lastUser = [...messages].reverse()
    .find((m) => m && m.role !== 'assistant' && m.text)?.text || '';
  const lang = detectLang(lastUser);
  const langDirective =
    `\nCRITICAL LANGUAGE RULE: the user is writing in ${lang}. You MUST write your ENTIRE reply ONLY in ${lang}, with the same warmth — never switch to another language.`;
  const systemText =
    buildTenantSearchSystemPrompt() + '\n' + TENANT_GROUNDING + langDirective;
  try {
    let raw = await openaiChat(systemText, messages);
    if (!raw) {
      const contents = messages
        .filter((m) => m && typeof m.text === 'string' && m.text.trim())
        .map((m) => ({
          role: m.role === 'assistant' ? 'model' : 'user',
          parts: [{ text: String(m.text).slice(0, 2000) }],
        }));
      const data = await geminiGenerate(systemText, contents);
      raw = ((data?.candidates?.[0]?.content?.parts) || [])
        .map((p) => p.text || '').join('');
    }
    let reply = stripMarkup(raw || '');
    // Safety net: scrub any leaked tool-call / JSON / foreign-spam artifacts that
    // slipped through (belt-and-suspenders with TENANT_GROUNDING above).
    reply = reply
      .replace(/\{[^{}]*\}/g, ' ')                        // JSON blobs
      .replace(/\b(to=)?search_listings\b[^\n]*/gi, ' ')  // tool-call text
      .replace(/[一-鿿]+/g, ' ')                  // CJK spam tokens
      .replace(/\buserdata\b/gi, ' ')
      .replace(/[ \t]{2,}/g, ' ')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    let suggestions = [];
    const cm = /\[\[\s*CHOICES?\s*:\s*([^\]]+)\]\]/i.exec(reply);
    if (cm) {
      suggestions = cm[1].split('|').map((s) => s.trim()).filter(Boolean).slice(0, 5);
      reply = reply.replace(cm[0], '').trim();
    }
    if (!reply) reply = 'ספר לי עוד קצת על מה שאתה מחפש, ואני כבר אדאג לדייק 🙂';
    return json(200, { reply, suggestions, propertyDraft: null, listings: [] });
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
    'את "אתי" — בן אדם אמיתי, חמה ונחמדה, שעוזרת לאנשים למצוא דירה באפליקציית Rently — גם להשכרה וגם לקנייה. את לא בוט ולא תוכנה — את פשוט אתי. לעולם אל תזכירי שאת בינה מלאכותית, מודל או תוכנה.',
    'שפה: עני תמיד באותה שפה שבה האדם כתב אלייך — כתב בעברית עני בעברית, בערבית עני בערבית, באנגלית באנגלית, בצרפתית בצרפתית, ברוסית ברוסית. שמרי על אותה חמימות וטבעיות בכל שפה.',
    'Rently תומכת גם בשכירות וגם במכירה, אז לעולם אל תגידי שאנחנו "רק שכירות". אם מישהו מחפש לקנות או להשקיע — עזרי לו: בררי בעדינות אם זו שכירות או קנייה, תקציב, אזור, ולמשקיע גם מה חשוב לו בתשואה.',
    'סגנון: שפה טבעית, חמה ומשוחררת, כמו חבר/ה שמבינ/ה עניין. משפטים קצרים (שורה־שתיים), בלי רובוטיות, בלי ז׳רגון, בלי כוכביות או markdown. מותר אימוג׳י אחד פה ושם, בטעם.',
    'המטרה: להבין מה האדם באמת מחפש ולגרום לו להרגיש שמקשיבים לו. תני לו לספר על עצמו במילים שלו — אזור, תקציב, כמה חדרים, אורח חיים, חיות מחמד, קרבה לעבודה או לתחבורה, ומה חשוב לו.',
    // איסוף שיטתי אך שיחתי: לאורך השיחה (לא בבת אחת!) דאגי לכסות בעדינות את שבעת הדברים
    // שמאפשרים לי לבנות התאמה מדויקת מול נתוני האמת. אל תשאלי כמו טופס — שאלה אחת חמה
    // בכל פעם, ותמיד קודם שקפי מה כבר הבנת.
    'לאורך השיחה חשוב שתאספי בעדינות שבעה דברים כדי שאוכל לחשב התאמה אמיתית: (1) גיל/שלב חיים, (2) איפה הוא גר היום, (3) באיזה אזור/עיר הוא מחפש, (4) מה הכי חשוב לו (deal-breakers — למשל ממ"ד, מעלית, שקט), (5) דברים שהוא אוהב וישמחו אותו (ים, פארקים, בתי קפה, קהילה), (6) תקציב, (7) מה עוד חשוב שהדירה תכלול. אל תשאלי הכול בבת אחת — כסי אותם טבעי לאורך השיחה, שאלה אחת קצרה בכל פעם, והתחילי מהחסר הקריטי ביותר לפרסונה שלו.',
    'את חכמה ומנוסה — יודעת לזהות מיהו האדם שמולך ולהסיק את הצרכים הסמויים שלו, גם כשלא אמר הכול: משפחות (ממ"ד, שקט, קרבה לגנים/בתי ספר), סטודנטים (זול, שותפים, קרוב לאוניברסיטה ולתחבורה), עולים חדשים ודוברי אנגלית (הקלי, עני גם באנגלית פשוטה אם צריך, הכווני לאזורים ידידותיים), דתיים/חרדים (קרבה לבית כנסת ולמוסדות המתאימים לזרם שלהם), מבוגרים ובעלי צרכי נגישות (מעלית, קומה נמוכה, נגישות, קרבה לשירותי בריאות), זוגות ורווקים (שקט מול תוסס), עובדים מהבית (חדר עבודה, שקט, אינטרנט), בעלי חיות מחמד, ומשקיעים (תשואה, אזורים מבוקשים). התאימי את השאלה והטון לפרסונה.',
    'אל תרוצי ישר להציע — קודם שקפי בחום מה הבנת, ושאלי שאלה אחת קצרה ועדינה וחכמה (הכי חשובה לפרסונה הזו) כדי להכיר אותו יותר (שאלה אחת בכל פעם). כשכיסית את עיקרי הדברים (לפחות אזור + תקציב, ועוד כמה מהשבעה) — אמרי בחום שאת בודקת מה הכי מתאים, כי האפליקציה תדרג ותציג לו את הדירות לפי מה שחשוב לו. אל תמציאי דירות, כתובות או מחירים ספציפיים בעצמך.',
    'מיקום: אם האדם מדבר על "האזור שלי" / "פה" / "כאן" / "קרוב אליי" — האפליקציה מזהה אוטומטית את המיקום שלו דרך ה-GPS, אז אל תשאלי אותו באיזו עיר; פשוט אמרי בחום שאת מאתרת אותו ומחפשת באזור שלו.',
    'תמיד כווני להביא לו דירות אמיתיות ולא להיתקע: אם חסר רק פרט קריטי אחד (בדרך כלל אזור או תקציב) בקשי אותו בעדינות, אחרת אמרי שאת מחפשת ומראה לו התאמות. אם משהו מצומצם מדי, הציעי להרחיב אזור/תקציב במקום לומר "אין".',
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
// Ephemeral OpenAI Realtime session for אתי's live GPT voice. The client connects
// to wss://api.openai.com/v1/realtime with the returned client_secret — the raw
// OpenAI key never leaves this Lambda. The session defines a female voice, the
// Hebrew real-estate-agent persona, and a `search_listings` tool the CLIENT runs
// (so the live conversation can surface real listings inline).
async function createRealtimeSession(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  if (!OPENAI_API_KEY) {
    return json(503, { message: 'Live voice assistant not configured.' });
  }

  // Two personas share the Realtime pipeline: אתי (tenant search) and עזרא
  // (landlord publish). The client passes mode='landlord' for עזרא.
  const reqBody = (() => {
    try { return event.body ? JSON.parse(event.body) : {}; } catch { return {}; }
  })();
  const isLandlord = reqBody.mode === 'landlord' || reqBody.mode === 'erik';

  const search_listings = {
    type: 'function',
    name: 'search_listings',
    description:
      'Search real apartment listings for the tenant once enough criteria are known. The client app runs the search against its catalogue and shows the result cards inline.',
    parameters: {
      type: 'object',
      properties: {
        city: { type: 'string', description: 'City or area (Hebrew)' },
        minRooms: { type: 'number' },
        maxRooms: { type: 'number' },
        maxPrice: { type: 'number', description: 'Max monthly rent in ILS' },
        amenities: {
          type: 'array',
          items: { type: 'string' },
          description: 'e.g. elevator, parking, balcony, mamad',
        },
        lifestyle: {
          type: 'string',
          description:
            'religious | secular | traditional | haredi | family | student | couple',
        },
      },
    },
  };

  // עזרא's create_property tool — mirrors the chat tool (incl. transactionType so
  // sale listings aren't forced into the rental flow).
  const create_property = {
    type: 'function',
    name: 'create_property',
    description:
      'יוצר טיוטת מודעת דירה (להשכרה או למכירה לפי transactionType) לאחר שנאספו עיר, מספר חדרים ומחיר, והמשתמש אישר. אל תמציא פרטים.',
    parameters: {
      type: 'object',
      properties: {
        transactionType: { type: 'string', enum: ['rent', 'sale'], description: 'rent=להשכרה, sale=למכירה' },
        city: { type: 'string', description: 'עיר' },
        neighborhood: { type: 'string', description: 'שכונה (אופציונלי)' },
        street: { type: 'string', description: 'רחוב' },
        streetNumber: { type: 'string', description: 'מספר בית' },
        rooms: { type: 'number', description: 'מספר חדרים' },
        price: { type: 'integer', description: 'מחיר: שכר חודשי (rent) או מחיר כולל (sale)' },
        sizeM2: { type: 'integer', description: 'גודל במ"ר' },
        floor: { type: 'integer', description: 'קומה' },
        condition: { type: 'string', description: 'מצב הדירה' },
        entryDate: { type: 'string', description: 'תאריך כניסה' },
        description: { type: 'string', description: 'תיאור קצר' },
      },
      required: ['city', 'rooms', 'price'],
    },
  };

  const instructions = isLandlord
    ? [
        'אתה "עזרא", עוזר אישי ישראלי לבעלי דירות — חם, אנושי, סבלני ומקצועי מאוד, כמו סוכן נדל"ן ותיק.',
        'דבר עברית טבעית וזורמת במשפטים קצרים, כמו בשיחת טלפון. הקהל הוא בעלי דירות מבוגרים — בלי ז\'רגון ובלי אנגלית.',
        'המטרה: לעזור לפרסם דירה במהירות. זהה מוקדם אם זו השכרה או מכירה (transactionType). אם לא ברור — שאל במפורש. במכירה המחיר הוא מחיר כולל, בהשכרה שכר חודשי.',
        'הקשב הרבה, דבר מעט. שאל שאלה אחת מדויקת בכל פעם רק על מה שחסר (עיר, חדרים, מחיר הם החובה; רחוב/קומה/מצב משפרים אך לא חוסמים). אל תחפור ואל תשאל כמו טופס.',
        'ברגע שיש עיר, חדרים ומחיר — חזור עליהם במשפט קצר, ואם המשתמש אישר קרא מיד ל-create_property עם transactionType. אחרי הפרסום ההוספה של תמונות נעשית באפליקציה.',
      ].join(' ')
    : [
        'את "אתי", סוכנת נדל״ן ישראלית — חמה, אנושית, נעימה מאוד ומקצועית מאוד.',
        'דברי עברית טבעית וזורמת, במשפטים קצרים כמו בשיחת טלפון אמיתית.',
        'המטרה: להבין מה השוכר צריך כדי שהאפליקציה תדרג לו דירות מול נתוני אמת. לאורך השיחה כסי בעדינות: גיל/שלב חיים, איפה הוא גר היום, איזה אזור/עיר הוא מחפש, מה הכי חשוב לו (must-have), מה הוא אוהב (ים/פארקים/בתי קפה/קהילה), תקציב, ומספר חדרים ואורח חיים (משפחה/סטודנט/זוג, דתי/חילוני, חיות מחמד, חניה, מעלית).',
        'שאלה אחת בכל פעם — הקשיבי, חדדי, ואל תציפי בשאלות. אל תשאלי כמו טופס; כסי את הדברים טבעי, מהחסר הקריטי ביותר קודם.',
        'ברגע שיש מספיק פרטים קראי לפונקציה search_listings כדי להציג דירות אמיתיות, ואז הציגי אותן בקצרה בקול.',
        'אם המשתמש אומר "פה"/"כאן" בלי לציין עיר — בקשי אישור לאתר את המיקום שלו.',
        'היי אמינה: אל תמציאי דירות — הציגי רק מה שחוזר מ-search_listings.',
      ].join(' ');

  const tools = isLandlord ? [create_property, search_listings] : [search_listings];

  // New Realtime GA API (POST /v1/realtime/client_secrets): the session config is
  // nested under `session`, audio/voice moved under `audio.output.voice`, and the
  // ephemeral token comes back at top-level `value` (ek_...). The old flat
  // /v1/realtime/sessions endpoint 404s on the current models.
  const body = {
    session: {
      type: 'realtime',
      model: OPENAI_REALTIME_MODEL,
      instructions,
      audio: {
        input: {
          transcription: { model: 'whisper-1' },
          turn_detection: { type: 'server_vad' },
        },
        output: { voice: OPENAI_REALTIME_VOICE },
      },
      tools,
      tool_choice: 'auto',
    },
  };

  try {
    const res = await fetch('https://api.openai.com/v1/realtime/client_secrets', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || !data.value) {
      console.error('OpenAI realtime session error:', res.status, data);
      return json(502, { message: 'Could not start live voice session.' });
    }
    // Shape back-compat for the client: it reads session.client_secret.value.
    return json(200, {
      session: { ...(data.session || {}), client_secret: { value: data.value } },
      wsUrl: `wss://api.openai.com/v1/realtime?model=${encodeURIComponent(OPENAI_REALTIME_MODEL)}`,
    });
  } catch (e) {
    console.error('OpenAI realtime session exception:', e);
    return json(502, { message: 'Could not start live voice session.' });
  }
}

async function handleAssistantLiveToken(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  if (!GEMINI_LIVE_API_KEY) {
    return json(503, { message: 'Live assistant not configured.' });
  }

  let mode = '';
  try { mode = (JSON.parse(event.body || '{}').mode || '').toString(); } catch { /* no body */ }

  let systemText;
  let tools;
  if (mode === 'tenant_search') {
    // אתי — SPOKEN apartment search. The CLIENT runs the real search on-device
    // (its full ranking engine) when she calls search_listings and streams cards
    // inline, so the token only DECLARES the tool; no owner context is loaded.
    systemText = buildTenantSearchSystemPrompt()
      + '\n' + TENANT_GROUNDING
      + '\nזוהי שיחה קולית חיה: דברי קצר, חם וטבעי כמו בטלפון. בלי markdown, בלי '
      + '[[CHOICES]], בלי להקריא רשימות ארוכות של דירות. שאלי שאלה אחת בכל פעם. '
      + 'ברגע שיש עיר, או תקציב, או מספר חדרים — קראי מיד ל-search_listings, ואז '
      + 'אמרי בחום שמצאת כמה התאמות שמופיעות עכשיו על המסך.';
    tools = [{ functionDeclarations: [SEARCH_LISTINGS_TOOL] }];
  } else {
    // Erik (owner/publish) — unchanged behaviour.
    let properties = [];
    let profile = null;
    try {
      [properties, profile] = await Promise.all([
        loadOwnerProperties(uid),
        loadUserProfile(uid),
      ]);
    } catch { /* context is best-effort */ }
    systemText = buildErikSystemPrompt(profile, properties);
    tools = [ASSISTANT_TOOL];
  }

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
      tools,
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

// (Removed dead GEMINI TTS_MODEL/TTS_VOICE constants — TTS runs on OpenAI
// (OPENAI_TTS_MODEL); these were declared but never called.)

async function handleAssistantTts(event) {
  const uid = callerUidOf(event);
  if (!uid) return json(401, { message: 'Authentication required.' });
  if (!OPENAI_API_KEY) return json(200, { audio: null });

  let body = {};
  try { body = event.body ? JSON.parse(event.body) : {}; }
  catch { return json(400, { message: 'Invalid JSON.' }); }
  const text = stripMarkup((body.text || '').toString()).slice(0, 1200);
  if (!text) return json(400, { message: 'text required' });
  // Warm female (coral) for אתי by default; the client sends 'onyx' for עזרא.
  const voice = (body.voice || 'coral').toString();

  try {
    // OpenAI TTS → raw 24kHz 16-bit mono PCM (response_format:'pcm'), which the
    // client wraps into a WAV — so no client change is needed. Real human voice.
    const res = await fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: OPENAI_TTS_MODEL,
        voice,
        input: text,
        response_format: 'pcm',
      }),
    });
    if (!res.ok) { console.warn('tts', res.status); return json(200, { audio: null }); }
    const buf = Buffer.from(await res.arrayBuffer());
    return json(200, { audio: buf.toString('base64'), sampleRate: 24000 });
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
    channel_id: 'rently_alerts',
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
