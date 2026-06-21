#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// data.gov.il ingestion — crime (safety) overlay
//
// Source: Israel Police "עבירות פליליות" (criminal offences), dataset
//   0d9a6652-41a8-4e99-b543-12ae1178c5bf. Latest yearly CSV with data:
//   2024 = 5fc13c50-b6f3-4712-b831-a75e0f91a17e (≈399k rows), each row is one
//   recorded offence (FictiveIDNumber = case id). Falls back to 2023.
//
// Discovered schema (records_format=objects):
//   _id, FictiveIDNumber, Year, Quarter, YeshuvKod, Yeshuv, PoliceDistrict*,
//   PoliceMerhav*, PoliceStation*, municipalKod, municipalName,
//   StatisticArea*, StatisticGroup (offence category), StatisticType (subtype).
//
// Aggregate per LOCALITY (Yeshuv, normalized like ingest.mjs):
//   total    = count of offence rows
//   violent  = subset whose StatisticGroup is against the body/person/morals
//              (keywords: גוף, אדם, מין — e.g. "עבירות נגד גוף")
//   property = subset whose StatisticGroup is against property (keyword: רכוש)
//
// Output → assets/data/govdata/crime.json
//   { "<normalized locality name>": { "total": int, "violent": int, "property": int } }
//
// Usage:  node scripts/govdata/crime.mjs
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');

const CKAN = 'https://data.gov.il/api/3/action/datastore_search';
const CRIME_2024 = '5fc13c50-b6f3-4712-b831-a75e0f91a17e';
const CRIME_2023 = '32aacfc9-3524-4fba-a282-3af052380244';

// ── CKAN paginated fetch (mirrors ingest.mjs) ────────────────────────────────
async function fetchAll(resourceId, { pageSize = 10000, label = '' } = {}) {
  const out = [];
  let offset = 0;
  for (;;) {
    const url = `${CKAN}?resource_id=${resourceId}&limit=${pageSize}&offset=${offset}&records_format=objects`;
    const res = await fetch(url, { headers: { accept: 'application/json' } });
    if (!res.ok) throw new Error(`CKAN ${res.status} for ${resourceId}`);
    const json = await res.json();
    if (json.success === false) throw new Error(`CKAN error for ${resourceId}`);
    const recs = json.result?.records ?? [];
    out.push(...recs);
    process.stdout.write(`\r  ${label}: ${out.length} rows`);
    if (recs.length < pageSize) break;
    offset += pageSize;
  }
  process.stdout.write('\n');
  return out;
}

// name normalization — identical to ingest.mjs / gov_data.dart
const normName = (s = '') =>
  s.replace(/["'״׳]/g, '').replace(/\s*-\s*/g, '-').replace(/\s+/g, ' ').trim();

// offence-category classification (best-effort by Hebrew keywords)
const VIOLENT_KEYS = ['גוף', 'אדם', 'מין']; // נגד גוף / נגד אדם / עבירות מין
const PROPERTY_KEYS = ['רכוש']; // עבירות כלפי הרכוש
const hasKey = (s, keys) => keys.some((k) => s.includes(k));

async function loadCrime() {
  let rows = await fetchAll(CRIME_2024, { label: 'crime 2024' });
  if (rows.length === 0) {
    console.log('  2024 empty → falling back to 2023');
    rows = await fetchAll(CRIME_2023, { label: 'crime 2023' });
  }
  return rows;
}

async function main() {
  console.log('▶ data.gov.il crime ingestion');
  mkdirSync(OUT_DIR, { recursive: true });

  const rows = await loadCrime();

  const byLoc = new Map(); // normName → {total, violent, property}
  const groups = new Set();
  let noName = 0;
  for (const r of rows) {
    const name = normName(r.Yeshuv ?? '');
    if (!name) { noName += 1; continue; }
    const group = (r.StatisticGroup ?? '').toString();
    groups.add(group);
    const agg = byLoc.get(name) ?? { total: 0, violent: 0, property: 0 };
    agg.total += 1;
    if (hasKey(group, VIOLENT_KEYS)) agg.violent += 1;
    if (hasKey(group, PROPERTY_KEYS)) agg.property += 1;
    byLoc.set(name, agg);
  }

  const out = {};
  for (const [name, agg] of [...byLoc].sort((a, b) => b[1].total - a[1].total)) {
    out[name] = agg;
  }

  const file = join(OUT_DIR, 'crime.json');
  writeFileSync(file, JSON.stringify(out));

  const sizeKb = (statSync(file).size / 1024).toFixed(1);
  const sample = Object.entries(out).slice(0, 3);
  console.log(`\n✓ wrote ${file} (${sizeKb} KB)`);
  console.log('rows fetched     :', rows.length, `(rows without Yeshuv: ${noName})`);
  console.log('localities       :', Object.keys(out).length);
  console.log('offence groups   :', [...groups].filter(Boolean));
  console.log('violent keywords :', VIOLENT_KEYS, ' property keywords:', PROPERTY_KEYS);
  console.log('sample entries   :');
  for (const [k, v] of sample) console.log('  ', k, '→', JSON.stringify(v));
}

main().catch((e) => {
  console.error('\n✗ crime ingestion failed:', e.message);
  process.exit(1);
});
