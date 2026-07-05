# Assistant → Filtering → Tagging: end-to-end architecture

How the smart assistant (אתי / אריק), the search/ranking engine, and the tagging
layers connect. The guiding principle: **intent is extracted once, expressed as a
single typed contract, and consumed by everything downstream.** No component
re-parses free text that another component already understood.

```
                        ┌──────────────────────────────────────────────┐
   user (voice/text) ──▶│  LAYER 1 — INTENT EXTRACTION                  │
                        │  • typed chat:  SmartSearch.parse             │
                        │  • assistant:   GPT search_listings tool      │
                        │      → both emit the SAME keys                │
                        └───────────────┬──────────────────────────────┘
                                        │  SearchQuery  (THE CONTRACT)
                                        │  { city, transactionType, min/maxPrice,
                                        │    min/maxRooms, features[], intents[],
                                        │    rawText }
                                        ▼
                        ┌──────────────────────────────────────────────┐
                        │  LAYER 2 — HARD GATES  (relax-if-empty)       │
                        │  rent/sale · city-metro(18km) · budget(+15%)  │
                        │  · near-sea(≤3km)                             │
                        └───────────────┬──────────────────────────────┘
                                        │  candidate set
                                        ▼
                        ┌──────────────────────────────────────────────┐
                        │  LAYER 3 — RANK (MAUT)                        │
                        │  intents → dimension weights (sharpen)        │
                        │  + gov-data features + market model           │
                        │  → fitScore, ordered                          │
                        └───────────────┬──────────────────────────────┘
                                        │  ScoredProperty[]
                                        ▼
                        ┌──────────────────────────────────────────────┐
                        │  LAYER 4 — TAGGING & EXPLAINABILITY           │
                        │  Scorecard: dimensions+stats, persona reasons,│
                        │  concerns, "why" tags  ·  persona tags → bias │
                        └───────────────┬──────────────────────────────┘
                                        ▼
                              cards + spoken summary
```

## The contract — `SearchQuery`

The single object every layer speaks. Filled identically by typed search and by
the assistant, so behaviour is consistent across text and voice.

| Field | Source (typed) | Source (assistant) |
|---|---|---|
| `city`, `min/maxPrice`, `min/maxRooms`, `neighborhood` | `SmartSearch.parse` regex | GPT `search_listings` args |
| `transactionType` (rent/sale) | sale/investment keywords | GPT `transactionType` enum |
| `features[]` (`feat_*`) | amenity keywords | GPT `features[]` |
| **`intents[]`** | `SearchIntent.fromText` | GPT `intents[]` enum (∪ text fallback) |
| `rawText` | the utterance | reconstructed from args |

### `intents[]` — the lifestyle/spatial taxonomy

Canonical keys, defined **once** in `lib/core/search/search_intent.dart` and
mirrored in the backend `search_listings` tool enum:

```
near_sea · nightlife · quiet · central · spacious · accessible · luxury ·
view · student · near_university · investment · roommates · wfh ·
good_schools · quality_area
```

`SearchIntent.fromText(text)` maps free text → this set (with implications, e.g.
`student ⇒ near_university`; elderly ⇒ `accessible`). The assistant fills the same
keys directly via its tool schema. **Add an intent once → the whole pipeline
gains it.**

## Layer boundaries (files)

| Boundary | Where | Contract |
|---|---|---|
| Typed text → contract | `smart_search.dart` (`SmartSearch.parse` → `SearchIntent.fromText`) | `SearchQuery` |
| Assistant → contract (backend) | `aws/lambda/router/index.mjs` `SEARCH_LISTINGS_TOOL` (intents/transactionType/features enums) | tool-call args |
| Assistant args → contract (client) | `search_chat_screen.dart` `_handleRealtimeSearch` (maps args → `SearchQuery`, unions `intents`) | `SearchQuery` |
| Contract → gates + rank | `recommendation_orchestrator.dart` `RecommendationEngine.recommend` | `ScoredProperty[]` |
| Intent → weights | `preference_model.dart` (`query.intents.contains(...)` → `sharpen(dim,…)`) | dimension weights |
| Rank → tags/why | `recommendation_orchestrator.dart` `_buildScorecard` + `Scorecard` | `Scorecard` |

## Layer 2 — Gates (deterministic, relax-if-empty)

Applied at the top of `recommend()`, in order. Each restricts the candidate set
only when it stays non-empty, so we honour the request without dead-ending:

1. **rent/sale** — `SmartSearch.applyTransactionFilter`; an investor never sees rentals.
2. **city → metro** — the named city plus everything within **18 km** (גוש דן, הקריות, השרון); far cities excluded.
3. **budget** — drop listings >15 % over a stated `maxPrice` when cheaper exist.
4. **near-sea** — `intents.near_sea` ⇒ keep only ≤ `SearchIntent.seaOkKm` (3 km) of the coast (close ≤1.5 km, near ≤3 km, far >3 km).

## Layer 3 — Intent → weights

The preference model **consumes** `query.intents` (it never re-parses text). Each
present intent sharpens the relevant MAUT dimension to a top tier (≈ value/size),
so an explicitly-requested factor actually re-ranks rather than nudging:

```
near_sea      → coast          quiet         → senior_area
investment    → yield          luxury        → luxury
near_university→ university     view          → view
nightlife     → young_area+loc spacious      → spaciousness
accessible    → accessibility  central       → location
roommates     → size+space     good_schools  → schools
wfh           → space+cond     quality_area  → neighborhood
```

Off by default (prior weight 0) → ordinary searches are unaffected.

## Layer 4 — Tagging & explainability

Two tag streams, both grounded in real data — never fabricated:

- **Listing tags / "why"** — `Scorecard` per result: weighted dimensions with
  their real numbers (price vs area median, distance to sea, safety percentile…),
  verified persona reasons (only a feature the listing actually has), honest
  concerns. Rendered by `WhyDetails` / `ScorecardView`.
- **Persona tags** — captured from the conversation (`importantDetails`,
  `dealBreakers`, religiosity, lifestyle) into `TenantProfile`; fed back as ranking
  bias (`_personaReasons`, cohort fit). The user's identity persists across turns.

## Invariants (the senior-architect rules)

1. **One extractor per surface, one contract.** Text and assistant both produce
   `SearchQuery`; nothing downstream re-parses text.
2. **Intent keys live in exactly one place** (`SearchIntent`), mirrored — not
   duplicated — in the tool enum. Drift is a bug.
3. **Gates are deterministic and honest** — they restrict, then relax rather than
   dead-end, and every compromise is surfaced as a concern.
4. **No fabricated signals.** A dimension exists only if backed by real data
   (gov datasets, the listing's own fields, or a documented bundled table).
5. **Off-by-default.** A factor influences ranking only when the user's intent
   turns it on.

## Extension recipe (add a new use-case, end to end)

1. Add the key + regex to `SearchIntent` (and its threshold const if spatial).
2. Add the same key to the `SEARCH_LISTINGS_TOOL` `intents` enum (backend).
3. Add a `sharpen(dim, …)` in `preference_model` guarded by `intents.contains(key)`.
4. If it needs a new dimension: add to `kScoringDimensions` + `dimensionValue` +
   a `LinearUtility` + `_dimLabel`; back it with a real feature.
5. If it needs a hard filter: add a relax-if-empty gate in `recommend()`.
6. Add a persona test (load gov data) proving it re-ranks and doesn't skew
   ordinary searches.
```
