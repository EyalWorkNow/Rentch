#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// Road/rail NOISE proxy → noise_roads.json
//
// Source: OpenStreetMap via Overpass. A physical-quiet proxy: presence of a
// MAJOR traffic artery or a rail line near a flat.
//   • major roads → highway = motorway | trunk | primary (the loud ones; we skip
//     secondary/residential — living on a quiet street is fine)
//   • rail        → railway = rail | light_rail | subway
//
// Output → assets/data/govdata/noise_roads.json
//   { "cell":0.005, "cells": { "<latIdx>_<lonIdx>": segmentCount } }
// FINE 0.005° cells (~500m) because noise is a local effect. gov_data.dart::
// _loadNoise reads it; roadNoiseScore() returns 1 in a road cell, 0.5 in the
// ring, 0 otherwise (→ low_noise = 1 - that).
//
// Run:  node scripts/govdata/noise.mjs
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../assets/data/govdata/noise_roads.json');
const GRID_DEG = 0.005;
const OVERPASS = 'https://overpass-api.de/api/interpreter';
const BBOX = '29.4,34.2,33.4,35.9';

const SELECTORS = [
  'way["highway"~"^(motorway|trunk|primary)$"]',
  'way["railway"~"^(rail|light_rail|subway)$"]',
];

async function overpass(selector, label) {
  const q = `[out:json][timeout:300];(${selector}(${BBOX}););out geom;`;
  process.stdout.write(`  ${label}: querying Overpass…`);
  const res = await fetch(OVERPASS, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'data=' + encodeURIComponent(q),
  });
  if (!res.ok) throw new Error(`Overpass ${res.status} for ${label}`);
  const json = await res.json();
  const els = json.elements ?? [];
  process.stdout.write(`\r  ${label}: ${els.length} ways        \n`);
  return els;
}

const key = (lat, lon) =>
  `${Math.round(lat / GRID_DEG)}_${Math.round(lon / GRID_DEG)}`;

async function main() {
  const cells = {}; // key → segment-node count
  let ways = 0;
  for (const sel of SELECTORS) {
    const els = await overpass(sel, sel.includes('railway') ? 'rail' : 'roads');
    for (const el of els) {
      ways++;
      // Sample every geometry node; each stamps its ~500m cell as "has an artery".
      for (const g of el.geometry ?? []) {
        if (Number.isFinite(g.lat) && Number.isFinite(g.lon)) {
          const k = key(g.lat, g.lon);
          cells[k] = (cells[k] ?? 0) + 1;
        }
      }
    }
  }

  const out = { cell: GRID_DEG, cells };
  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(out));
  console.log(
    `✓ wrote ${OUT}\n  ${Object.keys(cells).length} noisy cells from ${ways} ways`,
  );
}

main().catch((e) => {
  console.error('noise ingest failed:', e.message);
  process.exit(1);
});
