// nadlan_cbs.mjs — "good deal?" price badge from sold-deal comps + CBS trend.
//
// ponytail: TWO unofficial/awkward free sources here.
//   (1) nadlan sold deals (רשות המסים, surfaced via GovMap real-estate REST):
//       undocumented, rate-sensitive, and shapes drift. We throttle to ≤5 req/s,
//       back off on 429/5xx, and fail-soft to insufficient_data — a price badge
//       is a nice-to-have, never block the listing.
//   (2) CBS (api.cbs.gov.il) housing price index: REQUIRES a User-Agent header
//       (it 403s without one) and attribution in the product (CC-like terms).
// CACHING: deal comps for a location change slowly. Cache priceBadge() inputs
// rounded to ~250 m grid cells (lat/lng to 3 decimals) for 7–30 days. Cache
// cbsTrend(districtId) for 24h+ (the index updates monthly). Both are pure
// reads — safe to memoise hard. Bound nadlan calls so a hot listing-create
// path can't fan out and trip the source's rate limit.

const TIMEOUT_MS = 8000;
const UA = 'RentlyBot/1.0 (+https://rently.co.il; real-estate market signal; attribution: CBS/data.gov.il)';

// Hebrew badge labels (UI maps these; values here are stable enum keys):
//   great_deal       → "מתחת לשוק / מציאה"
//   fair             → "מחיר הוגן / תואם שוק"
//   above_market     → "מעל מחיר השוק"
//   insufficient_data→ "אין מספיק נתונים"

// ---------------------------------------------------------------------------
// Tiny client-side throttle: serialise nadlan calls to ≤5 req/s with backoff.
// (In Lambda each invocation is its own process, so this caps *per-invocation*
// fan-out — exactly what we need when enriching one listing.)
let _lastCall = 0;
const MIN_GAP_MS = 200; // 5 req/s
async function throttle() {
  const now = Date.now();
  const wait = Math.max(0, _lastCall + MIN_GAP_MS - now);
  if (wait) await sleep(wait);
  _lastCall = Date.now();
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchJson(url, opts = {}, retries = 2) {
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
    try {
      const res = await fetch(url, {
        ...opts,
        signal: ctrl.signal,
        headers: { 'User-Agent': UA, 'Accept': 'application/json', ...(opts.headers || {}) },
      });
      if (res.status === 429 || res.status >= 500) {
        clearTimeout(t);
        if (attempt < retries) { await sleep(300 * 2 ** attempt); continue; } // exp backoff
        return null;
      }
      if (!res.ok) { clearTimeout(t); return null; }
      return await res.json();
    } catch {
      if (attempt < retries) { await sleep(300 * 2 ** attempt); continue; }
      return null;
    } finally {
      clearTimeout(t);
    }
  }
  return null;
}

// ---- stats helpers ---------------------------------------------------------
function median(xs) {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
function quantile(sorted, q) {
  if (!sorted.length) return null;
  const pos = (sorted.length - 1) * q;
  const lo = Math.floor(pos), hi = Math.ceil(pos);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}
// IQR outlier trim: drop points outside [Q1-1.5·IQR, Q3+1.5·IQR].
function iqrTrim(xs) {
  if (xs.length < 4) return xs;
  const s = [...xs].sort((a, b) => a - b);
  const q1 = quantile(s, 0.25), q3 = quantile(s, 0.75);
  const iqr = q3 - q1;
  const lo = q1 - 1.5 * iqr, hi = q3 + 1.5 * iqr;
  return s.filter((x) => x >= lo && x <= hi);
}

// haversine metres
function distM(lat1, lng1, lat2, lng2) {
  const R = 6371000, toR = Math.PI / 180;
  const dLat = (lat2 - lat1) * toR, dLng = (lng2 - lng1) * toR;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * toR) * Math.cos(lat2 * toR) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// Pull comparable sold deals near a point from the nadlan REST surface.
// Returns [{ppm, rooms, dateMonthsAgo}] — best-effort, [] on failure.
async function fetchDeals(lat, lng) {
  // ponytail: BLOCKED — nadlan deals source needs session-cookie priming;
  // priceBadge is insufficient_data until a working comps source lands.
  // The govmap /api/real-estate/deals endpoint is 404 (dead), and the real
  // nadlan.gov.il source requires browser anti-bot cookies we can't mint
  // server-side. Return [] so priceBadge stays hidden rather than wrong.
  // (Left the fetch/normalise machinery below wired for when a source lands.)
  return [];
  // eslint-disable-next-line no-unreachable
  await throttle();
  // GovMap real-estate deals endpoint: query sold transactions around a point.
  // We request a radius window; the source returns deal records with price,
  // area (m²), rooms and a deal date. Field names vary, so we normalise hard.
  const url =
    'https://www.govmap.gov.il/api/real-estate/deals' +
    `?lat=${lat.toFixed(6)}&lng=${lng.toFixed(6)}&radius=700`;
  const raw = await fetchJson(url);
  const rows = pluckRows(raw);
  const now = Date.now();
  const out = [];
  for (const r of rows) {
    const price = num(r.price, r.Price, r.dealAmount, r.DEAL_AMOUNT, r.mchir, r.amount);
    const area = num(r.area, r.Area, r.squareMeters, r.AREA, r.shetach, r.size);
    const rooms = num(r.rooms, r.Rooms, r.ROOMS, r.chadarim, r.roomsNum);
    const dateRaw = r.dealDate ?? r.date ?? r.DEAL_DATE ?? r.dealDateTime ?? r.taarich;
    if (!price || !area || area < 10) continue;
    const ppm = price / area;
    if (!Number.isFinite(ppm) || ppm < 1000 || ppm > 300000) continue; // sanity ₪/m²
    const t = Date.parse(dateRaw);
    const monthsAgo = Number.isFinite(t) ? (now - t) / (1000 * 60 * 60 * 24 * 30.44) : 12;
    out.push({ ppm, rooms: rooms || null, monthsAgo: Math.max(0, monthsAgo) });
  }
  return out;
}

function pluckRows(raw) {
  if (!raw) return [];
  if (Array.isArray(raw)) return raw;
  for (const k of ['data', 'deals', 'results', 'items', 'records']) {
    if (Array.isArray(raw[k])) return raw[k];
    if (Array.isArray(raw[k]?.deals)) return raw[k].deals;
  }
  return [];
}
function num(...vals) {
  for (const v of vals) {
    if (v == null) continue;
    const n = typeof v === 'number' ? v : Number(String(v).replace(/[,\s₪]/g, ''));
    if (Number.isFinite(n) && n !== 0) return n;
  }
  return null;
}

// Time-adjust each comp's ₪/m² to "today" using CBS YoY trend if available,
// else leave as-is. trendPct is annual %, monthsAgo months → factor.
function timeAdjust(ppm, monthsAgo, yoyPct) {
  if (!Number.isFinite(yoyPct)) return ppm;
  const annual = yoyPct / 100;
  return ppm * Math.pow(1 + annual, monthsAgo / 12);
}

/**
 * Price badge for a listing vs. nearby comparable sold deals.
 * @param {{lat:number,lng:number,rooms:number,area:number,price:number}} l
 * @returns {Promise<{medianPpm:number,deltaPct:number,badge:string,sampleN:number}|null>}
 *          badge ∈ {great_deal, fair, above_market, insufficient_data}.
 *          Returns insufficient_data (not null) when comps are too few but the
 *          fetch succeeded; null only on bad input.
 */
export async function priceBadge({ lat, lng, rooms, area, price }) {
  if (![lat, lng, area, price].every(Number.isFinite) || area <= 0 || price <= 0) return null;
  const listingPpm = price / area;

  // ponytail: BLOCKED — fetchDeals returns [] (no working comps source yet),
  // so this always yields insufficient_data and the badge stays hidden. It
  // becomes real automatically once a comps source is wired into fetchDeals.
  const deals = await fetchDeals(lat, lng);

  // optional time adjustment via CBS national trend (best-effort, cached upstream).
  let yoy = NaN;
  const trend = await cbsTrend().catch(() => null);
  if (trend && Number.isFinite(trend.yoyPct)) yoy = trend.yoyPct;

  // comparable cohort: ±1 room, within ~24 months, IQR-trimmed.
  const cohortRaw = deals.filter((d) =>
    d.monthsAgo <= 24 &&
    (rooms == null || d.rooms == null || Math.abs(d.rooms - rooms) <= 1)
  ).map((d) => timeAdjust(d.ppm, d.monthsAgo, yoy));

  const cohort = iqrTrim(cohortRaw);
  const sampleN = cohort.length;

  if (sampleN < 5) {
    return { medianPpm: median(cohort) ?? 0, deltaPct: 0, badge: 'insufficient_data', sampleN };
  }

  const medianPpm = median(cohort);
  const deltaPct = ((listingPpm - medianPpm) / medianPpm) * 100;

  // thresholds: ≥10% below median = great_deal; within ±10% = fair; else above.
  let badge;
  if (deltaPct <= -10) badge = 'great_deal';
  else if (deltaPct <= 10) badge = 'fair';
  else badge = 'above_market';

  return { medianPpm: round(medianPpm), deltaPct: round(deltaPct, 1), badge, sampleN };
}

function round(x, d = 0) { const p = 10 ** d; return Math.round(x * p) / p; }

/**
 * CBS housing price-index trend → year-over-year %.
 * @param {string|number} [districtId] optional CBS series/district id. Falls
 *   back to the national dwelling-prices series when omitted.
 * @returns {Promise<{yoyPct:number, asOf:(string|null)}|null>} null on failure.
 * NOTE: api.cbs.gov.il 403s without a User-Agent header — always send one.
 * Attribution to the Central Bureau of Statistics is REQUIRED in the product.
 */
export async function cbsTrend(districtId) {
  // CBS open data index API. The dwelling-prices index ("מחירי דירות") lives
  // under id 40010 (120010 was the general CPI — wrong series). Format=json
  // returns the time series; we take the last 13 monthly points and compute
  // (latest / 12-months-ago − 1).
  const series = districtId ? String(districtId) : '40010';
  const url =
    'https://api.cbs.gov.il/index/data/price' +
    `?id=${encodeURIComponent(series)}&format=json&download=false&last=13`;
  const raw = await fetchJson(url);
  if (!raw) return null;

  // Normalise: find an array of {value, date}-ish points.
  const points = extractCbsPoints(raw);
  if (points.length < 13) {
    // fall back to whatever we have; need at least 2 a year apart
    if (points.length < 2) return null;
  }
  const sorted = points.sort((a, b) => a.t - b.t);
  const latest = sorted[sorted.length - 1];
  // value ~12 months before latest
  const target = latest.t - 365.25 * 24 * 3600 * 1000;
  let prior = sorted[0];
  for (const p of sorted) if (Math.abs(p.t - target) < Math.abs(prior.t - target)) prior = p;
  if (!prior?.v || !latest?.v) return null;

  const yoyPct = ((latest.v / prior.v) - 1) * 100;
  return { yoyPct: round(yoyPct, 2), asOf: latest.dateStr ?? null };
}

function extractCbsPoints(raw) {
  // CBS JSON nests data; dig for objects carrying a numeric value + a period.
  // CBS points carry `year` + `month` (+ `monthDesc`), NOT an ISO `date`, so we
  // build the timestamp from year/month via new Date(year, month-1). (Falling
  // back to an ISO date field if a differently-shaped series ever appears.)
  const out = [];
  const visit = (node) => {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(visit); return; }
    // The index level is currBase.value (e.g. 599.6). Do NOT fall back to
    // `percent`/`percentYear` — those are MoM/YoY change %, a different scale
    // that corrupts the YoY ratio (was yielding ~50%).
    const v = num(node?.currBase?.value, node.value, node.Value, node.index);
    const year = num(node.year, node.Year);
    const month = num(node.month, node.Month);
    let t = NaN, dateStr = null;
    if (Number.isFinite(year) && Number.isFinite(month)) {
      t = new Date(year, month - 1).getTime();
      dateStr = `${year}-${String(month).padStart(2, '0')}`;
    } else {
      const ds = node.date ?? node.Date ?? node.period ?? null;
      if (ds) { const parsed = Date.parse(ds); if (Number.isFinite(parsed)) { t = parsed; dateStr = String(ds); } }
    }
    if (Number.isFinite(v) && Number.isFinite(t)) out.push({ v, t, dateStr });
    Object.values(node).forEach(visit);
  };
  visit(raw);
  // de-dup by timestamp
  const seen = new Set();
  return out.filter((p) => (seen.has(p.t) ? false : (seen.add(p.t), true)));
}

// demo: (does NOT run at import — call manually)
//   import { priceBadge, cbsTrend } from './nadlan_cbs.mjs';
//   console.log(await priceBadge({ lat:32.0853, lng:34.7818, rooms:3, area:75, price:2_900_000 }));
//   // → { medianPpm: ~38000, deltaPct: ~+1.8, badge: 'fair', sampleN: 27 }
//   console.log(await cbsTrend());           // → { yoyPct: 5.2, asOf: '2026-04' }
