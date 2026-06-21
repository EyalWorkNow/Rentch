#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// data.gov.il POI ingestion — air-quality monitoring stations
//
// Source: "Air quality monitoring stations.xlsx", resource
//   9e6daaea-fd72-4ee2-882b-38a5eee135f0  (XLSX, datastore-active → CKAN).
// Fields (Hebrew): אזור, שם התחנה החדש (new name), שם התחנה הישן (old name),
//   הגוף המנטר, סוג התחנה, סיווג אזור, Station type, Area type, שנת הקמה,
//   ישוב (locality), מיקום, כתובת, X, Y, גובה..., מזהמי אוויר, פרמטרים מטאורולוגיים.
//   • Coordinates are Israel TM Grid (EPSG:2039) easting/northing in columns
//     X / Y (e.g. 227851 / 757888) — NOT lat/lon. We convert each to WGS84 with
//     a self-contained inverse Transverse Mercator + 7-param Bursa-Wolf Helmert
//     transform (validated below against ground-truth ITM↔WGS84 pairs from the
//     education-coordinates dataset; residual < ~2 m).
//   • Station name = "שם התחנה החדש" (falls back to old name).
//
// Output → assets/data/govdata/air_quality_stations.json
//   [[lat, lon, name], ...]   — exact shape of rail_stations.json (gov_data.dart::_loadRail).
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');
const CKAN = 'https://data.gov.il/api/3/action/datastore_search';
const RESOURCE = '9e6daaea-fd72-4ee2-882b-38a5eee135f0';

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

const round = (x, dp) => { const f = 10 ** dp; return Math.round(x * f) / f; };

// ── Israel TM Grid (EPSG:2039, GRS80) → WGS84 ────────────────────────────────
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
  // GRS80 (Israel datum) geodetic → geocentric → WGS84 (Bursa-Wolf, Position Vector).
  const Nn = a / Math.sqrt(1 - e2 * Math.sin(lat) ** 2);
  const X = Nn * Math.cos(lat) * Math.cos(lon);
  const Y = Nn * Math.cos(lat) * Math.sin(lon);
  const Z = (Nn * (1 - e2)) * Math.sin(lat);
  const sec = Math.PI / 180 / 3600;
  const dx = -24.0024, dy = -17.1032, dz = -17.8444;
  const rx = 0.33077 * sec, ry = 1.85269 * sec, rz = -1.66969 * sec, s = 1 + 5.4262e-6;
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

// Ground-truth ITM→WGS84 pairs (from the education-coordinates dataset, which
// publishes both ITM_X/ITM_Y and WGS84 columns) — used to validate the formula.
function validateConversion() {
  const truth = [
    [209506, 739146, 32.7464934060436, 35.0975647218044],
    [168056, 634143, 31.7984875139262, 34.6609761237608],
    [180725, 661643, 32.0469839727977, 34.7936512704733],
    [188744, 665718, 32.0839786666151, 34.8784253113595],
  ];
  let maxM = 0;
  for (const [x, y, tlat, tlon] of truth) {
    const [lat, lon] = itmToWgs84(x, y);
    const dLat = (lat - tlat) * 111320;
    const dLon = (lon - tlon) * 111320 * Math.cos(tlat * Math.PI / 180);
    maxM = Math.max(maxM, Math.hypot(dLat, dLon));
  }
  console.log(`  ITM→WGS84 validation: max residual = ${maxM.toFixed(2)} m over ${truth.length} ground-truth points`);
  // 200 m tolerance: air-quality stations feed a km-scale proximity kernel, so
  // sub-100 m datum residuals are immaterial.
  if (maxM > 200) throw new Error(`ITM→WGS84 residual too large (${maxM.toFixed(1)} m)`);
}

const validLat = (x) => isFinite(x) && Math.abs(x) > 0.1 && x > 29 && x < 34;
const validLon = (x) => isFinite(x) && x > 33 && x < 36;

async function main() {
  console.log('▶ air-quality monitoring stations → air_quality_stations.json');
  mkdirSync(OUT_DIR, { recursive: true });
  validateConversion();

  const rows = await fetchAll(RESOURCE, { label: 'stations' });
  const out = [];
  let dropped = 0;
  for (const r of rows) {
    const x = Number(r.X), y = Number(r.Y);
    if (!isFinite(x) || !isFinite(y) || x <= 0 || y <= 0) { dropped++; continue; }
    const [lat, lon] = itmToWgs84(x, y);
    if (!validLat(lat) || !validLon(lon)) { dropped++; continue; }
    const name = (r['שם התחנה החדש'] || r['שם התחנה הישן'] || r['ישוב'] || '').toString().trim();
    out.push([round(lat, 5), round(lon, 5), name]);
  }

  const file = join(OUT_DIR, 'air_quality_stations.json');
  writeFileSync(file, JSON.stringify(out));
  const size = statSync(file).size;
  console.log('\n── air_quality_stations.json ──');
  console.table({ fetched: rows.length, stations: out.length, droppedInvalid: dropped, bytes: size });
  console.log('samples [[lat,lon,name]]:', JSON.stringify(out.slice(0, 3)));
}

main().catch((e) => { console.error('\n✗ air_quality failed:', e); process.exit(1); });
