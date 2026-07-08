# אתי — Search & Ranking Algorithm: Session Work Summary

A single reference for the search/ranking-algorithm work done in this session:
bug fixes surfaced by aggressive multi-agent testing, comprehensive
qualitative-phrase understanding, five new government/OSM **map-data layers**, and
the test infrastructure that guards all of it.

**Bottom line:** 33 ranking dimensions, all wired to free-text intents +
personalization; ~90 new tests; **445 tests pass**, 8 pre-existing failures
(environment/golden, unrelated — see §7); **zero regressions**.

---

## 1. Architecture at a glance

```
user text ──► SmartSearch.parse ──► SearchQuery{ city, budget, rooms,
                 │                     requiredFeatures, amenities, intents, … }
                 │                                    │
     SearchIntent.fromText (phrases → intent keys)    │
                 │                                    ▼
                 └──────────────► RecommendationOrchestrator.recommend
                                     • city gate (identity + "אזור" expansion)
                                     • required-feature gate (deal-breakers)
                                     • PreferenceModelBuilder.build
                                         └ Bayesian per-dimension weights,
                                           sharpened by intents + persona
                                     • FeatureEngineer.engineer  ◄── GovData layers
                                     • rank → Scorecard (fit% + per-dim breakdown)
```

Every **dimension** = one signal. Intent-gated dimensions default to prior 0 and
only activate when their phrase fires, so an ordinary search isn't skewed. Each
gov/OSM layer is loaded independently and **degrades** to neutral if its asset is
missing — a broken dataset never breaks ranking.

---

## 2. Correctness fixes (from the 5-agent aggressive breaking test)

Five agents hammered the algorithm in parallel (geo, budget/rooms, cohort signals,
deal-breaker gates, ranking robustness). Confirmed, reproduced, fixed:

| ID | Severity | Bug | Fix |
|----|----------|-----|-----|
| **G1** | crash | `lat/lon = Infinity/NaN` crashed the engine (`_coastDimension`, geo grids) | `.isFinite` guard in `_validCoord` + `_coastDimension` |
| **D1** | high | one unsatisfiable required feature (`accessible`, no stock) voided a satisfiable one (`elevator`) → walk-ups leaked to a wheelchair searcher | gate drops only *unsatisfiable* keys; graceful fallback (never hides all) |
| **P1** | **critical** | a curated `TenantProfile`'s Hebrew deal-breakers ('נגישות'/'ממ"ד') were unmapped **and** routed to the wrong bucket → profile never touched ranking | map via the amenity lexicon → the model's `requiredFeatures` (must-have), not `dealBreakers` (must-be-absent) |
| **B1** | high | "2 מיליון" / "2500000" (no "עד") → budget silently dropped (60k cap) + sale-intent lost | accept the sale band (100k–30M) too; sale inference then fires |
| **B2** | high | "עד N חדרים" set a **minimum** (no max-rooms path) → "small apartment" surfaced the biggest units | dedicated upto/from room parsing |
| **Geo1** | high | ktiv-male "-ייה" (נהרייה/הרצלייה) + space-less typos (תלאביב/כפרסבא) dropped the city | collapse "ייה"→"יה"; match space-less multi-word cities (both prefix-stripped and raw) |
| **C3–C8** | med–high | negation ("בלי ילדים"→hasChildren), charedi over-tagged from city "בני ברק", English "aliyah"/"olah" dropped, building age ("בניין בן 40 שנה"→user age), "מבוגר"/"קושי בהליכה" missed | targeted cohort-signal rules |

Files: `lib/core/search/smart_search.dart`,
`lib/core/search/engine/recommendation_orchestrator.dart`,
`lib/core/search/engine/preference_model.dart`, `lib/core/govdata/gov_data.dart`.

> Note: the deal-breaker gate for **unrecorded** features (mamad/pets absent
> across the catalogue) deliberately degrades to the pool rather than hiding all
> results — absence of a flag ≠ the feature is banned. An existing product test
> enforces this. D1 + "gate-still-passes" guarantee no leak when qualifying stock
> exists.

---

## 3. Qualitative-phrase understanding

Goal: understand *meaning* — "שכונה טובה", "מקום שקט", "אזור צעיר", "קרוב לתחבורה",
"באזור של…", "פוטנציאל השבחה" — not just structured fields. A 102-phrase coverage
probe (`test/semantic_coverage_test.dart`) went from **59/102 → 97/102** understood.

`SearchIntent` (`lib/core/search/search_intent.dart`) now covers, and each routes
to a real dimension:

| Phrase family | Intent | Dimension (map layer) |
|---------------|--------|-----------------------|
| שכונה טובה / מטופחת / מבוקשת / נחשבת | `qualityArea` | neighborhood (CBS SES) |
| מקום שקט / רגוע / שלווה / בלי רעש | `quiet` | senior_area **+ low_noise** |
| אזור צעיר / סביבה צעירה / אוכלוסייה צעירה | `youngPop`/`nightlife` | young_area (CBS demographics) |
| שכונה בטוחה / לא מסוכן / בלי פשיעה | `safety` | safety (police crime) |
| קרוב לתחבורה / ליד רכבת / מטרו | `transit` | transit (transit grid + rail) |
| אזור ירוק / גינות / פארק / אוויר נקי | `green` | park |
| ליד סופר / מרכז קניות / קניון | `convenience` | convenience (retail POI) |
| קרוב לקופת חולים / בית חולים | `health` | health |
| קרוב לעבודה / הייטק / אזור תעסוקה | `employment` | employment (job hubs) |
| פוטנציאל השבחה / פינוי בינוי / מטרו עתידי | `growth` | future_value |
| שכונה דתית / חרדי / מסורתי | `religiousArea` | religious_area |

Plus negation-that-adds-intent ("לא באזור רועש" → quiet) and a stated numeric age
65+ → accessible/quiet. Deliberately **not** covered (no data layer): "שכונה
חילונית", "קהילה מעורבת", "ליד סופר-ספציפי"; and "לא ליד הים" is a *correct* drop.

---

## 4. Five new map-data layers

The neighbourhood-quality signals a good agent actually weighs. Each follows one
recipe (§5) and is degradable + has provenance in `gov_sources.dart`.

| Layer | Dimension | Activated by | Source / ETL |
|-------|-----------|--------------|--------------|
| Retail / errands | `convenience` | "ליד סופר / קניון" | OSM · `scripts/govdata/poi_retail.mjs` |
| Road/rail noise | `low_noise` | "מקום שקט" | OSM · `scripts/govdata/noise.mjs` |
| **Statistical area** | *upgrades* neighborhood / young_area / senior_area / family to **block level** | always (drop-in) | CBS · `scripts/govdata/stat_areas.mjs` |
| Future infrastructure | `future_value` | investment + "פוטנציאל / מטרו / פינוי-בינוי" | נת"ע / רשות התכנון · `scripts/govdata/future_infra.mjs` |
| Employment | `employment` | "קרוב לעבודה / הייטק" | OSM · `scripts/govdata/employment.mjs` |

**Statistical area** is the biggest accuracy lever: a point-in-polygon lookup
(ray-casting + bbox spatial index) finds the flat's own CBS block (~3,000
residents) and its SES/age split **override the whole-city average** — so two
flats in the same city rank differently by micro-neighbourhood.

**All 33 dimensions** (base + these): location, neighborhood, safety, budget,
value, size, amenities, transit, condition, freshness, popularity, trust, schools,
family, health, coast, park, religious_area, school_young, school_teen, nightlife,
yield, university, young_area, senior_area, luxury, view, spaciousness,
accessibility, **convenience, low_noise, future_value, employment**.

---

## 5. The unified map-layer recipe (how to add the next one)

Every layer is 7 steps — follow it for #A air-quality-as-a-dimension, #B
crime-by-category, #C parks-as-polygons, etc.:

1. **ETL → asset** — `scripts/govdata/<x>.mjs` fetches (data.gov.il CKAN / OSM
   Overpass) → `assets/data/govdata/<x>.json`.
2. **GovData** — fields + `_loadX` (registered via `_loadOptional`, degradable) +
   an `xScore(...)` accessor + clear in `dispose`.
3. **FeatureEngineer** — `f['x_feature'] = gov.xScore(...)`.
4. **PreferenceModel** — add to `kScoringDimensions`, a `satisfaction` case, a
   utility, a prior (0.0 = off), and an intent `sharpen`.
5. **SearchIntent** — intent key + Hebrew/English phrase patterns.
6. **GovSources** — provenance entry (honest source label).
7. **Test** — intent set + score>0/differentiates + dimension engaged + degradable.

Connection patterns by data shape: **density** → 0.02° grid (transit/schools/
retail/employment) · **fine local** → 0.005° grid (noise) · **city** → name→code
(crime/demo/health) · **point** → nearest-distance + kernel (rail/coast/future) ·
**polygon** → point-in-polygon + bbox index (statistical area).

---

## 6. Test infrastructure (≈90 new assertions)

| File | What it guards |
|------|----------------|
| `breaking_personas_30_test.dart` | 30 real personas; budget/sale/area/monotonic invariants |
| `algo_hardening_test.dart` | regressions for G1/D1/B1/B2/Geo1/C*/P1 |
| `personalization_25_testers_test.dart` | 25 testers × 37 queries; map layers engage + profile changes order |
| `semantic_coverage_test.dart` | 102 qualitative phrases understood |
| `poi_retail / noise_layer / stat_area / future_infra / employment_layer` | each new layer end-to-end |
| `all_dimensions_breaking_test.dart` | all 33 dims engage on their phrase, ≥6 together, adversarial invariants, all wired |

---

## 7. Status & next steps

- **Live now** on small **seed** assets (enough for tests + demo).
- **For nationwide coverage:** run the five `scripts/govdata/*.mjs` ETLs.
  `stat_areas.mjs` and `future_infra.mjs` need their **CBS / planning-authority
  resource IDs confirmed** (marked `REPLACE_…` / `TODO(confirm)` in the scripts).
- **8 pre-existing test failures** (`gov_sources`, `govdata`, `panorama`,
  `profile_card` ×2, `widget_test` ×3) fail **without** these changes too (proven
  by a `git stash` baseline) — environment/golden-render, **not** regressions.

### Candidate next layers (ranked)
1. Air quality **as a dimension** (stations already loaded; add `air`).
2. Crime **by category** (violent vs property — data already in `_crime`).
3. Parks as **polygons** (upgrade the `park` dimension from a proximity proxy).
4. Learning-to-rank from engagement (feature vectors already exist).
