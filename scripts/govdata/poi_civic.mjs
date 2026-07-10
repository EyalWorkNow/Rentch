#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// OSM Overpass → civic/community POI layers for the personalised "nearby" card.
//   synagogues.json [{lat,lon,n?}]     place_of_worship+jewish (many unnamed →
//                                      generic "בית כנסת"); religious/family value
//   culture.json    [{lat,lon,n,t}]    museums/theatres/cinemas/arts/מתנ״ס/library
// Same bundled-asset + per-statement-BBOX + retry pattern as poi_lifestyle.mjs.
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
    const name = (t.name || t['name:he'] || t.brand || '').trim();
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

function cultureType(t) {
  if (t.tourism === 'museum') return 'מוזיאון';
  if (t.tourism === 'gallery') return 'גלריה';
  switch (t.amenity) {
    case 'theatre': return 'תיאטרון';
    case 'cinema': return 'קולנוע';
    case 'arts_centre': return 'מרכז אמנויות';
    case 'community_centre': return 'מתנ״ס';
    case 'library': return 'ספרייה';
    default: return 'תרבות';
  }
}

async function main() {
  console.log('▶ OSM civic/community layers');
  mkdirSync(OUT_DIR, { recursive: true });
  const stats = {};

  // Synagogues — keep unnamed (most OSM synagogues have no name) → generic label.
  stats.synagogues = writeLayer('synagogues.json',
      await fetchNodes(['"amenity"="place_of_worship"]["religion"="jewish"']),
      { keepUnnamed: true });

  // Culture — museums / galleries / theatres / cinemas / arts / מתנ״ס / libraries.
  stats.culture = writeLayer('culture.json',
      await fetchNodes([
        '"tourism"="museum"', '"tourism"="gallery"',
        '"amenity"="theatre"', '"amenity"="cinema"', '"amenity"="arts_centre"',
        '"amenity"="community_centre"', '"amenity"="library"',
      ]),
      { typeOf: cultureType });

  console.log('── done ──');
  console.table(stats);
}

main().catch((e) => { console.error('\n✗ poi_civic failed:', e); process.exit(1); });
