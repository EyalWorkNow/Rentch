#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// data.gov.il POI ingestion — mental-health facilities → health.json
//
// Sources (both XLSX but datastore-active → read via CKAN datastore_search):
//   • f7a7b061-db5b-4e19-b1bf-2d7525af52ca — "מרפאות בריאות הנפש" (mental-health
//       clinics). Fields: HMO, clinic_name, city, street, phone, ownership, …
//   • 5b4dfe37-ca97-4973-9752-5f1950939832 — "בתי חולים פסיכיאטריים …"
//       (psychiatric hospitals). Fields: Code, hospital_name, district, city,
//       address, phone, …
//
// Neither dataset carries coordinates — only a city/locality string — so we
// produce PER-LOCALITY COUNTS rather than a coordinate grid:
//   { "<normalized locality name>": count }
// Locality names are normalized with the same rule as ingest.mjs::normName, so
// they join cleanly to localities.json in gov_data.dart.
//
// Output → assets/data/govdata/health.json   (per-locality counts)
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');
const CKAN = 'https://data.gov.il/api/3/action/datastore_search';
const CLINICS = 'f7a7b061-db5b-4e19-b1bf-2d7525af52ca';
const HOSPITALS = '5b4dfe37-ca97-4973-9752-5f1950939832';

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

// mirrors ingest.mjs::normName so names join to localities.json
const normName = (s = '') =>
  s.replace(/["'״׳]/g, '').replace(/\s*-\s*/g, '-').replace(/\s+/g, ' ').trim();

async function main() {
  console.log('▶ mental-health facilities → health.json');
  mkdirSync(OUT_DIR, { recursive: true });

  const clinics = await fetchAll(CLINICS, { label: 'clinics' });
  const hospitals = await fetchAll(HOSPITALS, { label: 'hospitals' });

  const counts = {};
  let skipped = 0;
  const tally = (rows, field) => {
    for (const r of rows) {
      const city = normName((r[field] ?? '').toString());
      if (!city) { skipped++; continue; }
      counts[city] = (counts[city] ?? 0) + 1;
    }
  };
  tally(clinics, 'city');
  tally(hospitals, 'city');

  const file = join(OUT_DIR, 'health.json');
  writeFileSync(file, JSON.stringify(counts));
  const size = statSync(file).size;

  console.log('\n── health.json (per-locality counts) ──');
  console.table({
    clinics: clinics.length,
    hospitals: hospitals.length,
    totalFacilities: clinics.length + hospitals.length,
    skippedNoCity: skipped,
    localities: Object.keys(counts).length,
    bytes: size,
  });
  const top = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 3);
  console.log('samples (top 3 by count):', JSON.stringify(top));
}

main().catch((e) => { console.error('\n✗ health failed:', e); process.exit(1); });
