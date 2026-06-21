# data.gov.il — Dataset Research & Ingestion

Research of the Israeli open-data portal (CKAN) for datasets that materially
improve the apartment-search recommendation engine, plus the ingestion pipeline
that turns them into compact, app-bundled assets.

CKAN API base: `https://data.gov.il/api/3/action/datastore_search?resource_id=<id>`
(paginated via `limit` + `offset`, `records_format=objects`).

---

## Datasets evaluated

### ✅ 1. Public-transport stops — `e873e6a2-66c1-494f-a677-f5e77348edb0`
Dataset: `ministry_of_transport/bus_stops` ("תחנות תחבורה ציבורית").
- **33,937 records**, WGS84 coordinates.
- Fields: `StationId, CityCode, CityName, MetropolinCode, MetropolinName,
  StationTypeCode, StationTypeName, StationOperatorTypeCode,
  StationOperatorTypeName, Lat, Long`.
- **Why it's gold:**
  - Real transit accessibility (density of stops near any point) — replaces the
    23 hand-coded train stations.
  - `StationTypeName` separates rail/light-rail from bus → rail-proximity signal.
  - Averaging stop coordinates per `CityCode` yields a **real centroid for every
    locality** — which the official locality registry lacks.

### ✅ 2. Localities registry — `5c78e9fa-c2e2-4771-93ff-7f400a12f7ba`
Dataset: `citiesandsettelments` ("רשימת ישובים בישראל - מתעדכן").
- Fields: `סמל_ישוב` (locality code), `שם_ישוב`, `שם_ישוב_לועזי`,
  `סמל_נפה`/`שם_נפה` (sub-district), regional council.
- ~1,300 localities. **No coordinates** (we derive them from dataset #1 via
  `CityCode` join) and **no population/socioeconomic** (see #3).

### ⚠️ 3. Socioeconomic index (CBS) — clustered 1–10
CBS characterizes every locality into a socioeconomic **cluster 1 (lowest) – 10
(highest)** from 14 demographic/education/standard-of-living/employment
variables. Strong proxy for neighbourhood quality & desirability.
- Published by CBS; not a single stable CKAN datastore resource, so we ship a
  **curated seed** (`socioeconomic_seed.json`) of the well-known clusters for the
  major localities and let the pipeline overlay an authoritative CSV when a
  resource_id is configured.

### 🔭 4. Real-estate transactions (nadlan) — documented extension
`https://www.nadlan.gov.il` exposes deal data (price, date, rooms, m², address) →
authoritative ₪/m² per area for the hedonic model. Access requires a multi-step
session flow (resolve `ObjectID` via `GetDataByQuery`, then `GetAssestAndDeals`)
and is rate-limited, so it is **not** ingested at build time. We ship realistic
per-locality ₪/m² **priors** (`market_seed.json`) that the hedonic anchor uses
immediately; a nadlan overlay can replace them per-locality later via the same
asset contract (`{name: {rentPerSqm, salePerSqm, n}}`).

### Considered, deferred
- Education institutions (schools w/ coords) — useful for family personas; add
  as a POI layer later via the same grid mechanism.
- CBS peripherality index — overlaps with centrality we already derive.

---

## Pipeline outputs (bundled under `assets/data/govdata/`)

| Asset | Source | Shape |
|-------|--------|-------|
| `localities.json` | #1 ⨝ #2 ⨝ #3 | `[{code,name,nameEn,district,lat,lon,stops,rail,bus,ses}]` |
| `transit_grid.json` | #1 | `{cell:deg, cells:{ "lat_lon": [stopCount, railCount] }}` |
| `rail_stations.json` | #1 (rail types) | `[[lat,lon,name]]` (compact nearest-rail index) |
| `market_seed.json` | seed (+#4) | `{ localityName: {rentPerSqm, salePerSqm, n} }` |
| `meta.json` | pipeline | `{version, generatedAt, sources, counts}` |

All assets are small (grid + rail + locality summaries, not raw 33k points), so
they ship in-app and load synchronously after one async read.

## Running

```bash
node scripts/govdata/ingest.mjs   # fetches #1 + #2, derives centroids/grid/rail,
                                  # merges socioeconomic + market seeds → assets
```

Verified run: 33,937 stops → 1,199 locality centroids, 244 rail stations,
2,055 transit-density cells. Total bundled size ≈ 220 KB.
