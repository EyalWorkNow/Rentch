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
// Two CBS inputs, joined on the statistical-area id (YISHUV_STAT11 / stat_area):
//   1) BOUNDARIES  — the אזורים סטטיסטיים polygons (GeoJSON on data.gov.il / CBS
//      GIS). Geometry is often in ITM (EPSG:2039) and must be projected to WGS84
//      lon/lat; if the layer already serves EPSG:4326, use it directly.
//   2) SES INDEX   — "המדד החברתי-כלכלי לפי אזור סטטיסטי" (cluster 1..10) + the
//      age-group population shares per area.
//
// Output → assets/data/govdata/stat_areas.json
//   { "cell":0.02, "areas":[ { ses, young, child, senior, poly:[[lat,lon],…] } ] }
//
// NOTE: confirm the two resource ids below against data.gov.il before running —
// CBS republishes them periodically. Left as constants so this is a one-line fix.
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../assets/data/govdata/stat_areas.json');
const CKAN = 'https://data.gov.il/api/3/action/datastore_search';

// TODO(confirm): resource ids for the two CBS datasets.
const BOUNDARIES_RESOURCE = 'REPLACE_WITH_STAT_AREA_BOUNDARIES_RESOURCE_ID';
const SES_RESOURCE = 'REPLACE_WITH_STAT_AREA_SES_RESOURCE_ID';

async function fetchAll(resourceId, label) {
  const out = [];
  for (let offset = 0; ; offset += 10000) {
    const url = `${CKAN}?resource_id=${resourceId}&limit=10000&offset=${offset}&records_format=objects`;
    const res = await fetch(url, { headers: { accept: 'application/json' } });
    if (!res.ok) throw new Error(`CKAN ${res.status} for ${label}`);
    const recs = (await res.json()).result?.records ?? [];
    out.push(...recs);
    process.stdout.write(`\r  ${label}: ${out.length} rows`);
    if (recs.length < 10000) break;
  }
  process.stdout.write('\n');
  return out;
}

// A GeoJSON ring in [lon,lat] order → our [[lat,lon],…]. Handles Polygon and the
// outer ring of a MultiPolygon.
function ringToLatLon(geometry) {
  if (!geometry) return null;
  const ring =
    geometry.type === 'Polygon'
      ? geometry.coordinates?.[0]
      : geometry.type === 'MultiPolygon'
        ? geometry.coordinates?.[0]?.[0]
        : null;
  if (!Array.isArray(ring) || ring.length < 3) return null;
  return ring.map(([lon, lat]) => [lat, lon]);
}

const num = (v) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

async function main() {
  const boundaries = await fetchAll(BOUNDARIES_RESOURCE, 'boundaries');
  const sesRows = await fetchAll(SES_RESOURCE, 'ses');

  // index SES by statistical-area id
  const sesById = new Map();
  for (const r of sesRows) {
    const id = String(r.stat_area ?? r.YISHUV_STAT11 ?? r.id ?? '').trim();
    if (id) sesById.set(id, r);
  }

  const areas = [];
  for (const b of boundaries) {
    const id = String(b.stat_area ?? b.YISHUV_STAT11 ?? b.id ?? '').trim();
    const geom =
      typeof b.geometry === 'string' ? JSON.parse(b.geometry) : b.geometry;
    const poly = ringToLatLon(geom);
    const ses = sesById.get(id);
    if (!poly || !ses) continue;
    areas.push({
      ses: num(ses.cluster ?? ses.index_cluster) ?? 0,
      young: num(ses.share_20_64 ?? ses.young) ?? 0.5,
      child: num(ses.share_0_19 ?? ses.child) ?? 0.5,
      senior: num(ses.share_65p ?? ses.senior) ?? 0.5,
      poly,
    });
  }

  const out = { cell: 0.02, areas };
  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(out));
  console.log(`✓ wrote ${OUT}\n  ${areas.length} statistical areas`);
}

main().catch((e) => {
  console.error('stat_areas ingest failed:', e.message);
  process.exit(1);
});
