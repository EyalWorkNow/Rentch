#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// data.gov.il → assets/data/govdata/schools.json  (POINT-level, TYPED)
//
// Named education institutions (schools + kindergartens) each with a real TYPE
// (stage + supervision sector) and WGS84 coordinates, for the "nearby schools /
// kindergartens" lists on the property detail screen.
//
// Two data.gov.il resources, joined by סמל מוסד (institution code):
//   • MASTER  5548fd63-5868-4053-ad81-98caddc5e232  "מאפייני מוסדות חינוך"
//       → פיקוח (מ"מ / חמ"ד / חרדי), משכבה / עד שכבה (grade range → stage),
//         סוג מוסד ('גן ילדים' ⇒ kindergarten), שם מוסד.
//   • COORDS  5c5d6bb0-755d-470d-84b6-d7dd3135ba9c  "קואורדינטות מוסדות החינוך"
//       → SEMEL_MOSAD, UTM_X/UTM_Y (already WGS84 lon/lat) + ITM_X/Y fallback.
//
// Output → assets/data/govdata/schools.json
//   [ { "n": name, "lat", "lon", "t": stage, "s": sector }, ... ]
//   t ∈ גן | יסודי | חטיבת ביניים | תיכון      s ∈ ממלכתי | ממלכתי דתי | חרדי | ''
// Replaces the older OSM-derived schools.json (loaded by IsraelGeoIndex.loadSchools).
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');
const CKAN = 'https://data.gov.il/api/3/action/datastore_search';
const MASTER = '5548fd63-5868-4053-ad81-98caddc5e232';
const COORDS = '5c5d6bb0-755d-470d-84b6-d7dd3135ba9c';

async function fetchAll(resourceId, { pageSize = 10000, label = '' } = {}) {
  const out = [];
  let offset = 0;
  for (;;) {
    const url = `${CKAN}?resource_id=${resourceId}&limit=${pageSize}&offset=${offset}&records_format=objects`;
    const res = await fetch(url, { headers: { accept: 'application/json' } });
    if (!res.ok) throw new Error(`CKAN ${res.status} for ${resourceId}`);
    const json = await res.json();
    const recs = json.result?.records ?? [];
    out.push(...recs);
    process.stdout.write(`\r  ${label}: ${out.length} rows`);
    if (recs.length < pageSize) break;
    offset += pageSize;
  }
  process.stdout.write('\n');
  return out;
}

// Israel TM Grid (EPSG:2039) → WGS84 — fallback only (same routine as schools.mjs).
function itmToWgs84(E, N) {
  const a = 6378137.0, f = 1 / 298.257222101, e2 = f * (2 - f);
  const k0 = 1.0000067;
  const lat0 = 31.7343936111111 * Math.PI / 180;
  const lon0 = 35.2045169444444 * Math.PI / 180;
  const FE = 219529.584, FN = 626907.39;
  const e1 = (1 - Math.sqrt(1 - e2)) / (1 + Math.sqrt(1 - e2));
  const arc = (p) => a * ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 ** 3 / 256) * p
    - (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * e2 ** 3 / 1024) * Math.sin(2 * p)
    + (15 * e2 * e2 / 256 + 45 * e2 ** 3 / 1024) * Math.sin(4 * p)
    - (35 * e2 ** 3 / 3072) * Math.sin(6 * p));
  const M = arc(lat0) + (N - FN) / k0;
  const mu = M / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 ** 3 / 256));
  const phi1 = mu
    + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * Math.sin(2 * mu)
    + (21 * e1 * e1 / 16 - 55 * e1 ** 4 / 32) * Math.sin(4 * mu)
    + (151 * e1 ** 3 / 96) * Math.sin(6 * mu)
    + (1097 * e1 ** 4 / 512) * Math.sin(8 * mu);
  const ep2 = e2 / (1 - e2);
  const C1 = ep2 * Math.cos(phi1) ** 2;
  const T1 = Math.tan(phi1) ** 2;
  const N1 = a / Math.sqrt(1 - e2 * Math.sin(phi1) ** 2);
  const R1 = a * (1 - e2) / Math.pow(1 - e2 * Math.sin(phi1) ** 2, 1.5);
  const D = (E - FE) / (N1 * k0);
  const lat = phi1 - (N1 * Math.tan(phi1) / R1) * (D * D / 2
    - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * ep2) * D ** 4 / 24
    + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * ep2 - 3 * C1 * C1) * D ** 6 / 720);
  const lon = lon0 + (D - (1 + 2 * T1 + C1) * D ** 3 / 6
    + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * ep2 + 24 * T1 * T1) * D ** 5 / 120) / Math.cos(phi1);
  const Nn = a / Math.sqrt(1 - e2 * Math.sin(lat) ** 2);
  const X = Nn * Math.cos(lat) * Math.cos(lon);
  const Y = Nn * Math.cos(lat) * Math.sin(lon);
  const Z = (Nn * (1 - e2)) * Math.sin(lat);
  const sec = Math.PI / 180 / 3600;
  const dx = -24.0024, dy = -17.1032, dz = -17.8444;
  const rx = -0.33077 * sec, ry = -1.85269 * sec, rz = 1.66969 * sec, s = 1 + 5.4262e-6;
  const Xw = dx + s * (X - rz * Y + ry * Z);
  const Yw = dy + s * (rz * X + Y - rx * Z);
  const Zw = dz + s * (-ry * X + rx * Y + Z);
  const aw = 6378137.0, ew2 = (1 / 298.257223563) * (2 - 1 / 298.257223563);
  const p = Math.sqrt(Xw * Xw + Yw * Yw);
  let latw = Math.atan2(Zw, p * (1 - ew2));
  for (let i = 0; i < 6; i++) {
    const Nw = aw / Math.sqrt(1 - ew2 * Math.sin(latw) ** 2);
    latw = Math.atan2(Zw + ew2 * Nw * Math.sin(latw), p);
  }
  return [latw * 180 / Math.PI, Math.atan2(Yw, Xw) * 180 / Math.PI];
}

const validLat = (x) => isFinite(x) && x > 29 && x < 34;
const validLon = (x) => isFinite(x) && x > 33 && x < 36;
const clean = (s = '') => String(s).replace(/["']/g, '').trim();

// פיקוח → readable sector. Values arrive CSV-escaped, e.g. 'מ""מ' / 'חמ""ד'.
function sectorOf(pikuach) {
  const c = clean(pikuach);
  if (!c) return '';
  if (c.includes('חמד') || c.includes('ממד')) return 'ממלכתי דתי';
  if (c.includes('חרדי')) return 'חרדי';
  if (c.includes('ממ') || c.includes('מ"מ')) return 'ממלכתי';
  return '';
}

// Grade range (+ 'גן ילדים' type) → education stage. Classify by the HIGHEST
// grade the school teaches up to, so a 7–12 six-year school reads as תיכון
// (not חטיבת ביניים) — the level that actually matters to a parent.
function stageOf(fromG, toG, sugMosad) {
  // A kindergarten ONLY when the institution type says so — do NOT infer גן from
  // a 0..0 grade range, or colleges / admin centres (no K-12 grades) leak in.
  if (clean(sugMosad).includes('גן')) return 'גן';
  const f = Number(fromG), t = Number(toG);
  if (!isFinite(t) || t <= 0) return ''; // no real school grades → drop (college/…)
  if (t <= 6) return 'יסודי';               // ends by grade 6
  if (isFinite(f) && f >= 7) {              // starts middle/high
    return t >= 10 ? 'תיכון' : 'חטיבת ביניים'; // 7-9 middle, 7-12/9-12 high
  }
  return 'יסודי'; // spans grade 1 into higher (1-8 / 1-12) → local elementary
}

async function main() {
  console.log('▶ education institutions (typed points) → schools.json');
  mkdirSync(OUT_DIR, { recursive: true });

  // 1. master: סמל מוסד → { name, sector, stage }
  const master = await fetchAll(MASTER, { label: 'master' });
  const meta = new Map();
  for (const r of master) {
    const semel = clean(r['סמל מוסד']);
    if (!semel) continue;
    meta.set(semel, {
      name: clean(r['שם מוסד']),
      sector: sectorOf(r['פיקוח']),
      stage: stageOf(r['משכבה'], r['עד שכבה'], r['סוג מוסד']),
    });
  }

  // 2. coords: SEMEL_MOSAD → lat/lon, joined with master.
  const coords = await fetchAll(COORDS, { label: 'coords' });
  const out = [];
  const seen = new Set();
  let joined = 0, noMeta = 0, dropped = 0;
  for (const r of coords) {
    const semel = clean(r.SEMEL_MOSAD);
    let lat = Number(r.UTM_Y), lon = Number(r.UTM_X);
    if (!(validLat(lat) && validLon(lon))) {
      const ix = Number(r.ITM_X), iy = Number(r.ITM_Y);
      if (isFinite(ix) && isFinite(iy) && ix > 0 && iy > 0) [lat, lon] = itmToWgs84(ix, iy);
    }
    if (!validLat(lat) || !validLon(lon)) { dropped++; continue; }

    const m = meta.get(semel);
    let stage, sector, name;
    if (m) { joined++; stage = m.stage; sector = m.sector; name = m.name || clean(r.SHEM_MOSAD); }
    else {
      noMeta++;
      name = clean(r.SHEM_MOSAD);
      stage = /^גן(ון)?(\s|$)|^מעון|גנון/.test(name) ? 'גן' : ''; // name-based fallback
      sector = '';
    }
    if (!stage) { dropped++; continue; } // keep only classified schools/kindergartens
    if (!name) continue;

    // dedup by semel (a code can appear twice in coords)
    if (semel && seen.has(semel)) continue;
    if (semel) seen.add(semel);

    out.push({
      n: name,
      lat: Math.round(lat * 1e5) / 1e5,
      lon: Math.round(lon * 1e5) / 1e5,
      t: stage,
      s: sector,
    });
  }

  const file = join(OUT_DIR, 'schools.json');
  writeFileSync(file, JSON.stringify(out));

  const byStage = {};
  const bySector = {};
  for (const o of out) { byStage[o.t] = (byStage[o.t] || 0) + 1; bySector[o.s || '—'] = (bySector[o.s || '—'] || 0) + 1; }
  console.log('\n── schools.json ──');
  console.table({
    masterRows: master.length, coordRows: coords.length,
    joinedWithType: joined, coordsWithoutMaster: noMeta, droppedNoCoordOrStage: dropped,
    output: out.length, bytes: statSync(file).size,
  });
  console.log('by stage:', JSON.stringify(byStage));
  console.log('by sector:', JSON.stringify(bySector));
  console.log('samples:', JSON.stringify(out.slice(0, 4)));
}

main().catch((e) => { console.error('\n✗ schools_points failed:', e); process.exit(1); });
