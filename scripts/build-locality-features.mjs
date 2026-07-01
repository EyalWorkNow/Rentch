#!/usr/bin/env node
// build-locality-features.mjs — precomputes a per-locality features table keyed
// by CBS code, joining population + socio-economic + crime + school composition
// (pikuah/sector) from data.gov.il. Bundled into the Lambda so the neighborhood
// scorer reads safety + school composition from a local table (fast, no runtime
// CKAN calls, no name-format fragility, never times out to "undefined").
//
//   node scripts/build-locality-features.mjs
//
// mosdot has no locality code, so its rows are grouped by fuzzy name→cbs_id via
// muni_ids (resolveLocality). Everything else joins by the CBS code directly.

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { resolveLocality } from '../aws/lambda/router/lib/muni.mjs';
import { normPikuah, normSector } from '../aws/lambda/router/lib/neighborhood.mjs';

const RES = {
  mosdot: '5548fd63-5868-4053-ad81-98caddc5e232',
  pop: '38207cf8-afe2-48ed-a3b0-c8f70c796015',
  socio: '7c860e04-9f8d-41c2-9f24-6249958d2081',
  crime: '5fc13c50-b6f3-4712-b831-a75e0f91a17e',
};
const OUT = join(dirname(fileURLToPath(import.meta.url)),
  '..', 'aws', 'lambda', 'router', 'lib', 'locality_features.generated.json');

async function j(url) {
  const r = await fetch(url);
  const t = await r.text();
  try { return JSON.parse(t); } catch { return null; }
}
async function page(id, limit = 32000) {
  const out = [];
  for (let offset = 0; offset < 300000; offset += limit) {
    const d = await j(`https://data.gov.il/api/3/action/datastore_search?resource_id=${id}&limit=${limit}&offset=${offset}`);
    const recs = d?.result?.records || [];
    out.push(...recs);
    if (recs.length < limit) break;
  }
  return out;
}
async function count(id, filters) {
  const d = await j(`https://data.gov.il/api/3/action/datastore_search?resource_id=${id}&filters=${encodeURIComponent(JSON.stringify(filters))}&limit=0`);
  return Number.isFinite(d?.result?.total) ? d.result.total : null;
}
const numLoose = (v) => { const n = Number(String(v).replace(/[, ]/g, '')); return Number.isFinite(n) ? n : null; };

const feat = {};
const ensure = (cbs) => (feat[cbs] ||= { pop: null, eshkol: null, crime: null, pikuah: new Set(), sectors: new Set() });

async function main() {
  console.log('population…');
  for (const r of await page(RES.pop)) {
    const cbs = numLoose(r.LocalityCode); const pop = numLoose(r.Total_Population);
    if (cbs && pop) ensure(cbs).pop = pop;
  }
  console.log('socio…');
  for (const r of await page(RES.socio)) {
    const cbs = numLoose(r['LOCALITY SYMBOL']); const e = numLoose(r['ESHKOL 2019']);
    if (cbs && e) ensure(cbs).eshkol = e;
  }
  console.log('mosdot (school composition)…');
  const mosdot = await page(RES.mosdot);
  for (const r of mosdot) {
    const m = resolveLocality(r['שם רשות'] || r['שם ישוב']);
    if (!m) continue;
    const f = ensure(Number(m.cbs_id));
    const p = normPikuah(r['פיקוח']); if (p) f.pikuah.add(p);
    const s = normSector(r['מגזר']); if (s) f.sectors.add(s);
  }
  console.log(`mosdot rows=${mosdot.length}; crime counts for ${Object.keys(feat).length} localities…`);
  const cbsList = Object.keys(feat);
  for (let i = 0; i < cbsList.length; i += 8) {
    await Promise.all(cbsList.slice(i, i + 8).map(async (cbs) => {
      feat[cbs].crime = await count(RES.crime, { YeshuvKod: Number(cbs) });
    }));
  }

  const out = {};
  for (const cbs in feat) {
    const f = feat[cbs];
    out[cbs] = {
      pop: f.pop, eshkol: f.eshkol, crime: f.crime,
      pikuah: [...f.pikuah], sectors: [...f.sectors],
    };
  }
  writeFileSync(OUT, JSON.stringify(out));
  console.log(`Wrote ${Object.keys(out).length} localities → ${OUT}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
