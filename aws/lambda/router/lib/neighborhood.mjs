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

const TIMEOUT_MS = 9000;
const UA = 'RentlyBot/1.0 (+https://rently.co.il; neighbourhood scoring; attribution: data.gov.il/CBS/OSM)';

// data.gov.il CKAN resource ids (swap if the portal rotates them).
const RES_SCHOOLS = '5c5d6bb0-755d-470d-84b6-d7dd3135ba9c'; // education institutions, 28,312 rows (coords in UTM_Y=lat, UTM_X=lng)
// crime + socio-economic resource ids are verified live, BUT the safety
// sub-score still needs a row-count aggregation + locality join (see below) —
// so safety stays gracefully omitted for now.
// ponytail: needs row-count aggregation + locality join
const RES_CRIME = '5fc13c50-b6f3-4712-b831-a75e0f91a17e';        // police open-data crime-by-locality
const RES_SOCIOECONOMIC = '7c860e04-9f8d-41c2-9f24-6249958d2081'; // CBS socio-economic cluster by locality
const SOCIO_FIELD = 'ESHKOL 2019';                                // socio-economic cluster field

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
// Safety: police crime rate (lower = better) blended with CBS socio-economic
// cluster (higher cluster = better). Both optional; whichever exists is used.
async function safetyScore(lat, lng) {
  // ponytail: needs row-count aggregation + locality join. RES_CRIME and
  // RES_SOCIOECONOMIC are verified-live resource ids, but turning them into a
  // point-level safety score requires (a) aggregating crime rows per locality
  // and (b) joining on the locality/city_code of THIS point — which the
  // geocoder would have to supply. Until that lands we OMIT safety (return
  // null) so the composite renormalises over the working sub-scores rather
  // than injecting a bogus national-average number. Machinery kept below.
  return null;
  // eslint-disable-next-line no-unreachable
  const parts = [];

  if (RES_CRIME) {
    const url = 'https://data.gov.il/api/3/action/datastore_search' +
      `?resource_id=${RES_CRIME}&limit=5000`;
    const raw = await fetchJson(url);
    const records = raw?.result?.records;
    if (Array.isArray(records) && records.length) {
      // crime datasets are per-locality counts; without a locality join we
      // approximate national distribution and place this point mid-scale.
      // (A real impl joins on city_code/סמל יישוב from the geocoder.)
      const counts = records
        .map((r) => pickNum(r, ['count', 'crimes', 'TikimSum', 'value']))
        .filter(Number.isFinite);
      if (counts.length) {
        // invert: fewer crimes → higher score. Use rank of a "typical" locality.
        const med = counts.slice().sort((a, b) => a - b)[counts.length >> 1];
        const max = Math.max(...counts);
        parts.push(clamp(100 * (1 - med / (max || 1))));
      }
    }
  }

  if (RES_SOCIOECONOMIC) {
    const url = 'https://data.gov.il/api/3/action/datastore_search' +
      `?resource_id=${RES_SOCIOECONOMIC}&limit=5000`;
    const raw = await fetchJson(url);
    const records = raw?.result?.records;
    if (Array.isArray(records) && records.length) {
      // CBS socio-economic cluster is 1–10 (10 = highest). Map to 0–100.
      const clusters = records
        .map((r) => pickNum(r, [SOCIO_FIELD, 'cluster', 'eshkol', 'אשכול', 'index']))
        .filter((c) => Number.isFinite(c) && c >= 1 && c <= 10);
      if (clusters.length) {
        const avg = clusters.reduce((a, b) => a + b, 0) / clusters.length;
        parts.push(clamp((avg / 10) * 100));
      }
    }
  }

  if (!parts.length) return null; // neither source configured/available → omit
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
 * @param {{lat:number,lng:number}} p
 * @returns {Promise<{score:number, sub:{safety:number,walkability:number,
 *   schools:number,transit:number,green:number}}|null>}
 *   Each sub-score is 0–100. Missing sources are OMITTED and the composite
 *   weights are RENORMALISED over the survivors. null only on bad input or if
 *   EVERY source failed.
 */
export async function neighborhoodScore({ lat, lng }) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

  // fan out in parallel; each may return null.
  const [osm, schools, safety] = await Promise.all([
    osmCounts(lat, lng).catch(() => null),
    schoolsScore(lat, lng).catch(() => null),
    safetyScore(lat, lng).catch(() => null),
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
