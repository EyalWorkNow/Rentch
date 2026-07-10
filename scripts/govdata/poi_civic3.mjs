#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// OSM Overpass → the final civic/lifestyle layers for the "nearby" card.
//   pools.json     [{lat,lon,n,t}]  swimming_pool / sports_centre / pitch  (active/family)
//   dog_parks.json [{lat,lon,n?}]   leisure=dog_park (mostly unnamed)       (pet owners)
//   vets.json      [{lat,lon,n}]    amenity=veterinary                       (pet owners)
//   bike_share.json[{lat,lon,n?}]   amenity=bicycle_rental                   (car-free/young)
//   coworking.json [{lat,lon,n}]    office=coworking / coworking_space       (WFH/freelance/student)
//   parking.json   [{lat,lon,n}]    amenity=parking (NAMED garages only)     (car owners)
// Same per-statement-BBOX + retry pattern as poi_civic2.mjs.
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');
const OVERPASS = 'https://overpass-api.de/api/interpreter';
const BBOX = '29.4,34.2,33.4,35.9';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function overpass(query, { tries = 5 } = {}) {
  for (let i = 1; i <= tries; i++) {
    try {
      const res = await fetch(OVERPASS, {
        method: 'POST',
        headers: {
          'User-Agent': 'RentlyETL/1.0 (apartment-matching; contact hh3466@gmail.com)',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'data=' + encodeURIComponent(query),
      });
      if (res.ok) return await res.json();
      console.log(`  overpass ${res.status} (try ${i})`);
    } catch (e) {
      console.log(`  overpass error (try ${i}): ${e.message}`);
    }
    if (i < tries) await sleep(15000 * i);
  }
  throw new Error('Overpass failed after retries');
}

const validLat = (x) => isFinite(x) && x > 29 && x < 34;
const validLon = (x) => isFinite(x) && x > 33 && x < 36;
const r5 = (x) => Math.round(x * 1e5) / 1e5;
const coordOf = (e) => [e.lat ?? e.center?.lat, e.lon ?? e.center?.lon];

async function fetchNodes(selectors) {
  const body = selectors.map((s) => `node[${s}](${BBOX});`).join('');
  const raw = await overpass(`[out:json][timeout:180];(${body});out center;`);
  return raw.elements || [];
}

function writeLayer(file, elements, { keepUnnamed = false, typeOf } = {}) {
  const out = [];
  const seen = new Set();
  for (const e of elements) {
    const t = e.tags || {};
    const name = (t.name || t['name:he'] || t.brand || t.operator || '').trim();
    if (!name && !keepUnnamed) continue;
    const [lat, lon] = coordOf(e);
    if (!validLat(lat) || !validLon(lon)) continue;
    const key = `${name}_${r5(lat)}_${r5(lon)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const rec = { lat: r5(lat), lon: r5(lon) };
    if (name) rec.n = name;
    if (typeOf) rec.t = typeOf(t);
    out.push(rec);
  }
  writeFileSync(join(OUT_DIR, file), JSON.stringify(out));
  return { count: out.length, named: out.filter((r) => r.n).length, bytes: statSync(join(OUT_DIR, file)).size };
}

function poolType(t) {
  if (t.leisure === 'swimming_pool') return 'בריכה';
  if (t.leisure === 'sports_centre') return 'מרכז ספורט';
  return 'מגרש ספורט';
}

async function main() {
  console.log('▶ OSM civic layers (round 3)');
  mkdirSync(OUT_DIR, { recursive: true });
  const stats = {};

  stats.pools = writeLayer('pools.json',
      await fetchNodes(['"leisure"="swimming_pool"', '"leisure"="sports_centre"', '"leisure"="pitch"']),
      { typeOf: poolType });

  stats.dog_parks = writeLayer('dog_parks.json',
      await fetchNodes(['"leisure"="dog_park"']), { keepUnnamed: true });

  stats.vets = writeLayer('vets.json',
      await fetchNodes(['"amenity"="veterinary"']));

  stats.bike_share = writeLayer('bike_share.json',
      await fetchNodes(['"amenity"="bicycle_rental"']), { keepUnnamed: true });

  stats.coworking = writeLayer('coworking.json',
      await fetchNodes(['"office"="coworking"', '"amenity"="coworking_space"']));

  // NAMED parking only → real garages/חניונים, not every street bay.
  stats.parking = writeLayer('parking.json',
      await fetchNodes(['"amenity"="parking"']));

  console.log('── done ──');
  console.table(stats);
}

main().catch((e) => { console.error('\n✗ poi_civic3 failed:', e); process.exit(1); });
