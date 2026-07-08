#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// Retail / errands POI ingestion → poi_retail.json
//
// Source: OpenStreetMap via the Overpass API (data.gov.il has no clean national
// retail layer; OSM is the practical, open, well-tagged source — and is what the
// backend already uses for POI distances).
//   • supermarkets  → shop=supermarket, shop=convenience, shop=greengrocer
//   • shopping ctrs  → shop=mall, shop=department_store, amenity=marketplace
//
// Output → assets/data/govdata/poi_retail.json
//   { "cell":0.02, "cells": { "<latIdx>_<lonIdx>": [marketCount, mallCount] } }
// Mirrors schools_grid.json exactly, so gov_data.dart::_loadRetail reads it
// unchanged. retailAccessScore() sums a 3×3 window and weights malls ×2.
//
// Run:  node scripts/govdata/poi_retail.mjs
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../assets/data/govdata/poi_retail.json');
const GRID_DEG = 0.02;
const OVERPASS = 'https://overpass-api.de/api/interpreter';

// Israel + West Bank settlements bbox (south,west,north,east).
const BBOX = '29.4,34.2,33.4,35.9';

const MARKET_Q = 'nwr["shop"~"^(supermarket|convenience|greengrocer)$"]';
const MALL_Q =
  'nwr["shop"~"^(mall|department_store)$"];nwr["amenity"="marketplace"]';

async function overpass(selector, label) {
  const q = `[out:json][timeout:180];(${selector}(${BBOX}););out center;`;
  process.stdout.write(`  ${label}: querying Overpass…`);
  const res = await fetch(OVERPASS, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'data=' + encodeURIComponent(q),
  });
  if (!res.ok) throw new Error(`Overpass ${res.status} for ${label}`);
  const json = await res.json();
  const els = json.elements ?? [];
  process.stdout.write(`\r  ${label}: ${els.length} POIs        \n`);
  return els;
}

// element → [lat, lon] (nodes carry lat/lon; ways/relations carry .center).
function coords(el) {
  const lat = el.lat ?? el.center?.lat;
  const lon = el.lon ?? el.center?.lon;
  return Number.isFinite(lat) && Number.isFinite(lon) ? [lat, lon] : null;
}

function cellKey(lat, lon) {
  const cx = Math.round(lat / GRID_DEG);
  const cy = Math.round(lon / GRID_DEG);
  return `${cx}_${cy}`;
}

async function main() {
  const markets = await overpass(MARKET_Q, 'supermarkets');
  const malls = await overpass(MALL_Q, 'shopping centres');

  const cells = {}; // key → [markets, malls]
  const bump = (el, idx) => {
    const c = coords(el);
    if (!c) return;
    const k = cellKey(c[0], c[1]);
    (cells[k] ??= [0, 0])[idx]++;
  };
  for (const el of markets) bump(el, 0);
  for (const el of malls) bump(el, 1);

  // Drop empty cells; keep it compact.
  const out = { cell: GRID_DEG, cells: {} };
  for (const [k, v] of Object.entries(cells)) {
    if (v[0] + v[1] > 0) out.cells[k] = v;
  }

  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(out));
  const n = Object.keys(out.cells).length;
  console.log(
    `✓ wrote ${OUT}\n  ${n} cells · ${markets.length} markets · ${malls.length} malls`,
  );
}

main().catch((e) => {
  console.error('poi_retail ingest failed:', e.message);
  process.exit(1);
});
