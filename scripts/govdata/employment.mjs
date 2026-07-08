#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// Employment density → employment.json
//
// "קרוב לעבודה" made real: instead of a transit proxy, score proximity to where
// the jobs actually are — office clusters + commercial/industrial zones.
//
// Source: OpenStreetMap via Overpass.
//   • offices     → office=* (companies, coworking, government, IT…)
//   • job zones   → landuse=commercial | industrial | retail (area centroids)
// Each place stamps its 0.02° cell; gov_data.dart::employmentAccessScore sums a
// 3×3 window and log-scales it. CBS "משרות שכיר לפי אזור" would be a richer
// official layer — swap it in when available.
//
// Output → assets/data/govdata/employment.json
//   { "cell":0.02, "cells": { "<latIdx>_<lonIdx>": jobPlaceCount } }
//
// Run:  node scripts/govdata/employment.mjs
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../assets/data/govdata/employment.json');
const GRID_DEG = 0.02;
const OVERPASS = 'https://overpass-api.de/api/interpreter';
const BBOX = '29.4,34.2,33.4,35.9';

const SELECTOR =
  'nwr["office"];nwr["landuse"~"^(commercial|industrial|retail)$"]';

const key = (lat, lon) =>
  `${Math.round(lat / GRID_DEG)}_${Math.round(lon / GRID_DEG)}`;

async function main() {
  const q = `[out:json][timeout:300];(${SELECTOR}(${BBOX}););out center;`;
  process.stdout.write('  querying Overpass…');
  const res = await fetch(OVERPASS, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'data=' + encodeURIComponent(q),
  });
  if (!res.ok) throw new Error(`Overpass ${res.status}`);
  const els = (await res.json()).elements ?? [];
  process.stdout.write(`\r  ${els.length} job places            \n`);

  const cells = {};
  for (const el of els) {
    const lat = el.lat ?? el.center?.lat;
    const lon = el.lon ?? el.center?.lon;
    if (Number.isFinite(lat) && Number.isFinite(lon)) {
      const k = key(lat, lon);
      cells[k] = (cells[k] ?? 0) + 1;
    }
  }

  const out = { cell: GRID_DEG, cells };
  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(out));
  console.log(`✓ wrote ${OUT}\n  ${Object.keys(cells).length} cells`);
}

main().catch((e) => {
  console.error('employment ingest failed:', e.message);
  process.exit(1);
});
