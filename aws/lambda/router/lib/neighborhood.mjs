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

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { resolveLocality } from './muni.mjs';

const TIMEOUT_MS = 9000;
const UA = 'RentlyBot/1.0 (+https://rently.co.il; neighbourhood scoring; attribution: data.gov.il/CBS/OSM)';

// data.gov.il CKAN resource ids (verified live 2026-07). All per-locality joins
// use the CBS locality code (YeshuvKod / LocalityCode / LOCALITY SYMBOL), bridged
// from the listing's city via muni_ids (resolveLocality → cbs_id) — robust vs
// name-format drift. The SQL endpoint (datastore_search_sql) is DISABLED on the
// portal, so per-locality counts use filters + limit=0 → result.total.
const RES_SCHOOLS = '5c5d6bb0-755d-470d-84b6-d7dd3135ba9c';        // coordinates only (UTM_Y=lat, UTM_X=lng, SHEM_MOSAD name)
const RES_SCHOOLS_META = '5548fd63-5868-4053-ad81-98caddc5e232';  // "מאפייני מוסדות חינוך" — פיקוח/מגזר/סוג מוסד by locality name
const RES_CRIME = '5fc13c50-b6f3-4712-b831-a75e0f91a17e';         // police crime, PER-INCIDENT rows (count via filters+limit=0)
const RES_POPULATION = '38207cf8-afe2-48ed-a3b0-c8f70c796015';    // 2022 census population by LocalityCode
const RES_SOCIOECONOMIC = '7c860e04-9f8d-41c2-9f24-6249958d2081'; // CBS socio-economic cluster (partial city coverage)
const SOCIO_FIELD = 'ESHKOL 2019';

// CBS-locality-code columns per dataset (the join keys).
const CRIME_CODE_KEY = 'YeshuvKod';
const POP_CODE_KEY = 'LocalityCode';
const POP_VALUE_KEY = 'Total_Population';
const SOCIO_CODE_KEY = 'LOCALITY SYMBOL';

// National crimes-per-capita benchmark over the dataset's span. Tunable — safety
// = 100·(1 − rate/benchmark). ponytail: heuristic anchor; recalibrate against the
// observed distribution if it skews.
const CRIME_RATE_BENCHMARK = 0.10;

// mosdot (RES_SCHOOLS_META) composition columns.
const PIKUAH_KEYS = ['פיקוח', 'סוג_פיקוח', 'סמל_פיקוח', 'SUG_PIKUAH', 'pikuah', 'Supervision'];
const SECTOR_KEYS = ['מגזר', 'מגזר_מוסד', 'SECTOR', 'sector'];
// Kindergarten detection reads the school NAME/type (coords dataset has SHEM_MOSAD;
// mosdot has סוג מוסד = "גן ילדים").
const STAGE_KEYS = ['סוג מוסד', 'סוג_מוסד', 'סוג מסגרת אירגונית', 'SHEM_MOSAD', 'שם מוסד', 'stage', 'type'];
// Coordinate columns in the coords dataset.
const EDU_LAT_KEYS = ['UTM_Y', 'lat', 'Y', 'latitude', 'kts_y', 'Latitude'];
const EDU_LNG_KEYS = ['UTM_X', 'lng', 'lon', 'X', 'longitude', 'kts_x', 'Longitude'];

// Single source of truth for scripts/verify-gov-fields.mjs — the exact resource
// ids + candidate field lists this module relies on, so the verifier tests the
// real thing rather than a drifting copy.
export const GOV_FIELDS = {
  resources: {
    RES_SCHOOLS, RES_SCHOOLS_META, RES_CRIME, RES_POPULATION, RES_SOCIOECONOMIC, SOCIO_FIELD,
  },
  codes: {
    CRIME_CODE_KEY, POP_CODE_KEY, POP_VALUE_KEY, SOCIO_CODE_KEY,
  },
  eduLat: EDU_LAT_KEYS,
  eduLng: EDU_LNG_KEYS,
  pikuah: PIKUAH_KEYS,
  sector: SECTOR_KEYS,
  stage: STAGE_KEYS,
};

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
// Is this education row a kindergarten / preschool vs a school? Reads the name
// (coords dataset SHEM_MOSAD, e.g. "גן שלוה") or type (mosdot "סוג מוסד" = "גן
// ילדים"). Tightened so a place-name like "גני תקווה" doesn't false-match.
export function isKindergarten(r) {
  return /(^|\s)גן\s|גן ילדים|גני ילדים|מעון|טרום.?חובה|preschool|kinder/i.test(pickStr(r, STAGE_KEYS));
}

// Canonicalise the supervision (פיקוח) so cohort logic can match: religious
// families want ממ"ד/חרדי, Arab families want Arab-sector schools, etc.
// Real mosdot פיקוח values are ABBREVIATIONS with gershayim, and the portal
// leaks CSV double-quote escaping ("מ""מ", "חמ""ד). Strip all quote chars first,
// then match: מ"מ→ממ (ממלכתי), חמ"ד→חמד (ממלכתי-דתי), חרדי. Most-specific first.
export function normPikuah(s) {
  const t = String(s || '').replace(/["'׳״]/g, '');
  if (/חמד|ממ"?ד|ממלכתי.?דתי|דתי/.test(t)) return 'mamlachti_dati';
  if (/חרדי|עצמאי|מוכר/.test(t)) return 'charedi';
  if (/ערבי|בדואי|דרוזי/.test(t)) return 'arab';
  if (/ממלכתי|ממ|רשמי|state/i.test(t)) return 'mamlachti';
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

// Precomputed per-locality features (built offline by scripts/build-locality-
// features.mjs, keyed by CBS code). Read once, fail-soft to empty if not built —
// safety/composition then return null and the composite renormalises.
let _localityFeatures = null;
function localityFeatures() {
  if (_localityFeatures) return _localityFeatures;
  _localityFeatures = {};
  try {
    const here = dirname(fileURLToPath(import.meta.url));
    _localityFeatures = JSON.parse(readFileSync(join(here, 'locality_features.generated.json'), 'utf8'));
  } catch { /* not built → empty */ }
  return _localityFeatures;
}
function localityFeatureFor(locality) {
  const m = resolveLocality(locality);
  if (!m) return null;
  return localityFeatures()[String(Number(m.cbs_id))] || null;
}

// Safety for a locality from the precomputed table: socio-economic cluster
// (higher = better) blended with PER-CAPITA crime (lower = better vs benchmark).
// No runtime network → never times out to undefined for a covered locality.
async function safetyScore(locality) {
  const f = localityFeatureFor(locality);
  if (!f) return null;
  const parts = [];
  if (Number.isFinite(f.eshkol) && f.eshkol >= 1 && f.eshkol <= 10) parts.push(clamp((f.eshkol / 10) * 100));
  if (Number.isFinite(f.crime) && Number.isFinite(f.pop) && f.pop > 0) {
    parts.push(clamp(100 * (1 - (f.crime / f.pop) / CRIME_RATE_BENCHMARK)));
  }
  if (!parts.length) return null;
  return clamp(parts.reduce((a, b) => a + b, 0) / parts.length);
}

// Geolocated schools (built offline: mosdot metadata × coords by SEMEL_MOSAD).
// Each: {lat, lng, p:pikuah, s:sector, k:isKindergarten}. Fail-soft to [].
let _schoolsGeo = null;
function schoolsGeo() {
  if (_schoolsGeo) return _schoolsGeo;
  _schoolsGeo = [];
  try {
    const here = dirname(fileURLToPath(import.meta.url));
    _schoolsGeo = JSON.parse(readFileSync(join(here, 'schools_geo.generated.json'), 'utf8'));
  } catch { /* not built → empty */ }
  return _schoolsGeo;
}

// POINT-LEVEL school analysis: scans the geolocated schools around a coordinate
// (single O(n) pass, n≈30k, sub-millisecond). Returns proximity counts for the
// schools sub-score + kindergarten sub-score, AND the pikuah/sector composition
// of schools WITHIN 2km — so the cohort gates reflect the actual surroundings of
// THIS apartment, not the whole municipality.
const SCHOOL_RADIUS_M = 2000;      // schools proximity sub-score
const KG_RADIUS_M = 1500;          // kindergarten proximity sub-score
const COMPOSITION_RADIUS_M = 1500; // composition for the gates (tighter)
function schoolsNear(lat, lng) {
  // Composition uses SCHOOLS ONLY (kindergartens are 70%+ of records and dilute
  // the signal) and per-stream COUNTS (so gates can use dominance/fraction, not
  // mere presence — presence is true everywhere in dense metros).
  const pikuah = {};
  const sectors = {};
  let schoolTotal = 0;
  let sCount = 0;
  let sNearest = Infinity;
  let kCount = 0;
  let kNearest = Infinity;
  for (const sc of schoolsGeo()) {
    const d = distM(lat, lng, sc.lat, sc.lng);
    if (d > SCHOOL_RADIUS_M) continue;
    if (sc.k) {
      if (d <= KG_RADIUS_M) { kCount++; if (d < kNearest) kNearest = d; }
      continue;
    }
    sCount++; if (d < sNearest) sNearest = d;
    if (d <= COMPOSITION_RADIUS_M) {
      schoolTotal++;
      if (sc.p) pikuah[sc.p] = (pikuah[sc.p] || 0) + 1;
      if (sc.s) sectors[sc.s] = (sectors[sc.s] || 0) + 1;
    }
  }
  return { pikuah, sectors, schoolTotal, sCount, sNearest, kCount, kNearest };
}

// count-within-radius + proximity-to-nearest → 0..100 (20 floor = "some data,
// none nearby"). null when the schools table isn't loaded at all.
function proximityFrom(count, nearest, radiusM, target) {
  if (!Number.isFinite(nearest)) return 20;
  return clamp(0.6 * saturate(count, target) + 0.4 * clamp(100 * (1 - nearest / radiusM)));
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

  // OSM (live) + safety (precomputed table, no network) in parallel.
  const [osm, safety] = await Promise.all([
    osmCounts(lat, lng).catch(() => null),
    safetyScore(locality).catch(() => null),
  ]);

  // Point-level schools: one scan of the bundled geolocated schools gives the
  // schools + kindergarten proximity AND the pikuah/sector composition of what's
  // actually within 2km of THIS apartment (drives the cohort gates).
  const geoLoaded = schoolsGeo().length > 0;
  const near = geoLoaded ? schoolsNear(lat, lng) : null;
  const schools = near ? proximityFrom(near.sCount, near.sNearest, SCHOOL_RADIUS_M, 6) : null;
  const kindergarten = near ? proximityFrom(near.kCount, near.kNearest, KG_RADIUS_M, 4) : null;
  const schoolsMeta = (near && near.schoolTotal)
    ? { pikuah: near.pikuah, sectors: near.sectors, total: near.schoolTotal } : null;

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
