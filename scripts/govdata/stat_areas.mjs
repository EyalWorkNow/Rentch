#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// CBS statistical areas (אזור סטטיסטי) → stat_areas.json
//
// The single biggest ranking-accuracy upgrade: per-BLOCK (~3,000 residents)
// socioeconomic cluster + age split instead of a whole-city average. gov_data.dart
// runs a point-in-polygon lookup and OVERRIDES the city-level
// neighbourhood/young_area/senior_area/family features for any flat inside a
// known area.
//
// SOURCE — the official CBS GIS layer "מדד חברתי כלכלי לפי אזור סטטיסטי 2021"
// (org ISRAEL_CBS_GIS). It already joins, per statistical-area polygon:
//   • eshkol_mad          — socioeconomic cluster 1..10 (the SES index)
//   • Pop_Total + age_0_4…age_85_up — the full age histogram
// served as GeoJSON in WGS84 (f=geojson), so NO shapefile / 7z / ITM reprojection.
// One layer, one fetch → boundaries + SES + age together.
//
// Output → assets/data/govdata/stat_areas.json
//   { "cell":0.02, "areas":[ { ses, young, child, senior, poly:[[lat,lon],…] } ] }
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../assets/data/govdata/stat_areas.json');

const LAYER =
  'https://services2.arcgis.com/xMRYm7cNgdR5RN6F/arcgis/rest/services/SOEC_Stat11_2021/FeatureServer/27';
const AGE = [
  'age_0_4', 'age_5_9', 'age_10_14', 'age_15_19', 'age_20_24', 'age_25_29',
  'age_30_34', 'age_35_39', 'age_40_44', 'age_45_49', 'age_50_54', 'age_55_59',
  'age_60_64', 'age_65_69', 'age_70_74', 'age_75_79', 'age_80_84', 'age_85_up',
];
const OUT_FIELDS =
    ['eshkol_mad', 'Pop_Total', 'Shem_Yishuv', 'YISHUV_STA', ...AGE].join(',');
const PAGE = 2000; // = the layer's maxRecordCount

const num = (v) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

// Outer ring of a Polygon / first ring of a MultiPolygon → [[lat,lon],…], rounded
// to 5 dp and radial-distance–simplified: drop any vertex within ~20 m of the last
// KEPT one (first + last always kept). An apartment coordinate is never precise to
// <20 m, so this doesn't change which area a point falls in — but it roughly
// halves the asset. 0.00018° ≈ 20 m at Israel's latitude.
const MIN_STEP = 0.00018;
function ringToLatLon(geometry) {
  if (!geometry) return null;
  const ring =
    geometry.type === 'Polygon'
      ? geometry.coordinates?.[0]
      : geometry.type === 'MultiPolygon'
        ? geometry.coordinates?.[0]?.[0]
        : null;
  if (!Array.isArray(ring) || ring.length < 4) return null;
  const out = [];
  let klat = null, klon = null;
  for (let i = 0; i < ring.length; i++) {
    const lat = Math.round(ring[i][1] * 1e5) / 1e5;
    const lon = Math.round(ring[i][0] * 1e5) / 1e5;
    const last = i === ring.length - 1;
    if (klat != null && !last &&
        Math.abs(lat - klat) < MIN_STEP && Math.abs(lon - klon) < MIN_STEP) {
      continue;
    }
    out.push([lat, lon]);
    klat = lat;
    klon = lon;
  }
  return out.length >= 3 ? out : null;
}

async function fetchPage(offset) {
  const url =
    `${LAYER}/query?where=Pop_Total%3E0&outFields=${OUT_FIELDS}` +
    `&resultOffset=${offset}&resultRecordCount=${PAGE}` +
    `&geometryPrecision=5&f=geojson`;
  const res = await fetch(url, { headers: { 'User-Agent': 'rently-etl/1.0' } });
  if (!res.ok) throw new Error(`ArcGIS ${res.status} @offset ${offset}`);
  const j = await res.json();
  if (j.error) throw new Error(`ArcGIS: ${JSON.stringify(j.error)}`);
  return j.features ?? [];
}

async function main() {
  const areas = [];
  for (let offset = 0; ; offset += PAGE) {
    const feats = await fetchPage(offset);
    for (const f of feats) {
      const poly = ringToLatLon(f.geometry);
      const p = f.properties ?? {};
      const pop = num(p.Pop_Total);
      if (!poly || pop <= 0) continue;
      const sum = (a, b) => a.slice(b[0], b[1]).reduce((s, k) => s + num(p[k]), 0);
      const child = sum(AGE, [0, 4]); // 0-19
      const workingAge = sum(AGE, [4, 13]); // 20-64
      const senior = sum(AGE, [13, 18]); // 65+
      areas.push({
        ses: num(p.eshkol_mad), // cluster 1..10 (0 = unknown → loader ignores)
        young: Math.round((workingAge / pop) * 1000) / 1000,
        child: Math.round((child / pop) * 1000) / 1000,
        senior: Math.round((senior / pop) * 1000) / 1000,
        city: (p.Shem_Yishuv ?? '').trim(), // settlement name — for city ranking
        id: num(p.YISHUV_STA), // YISHUV*10000 + stat-area
        poly,
      });
    }
    process.stdout.write(`\r  fetched ${areas.length} areas`);
    if (feats.length < PAGE) break;
  }
  process.stdout.write('\n');

  const out = { cell: 0.02, areas };
  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(out));
  const mb = (JSON.stringify(out).length / 1e6).toFixed(1);
  console.log(`✓ wrote ${OUT}\n  ${areas.length} statistical areas · ${mb} MB`);
}

main().catch((e) => {
  console.error('stat_areas ingest failed:', e.message);
  process.exit(1);
});
