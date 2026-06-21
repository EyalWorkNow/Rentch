#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// data.gov.il ingestion pipeline (Part A)
//
// Fetches real open datasets and compiles them into compact, app-bundled assets:
//   • transit stops  (33,937 pts) → per-locality centroids + density grid + rail
//   • localities      registry    → code → name / district
//   • socioeconomic   seed (CBS clusters) merged in
//   • market          seed (₪/m²) for hedonic priors (nadlan overlay optional)
//
// Output → assets/data/govdata/{localities,transit_grid,rail_stations,
//                                market_seed,meta}.json
//
// Usage:  node scripts/govdata/ingest.mjs
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');

const CKAN = 'https://data.gov.il/api/3/action/datastore_search';
const STOPS_RESOURCE = 'e873e6a2-66c1-494f-a677-f5e77348edb0';
const LOCALITIES_RESOURCE = '5c78e9fa-c2e2-4771-93ff-7f400a12f7ba';

const GRID_DEG = 0.02; // ~2 km transit-density cells
const RAIL_DEDUPE_DEG = 0.004; // ~400 m rail-station clustering

// ── CKAN paginated fetch ──────────────────────────────────────────────────────
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

const round = (x, dp) => {
  const f = 10 ** dp;
  return Math.round(x * f) / f;
};
const cellKey = (lat, lon) =>
  `${Math.round(lat / GRID_DEG)}_${Math.round(lon / GRID_DEG)}`;
const isRail = (typeName = '') =>
  typeName.includes('רכבת') || typeName.includes('רק"ל') || typeName.includes('רכבל');

// ── curated seeds (overridable by authoritative fetches) ─────────────────────
// CBS socioeconomic cluster (1 lowest .. 10 highest) for major localities.
const SES_SEED = {
  'תל אביב -יפו': 8, 'תל אביב יפו': 8, 'תל אביב': 8, 'ירושלים': 4, 'חיפה': 7,
  'ראשון לציון': 7, 'פתח תקווה': 7, 'אשדוד': 5, 'נתניה': 6, 'באר שבע': 5,
  'בני ברק': 2, 'חולון': 6, 'רמת גן': 8, 'אשקלון': 5, 'רחובות': 7, 'בת ים': 5,
  'הרצליה': 9, 'כפר סבא': 8, 'חדרה': 5, 'מודיעין-מכבים-רעות': 8, 'רעננה': 9,
  'רמת השרון': 10, 'גבעתיים': 9, 'הוד השרון': 9, 'קריית אתא': 5, 'נהריה': 5,
  'לוד': 3, 'רמלה': 4, 'עפולה': 4, 'נצרת': 3, 'אילת': 6, 'טבריה': 4,
  'יבנה': 6, 'דימונה': 4, 'אור יהודה': 5, 'צפת': 3, 'קריית גת': 4,
  'ראש העין': 7, 'גבעת שמואל': 9, 'יהוד-מונוסון': 7, 'נס ציונה': 8,
  'קריית אונו': 9, 'שוהם': 10, 'מבשרת ציון': 9, 'אריאל': 5, 'כרמיאל': 5,
  'נוף הגליל': 5, 'קריית מוצקין': 6, 'קריית ביאליק': 6, 'קריית ים': 4,
  'מעלה אדומים': 6, 'בית שמש': 3, 'קריית מלאכי': 4, 'שדרות': 4, 'נתיבות': 3,
  'אום אל-פחם': 2, 'טייבה': 3, 'רהט': 1, 'טמרה': 3, 'סח\'נין': 3,
};

// Seed ₪/m² priors (monthly rent & sale) for the hedonic anchor. Rough but
// realistic; `fetch_nadlan.mjs` overlays authoritative transaction medians.
const MARKET_SEED = {
  'תל אביב -יפו': { rentPerSqm: 88, salePerSqm: 56000 },
  'הרצליה': { rentPerSqm: 72, salePerSqm: 46000 },
  'רמת גן': { rentPerSqm: 66, salePerSqm: 38000 },
  'גבעתיים': { rentPerSqm: 68, salePerSqm: 42000 },
  'רמת השרון': { rentPerSqm: 70, salePerSqm: 47000 },
  'ירושלים': { rentPerSqm: 56, salePerSqm: 38000 },
  'חיפה': { rentPerSqm: 42, salePerSqm: 20000 },
  'ראשון לציון': { rentPerSqm: 52, salePerSqm: 30000 },
  'פתח תקווה': { rentPerSqm: 54, salePerSqm: 29000 },
  'אשדוד': { rentPerSqm: 44, salePerSqm: 24000 },
  'נתניה': { rentPerSqm: 50, salePerSqm: 30000 },
  'באר שבע': { rentPerSqm: 33, salePerSqm: 13000 },
  'חולון': { rentPerSqm: 53, salePerSqm: 30000 },
  'בת ים': { rentPerSqm: 53, salePerSqm: 31000 },
  'רעננה': { rentPerSqm: 62, salePerSqm: 39000 },
  'כפר סבא': { rentPerSqm: 56, salePerSqm: 34000 },
  'מודיעין-מכבים-רעות': { rentPerSqm: 50, salePerSqm: 30000 },
  'רחובות': { rentPerSqm: 50, salePerSqm: 28000 },
  'אשקלון': { rentPerSqm: 40, salePerSqm: 22000 },
  'חדרה': { rentPerSqm: 38, salePerSqm: 21000 },
  'נס ציונה': { rentPerSqm: 56, salePerSqm: 34000 },
  'קריית אונו': { rentPerSqm: 60, salePerSqm: 38000 },
  'גבעת שמואל': { rentPerSqm: 58, salePerSqm: 36000 },
  'ראש העין': { rentPerSqm: 52, salePerSqm: 31000 },
  'אילת': { rentPerSqm: 46, salePerSqm: 27000 },
  'טבריה': { rentPerSqm: 34, salePerSqm: 15000 },
  'בית שמש': { rentPerSqm: 42, salePerSqm: 24000 },
};

const normName = (s = '') =>
  s.replace(/["'״׳]/g, '').replace(/\s*-\s*/g, '-').replace(/\s+/g, ' ').trim();

const SES_NORM = {};
for (const [k, v] of Object.entries(SES_SEED)) SES_NORM[normName(k)] = v;

function sesFor(name) {
  if (!name) return 0;
  const n = normName(name);
  if (SES_NORM[n] != null) return SES_NORM[n];
  // try the base name before a hyphen (e.g. "תל אביב-יפו" → "תל אביב")
  const base = n.split('-')[0].trim();
  return SES_NORM[base] ?? 0;
}

// ── main ──────────────────────────────────────────────────────────────────────
async function main() {
  console.log('▶ data.gov.il ingestion');
  mkdirSync(OUT_DIR, { recursive: true });

  // 1. transit stops
  console.log('• fetching public-transport stops …');
  const stops = await fetchAll(STOPS_RESOURCE, { label: 'stops' });

  // aggregate
  const byCity = new Map(); // CityCode → {name, sumLat, sumLon, n, rail, bus}
  const grid = new Map(); // cellKey → [count, railCount]
  const railPts = []; // [{lat,lon,name}]
  const typeNames = new Set();

  for (const s of stops) {
    const lat = Number(s.Lat);
    const lon = Number(s.Long);
    if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) < 0.1) continue;
    const rail = isRail(s.StationTypeName);
    typeNames.add(s.StationTypeName);

    const code = Number(s.CityCode);
    const agg = byCity.get(code) ?? {
      name: s.CityName, sumLat: 0, sumLon: 0, n: 0, rail: 0, bus: 0,
    };
    agg.sumLat += lat; agg.sumLon += lon; agg.n += 1;
    if (rail) agg.rail += 1; else agg.bus += 1;
    byCity.set(code, agg);

    const k = cellKey(lat, lon);
    const cell = grid.get(k) ?? [0, 0];
    cell[0] += 1; if (rail) cell[1] += 1;
    grid.set(k, cell);

    if (rail) railPts.push({ lat, lon, name: s.CityName });
  }

  // dedupe rail points into stations (cluster by ~400m)
  const railSeen = new Set();
  const railStations = [];
  for (const p of railPts) {
    const rk = `${Math.round(p.lat / RAIL_DEDUPE_DEG)}_${Math.round(p.lon / RAIL_DEDUPE_DEG)}`;
    if (railSeen.has(rk)) continue;
    railSeen.add(rk);
    railStations.push([round(p.lat, 5), round(p.lon, 5), p.name]);
  }

  // 2. localities registry
  console.log('• fetching localities registry …');
  const localities = await fetchAll(LOCALITIES_RESOURCE, { label: 'localities' });
  const regByCode = new Map();
  for (const r of localities) {
    const code = Number(r['סמל_ישוב']);
    regByCode.set(code, {
      name: (r['שם_ישוב'] ?? '').trim(),
      nameEn: (r['שם_ישוב_לועזי'] ?? '').trim(),
      district: (r['שם_נפה'] ?? '').trim(),
    });
  }

  // 3. merge → locality records with derived centroids
  const localityRecords = [];
  for (const [code, agg] of byCity) {
    if (agg.n < 1) continue;
    const reg = regByCode.get(code);
    const name = (reg?.name && reg.name.length > 0) ? reg.name : agg.name;
    if (!name) continue;
    localityRecords.push({
      code,
      name,
      nameEn: reg?.nameEn ?? '',
      district: reg?.district ?? '',
      lat: round(agg.sumLat / agg.n, 5),
      lon: round(agg.sumLon / agg.n, 5),
      stops: agg.n,
      rail: agg.rail,
      bus: agg.bus,
      ses: sesFor(name),
    });
  }
  localityRecords.sort((a, b) => b.stops - a.stops);

  // 4. grid object
  const gridObj = {};
  for (const [k, v] of grid) gridObj[k] = v;

  // ── write assets ────────────────────────────────────────────────────────────
  const meta = {
    version: 1,
    generatedAt: new Date().toISOString(),
    sources: {
      stops: STOPS_RESOURCE,
      localities: LOCALITIES_RESOURCE,
    },
    counts: {
      stops: stops.length,
      localities: localityRecords.length,
      railStations: railStations.length,
      gridCells: Object.keys(gridObj).length,
    },
    stationTypes: [...typeNames].filter(Boolean),
  };

  const write = (file, obj) =>
    writeFileSync(join(OUT_DIR, file), JSON.stringify(obj));

  write('localities.json', localityRecords);
  write('transit_grid.json', { cell: GRID_DEG, cells: gridObj });
  write('rail_stations.json', railStations);
  write('market_seed.json', MARKET_SEED);
  write('meta.json', meta);

  console.log('\n✓ assets written to assets/data/govdata/');
  console.table({
    stops: stops.length,
    localities: localityRecords.length,
    railStations: railStations.length,
    gridCells: meta.counts.gridCells,
  });
  console.log('station types seen:', meta.stationTypes.slice(0, 12));
}

main().catch((e) => {
  console.error('\n✗ ingestion failed:', e.message);
  process.exit(1);
});
