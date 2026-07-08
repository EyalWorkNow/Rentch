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
  // Under-construction / proposed rail stations (the future stops).
  const q = `[out:json][timeout:180];(
      node["railway"="construction"](${BBOX});
      node["railway"="station"]["station"~"subway|light_rail"]["construction"](${BBOX});
      node["railway"="proposed"](${BBOX});
    );out center;`;
  const res = await fetch(OVERPASS, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'data=' + encodeURIComponent(q),
  });
  if (!res.ok) throw new Error(`Overpass ${res.status}`);
  const els = (await res.json()).elements ?? [];
  return els
    .map((e) => [e.lat ?? e.center?.lat, e.lon ?? e.center?.lon])
    .filter(([a, b]) => Number.isFinite(a) && Number.isFinite(b));
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
