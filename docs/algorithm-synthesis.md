# Rently Algorithm — Research Synthesis (the super-report)

Synthesised from the 10-agent Research Corps (R1–R10). This is the spec that drives the expert build waves. Everything chosen is **free + commercial-license-clean** unless flagged.

## The 3 white-space bets (confirmed gaps no Israeli competitor fills)
1. **Natural-language conversational search as the MAIN search bar.** Yad2 killed its "Doron" NL chatbot (2023); Madlan never had one. Rently already ships Gemini chat→extract→DB-search — promote it from a side tab to the primary bar. (R10, R5)
2. **Per-listing "Ask Rently" Q&A.** Redfin's highest-intent feature (59% of questions are about the viewed listing). No IL competitor has a per-listing chatbot. Reuse Erik's Gemini pattern scoped to one listing + neighbourhood data. (R10)
3. **Draw-on-map polygon search.** Every Israeli player does radius/area only. Flutter map + geo-polygon query. (R10, R2)

## The free, commercial-clean foundation stack
- **Israeli data spine:** `data.gov.il` CKAN API + **GovMap** (geocode + gush/helka) + **nadlan** sold prices + **CBS** indices. Join keys: **סמל יישוב** (city_code) + **גוש/חלקה**. Coords are ITM/EPSG:2039 → reproject to WGS84. CBS requires attribution. (R1, R8)
- **Maps/geo:** **MapLibre GL** (BSD) + **Protomaps PMTiles** (CC0) self-hosted on S3 — no key, no per-load cost. **Valhalla** self-host (Israel OSM + MoT GTFS) for commute/isochrones. **Overpass/Photon/Nominatim** self-host for POI + geocode. Client touches only PMTiles from S3; all geo logic in Lambda, precomputed + cached. (R2)
- **Vector/semantic:** **BGE-M3** or **multilingual-e5-large** (both MIT) embeddings + **pgvector on Aurora Serverless**, hybrid (vector + Postgres full-text) blended with the existing DynamoDB filter search. Re-embed event-driven on listing write. (R4) — NOTE: introduces Postgres alongside DynamoDB.
- **Hebrew NLP:** delegate query parsing to **Gemini** (already done). Use **DICTA dictabert-joint** (CC-BY) only to lemmatise+NER listing text into a normalised search index (the one thing Gemini can't replace cheaply). (R6)

## SEARCH algorithm — what ships
- **Ranker (R3):** ship a **transparent linear feature-weighted scorer in the Node Lambda** now — `score = w·tag_overlap + w·price_fit + w·distance_decay + w·recency + w·popularity_prior + w·explore(UCB/ε-greedy)`. Explainable, zero infra, handles cold-start. **Critical: start logging per-impression feature vectors NOW** — that log is the training set for the phase-2 **LightGBM lambdarank** (MIT) upgrade. Then **implicit ALS** (MIT) as a candidate generator.
- **Enrichment (R1/R7/R8):** on listing create, a Lambda attaches: geocode+gush/helka (GovMap), **neighbourhood score** (R7: 0.30·safety + 0.25·walkability + 0.20·schools + 0.15·transit + 0.10·green, from data.gov.il + OSM), **price badge** (nadlan comps + CBS trend → "מעל/מתחת לשוק"), POI distances. Cached in DynamoDB.
- **Query understanding (R6):** Gemini parses Hebrew free-text → structured criteria (already the pattern); add a lemmatised index for keyword precision.
- **Semantic (R4):** phase-2 vector retrieval for "vibe" queries beyond hard filters.

## ASSISTANT (Erik) — what ships
- **Tool-loop (R5, P0):** re-architect Erik around Gemini **function-calling** with a real `search_listings` tool (+ get_neighbourhood, save_draft, book_viewing). Erik *acts* instead of talking. The FC loop gives ReAct reasoning for free.
- **Extraction (R5, P0):** switch to **`responseSchema` controlled generation** (full JSON Schema, enums for city/type) — bulletproof Hebrew extraction.
- **RAG + grounding (R5, P0/P1):** gemini-embedding-001 + pgvector over listings/neighbourhoods + strict "answer only from context, cite listing_id" instruction → kills invented apartments/prices.
- **Memory (R5, P1):** short-term rolling summary + long-term per-user preference JSON.
- **Voice (R9):** ship **native STT (he-IL, free) + Gemini + Gemini TTS** turn-based, streaming TTS on first sentence. Realtime target = **Gemini Live** (Hebrew, ~$1.4/hr, 25× cheaper than OpenAI); blocker is **access/provisioning, not quota** → request Live API access for the project. STT upgrade: ivrit.ai faster-whisper (Apache).

## Phase plan (impact × feasibility)
**Phase 1 — cheap, high-impact, mostly reuses existing infra (Gemini/FCM/tags/Erik):**
1. NL search as the main bar (promote+harden existing extract→search).
2. Auto smart-tags from listing text+photos (one Gemini multimodal call at publish).
3. Per-listing "Ask Rently" Q&A.
4. Instant saved-search alerts (Lambda on listing insert → run saved searches → existing FCM push; no polling).
5. Transparent ranker + per-impression feature logging.
6. Erik tool-loop (`search_listings`) + responseSchema extraction.
7. Price badge (nadlan comps + CBS trend, on-demand + cache).
8. Neighbourhood score (data.gov.il + OSM, precompute on create).

**Phase 2:** vector/semantic search (BGE-M3 + pgvector) + lemmatised Hebrew index; MapLibre+PMTiles map UX + draw-polygon + Valhalla commute filter; Erik RAG + memory; LightGBM ranker (once logs accrue).

**Phase 3:** Gemini Live realtime voice; two-tower retrieval (only if corpus→1M+); consented trust/screening layer (WeCheck-style "score the deal, not the person").

## License landmines (hard gate — Rently is a commercial app + plans a data-resale layer)
- ❌ Avoid in product: **OSM ODbL** share-alike (matters for resale — keep derived DBs separate / attribute), **WAQI** (non-commercial), **Cohere** weights (non-commercial), **GRU4Rec / RecBole** (non-commercial), **HebMorph / hspell** (AGPL).
- ✅ Clean: LightGBM/implicit/e5/BGE-M3/HebSpacy (MIT), XGBoost/Stanza/Valhalla/Photon/AlephBERT (Apache), MapLibre/OSRM (BSD), Protomaps (CC0), DICTA (CC-BY attribution), data.gov.il + CBS (open + attribution).
