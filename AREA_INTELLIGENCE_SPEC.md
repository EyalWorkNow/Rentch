# Area Intelligence — spec (בעלי דירה + מתווכים)

Supply-side mirror of the tenant search engine: instead of ranking apartments for
a tenant, it profiles a **location** and ranks **areas** for a target tenant
persona. Access-gated to `landlord` + `broker` account types.

## Capabilities
1. **Address profile** — enter an address → geocode (`locationFromAddress`) →
   full gov-data card at the point (all layers) + "which personas this place
   serves best, and why".
2. **Area ranking (Phase 2)** — pick a target persona + city → rank the city's
   statistical areas best→worst, each with a fit % + top-3 "why" layers + an
   investment lens.

## Core algorithm (reuse-first)
- Build a synthetic `RentalProperty` at the point/area-centroid → run
  `FeatureEngineer.engineer()` → a full `PropertyFeatureVector` (all place layers,
  with the corrected safety + block-level stat-area override, for free).
- Target persona → `UserPreferenceModel` via `PreferenceModelBuilder.build` (reuses
  intents + the 67 inference rules).
- **Area fit** = `Σ w·satisfaction(dim, pfv) / Σ w` over the PLACE dimensions only
  (centrality/neighborhood/safety/transit/schools/family/health/coast/park/
  religious_area/nightlife/young_area/senior_area/employment/convenience/low_noise/
  future_value/university) — NOT budget/rooms/amenities/condition. Same MAUT, inverted.
- **"Why"** = the top-3 contributing dimensions (like the scorecard).

## Target personas (presets)
young-couples · families · students · high-tech · seniors · high-yield-investor ·
value-add-investor. Each = a SearchQuery (intents/text) → weight profile.

## Investment lens
- Yield: MVP proxy = `future_value` + centrality. Phase 3 = real CBS
  `AppValueStat11` (apartment value per statistical area) → true yield.
- Appreciation: existing `future_value` (planned metro/light-rail + urban renewal).

## Phases
- **Phase 1 (MVP)** — address → layer card + persona fit at the point (no map).
- **Phase 2** — rank a city's stat-areas for a persona (list + %/why). Requires
  re-running `stat_areas.mjs` to add settlement/id per area (currently absent).
- **Phase 3** — `flutter_map` heatmap of areas + real CBS AppValue yield layer.

## Files
- `core/insights/target_personas.dart` — persona → query/weights presets.
- `core/insights/area_intelligence.dart` — AreaProfile + profileAt + fitFor + suitablePersonas.
- `presentation/features/broker/area_intel_screen.dart` — UI (address + persona picker + results).
- Entry: broker tools tab + landlord dashboard shortcut.

## Open (defaulted for MVP)
- Yield → proxy. Map → Phase 2 list-first. Entry → both. Personas → the 7 above.

---

# Phase 2 — City area ranking (architecture)

Goal: pick a target persona + a city → rank ALL that city's statistical areas
best→worst for the persona, as a ranked list AND a colour-coded map.

**Data (prerequisite):** `stat_areas.json` today has no city/id per area, so a
city can't be resolved. Fix in the ETL:
- `stat_areas.mjs`: add `city` (`Shem_Yishuv`) + `id` (`YISHUV_STA`) per area.
  Re-run → new asset (~+50 KB). Centroid computed in Dart from the polygon.
- `StatArea` model + `_loadStatAreas`: parse `city` + `id`; add a `centroid` getter
  (mean of ring vertices — enough for profiling + map placement).
- `GovData.statAreasInCity(city)`: normalized-name filter → the city's areas.

**Engine:** `AreaIntelligence.rankCityAreas(city, persona, {limit})`:
- for each `StatArea` in the city → `profileAt(centroid)` → `fit(persona)` →
  `RankedArea(area, profile, fit)`; sort desc by fit%. Cache per (city, persona).
- O(areas) FeatureEngineer runs; a big city (~500 areas) is a ~1 s one-shot — run
  off the UI frame + show a spinner; cache the result.

**UI:** extend `area_intel_screen.dart` with a second MODE ("דרג אזורים בעיר"):
- city field (autocomplete off `GovData.localities`) + persona picker → "דרג".
- **List:** ranked rows (rank #, best-effort neighbourhood label via
  reverse-geocode of the top-N centroids, fit %, top reason, mini-bar). Tap → the
  Phase-1 layer card for that area's centroid.
- **Map (the wow):** `flutter_map` centred on the city, top-N areas drawn as
  colour-graded polygons (green=high fit → amber=low), tap a polygon → its card.

**Tests:** `statAreasInCity` returns a non-trivial set for a big city; centroid
inside the polygon bbox; `rankCityAreas` sorted + persona-discriminating; crush
(unknown city → empty, no throw).

Phase 3 (real CBS AppValue yield) still deferred.
