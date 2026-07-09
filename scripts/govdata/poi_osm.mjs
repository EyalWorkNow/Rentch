#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// OSM Overpass → assets/data/govdata/{clinics.json, supermarkets.json}
//
// Named point POIs for the "nearby places" lists on the property detail screen:
//   • clinics.json     — health clinics / קופות חולים, each tagged with its HMO
//                        (כללית / מכבי / לאומית / מאוחדת) when identifiable.
//                        [ { "n": name, "lat", "lon", "h": hmo } ]
//   • supermarkets.json — grocery stores. [ { "n": name, "lat", "lon" } ]
//
// Source: OpenStreetMap via Overpass (POST + User-Agent; the GET form 406s).
// Same bundled-asset shape as parks.json, loaded by IsraelGeoIndex.
// ════════════════════════════════════════════════════════════════════════════

import { writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '../../assets/data/govdata');
const OVERPASS = 'https://overpass-api.de/api/interpreter';
const BBOX = '29.4,34.2,33.4,35.9'; // all of Israel

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function overpass(query, { tries = 4 } = {}) {
  for (let i = 1; i <= tries; i++) {
    try {
      const res = await fetch(OVERPASS, {
        method: 'POST',
        headers: { 'User-Agent': 'RentlyETL/1.0', 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'data=' + encodeURIComponent(query),
      });
      if (res.ok) return await res.json();
      const body = (await res.text()).slice(0, 80);
      console.log(`  overpass ${res.status} (try ${i}) — ${body}`);
    } catch (e) {
      console.log(`  overpass error (try ${i}): ${e.message}`);
    }
    if (i < tries) await sleep(15000 * i); // back off; endpoint is load-based
  }
  throw new Error('Overpass failed after retries');
}

const validLat = (x) => isFinite(x) && x > 29 && x < 34;
const validLon = (x) => isFinite(x) && x > 33 && x < 36;
const r5 = (x) => Math.round(x * 1e5) / 1e5;

// Detect the HMO (health fund) from an OSM element's name/operator/brand.
function hmoOf(t) {
  const s = `${t.name || ''} ${t.operator || ''} ${t.brand || ''}`;
  if (/כללית|clalit/i.test(s)) return 'כללית';
  if (/מכבי|maccabi|makabi/i.test(s)) return 'מכבי';
  if (/לאומית|leumit/i.test(s)) return 'לאומית';
  if (/מאוחדת|meuhedet/i.test(s)) return 'מאוחדת';
  return '';
}

function coordOf(e) {
  const lat = e.lat ?? e.center?.lat;
  const lon = e.lon ?? e.center?.lon;
  return [lat, lon];
}

async function main() {
  console.log('▶ OSM → clinics.json + supermarkets.json');
  mkdirSync(OUT_DIR, { recursive: true });

  // ── clinics (HMO health funds + general clinics) ──────────────────────────
  const clinicQ = `[out:json][timeout:180];(
    node["amenity"="clinic"](${BBOX});
    node["healthcare"="clinic"](${BBOX});
  );out center;`;
  const clinicRaw = await overpass(clinicQ);
  const clinics = [];
  const cseen = new Set();
  let withHmo = 0;
  for (const e of clinicRaw.elements || []) {
    const t = e.tags || {};
    const name = (t.name || '').trim();
    if (!name) continue;
    const [lat, lon] = coordOf(e);
    if (!validLat(lat) || !validLon(lon)) continue;
    const key = `${name}_${r5(lat)}_${r5(lon)}`;
    if (cseen.has(key)) continue;
    cseen.add(key);
    const h = hmoOf(t);
    if (h) withHmo++;
    clinics.push({ n: name, lat: r5(lat), lon: r5(lon), h });
  }
  writeFileSync(join(OUT_DIR, 'clinics.json'), JSON.stringify(clinics));

  // ── supermarkets ──────────────────────────────────────────────────────────
  const supQ = `[out:json][timeout:180];(
    node["shop"="supermarket"](${BBOX});
  );out center;`;
  const supRaw = await overpass(supQ);
  const sup = [];
  const sseen = new Set();
  for (const e of supRaw.elements || []) {
    const t = e.tags || {};
    const name = (t.name || t.brand || '').trim();
    if (!name) continue;
    const [lat, lon] = coordOf(e);
    if (!validLat(lat) || !validLon(lon)) continue;
    const key = `${name}_${r5(lat)}_${r5(lon)}`;
    if (sseen.has(key)) continue;
    sseen.add(key);
    sup.push({ n: name, lat: r5(lat), lon: r5(lon) });
  }
  writeFileSync(join(OUT_DIR, 'supermarkets.json'), JSON.stringify(sup));

  const byHmo = {};
  for (const c of clinics) byHmo[c.h || '—'] = (byHmo[c.h || '—'] || 0) + 1;
  console.log('── done ──');
  console.table({
    clinics: clinics.length, clinicsWithHmo: withHmo,
    supermarkets: sup.length,
    clinicsBytes: statSync(join(OUT_DIR, 'clinics.json')).size,
    supBytes: statSync(join(OUT_DIR, 'supermarkets.json')).size,
  });
  console.log('clinics by HMO:', JSON.stringify(byHmo));
  console.log('clinic samples:', JSON.stringify(clinics.slice(0, 3)));
  console.log('super samples:', JSON.stringify(sup.slice(0, 3)));
}

main().catch((e) => { console.error('\n✗ poi_osm failed:', e); process.exit(1); });
