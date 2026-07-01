// govmap.mjs — Israeli address → {lat,lng,gush,helka} via GovMap (free, no key).
//
// ponytail: GovMap is an unauthenticated *internal* web API. It has no SLA, no
// docs, and the host/path can change without notice. Treat every call as
// best-effort: hard timeout, swallow all errors, return null. NEVER let a
// GovMap outage block listing creation — the caller must degrade gracefully.
// CACHING: this is a pure function of `addressHe`. Cache results keyed by the
// normalised address string FOREVER (addresses don't move). A geocode result
// is also a pure function of gush/helka, so the {gush,helka} pair is a stable
// secondary cache key. Recommended: DynamoDB item geo#<address> with no TTL.
//
// Endpoints used (observed live on www.govmap.gov.il):
//   1) search-service autocomplete  → POST resolves free Hebrew text to a result
//      that carries a shape WKT "POINT(x y)" in EPSG:3857 Web Mercator.
//   2) entitiesByPoint (parcel layer)→ BLOCKED: returns 400 "access denied"
//      (needs a session token we don't have). gush/helka left null best-effort.
// ponytail: the autocomplete `shape` coords are EPSG:3857 Web Mercator, NOT ITM.
// We invert Web-Mercator to WGS84 directly (webMercatorToWgs84 below). The old
// ITM reprojection + easting-magnitude gate rejected 3857 coords — the geocode
// path now bypasses it. itmToWgs84() is retained only for reference/other paths.

const TIMEOUT_MS = 7000;
const UA = 'RentlyBot/1.0 (+https://rently.co.il; real-estate enrichment)';

// ---------------------------------------------------------------------------
// EPSG:2039 (Israeli TM Grid / ITM) → WGS84 (EPSG:4326) inverse Transverse
// Mercator. Datum is Israel 1993 (GRS80 ellipsoid); the tiny Israel↔WGS84
// datum shift (<~0.5 m) is ignored — irrelevant for "which neighbourhood".
//
// ITM grid definition:
//   ellipsoid GRS80:  a = 6378137,  f = 1/298.257222101
//   lat0 = 31°44'02.749"N, lon0 = 35°12'16.261"E  (central meridian)
//   k0   = 1.0000067
//   FE   = 219529.584 m (false easting),  FN = 626907.39 m (false northing)
// Standard inverse TM series (Snyder, USGS Prof. Paper 1395).
function itmToWgs84(E, N) {
  const a = 6378137.0;
  const f = 1 / 298.257222101;
  const e2 = f * (2 - f);              // first eccentricity squared
  const ep2 = e2 / (1 - e2);           // second eccentricity squared
  const k0 = 1.0000067;
  const lat0 = (31 + 44 / 60 + 2.749 / 3600) * Math.PI / 180;
  const lon0 = (35 + 12 / 60 + 16.261 / 3600) * Math.PI / 180;
  const FE = 219529.584;
  const FN = 626907.39;

  const x = E - FE;
  const y = N - FN;

  // Meridional arc length from equator to lat0 (M0).
  const M0 = meridionalArc(lat0, a, e2);
  const M = M0 + y / k0;

  // Footpoint latitude via series in e1.
  const e1 = (1 - Math.sqrt(1 - e2)) / (1 + Math.sqrt(1 - e2));
  const mu = M / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256));
  const phi1 = mu
    + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * Math.sin(2 * mu)
    + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * Math.sin(4 * mu)
    + (151 * e1 ** 3 / 96) * Math.sin(6 * mu)
    + (1097 * e1 ** 4 / 512) * Math.sin(8 * mu);

  const sin1 = Math.sin(phi1);
  const cos1 = Math.cos(phi1);
  const tan1 = Math.tan(phi1);

  const C1 = ep2 * cos1 * cos1;
  const T1 = tan1 * tan1;
  const N1 = a / Math.sqrt(1 - e2 * sin1 * sin1);                 // prime vertical radius
  const R1 = a * (1 - e2) / Math.pow(1 - e2 * sin1 * sin1, 1.5);  // meridian radius
  const D = x / (N1 * k0);

  const lat = phi1 - (N1 * tan1 / R1) * (
    D * D / 2
    - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * ep2) * D ** 4 / 24
    + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * ep2 - 3 * C1 * C1) * D ** 6 / 720
  );

  const lon = lon0 + (
    D
    - (1 + 2 * T1 + C1) * D ** 3 / 6
    + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * ep2 + 24 * T1 * T1) * D ** 5 / 120
  ) / cos1;

  return { lat: lat * 180 / Math.PI, lng: lon * 180 / Math.PI };
}

// EPSG:3857 (Web Mercator) → WGS84 (EPSG:4326). GovMap autocomplete `shape`
// WKT "POINT(x y)" carries x/y in metres on the 3857 sphere.
function webMercatorToWgs84(x, y) {
  const lon = (x / 20037508.34) * 180;
  let lat = (y / 20037508.34) * 180;
  lat = (180 / Math.PI) * (2 * Math.atan(Math.exp((lat * Math.PI) / 180)) - Math.PI / 2);
  return { lat, lng: lon };
}

// Parse a WKT "POINT(x y)" string → {x,y} (numbers). null if not parseable.
function parseWktPoint(shape) {
  if (typeof shape !== 'string') return null;
  const m = shape.match(/POINT\s*\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s*\)/i);
  if (!m) return null;
  const x = Number(m[1]), y = Number(m[2]);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  return { x, y };
}

function meridionalArc(phi, a, e2) {
  return a * (
    (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256) * phi
    - (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * e2 * e2 * e2 / 1024) * Math.sin(2 * phi)
    + (15 * e2 * e2 / 256 + 45 * e2 * e2 * e2 / 1024) * Math.sin(4 * phi)
    - (35 * e2 * e2 * e2 / 3072) * Math.sin(6 * phi)
  );
}

// fetch with an AbortController timeout; returns null on any failure.
async function fetchJson(url, opts = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      ...opts,
      signal: ctrl.signal,
      headers: { 'User-Agent': UA, 'Accept': 'application/json', ...(opts.headers || {}) },
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}

// Pull an ITM X/Y point out of whatever shape GovMap returns (defensive: the
// autocomplete payload shape varies by result type).
function extractItmPoint(obj) {
  if (!obj || typeof obj !== 'object') return null;
  // Common shapes seen: {X,Y}, {x,y}, {ResultLat,ResultLng} already-projected,
  // or a "Shape"/"geometry" with x/y. We only accept ITM-magnitude numbers
  // (Israel ITM easting ~120k–280k, northing ~380k–800k).
  const cand = [
    [obj.X, obj.Y], [obj.x, obj.y],
    [obj?.Shape?.x, obj?.Shape?.y],
    [obj?.geometry?.x, obj?.geometry?.y],
    [obj?.data?.X, obj?.data?.Y],
  ];
  for (const [X, Y] of cand) {
    const nx = Number(X), ny = Number(Y);
    if (Number.isFinite(nx) && Number.isFinite(ny) &&
        nx > 100000 && nx < 300000 && ny > 350000 && ny < 850000) {
      return { X: nx, Y: ny };
    }
  }
  return null;
}

// Parse "גוש 6638 חלקה 25" style labels OR explicit fields from entitiesByPoint.
function extractGushHelka(obj) {
  if (!obj || typeof obj !== 'object') return { gush: null, helka: null };
  // explicit fields (various casings GovMap parcel layer has used)
  const g = obj.GUSH_NUM ?? obj.gush ?? obj.Gush ?? obj.GUSH ?? null;
  const h = obj.PARCEL ?? obj.helka ?? obj.Helka ?? obj.CHELKA ?? obj.PARCEL_NUM ?? null;
  if (g != null || h != null) {
    return { gush: g != null ? Number(g) : null, helka: h != null ? Number(h) : null };
  }
  // fallback: scrape a Hebrew label like "גוש 6638 חלקה 25"
  const text = JSON.stringify(obj);
  const gm = text.match(/גוש\D{0,4}(\d{2,6})/);
  const hm = text.match(/חלקה\D{0,4}(\d{1,5})/);
  return {
    gush: gm ? Number(gm[1]) : null,
    helka: hm ? Number(hm[1]) : null,
  };
}

/**
 * Geocode a free-text Hebrew address to coordinates + cadastral gush/helka.
 * @param {string} addressHe e.g. "דיזנגוף 100 תל אביב"
 * @returns {Promise<{lat:number,lng:number,gush:(number|null),helka:(number|null)}|null>}
 *          null on any failure (no match / network / timeout) — fail-soft.
 */
export async function geocode(addressHe) {
  if (!addressHe || typeof addressHe !== 'string' || !addressHe.trim()) return null;
  const q = addressHe.trim();

  // 1) Autocomplete / search → resolve text to a Web-Mercator (3857) point.
  // The endpoint is POST (not GET): body {searchText, language}. Response:
  //   { results: [{ type, text, shape: "POINT(x y)" }] }  with x/y in EPSG:3857.
  const searchUrl = 'https://www.govmap.gov.il/api/search-service/autocomplete';
  let point = null; // {x,y} in EPSG:3857

  const sr = await fetchJson(searchUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ searchText: q, language: 'he' }),
  });
  if (sr) {
    // Result list lives under `results` (fall back to a couple of legacy keys).
    const lists = [
      sr?.results, sr?.data?.results, sr?.data, Array.isArray(sr) ? sr : null,
    ].filter(Array.isArray);
    outer:
    for (const list of lists) {
      for (const item of list) {
        const p = parseWktPoint(item?.shape ?? item?.Shape ?? item?.data?.shape);
        if (p) { point = p; break outer; }
      }
    }
  }

  if (!point) return null;

  // ponytail: coords are EPSG:3857 Web Mercator — invert directly, do NOT run
  // the ITM reprojection (its easting-magnitude gate rejects 3857 numbers).
  const { lat, lng } = webMercatorToWgs84(point.x, point.y);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

  // 2) gush/helka via entitiesByPoint is BLOCKED: the parcel layer returns
  // 400 "access denied" (needs a session token we don't have). Leave null —
  // geocode still returns valid coords. Best-effort only.
  const gush = null, helka = null;

  return { lat, lng, gush, helka };
}

// Dig out the first feature/attributes object from an entitiesByPoint payload.
function firstFeature(ebp) {
  const data = ebp?.data ?? ebp;
  const arr = Array.isArray(data) ? data : (data?.entities || data?.features || []);
  const f = Array.isArray(arr) ? arr[0] : null;
  return f?.attributes ?? f?.properties ?? f ?? {};
}

// demo: (does NOT run at import — call manually)
//   import { geocode } from './govmap.mjs';
//   console.log(await geocode('רוטשילד 1 תל אביב'));
//   // → { lat: 32.063, lng: 34.769, gush: null, helka: null }
//   (gush/helka are null: entitiesByPoint is access-denied without a session.)
//
// Sanity-check the reprojection math without any network (known ITM↔WGS84 pair,
// Tel Aviv approx): itmToWgs84(178500, 663900) ≈ { lat: 32.07, lng: 34.79 }.
// (itmToWgs84 is module-private; add `export` to it if you want to unit-test
//  the projection in isolation.)
