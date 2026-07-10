#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// OSM Overpass → lifestyle POI layers for the personalised "nearby" card.
//   pharmacies.json  [{n,lat,lon}]   amenity=pharmacy         (family/everyone)
//   playgrounds.json [{lat,lon}]     leisure=playground       (family — mostly unnamed)
//   gyms.json        [{n,lat,lon}]   leisure=fitness_centre + amenity=gym (active)
//   dining.json      [{n,lat,lon,t}] amenity=restaurant|cafe  (couples/singles) t=מסעדה/בית קפה
//   nightlife.json   [{n,lat,lon,t}] amenity=bar|pub          (singles/roommates) t=בר/פאב
// Same bundled-asset pattern as clinics/supermarkets (poi_osm.mjs); nodes only.
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');
const OVERPASS = 'https://overpass-api.de/api/interpreter';
const BBOX = '29.4,34.2,33.4,35.9';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function overpass(query, { tries = 4 } = {}) {
  for (let i = 1; i <= tries; i++) {
    try {
      const res = await fetch(OVERPASS, {
        method: 'POST',
        headers: { 'User-Agent': 'RentlyETL/1.0', 'Content-Type': 'application/x-www-form-urlencoded' },
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

// Write a simple named-point layer; keep unnamed too when keepUnnamed.
function writeLayer(file, elements, { keepUnnamed = false, typeOf } = {}) {
  const out = [];
  const seen = new Set();
  for (const e of elements) {
    const t = e.tags || {};
    const name = (t.name || t.brand || '').trim();
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
  return { count: out.length, bytes: statSync(join(OUT_DIR, file)).size };
}

// Scoring nightlife: weighted density points [lat,lon,w] for IsraelGeoIndex.
// bars/pubs/clubs → 1.0, cafés → 0.4 (a café adds vibrancy but less than a bar).
function writeScoringNightlife(file, nightEls, diningEls) {
  const out = [];
  const seen = new Set();
  const add = (e, w) => {
    const [lat, lon] = coordOf(e);
    if (!validLat(lat) || !validLon(lon)) return;
    const key = `${r5(lat)}_${r5(lon)}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push([r5(lat), r5(lon), w]);
  };
  for (const e of nightEls) add(e, 1.0);
  for (const e of diningEls) {
    if ((e.tags || {}).amenity === 'cafe') add(e, 0.4);
  }
  writeFileSync(join(OUT_DIR, file), JSON.stringify(out));
  return { count: out.length, bytes: statSync(join(OUT_DIR, file)).size };
}

async function main() {
  console.log('▶ OSM lifestyle layers');
  mkdirSync(OUT_DIR, { recursive: true });
  const stats = {};

  stats.pharmacies = writeLayer('pharmacies.json',
      await fetchNodes(['"amenity"="pharmacy"']));

  stats.playgrounds = writeLayer('playgrounds.json',
      await fetchNodes(['"leisure"="playground"']), { keepUnnamed: true });

  stats.gyms = writeLayer('gyms.json',
      await fetchNodes(['"leisure"="fitness_centre"', '"amenity"="gym"']));

  const diningEls =
      await fetchNodes(['"amenity"="restaurant"', '"amenity"="cafe"']);
  stats.dining = writeLayer('dining.json', diningEls,
      { typeOf: (t) => (t.amenity === 'cafe' ? 'בית קפה' : 'מסעדה') });

  const nightEls =
      await fetchNodes(['"amenity"="bar"', '"amenity"="pub"', '"amenity"="nightclub"']);
  // CARD layer — named venues (bars/pubs/clubs), object format [{n,lat,lon,t}].
  stats.nightlife_venues = writeLayer('nightlife_venues.json', nightEls, {
    typeOf: (t) => (t.amenity === 'pub'
        ? 'פאב'
        : t.amenity === 'nightclub'
            ? 'מועדון'
            : 'בר'),
  });
  // SCORING layer — weighted density points [lat,lon,w]. This is a SEPARATE file
  // and format from the card: IsraelGeoIndex.loadNightlife() parses [[lat,lon,w]]
  // (bars/pubs/clubs weighted 1.0, cafés 0.4). They MUST NOT share a filename.
  stats.nightlife = writeScoringNightlife('nightlife.json', nightEls, diningEls);

  console.log('── done ──');
  console.table(stats);
}

main().catch((e) => { console.error('\n✗ poi_lifestyle failed:', e); process.exit(1); });
