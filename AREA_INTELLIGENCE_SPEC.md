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
