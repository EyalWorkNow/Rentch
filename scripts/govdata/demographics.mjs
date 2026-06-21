#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// data.gov.il ingestion — demographics overlay
//
// NOTE on resource: the brief named 9ba87444-aec5-4f46-89a5-a690a32668e2, but
// that resource_id returns "Not Found" on the live CKAN. The probe instead used
// the CBS Census-2022 per-locality table, which carries BOTH population and age
// bands in one resource keyed by locality name:
//   9a9e085f-3bc8-41df-b15f-be0daaf99e30
//   ("נתונים נבחרים לפי יישובים ואזורים סטטיסטיים - מפקד 2022", 3,379 rows).
//
// Discovered schema (relevant fields):
//   LocNameHeb (locality name), LocalityCode, StatArea / StatAreaCmb,
//   pop_approx (population), age0_19_pcnt, age20_64_pcnt, age65_pcnt, …
//   • A row is the LOCALITY TOTAL when StatArea is null; rows with a StatArea
//     value are statistical-area breakdowns within the locality (skipped).
//   • The national row ('כלל ארצי') has LocalityCode null (skipped).
//
// Census age bands are 0-19 / 20-64 / 65+, so shares are mapped to the closest
// available buckets and documented as such:
//   childShare  = age0_19_pcnt/100   (ages 0-19  ≈ children/youth)
//   youngShare  = age20_64_pcnt/100  (ages 20-64 ≈ working-age adults)
//   seniorShare = age65_pcnt/100     (ages 65+)
//
// Output → assets/data/govdata/demographics.json
//   { "<normalized locality name>": { "pop": int, "youngShare": num,
//                                     "childShare": num, "seniorShare": num } }
//
// Usage:  node scripts/govdata/demographics.mjs
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');

const CKAN = 'https://data.gov.il/api/3/action/datastore_search';
const DEMOG_RESOURCE = '9a9e085f-3bc8-41df-b15f-be0daaf99e30';

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

// CBS cells arrive as numbers or strings (with stray commas/spaces). Parse safe.
const num = (v) => {
  if (v == null) return null;
  const n = Number(String(v).replace(/[,\s]/g, ''));
  return Number.isFinite(n) ? n : null;
};
const round3 = (x) => Math.round(x * 1000) / 1000;
const share = (pct) => (pct == null ? null : round3(pct / 100));

async function main() {
  console.log('▶ data.gov.il demographics ingestion');
  mkdirSync(OUT_DIR, { recursive: true });

  const rows = await fetchAll(DEMOG_RESOURCE, { label: 'demographics' });

  const out = {};
  let localityRows = 0;
  let withShares = 0;
  for (const r of rows) {
    // keep only whole-locality totals (StatArea null) with a real locality
    if (r.StatArea != null && String(r.StatArea).trim() !== '') continue;
    if (r.LocalityCode == null) continue; // skip national 'כלל ארצי'
    const name = normName(r.LocNameHeb ?? '');
    if (!name) continue;
    const pop = num(r.pop_approx);
    if (pop == null) continue;
    localityRows += 1;

    const rec = { pop: Math.round(pop) };
    const young = share(num(r.age20_64_pcnt));
    const child = share(num(r.age0_19_pcnt));
    const senior = share(num(r.age65_pcnt));
    if (young != null) rec.youngShare = young;
    if (child != null) rec.childShare = child;
    if (senior != null) rec.seniorShare = senior;
    if (young != null || child != null || senior != null) withShares += 1;

    // keep the largest population on any name collision
    if (!out[name] || out[name].pop < rec.pop) out[name] = rec;
  }

  const file = join(OUT_DIR, 'demographics.json');
  writeFileSync(file, JSON.stringify(out));

  const sizeKb = (statSync(file).size / 1024).toFixed(1);
  const sample = Object.entries(out).slice(0, 3);
  console.log(`\n✓ wrote ${file} (${sizeKb} KB)`);
  console.log('rows fetched      :', rows.length);
  console.log('locality totals   :', localityRows, `(with age shares: ${withShares})`);
  console.log('output localities :', Object.keys(out).length);
  console.log('fields used       : LocNameHeb, LocalityCode, StatArea, pop_approx,');
  console.log('                    age0_19_pcnt, age20_64_pcnt, age65_pcnt');
  console.log('sample entries    :');
  for (const [k, v] of sample) console.log('  ', k, '→', JSON.stringify(v));
}

main().catch((e) => {
  console.error('\n✗ demographics ingestion failed:', e.message);
  process.exit(1);
});
