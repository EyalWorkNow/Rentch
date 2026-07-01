#!/usr/bin/env node
// Fetches matanhakim/general_files muni_ids.csv (the CBS↔Education↔Tax locality
// crosswalk) and writes it as aws/lambda/router/lib/muni_ids.generated.json for
// muni.mjs to load. Run once (and whenever the source updates):
//
//   node scripts/build-muni-ids.mjs
//
// Committed output is what ships in the Lambda; muni.mjs fails soft if it's
// missing (name-based joins still work).

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const SRC = 'https://raw.githubusercontent.com/matanhakim/general_files/main/muni_ids.csv';
const OUT = join(
  dirname(fileURLToPath(import.meta.url)),
  '..', 'aws', 'lambda', 'router', 'lib', 'muni_ids.generated.json',
);

// Minimal CSV: split lines, comma-split fields. muni_ids has no embedded commas
// in its name fields; if the source ever adds quoted fields, revisit.
function parseCsv(text) {
  const lines = text.trim().split(/\r?\n/);
  const headers = lines[0].split(',').map((h) => h.trim());
  return lines.slice(1).map((line) => {
    const cells = line.split(',');
    const row = {};
    headers.forEach((h, i) => { row[h] = (cells[i] || '').trim(); });
    return row;
  });
}

async function main() {
  const res = await fetch(SRC);
  if (!res.ok) throw new Error(`fetch muni_ids.csv → HTTP ${res.status}`);
  const rows = parseCsv(await res.text())
    .filter((r) => r.cbs_id && r.cbs_name);
  writeFileSync(OUT, JSON.stringify(rows, null, 0));
  console.log(`Wrote ${rows.length} localities → ${OUT}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
