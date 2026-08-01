// Morning (חשבונית ירוקה / Green Invoice) + Grow integration client.
//
// One thin, testable wrapper around the Green Invoice REST API. The router
// never talks to the provider directly — it calls these functions. Every
// provider-specific field/endpoint is centralised here and marked `CONFIRM`
// so finalising against the Green Invoice API docs is a one-file change.
//
// Auth model: POST /account/token {id, secret} → JWT, sent as
// `Authorization: Bearer <jwt>` on every call. Token cached ~55 min.
//
// Secrets come ONLY from env (never hard-coded): MORNING_API_KEY,
// MORNING_API_SECRET, MORNING_WEBHOOK_SECRET. Config: MORNING_API_BASE,
// MORNING_PLUGIN_ID, MORNING_VAT_TYPE.
//
// `fetch` is injectable (setFetch) so the self-check runs with zero network.

import crypto from 'node:crypto';

const DEFAULT_BASE = 'https://api.greeninvoice.co.il/api/v1';
// Sandbox base (set MORNING_API_BASE to this for testing):
//   https://sandbox.d.greeninvoice.co.il/api/v1

// Green Invoice document types (CONFIRM against account config):
//   320 = חשבונית מס/קבלה (tax invoice + receipt, the one we want per charge)
//   400 = קבלה (receipt only)
export const DOC_TYPE = { INVOICE_RECEIPT: 320, RECEIPT: 400 };

// OAuth 2.0 token endpoint (Morning 2.0.0). NOTE: a different HOST from the REST
// base — prod api.morning.co, sandbox api.sandbox.morning.dev. Override via
// MORNING_OAUTH_TOKEN_URL when testing against sandbox.
const DEFAULT_OAUTH_TOKEN_URL = 'https://api.morning.co/idp/v1/oauth/token';

function cfg() {
  return {
    base: (process.env.MORNING_API_BASE || DEFAULT_BASE).replace(/\/+$/, ''),
    key: process.env.MORNING_API_KEY || '',
    secret: process.env.MORNING_API_SECRET || '',
    pluginId: process.env.MORNING_PLUGIN_ID || '',
    // Green Invoice vatType: 0 = default (VAT applies). We charge VAT-inclusive.
    vatType: process.env.MORNING_VAT_TYPE != null ? Number(process.env.MORNING_VAT_TYPE) : 0,
    // Payment-form method group. REQUIRED by the Digital-Payments (Grow) plugin
    // our live terminal uses. 100 = credit card (also: 110 PayPal, 120 Bit,
    // 150 Google Pay, 160 Apple Pay). Override via MORNING_PAYMENT_GROUP.
    paymentGroup: process.env.MORNING_PAYMENT_GROUP != null ? Number(process.env.MORNING_PAYMENT_GROUP) : 100,
    webhookSecret: process.env.MORNING_WEBHOOK_SECRET || '',
    // Auth mode: OAuth 2.0 client_credentials (2.0.0) when MORNING_OAUTH is set,
    // else the legacy /account/token flow. Same key/secret pair either way.
    oauth: /^(1|true|yes)$/i.test(String(process.env.MORNING_OAUTH || '')),
    oauthTokenUrl: process.env.MORNING_OAUTH_TOKEN_URL || DEFAULT_OAUTH_TOKEN_URL,
  };
}

// ── fetch injection (tests stub this) ────────────────────────────────────────
let _fetch = (...a) => globalThis.fetch(...a);
export function setFetch(fn) { _fetch = fn; }

// ── token cache ──────────────────────────────────────────────────────────────
let _token = { jwt: null, exp: 0 };
let _tokenInflight = null; // de-dup concurrent mints (e.g. the cron charging many subs)
export function _resetTokenCache() { _token = { jwt: null, exp: 0 }; _tokenInflight = null; }

export async function getToken() {
  const now = Date.now();
  if (_token.jwt && _token.exp - 60_000 > now) return _token.jwt;
  if (_tokenInflight) return _tokenInflight; // a mint is already in progress → share it
  _tokenInflight = (async () => {
    const c = cfg();
    if (!c.key || !c.secret) throw new Error('MORNING credentials missing (MORNING_API_KEY/SECRET)');
    const req = c.oauth
      // OAuth 2.0 (2.0.0): client_credentials on the IdP host → { accessToken, expiresAt }.
      ? { url: c.oauthTokenUrl,
          body: { grant_type: 'client_credentials', client_id: c.key, client_secret: c.secret } }
      // Legacy: /account/token on the REST base → { token }.
      : { url: `${c.base}/account/token`, body: { id: c.key, secret: c.secret } };
    const res = await _fetch(req.url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body),
    });
    if (!res.ok) throw new Error(`morning token failed: ${res.status}`);
    const data = await res.json();
    const jwt = data.accessToken || data.token || data.jwt;
    if (!jwt) throw new Error('morning token: no token in response');
    // OAuth reports expiresAt (unix seconds) → cache to 60s before it; the token
    // is valid 1h. Legacy tokens live ~30 min → cache 25 min. api()'s 401-retry
    // is the backstop for either.
    const exp = c.oauth && Number(data.expiresAt)
      ? Number(data.expiresAt) * 1000 - 60_000
      : Date.now() + (c.oauth ? 55 * 60_000 : 25 * 60_000);
    _token = { jwt, exp };
    return jwt;
  })();
  try {
    return await _tokenInflight;
  } finally {
    _tokenInflight = null; // clear so a later expiry re-mints
  }
}

// Authenticated JSON call. Retries once on 401 with a fresh token.
async function api(path, { method = 'POST', body, headers } = {}, _retry = true) {
  const c = cfg();
  const jwt = await getToken();
  const res = await _fetch(`${c.base}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${jwt}`,
      ...(headers || {}),
    },
    body: body != null ? JSON.stringify(body) : undefined,
  });
  if (res.status === 401 && _retry) {
    _resetTokenCache();
    return api(path, { method, body, headers }, false);
  }
  const text = await res.text();
  let data;
  try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
  if (!res.ok) {
    const err = new Error(`morning ${method} ${path} → ${res.status}`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

// ── clients ──────────────────────────────────────────────────────────────────
// Find-or-create a Green Invoice client for a landlord. Returns the client id.
export async function upsertClient({ name, email, taxId }) {
  // CONFIRM: /clients/search request/response shape.
  if (email) {
    try {
      const found = await api('/clients/search', { body: { emails: [email], page: 1, pageSize: 1 } });
      const hit = (found.items || found.data || [])[0];
      if (hit && hit.id) return hit.id;
    } catch { /* fall through to create */ }
  }
  const created = await api('/clients', {
    body: {
      name: name || email || 'Rently landlord',
      emails: email ? [email] : [],
      ...(taxId ? { taxId } : {}),
    },
  });
  return created.id;
}

// ── hosted payment page (first payment; saves a token for recurring) ─────────
// Returns { url } — the client opens it in a WebView. `plan` is our plan object.
export async function createPaymentForm({
  plan, clientId, clientName, clientEmail, successUrl, failureUrl, notifyUrl, subscriptionId,
}) {
  const c = cfg();
  const priceIls = plan.priceAgorot / 100;
  // Verified against the live Green Invoice API: /payments/form takes the TOTAL
  // in `amount` (top level). `price` is ignored → errorCode 2417 "סכום מסמך לא
  // תקין". `income` still carries the invoice line items.
  const body = {
    description: `מנוי Rently — ${plan.label}`,
    type: 320,                       // generate a חשבונית מס/קבלה on success
    lang: 'he',
    currency: 'ILS',
    amount: priceIls,                // ← the charge total (verified field)
    vatType: c.vatType,              // required by /payments/form (spec)
    maxPayments: 1,
    pluginId: c.pluginId || undefined,
    group: c.paymentGroup,           // required by the Grow (Digital Payments) terminal
    client: {
      id: clientId || undefined,
      name: clientName || undefined,
      emails: clientEmail ? [clientEmail] : undefined,
    },
    // NOTE: do NOT send an `income` array on /payments/form — with `amount`
    // present it triggers 2417/2422 (receipts≠payments). The document line is
    // generated from `amount` + `description` when the payment completes.
    // Save the payment method so the monthly cron can charge it later.
    addToken: true,                  // CONFIRM: exact flag to persist a token
    successUrl,
    failureUrl,
    notifyUrl,                       // server-to-server IPN → our /billing/webhook
    // Round-trips back to us in the IPN so we can match the payment to its sub.
    custom: subscriptionId,
  };
  const out = await api('/payments/form', { body });
  const url = out.url || out.data?.url;
  if (!url) { const e = new Error('morning: no payment url'); e.data = out; throw e; }
  return { url, raw: out };
}

// ── one-off hosted payment (no saved token) — e.g. the 50₪ AI-contract unlock ─
// Same verified shape as createPaymentForm (total in `amount`, no `income`), but
// a fixed arbitrary amount and NO token save (single charge, not recurring).
export async function createPaymentFormOneOff({
  amountIls, description, clientId, clientName, clientEmail, custom,
  successUrl, failureUrl, notifyUrl,
}) {
  const c = cfg();
  const out = await api('/payments/form', {
    body: {
      description: description || 'Rently',
      type: 320,
      lang: 'he',
      currency: 'ILS',
      amount: Number(amountIls),
      vatType: c.vatType,            // required by /payments/form (spec)
      maxPayments: 1,
      pluginId: c.pluginId || undefined,
      group: c.paymentGroup,         // required by the Grow (Digital Payments) terminal
      client: {
        id: clientId || undefined,
        name: clientName || undefined,
        emails: clientEmail ? [clientEmail] : undefined,
      },
      successUrl,
      failureUrl,
      notifyUrl,
      custom,
    },
  });
  const url = out.url || out.data?.url;
  if (!url) { const e = new Error('morning: no one-off payment url'); e.data = out; throw e; }
  return { url, raw: out };
}

// ── recurring charge of a saved token (monthly/annual renewal) ───────────────
// Charges the stored token and (via type:320) issues a tax-invoice/receipt.
// `idempotencyKey` MUST be stable for a given billing cycle (e.g.
// "<uid>:<periodEnd>") so a retried charge for the same period is deduped
// provider-side and never captures money twice (CONFIRM the exact Green Invoice
// field — sent as both a body field and a header for safety).
export async function chargeToken({ plan, token, clientId, clientName, clientEmail, idempotencyKey }) {
  const c = cfg();
  const priceIls = plan.priceAgorot / 100;
  // Mirrors the verified /payments/form shape: total in `amount`, NO income
  // array (income + amount → 2417/2422). CONFIRM the exact token-charge endpoint
  // once a real saved token exists (this path is exercised only by the cron).
  const body = {
    token,
    type: 320,
    lang: 'he',
    currency: 'ILS',
    amount: priceIls,
    ...(idempotencyKey ? { idempotencyKey } : {}),
    pluginId: c.pluginId || undefined,
    client: {
      id: clientId || undefined,
      name: clientName || undefined,
      emails: clientEmail ? [clientEmail] : undefined,
    },
  };
  const out = await api('/payments', {
    body,
    headers: idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : undefined,
  });
  // Normalise the varied success shapes into one result. IMPORTANT: never treat
  // a bare `id` as success — declined charges are also assigned a reference id,
  // so `!!out.id` would false-positive a failed charge (silent revenue loss).
  const ok = out.success === true || out.status === 1 || out.errorCode === 0;
  return {
    ok,
    transactionId: String(out.transactionId || out.paymentId || out.id || ''),
    docId: out.documentId || out.docId || out.document?.id || null,
    docUrl: out.documentUrl || out.document?.url?.he || out.document?.url?.origin || null,
    raw: out,
  };
}

// ── explicit document creation (fallback when a charge didn't auto-issue one) ─
export async function createDocument({ type = DOC_TYPE.INVOICE_RECEIPT, plan, clientId, clientName, clientEmail }) {
  const c = cfg();
  const priceIls = plan.priceAgorot / 100;
  const out = await api('/documents', {
    body: {
      type,
      lang: 'he',
      currency: 'ILS',
      client: {
        id: clientId || undefined,
        name: clientName || undefined,
        emails: clientEmail ? [clientEmail] : undefined,
      },
      income: [{
        description: `מנוי Rently (${plan.label})`,
        quantity: 1,
        price: priceIls,
        currency: 'ILS',
        vatType: c.vatType,
      }],
    },
  });
  return {
    docId: out.id || null,
    docUrl: out.url?.he || out.url?.origin || out.url || null,
    raw: out,
  };
}

// ── webhook verification ─────────────────────────────────────────────────────
// The provider's IPN can't carry a Firebase JWT, so we verify a shared secret.
// Scheme (CONFIRM): HMAC-SHA256 of the raw request body, hex, compared to the
// `x-morning-signature` header, in constant time. If no webhook secret is
// configured we FAIL CLOSED (reject) — a webhook must be verifiable.
export function verifyWebhook(headers = {}, rawBody = '') {
  const c = cfg();
  if (!c.webhookSecret) return false; // fail closed: never trust an unverified IPN
  // API Gateway REST APIs PRESERVE header casing (Title-Case, e.g.
  // `X-Morning-Signature`), so normalise to a lowercase-keyed map before lookup
  // rather than guessing a few casings.
  const lower = {};
  for (const [k, v] of Object.entries(headers)) lower[k.toLowerCase()] = v;
  // Morning 2.0.0 signs webhooks with `x-webhook-signature` (HMAC-SHA256 hex of
  // the raw body). Keep the legacy names as fallbacks for the Grow notifyUrl IPN.
  const provided = String(
    lower['x-webhook-signature'] ||
    lower['x-morning-signature'] ||
    lower['x-signature'] || '').trim();
  if (!provided) return false;
  const expected = crypto.createHmac('sha256', c.webhookSecret).update(rawBody, 'utf8').digest('hex');
  const a = Buffer.from(expected);
  const b = Buffer.from(provided);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// Normalise an IPN payload into the fields the router cares about. Tolerant of
// Green Invoice's varied field names (CONFIRM against a real IPN sample).
export function parseWebhook(payload = {}) {
  const p = payload.data || payload;
  // `custom` round-trips as "<uid>::<planId>" so the plan GRANTED is bound to the
  // specific payment link that was actually paid — not a mutable server field.
  const rawCustom = String(p.custom || p.customData || '');
  const [subId, planId] = rawCustom.split('::');
  // Best-effort charged amount (agorot) for a defense-in-depth price cross-check.
  const amountIls = p.sum ?? p.amount ?? p.price ?? p.total ?? null;
  return {
    subscriptionId: subId || rawCustom || null,
    planId: planId || null,
    amountAgorot: amountIls != null && !Number.isNaN(Number(amountIls))
      ? Math.round(Number(amountIls) * 100) : null,
    success: p.status === 1 || p.success === true || p.errorCode === 0,
    token: p.token || p.cardToken || null,
    cardLast4: p.cardSuffix || p.last4 || p.lastDigits || null,
    cardBrand: p.cardBrand || p.brand || null,
    transactionId: String(p.transactionId || p.paymentId || p.asmachta || p.id || ''),
    docId: p.documentId || p.docId || null,
    docUrl: p.documentUrl || p.docUrl || null,
    clientId: p.clientId || null,
    email: p.payerEmail || p.email || null,
  };
}
