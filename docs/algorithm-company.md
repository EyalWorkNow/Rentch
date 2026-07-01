# Rently Algorithm Company — 35-Agent Org

Mission: make the **apartment-search algorithm** and the **personal-assistant (אריק/Erik) algorithm** dramatically smarter, and surface free data sources, maps, datasets, algorithms and capabilities that turn Rently into an unfair-advantage product.

Product context every agent assumes: Rently = Israeli **Hebrew RTL** real-estate marketplace (rent + sale; two-sided landlords/tenants/brokers; swipe UX). Stack: Flutter app; AWS Lambda `rentch-router` (Node ESM, DynamoDB, S3); a `appwrite_client` shim that actually calls the router; search via `property_search_repository.dart` + backend `listItems`; assistant via `assistant_service.dart` + `/assistant/*` routes + **Gemini** (gemini-2.5-flash). Constraints: prefer **free / open-source / self-hostable**; **commercial-friendly licenses only** (no GPL/AGPL/research-only in the product); Israel-relevance + Hebrew matter.

Operating model: **Research Corps (10)** runs first (read-only, web research → integration-ready briefs). **Synthesis** turns briefs into a concrete spec. **Expert Divisions (25)** implement in disjoint-file waves. No agent commits; the orchestrator integrates + verifies.

---

## RESEARCH CORPS (10) — read-only web research, launched first

**R1 — Israeli real-estate open data.** Find every free/official Israeli dataset and feed relevant to apartment search: gov.il / data.gov.il, Lamas/CBS (הלשכה המרכזית לסטטיסטיקה) housing & price indices, רשות המסים deal prices (נדל"ן – עסקאות), מדד מחירי הדיור, RAMI/רמ"י, municipal GIS open data (Tel Aviv, Jerusalem, Haifa), and any public listing feeds. For each: what it contains, granularity, update cadence, access (API/CSV/scrape), licence, Hebrew fields, and EXACTLY how it could enrich a listing or a search filter. Output a ranked, integration-ready table.

**R2 — Maps, geospatial & transit (free).** OpenStreetMap + Overpass API (POIs: schools, groceries, parks, clinics, synagogues), free tiles (MapLibre + free tile sources), geocoding (Nominatim, Pelias), routing/commute & **isochrones** (OpenRouteService, Valhalla, OSRM), and Israeli **GTFS** public-transit data (משרד התחבורה open GTFS) for "X minutes by bus/train". For each: free tier/limits, self-host option, licence, Hebrew support, and how to compute commute-time / walkability / "near a school" at search time.

**R3 — Ranking & recommendation algorithms.** Survey commercial-friendly learning-to-rank and recsys approaches usable on a marketplace with implicit feedback (swipes/likes/views): LambdaMART/XGBoost-rank, two-tower retrieval, matrix factorisation (implicit ALS), session-based recsys, and bandits/exploration for cold-start. For each: when it fits Rently's data, training cost, inference cost on Lambda, libraries (licence), and a concrete "phase 1 we'd ship" recommendation.

**R4 — Vector / semantic search infra (free / self-host).** Compare embeddings + vector search options for Hebrew listing text + query understanding: pgvector, Qdrant, LanceDB, sqlite-vss, FAISS; plus embedding models (multilingual-e5, BGE-m3, Gemini embeddings free tier, Cohere free). For each: licence, self-host/serverless cost, Hebrew quality, and an architecture that fits the existing AWS/DynamoDB stack (where would vectors live, how to keep them fresh).

**R5 — LLM agent architecture (assistant intelligence).** Research state-of-the-art patterns to make Erik genuinely smart: structured tool-use / function-calling, RAG over listings + neighbourhood data, planning/ReAct, multi-turn memory, self-critique, and grounding to avoid hallucination. Focus on what's achievable with **Gemini** (function calling, JSON mode, long context) + free tooling. Deliver concrete prompt/architecture patterns Rently can adopt, with examples.

**R6 — Hebrew NLP.** Find free/open resources for Hebrew query & text understanding: tokenisation/lemmatisation (HebSpacy, Stanza, dicta-il models), NER for places/streets/neighbourhoods, spell/normalise user queries, and Hebrew embeddings. For each: licence, quality, size, runtime fit (Lambda/edge/Gemini-instead), and how it improves query parsing ("3 חדרים בצפון ת"א עד 6000").

**R7 — Neighbourhood quality-of-life data.** Find free sources to score a location: schools & ratings, crime/safety, noise, air quality, walkability, green space, parking, distance to coast/centre — Israel-specific where possible (משרד החינוך schools, police open data, municipal GIS), global fallbacks (OSM-derived walkscore-style metrics). Deliver how to turn each into a 0–100 sub-score shown on a listing and usable as a ranking signal.

**R8 — Price / valuation & market signals.** Research free ways to estimate fair price & deal quality: רשות המסים transaction prices, CBS price indices, simple hedonic/AVM models (features → price), and "is this listing over/under-priced vs area" signals. Deliver a concrete plan for a lightweight valuation signal + "good deal" badge using only free data.

**R9 — Voice AI (STT / TTS / realtime), free-or-cheap.** Map the realistic options for Erik's voice given current blockers (Gemini Live no model; OpenAI Realtime quota-blocked): on-device STT/TTS, Gemini TTS, open models (Whisper/faster-whisper, Coqui/Piper TTS, Kokoro), and any free realtime path. For each: quality (esp. Hebrew), latency, cost, on-device vs server, licence. Recommend the best turn-based + the cheapest path to true realtime.

**R10 — Competitive teardown.** Reverse-engineer what makes search + AI great at Zillow, Redfin, Compass, Rightmove, and **Yad2 / Madlan (מדלן) / Homeless** (Israel). What signals, filters, map UX, "smart" features, and AI assistants do they ship? Deliver a prioritised list of "features that would move the needle for Rently" with feasibility notes on the free stack.

---

## SEARCH DIVISION (13 experts)

### Team S-RANK — ranking & relevance (3)
**S-Rank-1 — Implicit-feedback ranker.** Design + implement a ranking model over swipes/likes/views/saves that reorders search results per user. Start with a transparent feature-weighted scorer (extends `_score` in `property_search_repository.dart`), with a clean path to learning-to-rank once data exists. Owns the client ranking layer.
**S-Rank-2 — Server ranking & signals.** In `index.mjs` `listItems`/a new ranking endpoint, compute server-side ranking signals (freshness, popularity, completeness, price-fit, location-fit) and expose them so the client ranker can blend them. Owns the backend ranking signals.
**S-Rank-3 — Cold-start & exploration.** Add bandit-style exploration + diversity so new listings and new users get good results (no filter bubble); define the onboarding "taste" capture. Owns exploration/diversity logic.

### Team S-DATA — enrichment & sources (3)
**S-Data-1 — Listing enrichment pipeline.** Using R1/R7/R8 findings, build a backend enrichment step that attaches neighbourhood, POI, price-fairness and quality sub-scores to a listing on create/update (DynamoDB fields + an S3/precompute cache). Owns the enrichment write-path.
**S-Data-2 — External data connectors.** Implement the actual connectors to the top free sources R1/R2 surfaced (gov/CBS/OSM/GTFS), with caching + graceful fallback. Owns `aws/lambda` data-connector code (new module).
**S-Data-3 — Data freshness & quality.** Dedup, validate, and keep enriched data fresh; flag stale/low-quality listings; expose a data-quality score. Owns the data-quality/refresh jobs.

### Team S-GEO — maps, commute, geospatial (3)
**S-Geo-1 — Map search UX.** Add a real map view to discover/search (MapLibre + free tiles), draw-to-search, pins with price, cluster. Owns the Flutter map screen (new).
**S-Geo-2 — Commute & isochrone filters.** "≤30 min to <workplace> by transit/car" filter using R2 routing/GTFS; precompute isochrones server-side. Owns the commute filter (backend + filter UI hook).
**S-Geo-3 — Proximity signals.** "Near schools / sea / park / station" filters + distance signals feeding ranking. Owns proximity computation + the related filter chips.

### Team S-NLU — query understanding (2)
**S-NLU-1 — Hebrew query parser.** Turn free-text Hebrew ("3 חד' בצפון ת״א עד 6000 עם מרפסת") into structured `PropertySearchCriteria` using Gemini + R6 Hebrew NLP, robust to typos/slang. Owns query parsing.
**S-NLU-2 — Semantic retrieval.** Add embedding-based retrieval (R4) over listing descriptions for "vibe" queries beyond hard filters, blended with the structured search. Owns the semantic layer.

### Team S-INFRA — search infra & performance (2)
**S-Infra-1 — Vector store + index.** Stand up the chosen vector store (R4) and keep listing embeddings fresh; expose a retrieval API. Owns vector infra.
**S-Infra-2 — Search performance & relevance eval.** Add latency budgets, caching, and an offline relevance-eval harness (precision@k on held-out likes) so every ranking change is measured. Owns the eval harness + perf.

---

## ASSISTANT DIVISION (12 experts)

### Team E-REASON — reasoning, planning, tool-use (3)
**E-Reason-1 — Tool-use core.** Re-architect Erik around Gemini **function-calling** with a clean tool registry (search_properties, get_neighbourhood, schedule_tour, build_listing, compare). Owns the assistant tool-loop in `assistant_service.dart` + backend `/assistant`.
**E-Reason-2 — Planning & grounding.** Add ReAct-style planning + grounding to real DB/data so Erik stops hallucinating and actually executes multi-step tasks. Owns the planning/grounding prompts + flow.
**E-Reason-3 — Self-critique & safety.** Add a validate-before-answer pass (model-as-judge) for correctness + Hebrew tone + no-overpromising. Owns the critique layer.

### Team E-EXTRACT — structured understanding (2)
**E-Extract-1 — Listing builder.** Make the "describe your apartment → publishable draft" extraction near-perfect (Hebrew, partial info, follow-up questions) feeding `create_property`. Owns extraction prompts + `/assistant/extract`.
**E-Extract-2 — Preference capture.** Turn conversation into a durable tenant preference profile (must-haves, deal-breakers, budget, vibe) that powers ranking + matching. Owns the preference model + capture.

### Team E-MATCH — two-sided matching & explainability (3)
**E-Match-1 — Match engine v2.** Upgrade the two-sided MatchEngine (tenant↔listing + landlord lead ranking) with the new signals + preference profiles. Owns the match engine.
**E-Match-2 — Explainability.** "Why this apartment / why this lead" human Hebrew explanations grounded in real signals. Owns explanation generation.
**E-Match-3 — Deal-breaker & fairness gates.** Hard gates (pets, budget, location) + fairness (no illegal discrimination) on both sides. Owns the gating logic.

### Team E-MEMORY — memory & personalisation (2)
**E-Memory-1 — Long-term memory.** Give Erik durable per-user memory (preferences, past chats, shown listings) with retrieval, so it feels continuous. Owns the memory store + retrieval.
**E-Memory-2 — Personalised proactivity.** Proactive nudges ("3 חדשות שמתאימות לך", price drops on saved) via the broadcast/notification rails already built. Owns proactive triggers.

### Team E-VOICE — realtime voice (2)
**E-Voice-1 — Turn-based voice excellence.** Make the STT→Gemini→TTS hands-free loop feel instant + natural (barge-in, fast TTS, Hebrew), using R9. Owns the voice loop.
**E-Voice-2 — Realtime path readiness.** Build the abstraction so that when a realtime provider unblocks (OpenAI Realtime funded / Gemini Live access), it drops in behind the same interface. Owns the realtime adapter.

---

## Wave plan
1. **Research Corps (10)** → integration-ready briefs. (Running.)
2. **Synthesis** → one prioritised technical spec (what ships in phase 1, exact files, free sources chosen).
3. **Expert waves** → implement on **disjoint files**, each followed by an adversarial QA agent; orchestrator integrates, `flutter analyze` + `node --check`, redeploy, single commit per wave.
