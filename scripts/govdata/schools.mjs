#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// data.gov.il POI ingestion — education institutions → schools_grid.json
//
// Source: "קואורדינטות מוסדות החינוך" (coordinates), resource
//   5c5d6bb0-755d-470d-84b6-d7dd3135ba9c  (CSV, datastore-active → CKAN).
// Fields: SEMEL_MOSAD, SHEM_MOSAD, ITM_X, ITM_Y, UTM_X, UTM_Y, RAMAT_DIYUK_MIKUM.
//   • UTM_X / UTM_Y are already WGS84 lon / lat in decimal degrees (mislabeled
//     "UTM"; values like 35.0975 / 32.7464). We use them directly — no projection
//     conversion needed. ITM_X/ITM_Y (Israel TM, EPSG:2039) are kept as a fallback
//     only when the WGS84 columns are blank/invalid.
//   • No explicit type column, so school vs kindergarten is inferred from the
//     institution name (גן / גנון / מעון → kindergarten, else school).
//
// Output → assets/data/govdata/schools_grid.json
//   { "cell":0.02, "cells": { "<latIdx>_<lonIdx>": [schoolCount, kindergartenCount] } }
// Mirrors transit_grid.json so gov_data.dart::_loadGrid reads it unchanged.
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');
const CKAN = 'https://data.gov.il/api/3/action/datastore_search';
const RESOURCE = '5c5d6bb0-755d-470d-84b6-d7dd3135ba9c';
const GRID_DEG = 0.02;

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

const cellKey = (lat, lon) =>
  `${Math.round(lat / GRID_DEG)}_${Math.round(lon / GRID_DEG)}`;

// Israel TM Grid (EPSG:2039, GRS80) → WGS84 — used only as a fallback when the
// WGS84 columns are missing. (Full inverse TM + 7-param Helmert; same routine as
// air_quality.mjs.)
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
  // GRS80 (Israel datum) → WGS84 via Bursa-Wolf 7-param (Position Vector).
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

// kindergarten if the name leads with גן / גנון / מעון (Hebrew preschool terms).
const isKindergarten = (name = '') =>
  /^גן(ון)?(\s|$)/.test(name) || /^מעון/.test(name) || /גנון/.test(name);

const validLat = (x) => isFinite(x) && Math.abs(x) > 0.1 && x > 29 && x < 34;
const validLon = (x) => isFinite(x) && x > 33 && x < 36;

async function main() {
  console.log('▶ education institutions → schools_grid.json');
  mkdirSync(OUT_DIR, { recursive: true });
  const rows = await fetchAll(RESOURCE, { label: 'schools' });

  const grid = new Map(); // key → [schoolCount, kindergartenCount]
  let usedWgs = 0, usedItm = 0, dropped = 0, schools = 0, kg = 0;

  for (const r of rows) {
    let lat = Number(r.UTM_Y), lon = Number(r.UTM_X);
    if (validLat(lat) && validLon(lon)) {
      usedWgs++;
    } else {
      const ix = Number(r.ITM_X), iy = Number(r.ITM_Y);
      if (isFinite(ix) && isFinite(iy) && ix > 0 && iy > 0) {
        [lat, lon] = itmToWgs84(ix, iy);
        usedItm++;
      }
    }
    if (!validLat(lat) || !validLon(lon)) { dropped++; continue; }

    const k = cellKey(lat, lon);
    const cell = grid.get(k) ?? [0, 0];
    if (isKindergarten(r.SHEM_MOSAD)) { cell[1]++; kg++; } else { cell[0]++; schools++; }
    grid.set(k, cell);
  }

  const cells = {};
  for (const [k, v] of grid) cells[k] = v;
  const file = join(OUT_DIR, 'schools_grid.json');
  writeFileSync(file, JSON.stringify({ cell: GRID_DEG, cells }));

  const size = statSync(file).size;
  console.log('\n── schools_grid.json ──');
  console.table({
    fetched: rows.length,
    coordsWGS84cols: usedWgs,
    coordsITMconverted: usedItm,
    droppedInvalid: dropped,
    schools, kindergartens: kg,
    gridCells: Object.keys(cells).length,
    bytes: size,
  });
  const samples = Object.entries(cells).slice(0, 3);
  console.log('samples [key → [schoolCount, kindergartenCount]]:', JSON.stringify(samples));
}

main().catch((e) => { console.error('\n✗ schools failed:', e); process.exit(1); });
