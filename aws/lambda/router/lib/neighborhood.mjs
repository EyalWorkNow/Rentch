// neighborhood.mjs — R7 composite quality-of-life score for a point.
//
//   score = 0.30·safety + 0.25·walkability + 0.20·schools + 0.15·transit + 0.10·green
//
// ponytail: this fans out to THREE flaky free sources (OSM Overpass, data.gov.il
// CKAN, CBS clusters). Each is independently best-effort: if a source fails we
// OMIT its sub-score and RENORMALISE the surviving weights, rather than zeroing
// it (a missing source must not look like a bad neighbourhood). Public Overpass
// is rate-limited and occasionally 429s/504s — for production, self-host
// Overpass or precompute on listing-create and cache; do NOT call this on every
// search request. CACHING: pure function of (lat,lng) snapped to a ~250 m grid
// (3-decimal lat/lng). Cache 30–90 days; neighbourhoods change slowly.
//
// Verified CKAN pattern (data.gov.il is a standard CKAN portal):
//   https://data.gov.il/api/3/action/datastore_search?resource_id=<id>&limit=...
// We keep the schools resource_id as a constant; swap it if the portal rotates
// the resource. Crime/socio-economic resource ids are left configurable too.

import { normalizeLocalityName } from './muni.mjs';

const TIMEOUT_MS = 9000;
const UA = 'RentlyBot/1.0 (+https://rently.co.il; neighbourhood scoring; attribution: data.gov.il/CBS/OSM)';

// data.gov.il CKAN resource ids (swap if the portal rotates them).
const RES_SCHOOLS = '5c5d6bb0-755d-470d-84b6-d7dd3135ba9c'; // education institutions, 28,312 rows (coords in UTM_Y=lat, UTM_X=lng)
const RES_CRIME = '5fc13c50-b6f3-4712-b831-a75e0f91a17e';        // police open-data crime-by-locality
const RES_SOCIOECONOMIC = '7c860e04-9f8d-41c2-9f24-6249958d2081'; // CBS socio-economic cluster by locality
const SOCIO_FIELD = 'ESHKOL 2019';                                // socio-economic cluster field

// Locality-name field candidates across gov datasets (used for the safety join).
const LOCALITY_NAME_KEYS = [
  'שם_ישוב', 'שם ישוב', 'שם_יישוב', 'שם יישוב', 'YISHUV_NAME', 'yishuv_name',
  'שם_רשות', 'שם רשות', 'רשות', 'Settlement', 'locality', 'MunicipalityName',
];
const SOCIO_VALUE_KEYS = [SOCIO_FIELD, 'cluster', 'eshkol', 'אשכול', 'index'];
const CRIME_VALUE_KEYS = ['TikimSum', 'count', 'crimes', 'value', 'סהכ', 'סה"כ'];

// Overpass mirrors — try in order, fail-soft to next.
const OVERPASS_ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchWithTimeout(url, opts = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      ...opts,
      signal: ctrl.signal,
      headers: { 'User-Agent': UA, ...(opts.headers || {}) },
    });
    if (!res.ok) return null;
    return res;
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}
async function fetchJson(url, opts) {
  const res = await fetchWithTimeout(url, opts);
  if (!res) return null;
  try { return await res.json(); } catch { return null; }
}

// haversine metres
function distM(lat1, lng1, lat2, lng2) {
  const R = 6371000, toR = Math.PI / 180;
  const dLat = (lat2 - lat1) * toR, dLng = (lng2 - lng1) * toR;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * toR) * Math.cos(lat2 * toR) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
const clamp = (x, lo = 0, hi = 100) => Math.max(lo, Math.min(hi, x));
// saturating count→score: maps a raw count to 0–100, hitting `score95` of the
// scale at `target` items (diminishing returns beyond).
function saturate(count, target) {
  return clamp(100 * (1 - Math.exp(-count / target)));
}

// ---------------------------------------------------------------------------
// Walkability + green + transit from ONE Overpass query (amenities within 800 m).
// Distance decay is implicit in the radius; we additionally weight by count.
async function osmCounts(lat, lng) {
  const R = 800; // metres — a walkable catchment
  // amenity/shop/leisure POIs (walkability), leisure=park/garden (green),
  // highway=bus_stop + railway=station/tram_stop (transit).
  const q = `[out:json][timeout:25];
(
  node(around:${R},${lat},${lng})[amenity~"^(supermarket|marketplace|pharmacy|cafe|restaurant|bank|atm|clinic|hospital|school|kindergarten|library|post_office)$"];
  node(around:${R},${lat},${lng})[shop];
  node(around:${R},${lat},${lng})[leisure~"^(park|garden|playground|fitness_centre|sports_centre)$"];
  way(around:${R},${lat},${lng})[leisure~"^(park|garden)$"];
  node(around:${R},${lat},${lng})[highway=bus_stop];
  node(around:${R},${lat},${lng})[railway~"^(station|tram_stop|subway_entrance)$"];
);
out tags center 2000;`; // raised from 200: the low cap truncated park ways so green read 0

  let data = null;
  for (const ep of OVERPASS_ENDPOINTS) {
    data = await fetchJson(ep, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'data=' + encodeURIComponent(q),
    });
    if (data) break;
    await sleep(250);
  }
  if (!data || !Array.isArray(data.elements)) return null;

  let walk = 0, green = 0, transit = 0;
  for (const el of data.elements) {
    const tags = el.tags || {};
    if (tags.highway === 'bus_stop' ||
        ['station', 'tram_stop', 'subway_entrance'].includes(tags.railway)) {
      transit++;
    } else if (['park', 'garden'].includes(tags.leisure)) {
      green++;
    } else if (tags.amenity || tags.shop || tags.leisure) {
      walk++;
    }
  }
  return {
    walkability: saturate(walk, 40),   // ~40 walkable POIs in 800 m ≈ great
    green: saturate(green, 5),         // ~5 parks/gardens nearby ≈ great
    transit: saturate(transit, 12),    // ~12 stops/stations ≈ great
  };
}

// ---------------------------------------------------------------------------
// Schools: nearest education institutions from data.gov.il, distance-decayed.
async function schoolsScore(lat, lng) {
  if (!RES_SCHOOLS) return null;
  // CKAN datastore_search with a bbox-ish filter is awkward; pull a page and
  // filter client-side by distance. We request a generous page and trust the
  // dataset carries lat/lng (X_Y / קואורדינטות) fields, normalising names.
  const url = 'https://data.gov.il/api/3/action/datastore_search' +
    `?resource_id=${RES_SCHOOLS}&limit=2000`;
  const raw = await fetchJson(url);
  const records = raw?.result?.records;
  if (!Array.isArray(records)) return null;

  let near = 0, nearest = Infinity;
  for (const r of records) {
    // NOTE THE SWAP: this dataset stores lat in UTM_Y and lng in UTM_X (despite
    // the "UTM" name the values are WGS84 degrees). Do NOT use ITM_X/ITM_Y.
    const slat = pickNum(r, ['UTM_Y', 'lat', 'Y', 'latitude', 'kts_y', 'Latitude']);
    const slng = pickNum(r, ['UTM_X', 'lng', 'lon', 'X', 'longitude', 'kts_x', 'Longitude']);
    if (!Number.isFinite(slat) || !Number.isFinite(slng)) continue;
    // skip rows that are clearly ITM (not lat/lng) — neighbourhood scoring
    // expects WGS84; coords in the 100k+ range are ITM and unsupported here.
    if (Math.abs(slat) > 90 || Math.abs(slng) > 180) continue;
    const d = distM(lat, lng, slat, slng);
    if (d <= 2000) { near++; nearest = Math.min(nearest, d); }
  }
  if (!Number.isFinite(nearest)) return 30; // dataset present but none nearby

  // blend: count of schools within 2 km (saturating) + proximity to nearest.
  const countScore = saturate(near, 6);
  const proxScore = clamp(100 * (1 - nearest / 2000));
  return clamp(0.6 * countScore + 0.4 * proxScore);
}

// ---------------------------------------------------------------------------
// CKAN page fetch → records array (null on failure).
async function fetchCkan(resourceId, limit = 5000) {
  if (!resourceId) return null;
  const raw = await fetchJson('https://data.gov.il/api/3/action/datastore_search' +
    `?resource_id=${resourceId}&limit=${limit}`);
  const recs = raw?.result?.records;
  return Array.isArray(recs) ? recs : null;
}

// Build a { normalizedLocalityName: value } map from dataset records. `sum`
// aggregates rows sharing a locality (crime counts); otherwise last-wins (a
// per-locality attribute like the socio-economic cluster). Pure + exported for
// testing without network. `valueOf(record) -> number | NaN`.
export function buildLocalityMap(records, nameKeys, valueOf, sum = false) {
  const map = {};
  if (!Array.isArray(records)) return map;
  for (const r of records) {
    let name = '';
    for (const k of nameKeys) { if (r[k]) { name = r[k]; break; } }
    const key = normalizeLocalityName(name);
    if (!key) continue;
    const v = valueOf(r);
    if (!Number.isFinite(v)) continue;
    map[key] = sum ? (map[key] || 0) + v : v;
  }
  return map;
}

// crime count → safety score (0–100): fewer crimes vs the national max → safer.
// ponytail: absolute count, not per-capita (big cities skew high). Upgrade to
// per-capita once locality population is joined via muni_ids.
export function crimeCountToSafety(count, maxCount) {
  if (!Number.isFinite(count) || !Number.isFinite(maxCount) || maxCount <= 0) return NaN;
  return clamp(100 * (1 - count / maxCount));
}

// Safety for a NAMED locality: CBS socio-economic cluster (higher = better)
// blended with police crime (lower = better), joined on the locality name. Both
// optional; returns null when the locality can't be matched in either source so
// the composite renormalises rather than inventing a number.
async function safetyScore(locality) {
  const key = normalizeLocalityName(locality);
  if (!key) return null;
  const parts = [];

  const socioRecs = await fetchCkan(RES_SOCIOECONOMIC);
  if (socioRecs) {
    const map = buildLocalityMap(
      socioRecs, LOCALITY_NAME_KEYS, (r) => pickNum(r, SOCIO_VALUE_KEYS), false);
    const cluster = map[key];
    if (Number.isFinite(cluster) && cluster >= 1 && cluster <= 10) {
      parts.push(clamp((cluster / 10) * 100));
    }
  }

  const crimeRecs = await fetchCkan(RES_CRIME);
  if (crimeRecs) {
    const map = buildLocalityMap(
      crimeRecs, LOCALITY_NAME_KEYS, (r) => pickNum(r, CRIME_VALUE_KEYS), true);
    const mine = map[key];
    if (Number.isFinite(mine)) {
      const values = Object.values(map);
      const s = crimeCountToSafety(mine, values.length ? Math.max(...values) : 0);
      if (Number.isFinite(s)) parts.push(s);
    }
  }

  if (!parts.length) return null;
  return clamp(parts.reduce((a, b) => a + b, 0) / parts.length);
}

function pickNum(obj, keys) {
  for (const k of keys) {
    if (obj[k] != null) {
      const n = Number(String(obj[k]).replace(/[, ]/g, ''));
      if (Number.isFinite(n)) return n;
    }
  }
  return NaN;
}

/**
 * Composite neighbourhood quality score for a coordinate.
 * @param {{lat:number,lng:number,locality?:string}} p  locality = city name,
 *   enables the safety sub-score (crime/socio joined by locality name).
 * @returns {Promise<{score:number, sub:{safety:number,walkability:number,
 *   schools:number,transit:number,green:number}}|null>}
 *   Each sub-score is 0–100. Missing sources are OMITTED and the composite
 *   weights are RENORMALISED over the survivors. null only on bad input or if
 *   EVERY source failed.
 */
export async function neighborhoodScore({ lat, lng, locality }) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

  // fan out in parallel; each may return null. Safety needs the locality NAME
  // (crime/socio are per-locality, joined by name) — omitted if none supplied.
  const [osm, schools, safety] = await Promise.all([
    osmCounts(lat, lng).catch(() => null),
    schoolsScore(lat, lng).catch(() => null),
    safetyScore(locality).catch(() => null),
  ]);

  // assemble available sub-scores with their R7 weights.
  const W = { safety: 0.30, walkability: 0.25, schools: 0.20, transit: 0.15, green: 0.10 };
  const sub = {};
  if (Number.isFinite(safety)) sub.safety = round(safety);
  if (osm) {
    sub.walkability = round(osm.walkability);
    sub.transit = round(osm.transit);
    sub.green = round(osm.green);
  }
  if (Number.isFinite(schools)) sub.schools = round(schools);

  const keys = Object.keys(sub);
  if (!keys.length) return null; // every source failed

  // renormalise weights over present sub-scores.
  const wSum = keys.reduce((s, k) => s + W[k], 0);
  const score = keys.reduce((s, k) => s + (W[k] / wSum) * sub[k], 0);

  return { score: round(score), sub };
}

function round(x, d = 0) { const p = 10 ** d; return Math.round(x * p) / p; }

// demo: (does NOT run at import — call manually)
//   import { neighborhoodScore } from './neighborhood.mjs';
//   console.log(await neighborhoodScore({ lat: 32.0853, lng: 34.7818 })); // Tel Aviv center
//   // → { score: 78, sub: { walkability: 92, transit: 80, green: 55, schools: 70 } }
//   //   (safety omitted here because RES_CRIME/RES_SOCIOECONOMIC are unset)
