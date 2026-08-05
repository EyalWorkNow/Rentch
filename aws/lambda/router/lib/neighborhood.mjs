// neighborhood.mjs — R8 composite quality-of-life score for a point.
//
//   score = 0.26·safety + 0.20·walkability + 0.16·schools + 0.08·kindergarten
//         + 0.12·transit + 0.10·green + 0.08·quiet
//
// R8 quality upgrades over R7 (raw-count era):
//   transit     rail-weighted (station×6, tram×3, bus×1) + nearest-rail proximity
//   green       count blended with nearest-park proximity
//   walkability POI count blended with essential-services coverage (5 categories)
//   quiet       NEW — big-road noise proxy (motorway/trunk/primary/secondary ≤250m)
//   safety      crime component percentile-calibrated vs the national distribution
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

// OSM is now the ONLY live call in neighborhoodScore (safety + schools come from
// bundled tables). The R8 query measures ~2-4s on public mirrors, so the old
// 1800ms abort killed it almost every time (subs silently missing). R8: one
// mirror gets most of the 4s publish budget (3300ms), the second is tried only
// if the first failed FAST enough to leave real budget. The query also carries
// [timeout:3] so Overpass itself gives up quickly instead of queueing 25s.
// A slow OSM still just omits walkability/transit/green/quiet — fail-soft.
const TIMEOUT_MS = 3300;
const OSM_BUDGET_MS = 3700; // total wall-clock for all mirror attempts
const QUERY_TIMEOUT_S = 3;  // server-side Overpass timeout hint
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
// R8: walkability + green + transit + quiet from ONE Overpass query.
// Beyond raw counts (R7), the scorers now use QUALITY signals: transit is
// rail-weighted, green and rail blend in proximity, walkability rewards
// essential-service coverage, and big roads nearby cost "quiet" points.

const WALK_R = 800;   // walkable catchment (m)
const ROAD_R = 250;   // noise-proxy radius (m)

// Essential daily-life categories for the walkability coverage component.
// Each maps to a predicate over OSM tags; coverage = fraction present in 800 m.
const ESSENTIALS = {
  grocery: (t) => ['supermarket', 'marketplace'].includes(t.amenity) ||
                  ['supermarket', 'convenience', 'greengrocer'].includes(t.shop),
  pharmacy: (t) => t.amenity === 'pharmacy' || t.shop === 'chemist',
  health: (t) => ['clinic', 'hospital', 'doctors'].includes(t.amenity),
  money: (t) => ['bank', 'atm'].includes(t.amenity),
  post: (t) => t.amenity === 'post_office',
};

// Pure scorers (exported for tests — no network, deterministic).
// counts: {bus, tram, rail, railNearestM} — rail counts stations, tram counts
// light-rail/subway entrances. A train station moves the needle ~6× a bus stop.
export function transitScoreFrom({ bus = 0, tram = 0, rail = 0, railNearestM = Infinity }) {
  const weighted = bus + 3 * tram + 6 * rail;
  const base = saturate(weighted, 14);
  const railBonus = Number.isFinite(railNearestM)
    ? clamp(100 * (1 - railNearestM / WALK_R)) : 0;
  return clamp(0.75 * base + 0.25 * railBonus);
}

// {count, nearestM}: a park you can actually reach beats "5 somewhere in radius".
export function greenScoreFrom({ count = 0, nearestM = Infinity }) {
  const prox = Number.isFinite(nearestM) ? clamp(100 * (1 - nearestM / WALK_R)) : 0;
  return clamp(0.6 * saturate(count, 5) + 0.4 * prox);
}

// {count, essentials}: essentials = how many of the 5 daily-life categories
// exist within the catchment. 40 cafés no longer read as "perfectly walkable".
export function walkScoreFrom({ count = 0, essentials = 0 }) {
  return clamp(0.55 * saturate(count, 40) + 0.45 * (essentials / Object.keys(ESSENTIALS).length) * 100);
}

// {motorwayTrunk, primary, secondary} = way SEGMENTS within 250 m. Segment
// counts are capped so one long road split into pieces doesn't nuke the score.
// ponytail: heuristic noise proxy; swap for the real noise raster if we ever
// bundle it.
export function quietScoreFrom({ motorwayTrunk = 0, primary = 0, secondary = 0 }) {
  const penalty =
    60 * Math.min(motorwayTrunk, 2) / 2 +
    30 * Math.min(primary, 3) / 3 +
    15 * Math.min(secondary, 4) / 4;
  return clamp(100 - penalty);
}

function elCoords(el) {
  const lat = el.lat ?? el.center?.lat;
  const lng = el.lon ?? el.center?.lon;
  return (Number.isFinite(lat) && Number.isFinite(lng)) ? { lat, lng } : null;
}

async function osmCounts(lat, lng) {
  const q = `[out:json][timeout:${QUERY_TIMEOUT_S}];
(
  node(around:${WALK_R},${lat},${lng})[amenity~"^(supermarket|marketplace|pharmacy|cafe|restaurant|bank|atm|clinic|doctors|hospital|school|kindergarten|library|post_office)$"];
  node(around:${WALK_R},${lat},${lng})[shop];
  node(around:${WALK_R},${lat},${lng})[leisure~"^(park|garden|playground|fitness_centre|sports_centre)$"];
  way(around:${WALK_R},${lat},${lng})[leisure~"^(park|garden)$"];
  node(around:${WALK_R},${lat},${lng})[highway=bus_stop];
  node(around:${WALK_R},${lat},${lng})[railway~"^(station|tram_stop|subway_entrance)$"];
  way(around:${ROAD_R},${lat},${lng})[highway~"^(motorway|trunk|primary|secondary)$"];
);
out tags center 2000;`; // 'out center' gives way centroids for proximity math

  // Race both mirrors — public-mirror latency is wildly variable (700ms–4s+),
  // and enrichment runs ONCE per listing so the extra request is negligible
  // load next to losing the score. First real JSON wins; null losers ignored.
  const attempts = OVERPASS_ENDPOINTS.map((ep) =>
    fetchJson(ep, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'data=' + encodeURIComponent(q),
    }).then((d) => (d && Array.isArray(d.elements) ? d : Promise.reject(new Error('no data')))));
  const data = await Promise.any(attempts).catch(() => null);
  if (!data) return null;

  let walk = 0;
  const essentialsSeen = new Set();
  let green = 0, greenNearest = Infinity;
  let bus = 0, tram = 0, rail = 0, railNearest = Infinity;
  let motorwayTrunk = 0, primary = 0, secondary = 0;

  for (const el of data.elements) {
    const tags = el.tags || {};
    const hw = tags.highway;
    if (['motorway', 'trunk'].includes(hw)) { motorwayTrunk++; continue; }
    if (hw === 'primary') { primary++; continue; }
    if (hw === 'secondary') { secondary++; continue; }

    if (hw === 'bus_stop') { bus++; continue; }
    if (tags.railway === 'station') {
      rail++;
      const c = elCoords(el);
      if (c) railNearest = Math.min(railNearest, distM(lat, lng, c.lat, c.lng));
      continue;
    }
    if (['tram_stop', 'subway_entrance'].includes(tags.railway)) { tram++; continue; }

    if (['park', 'garden'].includes(tags.leisure)) {
      green++;
      const c = elCoords(el);
      if (c) greenNearest = Math.min(greenNearest, distM(lat, lng, c.lat, c.lng));
      continue;
    }
    if (tags.amenity || tags.shop || tags.leisure) {
      walk++;
      for (const [key, match] of Object.entries(ESSENTIALS)) {
        if (!essentialsSeen.has(key) && match(tags)) essentialsSeen.add(key);
      }
    }
  }

  return {
    walkability: walkScoreFrom({ count: walk, essentials: essentialsSeen.size }),
    green: greenScoreFrom({ count: green, nearestM: greenNearest }),
    transit: transitScoreFrom({ bus, tram, rail, railNearestM: railNearest }),
    quiet: quietScoreFrom({ motorwayTrunk, primary, secondary }),
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

// R8: crime component is PERCENTILE-CALIBRATED against the national
// distribution of per-capita rates — POPULATION-WEIGHTED, and only over
// localities that actually report (pop ≥ 5k AND crime > 0). Unweighted
// percentile over all 1,200 rows is meaningless: half are tiny localities with
// zero recorded crime, which shoves every real city into the worst percentile.
// Weighting by population asks the honest question: "how does this place rank
// vs where people actually live?" Clamped to [5,95] — commercial-district
// inflation (crime counted against resident pop only) shouldn't read as 0.
const REPORTING_MIN_POP = 5000;
let _crimeDist = null;
function crimeDist() {
  if (_crimeDist) return _crimeDist;
  const rows = [];
  for (const f of Object.values(localityFeatures())) {
    if (Number.isFinite(f?.crime) && Number.isFinite(f?.pop) &&
        f.pop >= REPORTING_MIN_POP && f.crime > 0) {
      rows.push({ rate: f.crime / f.pop, pop: f.pop });
    }
  }
  rows.sort((a, b) => a.rate - b.rate);
  let cum = 0;
  const totalPop = rows.reduce((s, r) => s + r.pop, 0);
  for (const r of rows) { cum += r.pop; r.cumFrac = cum / totalPop; }
  _crimeDist = rows;
  return _crimeDist;
}
// Exported for tests. rate = crimes per capita; returns 0–100 (safer = higher).
export function crimePercentileScore(rate, dist = crimeDist()) {
  if (!Number.isFinite(rate) || rate < 0) return NaN;
  if (dist.length < 30) return clamp(100 * (1 - rate / CRIME_RATE_BENCHMARK));
  // population fraction living in localities with rate <= this one
  let pct = 0;
  for (const r of dist) { if (r.rate <= rate) pct = r.cumFrac; else break; }
  return clamp(100 * (1 - pct), 5, 95);
}

// Safety for a locality from the precomputed table: socio-economic cluster
// (higher = better) blended with the percentile-calibrated per-capita crime.
// No runtime network → never times out to undefined for a covered locality.
async function safetyScore(locality) {
  const f = localityFeatureFor(locality);
  if (!f) return null;
  const parts = [];
  if (Number.isFinite(f.eshkol) && f.eshkol >= 1 && f.eshkol <= 10) parts.push(clamp((f.eshkol / 10) * 100));
  if (Number.isFinite(f.crime) && Number.isFinite(f.pop) && f.pop > 0) {
    const p = crimePercentileScore(f.crime / f.pop);
    if (Number.isFinite(p)) parts.push(p);
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
      // schoolTotal is the CLASSIFIED denominator — count only schools whose
      // pikuah we actually know, so the fraction isn't diluted by unclassified
      // rows (which would wrongly push a community area below its threshold).
      if (sc.p) { schoolTotal++; pikuah[sc.p] = (pikuah[sc.p] || 0) + 1; }
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
  // NEIGHBORHOOD_SKIP_OSM=1 skips the flaky Overpass call — used by the bulk
  // backfill so it doesn't hammer/ban public Overpass over hundreds of listings
  // (schools + safety, both bundled, still give the cohort-differentiating core).
  const [osm, safety] = await Promise.all([
    process.env.NEIGHBORHOOD_SKIP_OSM === '1'
      ? Promise.resolve(null)
      : osmCounts(lat, lng).catch(() => null),
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

  // assemble available sub-scores with their weights (R8: quiet added, weights
  // rebalanced to sum 1.0; renormalisation over survivors unchanged).
  const W = { safety: 0.26, walkability: 0.20, schools: 0.16, kindergarten: 0.08, transit: 0.12, green: 0.10, quiet: 0.08 };
  const sub = {};
  if (Number.isFinite(safety)) sub.safety = round(safety);
  if (osm) {
    sub.walkability = round(osm.walkability);
    sub.transit = round(osm.transit);
    sub.green = round(osm.green);
    if (Number.isFinite(osm.quiet)) sub.quiet = round(osm.quiet);
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
