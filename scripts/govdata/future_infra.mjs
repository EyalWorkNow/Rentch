#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// Future infrastructure (investor upside) → future_infra.json
//
// Two forward-looking value drivers a good agent watches:
//   1) PLANNED / under-construction metro + light-rail stations (נת״ע). A flat a
//      few hundred metres from a future station appreciates before the line opens.
//   2) Urban-renewal projects — פינוי-בינוי / תמ״א (רשות התכנון / mavat).
//
// gov_data.dart::futureValueScore() takes the nearest of each as an exp-falloff
// bonus, weighted only on the investment/growth intent.
//
// Sources:
//   • Stations — OSM under-construction/proposed rail is the practical open feed:
//       node/way [railway=construction] and [railway=station][station~subway|
//       light_rail] with construction/proposed lifecycle tags. The official נת״ע
//       GIS layer is richer — swap it in when you have access.
//   • Renewal — the planning authority (רשות התכנון) publishes פינוי-בינוי / תמ״א
//       project locations; wire that CKAN/GIS resource here (TODO id below).
//
// Output → assets/data/govdata/future_infra.json
//   { "stations":[[lat,lon],…], "renewal":[[lat,lon],…] }
//
// Run:  node scripts/govdata/future_infra.mjs
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../assets/data/govdata/future_infra.json');
const OVERPASS = 'https://overpass-api.de/api/interpreter';
const BBOX = '29.4,34.2,33.4,35.9';
const CKAN = 'https://data.gov.il/api/3/action/datastore_search';

// TODO(confirm): planning-authority resource id for פינוי-בינוי / תמ״א projects.
const RENEWAL_RESOURCE = 'REPLACE_WITH_URBAN_RENEWAL_RESOURCE_ID';

async function overpassStations() {
  // FUTURE stops only — under-construction / proposed rail & LRT stations. We
  // deliberately exclude already-operating lines (e.g. the Red LRT) by requiring
  // a construction/proposed marker. Station nodes on an under-construction line
  // are tagged `construction:railway=light_rail|subway`, which the old bare
  // `railway=construction` node filter missed (only 3 nationwide).
  const q = `[out:json][timeout:180];(
      node["railway"="construction"](${BBOX});
      node["railway"="proposed"](${BBOX});
      node["construction:railway"~"light_rail|subway|rail"](${BBOX});
      node["proposed:railway"~"light_rail|subway|rail"](${BBOX});
      node["railway"~"station|halt"]["station"~"light_rail|subway"]["construction"](${BBOX});
      node["railway"~"station|halt"]["construction:railway"](${BBOX});
    );out center;`;
  const nodes = await overpassRun(q, 'stations');

  // Israel barely tags future STATION nodes, but it DOES map the under-
  // construction / proposed LINES as ways (Green & Purple LRT, the Metro). Sample
  // those line geometries so "proximity to a future line" drives future_value —
  // the correct GIS signal for linear infrastructure.
  const waysQ = `[out:json][timeout:180];(
      way["railway"="construction"]["construction"~"light_rail|subway|rail"](${BBOX});
      way["railway"="proposed"]["proposed"~"light_rail|subway|rail"](${BBOX});
      way["railway"="construction"](${BBOX});
    );out geom;`;
  const wayEls = await overpassRun(waysQ, 'lines');

  const seen = new Set();
  const out = [];
  const push = (a, b) => {
    if (!Number.isFinite(a) || !Number.isFinite(b)) return;
    const k = `${a.toFixed(3)}_${b.toFixed(3)}`; // ~110m dedup grid
    if (seen.has(k)) return;
    seen.add(k);
    out.push([a, b]);
  };
  for (const e of nodes) push(e.lat ?? e.center?.lat, e.lon ?? e.center?.lon);
  for (const w of wayEls) {
    const g = w.geometry ?? [];
    for (let i = 0; i < g.length; i += 4) push(g[i].lat, g[i].lon); // sample every ~4th node
  }
  return out;
}

async function overpassRun(q, label) {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  for (let i = 1; i <= 5; i++) {
    const res = await fetch(OVERPASS, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'RentlyETL/1.0 (apartment-matching; contact hh3466@gmail.com)' },
      body: 'data=' + encodeURIComponent(q),
    });
    if (res.ok) return (await res.json()).elements ?? [];
    console.warn(`  ${label}: Overpass ${res.status}, retrying…`);
    if (i === 5) throw new Error(`Overpass ${res.status} for ${label} after 5 tries`);
    await sleep(20000 * i);
  }
  return [];
}

async function ckanRenewal() {
  if (RENEWAL_RESOURCE.startsWith('REPLACE')) {
    console.warn('  renewal: resource id not set — skipping (stations only)');
    return [];
  }
  const out = [];
  for (let offset = 0; ; offset += 10000) {
    const url = `${CKAN}?resource_id=${RENEWAL_RESOURCE}&limit=10000&offset=${offset}&records_format=objects`;
    const res = await fetch(url, { headers: { accept: 'application/json' } });
    if (!res.ok) throw new Error(`CKAN ${res.status}`);
    const recs = (await res.json()).result?.records ?? [];
    for (const r of recs) {
      const lat = Number(r.lat ?? r.Y ?? r.latitude);
      const lon = Number(r.lon ?? r.X ?? r.longitude);
      if (Number.isFinite(lat) && Number.isFinite(lon)) out.push([lat, lon]);
    }
    if (recs.length < 10000) break;
  }
  return out;
}

async function main() {
  const [stations, renewal] = await Promise.all([
    overpassStations(),
    ckanRenewal(),
  ]);
  const out = { stations, renewal };
  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(out));
  console.log(
    `✓ wrote ${OUT}\n  ${stations.length} planned stations · ${renewal.length} renewal points`,
  );
}

main().catch((e) => {
  console.error('future_infra ingest failed:', e.message);
  process.exit(1);
});
