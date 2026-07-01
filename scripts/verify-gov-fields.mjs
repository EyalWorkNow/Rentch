#!/usr/bin/env node
// verify-gov-fields.mjs — probes the data.gov.il resources the neighborhood
// scorer depends on and checks the code's field lists (imported live from
// neighborhood.mjs — single source of truth) against the datasets' columns.
// Also validates the two capabilities the scorer relies on: filters+limit=0
// counting (the SQL endpoint is disabled) and the CBS-code join.
// Prints a ✓/✗ summary; exits non-zero if any CRITICAL check fails.
//
//   node scripts/verify-gov-fields.mjs
//
// Read-only: only GET requests to the public CKAN API.

import { GOV_FIELDS as F } from '../aws/lambda/router/lib/neighborhood.mjs';

const base = 'https://data.gov.il/api/3/action/datastore_search';
async function ckan(params) {
  const r = await fetch(`${base}?${params}`);
  const t = await r.text();
  try { return JSON.parse(t); } catch { return { __html: t.slice(0, 40) }; }
}
async function columns(id) {
  const j = await ckan(`resource_id=${id}&limit=1`);
  if (!j.result) throw new Error(j.error?.__type || j.__html || 'no result');
  const keys = new Set((j.result.fields || []).map((f) => f.id));
  for (const rec of j.result.records || []) for (const k in rec) keys.add(k);
  return { keys, row: j.result.records?.[0] || {} };
}

let criticalFail = 0;
const firstMatch = (keys, cands) => cands.find((c) => keys.has(c)) || null;
function line(label, ok, val, { optional = false } = {}) {
  const mark = ok ? '✓' : (optional ? '·' : '✗');
  if (!ok && !optional) criticalFail++;
  console.log(`   ${mark} ${String(label).padEnd(26)} ${ok ? `→ ${val}` : (optional ? 'absent (optional)' : `DARK — ${val || 'no match'}`)}`);
}

async function main() {
  const R = F.resources;
  console.log('Verifying data.gov.il fields against neighborhood.mjs …');

  // 1. Coordinates dataset — geo + name-based kindergarten.
  console.log(`\n━━ COORDS  (${R.RES_SCHOOLS})`);
  try {
    const { keys, row } = await columns(R.RES_SCHOOLS);
    const lat = firstMatch(keys, F.eduLat); const lng = firstMatch(keys, F.eduLng);
    line('lat / lng coords', lat && lng, `${lat}/${lng}`);
    const la = Number(row[lat]); const lo = Number(row[lng]);
    line('coords in Israel bbox', la >= 29 && la <= 34 && lo >= 34 && lo <= 36, `lat=${la} lng=${lo}`);
    line('kindergarten name/type', !!firstMatch(keys, F.stage), firstMatch(keys, F.stage));
  } catch (e) { line('fetch', false, e.message); }

  // 2. Education characteristics (mosdot) — pikuah/sector for the gates.
  console.log(`\n━━ SCHOOLS_META / mosdot  (${R.RES_SCHOOLS_META})`);
  try {
    const { keys } = await columns(R.RES_SCHOOLS_META);
    line('pikuah (gates)', !!firstMatch(keys, F.pikuah), firstMatch(keys, F.pikuah));
    line('sector (gates)', !!firstMatch(keys, F.sector), firstMatch(keys, F.sector));
    line('stage (kindergarten)', !!firstMatch(keys, F.stage), firstMatch(keys, F.stage));
  } catch (e) { line('fetch', false, e.message); }

  // 3. Crime — code column + filters+limit=0 counting capability.
  console.log(`\n━━ CRIME  (${R.RES_CRIME})`);
  try {
    const { keys } = await columns(R.RES_CRIME);
    line('locality code', keys.has(F.codes.CRIME_CODE_KEY), F.codes.CRIME_CODE_KEY);
    const c = await ckan(`resource_id=${R.RES_CRIME}&filters=${encodeURIComponent(JSON.stringify({ [F.codes.CRIME_CODE_KEY]: 8700 }))}&limit=0`);
    line('filters+limit=0 count', Number.isFinite(c.result?.total), `total=${c.result?.total} (רעננה)`);
  } catch (e) { line('fetch', false, e.message); }

  // 4. Population.
  console.log(`\n━━ POPULATION  (${R.RES_POPULATION})`);
  try {
    const { keys } = await columns(R.RES_POPULATION);
    line('locality code', keys.has(F.codes.POP_CODE_KEY), F.codes.POP_CODE_KEY);
    line('population value', keys.has(F.codes.POP_VALUE_KEY), F.codes.POP_VALUE_KEY);
  } catch (e) { line('fetch', false, e.message); }

  // 5. Socio-economic.
  console.log(`\n━━ SOCIO  (${R.RES_SOCIOECONOMIC})`);
  try {
    const { keys } = await columns(R.RES_SOCIOECONOMIC);
    line('locality code', keys.has(F.codes.SOCIO_CODE_KEY), F.codes.SOCIO_CODE_KEY);
    line(`socio field "${R.SOCIO_FIELD}"`, keys.has(R.SOCIO_FIELD), R.SOCIO_FIELD);
  } catch (e) { line('fetch', false, e.message); }

  console.log(`\n${criticalFail === 0
    ? '✅ all critical fields + capabilities verified — the pipeline lights up.'
    : `⚠️  ${criticalFail} critical check(s) failed — fix before trusting the feed.`}`);
  process.exit(criticalFail === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(2); });
