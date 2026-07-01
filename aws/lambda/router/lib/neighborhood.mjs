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
// Population per locality → per-capita crime (data.gov.il crime/socio rows often
// carry it; else we fall back to absolute counts).
const POPULATION_KEYS = ['אוכלוסיה', 'אוכלוסייה', 'תושבים', 'population', 'pop', 'total_population', 'סהכ_אוכלוסיה'];

// Education-dataset field candidates (defensive — the portal's column names vary).
const EDU_LAT_KEYS = ['UTM_Y', 'lat', 'Y', 'latitude', 'kts_y', 'Latitude'];
const EDU_LNG_KEYS = ['UTM_X', 'lng', 'lon', 'X', 'longitude', 'kts_x', 'Longitude'];
const PIKUAH_KEYS = ['פיקוח', 'סוג_פיקוח', 'סמל_פיקוח', 'SUG_PIKUAH', 'pikuah', 'Supervision'];
const SECTOR_KEYS = ['מגזר', 'מגזר_מוסד', 'SECTOR', 'sector'];
const STAGE_KEYS = ['שלב_חינוך', 'סוג_מוסד', 'שלב חינוך', 'SUG_MOSAD', 'SHLAV_HINUCH', 'stage', 'type'];

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
// Is this education row a kindergarten / preschool (גן/קדם) vs a school?
export function isKindergarten(r) {
  return /גן|קדם|preschool|kinder/i.test(pickStr(r, STAGE_KEYS));
}

// Canonicalise the supervision (פיקוח) so cohort logic can match: religious
// families want ממ"ד/חרדי, Arab families want Arab-sector schools, etc.
export function normPikuah(s) {
  const t = String(s || '');
  if (/חרדי|עצמאי|מוכר/.test(t)) return 'charedi';
  if (/דתי/.test(t)) return 'mamlachti_dati';   // checked before ממלכתי
  if (/ערבי|בדואי|דרוזי/.test(t)) return 'arab';
  if (/ממלכתי|רשמי|state/i.test(t)) return 'mamlachti';
  return '';
}
export function normSector(s) {
  const t = String(s || '');
  if (/יהוד|jew/i.test(t)) return 'jewish';
  if (/ערב|arab/i.test(t)) return 'arab';
  if (/דרוז|druze/i.test(t)) return 'druze';
  if (/בדוא|bedouin/i.test(t)) return 'bedouin';
  return '';
}

// Distance-decayed proximity over a set of geolocated records, plus the sector/
// supervision composition of the matches. Blend of count-within-radius and
// proximity-to-nearest. Score null only when the record set is empty; a low
// floor (20) marks "records exist but none nearby" (a real signal, not unknown).
function proximityScore(records, lat, lng, { radiusM, target, keep }) {
  let near = 0;
  let nearest = Infinity;
  const pikuah = new Set();
  const sectors = {};
  for (const r of records) {
    if (keep && !keep(r)) continue;
    const slat = pickNum(r, EDU_LAT_KEYS);
    const slng = pickNum(r, EDU_LNG_KEYS);
    if (!Number.isFinite(slat) || !Number.isFinite(slng)) continue;
    if (Math.abs(slat) > 90 || Math.abs(slng) > 180) continue; // ITM, not WGS84
    const d = distM(lat, lng, slat, slng);
    if (d > radiusM) continue;
    near++;
    if (d < nearest) nearest = d;
    const pk = normPikuah(pickStr(r, PIKUAH_KEYS)); if (pk) pikuah.add(pk);
    const sc = normSector(pickStr(r, SECTOR_KEYS)); if (sc) sectors[sc] = (sectors[sc] || 0) + 1;
  }
  const score = Number.isFinite(nearest)
    ? clamp(0.6 * saturate(near, target) + 0.4 * clamp(100 * (1 - nearest / radiusM)))
    : 20; // records exist but none within radius
  return { score, count: near, pikuah: [...pikuah], sectors };
}

// crime value (count OR per-capita rate) → safety 0–100: lower vs the max → safer.
export function crimeCountToSafety(value, maxValue) {
  if (!Number.isFinite(value) || !Number.isFinite(maxValue) || maxValue <= 0) return NaN;
  return clamp(100 * (1 - value / maxValue));
}

// { locality: count } ÷ { locality: population } → { locality: per-capita rate }.
// Falls back to the raw count for any locality with no population. Pure/exported.
export function buildCrimeRateMap(crimeMap, popMap) {
  const rate = {};
  for (const k in crimeMap) {
    const pop = popMap && popMap[k];
    rate[k] = Number.isFinite(pop) && pop > 0 ? crimeMap[k] / pop : crimeMap[k];
  }
  return rate;
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
    const crimeMap = buildLocalityMap(
      crimeRecs, LOCALITY_NAME_KEYS, (r) => pickNum(r, CRIME_VALUE_KEYS), true);
    // Population per locality → per-capita rate (else absolute count). Prefer the
    // crime dataset's own population column, else the socio-economic dataset.
    let popMap = buildLocalityMap(
      crimeRecs, LOCALITY_NAME_KEYS, (r) => pickNum(r, POPULATION_KEYS), false);
    if (!Object.keys(popMap).length && socioRecs) {
      popMap = buildLocalityMap(
        socioRecs, LOCALITY_NAME_KEYS, (r) => pickNum(r, POPULATION_KEYS), false);
    }
    const rateMap = buildCrimeRateMap(crimeMap, popMap);
    const mine = rateMap[key];
    if (Number.isFinite(mine)) {
      const values = Object.values(rateMap);
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
function pickStr(obj, keys) {
  for (const k of keys) {
    if (obj[k] != null && String(obj[k]).trim()) return String(obj[k]).trim();
  }
  return '';
}

/**
 * Composite neighbourhood quality score for a coordinate.
 * @param {{lat:number,lng:number,locality?:string}} p  locality = city name,
 *   enables the safety sub-score (crime/socio joined by locality name).
 * @returns {Promise<{score:number, sub:{safety:number,walkability:number,
 *   schools:number,kindergarten:number,transit:number,green:number},
 *   schoolsMeta?:{count:number,pikuah:string[],sectors:object,kindergartenCount:number}}|null>}
 *   Each sub-score is 0–100. Missing sources are OMITTED and the composite
 *   weights are RENORMALISED over the survivors. null only on bad input or if
 *   EVERY source failed.
 */
export async function neighborhoodScore({ lat, lng, locality }) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

  // fan out in parallel; each may return null. Safety needs the locality NAME
  // (crime/socio are per-locality, joined by name) — omitted if none supplied.
  // Education is fetched ONCE and split into schools + kindergartens.
  const [osm, education, safety] = await Promise.all([
    osmCounts(lat, lng).catch(() => null),
    fetchCkan(RES_SCHOOLS, 2000).catch(() => null),
    safetyScore(locality).catch(() => null),
  ]);

  let schools = null;
  let kindergarten = null;
  let schoolsMeta = null;
  if (Array.isArray(education)) {
    const sc = proximityScore(education, lat, lng, { radiusM: 2000, target: 6, keep: (r) => !isKindergarten(r) });
    const kg = proximityScore(education, lat, lng, { radiusM: 1000, target: 4, keep: isKindergarten });
    schools = sc.score;
    kindergarten = kg.score;
    // Parsed composition (retained instead of discarded) for cohort matching.
    schoolsMeta = { count: sc.count, pikuah: sc.pikuah, sectors: sc.sectors, kindergartenCount: kg.count };
  }

  // assemble available sub-scores with their weights (kindergarten split out).
  const W = { safety: 0.28, walkability: 0.22, schools: 0.18, kindergarten: 0.10, transit: 0.12, green: 0.10 };
  const sub = {};
  if (Number.isFinite(safety)) sub.safety = round(safety);
  if (osm) {
    sub.walkability = round(osm.walkability);
    sub.transit = round(osm.transit);
    sub.green = round(osm.green);
  }
  if (Number.isFinite(schools)) sub.schools = round(schools);
  if (Number.isFinite(kindergarten)) sub.kindergarten = round(kindergarten);

  const keys = Object.keys(sub);
  if (!keys.length) return null; // every source failed

  // renormalise weights over present sub-scores.
  const wSum = keys.reduce((s, k) => s + W[k], 0);
  const score = keys.reduce((s, k) => s + (W[k] / wSum) * sub[k], 0);

  return { score: round(score), sub, ...(schoolsMeta ? { schoolsMeta } : {}) };
}

function round(x, d = 0) { const p = 10 ** d; return Math.round(x * p) / p; }

// demo: (does NOT run at import — call manually)
//   import { neighborhoodScore } from './neighborhood.mjs';
//   console.log(await neighborhoodScore({ lat: 32.0853, lng: 34.7818 })); // Tel Aviv center
//   // → { score: 78, sub: { walkability: 92, transit: 80, green: 55, schools: 70 } }
//   //   (safety omitted here because RES_CRIME/RES_SOCIOECONOMIC are unset)
