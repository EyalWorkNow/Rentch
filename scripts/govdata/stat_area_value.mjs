#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// CBS estimated apartment value per statistical area (2013) → stat_area_value.json
//
// Source: ISRAEL_CBS_GIS "שווי דירת מגורים לפי אזורים סטטיסטיים 2013"
// (AppValueStat11_2013). Field `est_value_` = ₪/m², keyed by YISHUV_STA — the
// SAME id as stat_areas.json. Used by Area Intelligence for a RELATIVE price tier
// (the 2013 vintage is stale in absolute terms but relative positioning is fairly
// stable) + a labelled rough yield estimate.
//
// Output → assets/data/govdata/stat_area_value.json
//   { "<YISHUV_STA>": <est_value_per_sqm_2013>, … }
// ════════════════════════════════════════════════════════════════════════════
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../assets/data/govdata/stat_area_value.json');
const LAYER =
  'https://services2.arcgis.com/xMRYm7cNgdR5RN6F/arcgis/rest/services/AppValueStat11_2013/FeatureServer/0';
const PAGE = 1000;

async function fetchPage(offset) {
  const url =
    `${LAYER}/query?where=est_value_%3E0&outFields=YISHUV_STA,est_value_,reliabilit` +
    `&returnGeometry=false&resultOffset=${offset}&resultRecordCount=${PAGE}&f=json`;
  const res = await fetch(url, { headers: { 'User-Agent': 'rently-etl/1.0' } });
  if (!res.ok) throw new Error(`ArcGIS ${res.status} @${offset}`);
  const j = await res.json();
  if (j.error) throw new Error(JSON.stringify(j.error));
  return j.features ?? [];
}

async function main() {
  const out = {};
  for (let offset = 0; ; offset += PAGE) {
    const feats = await fetchPage(offset);
    for (const f of feats) {
      const a = f.attributes ?? {};
      const id = Number(a.YISHUV_STA);
      const v = Number(a.est_value_);
      if (Number.isFinite(id) && Number.isFinite(v) && v > 0) {
        out[id] = Math.round(v); // ₪/m² (2013)
      }
    }
    process.stdout.write(`\r  ${Object.keys(out).length} areas`);
    if (feats.length < PAGE) break;
  }
  process.stdout.write('\n');
  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(out));
  const vals = Object.values(out).sort((a, b) => a - b);
  const med = vals[Math.floor(vals.length / 2)];
  console.log(`✓ wrote ${OUT}\n  ${vals.length} areas · median ₪${med}/m² (2013)`);
}

main().catch((e) => {
  console.error('stat_area_value ingest failed:', e.message);
  process.exit(1);
});
