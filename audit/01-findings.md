# Rently AWS Audit — Findings

## Executive summary (5 lines)

Current spend: **$0.24/mo gross, $0.00 net** (credits + free tier absorb everything) — there is nothing material to cut today; this audit is about defusing scale-time cost bombs and improving the wire. The three bombs, in order: (1) the app-state sync writes a full ~16 KB state blob to DynamoDB on every user action — 55 un-debounced call sites, already 75k WCU/mo with ~5 users, ≈ **$1.4k/mo at 5k MAU** if untouched; (2) three telemetry tables (search-log, events, property-views) are write-only with TTL disabled — data accretes forever and events/views are never read at all; (3) the main REST API pays the $3.50/M tax with no CDN in front, where an HTTP API does the same job for $1.00/M. First three actions: debounce/diff the app-state writes (client-only change), enable TTL on the three telemetry tables, plan REST→HTTP API migration. Payback: immediate at scale; at today's traffic the payback is $0 — which is exactly why now is the cheap time to fix all three.

---

## PHASE 1 — Cost teardown

Measured window: 30 days (2026-07-21 → 2026-08-20) via CloudWatch unless noted. "At-scale" = the baseline's 5k-MAU model (≈45× current API traffic), always labeled.

### F1 — app-state full-blob upsert on every action (the #1 scale bomb)

**Evidence:** `rentch-app-state` consumed **75,467 WCU in 30d** — 1.8× every other table combined excluding the one-off 22.5k-listing bulk load — while holding only **120 items / 1.95 MB (≈16 KB avg item)** (CloudWatch ConsumedWriteCapacityUnits; describe-table). A 16 KB item costs 16 WCU per write → ≈4,700 full-blob writes/mo from a handful of users. Client: `lib/data/providers/dating_provider.dart` has **55 `_persist()` call sites** (every swipe/like/settings change); `lib/core/services/local_storage.dart:129` documents the remote write as "immediate/awaited (not debounced)"; `_saveRemoteState` (local_storage.dart:255) re-serializes and upserts the **entire** state (tenantProfile, all customProperties incl. media lists) every time.

**Cost:** today ~$0.09/mo. **At scale (H confidence in the mechanism, M in the multiplier): 5k MAU × ~30 persists/day × 16 WCU ≈ 72M WCU/mo ≈ $90–1,400/mo** depending on real per-user action rate (range = 2–30 persists/day). This is the single largest modeled line item in the account.

**Recommendation (client-only, no server change):**
1. Debounce remote sync (e.g. 10 s trailing) — collapses swipe bursts into one write.
2. Skip the write when the serialized payload hash is unchanged.
3. Longer term: split hot fields (likes/seen-ids) from the cold blob so a swipe writes ~100 B, not 16 KB.

**Implementation sketch** (in `_saveRemoteState`, before the upsert):
```dart
final encoded = jsonEncode(remoteState);
if (encoded.hashCode == _lastSyncedHash) return;   // skip no-op writes
// + wrap the whole call in the existing WriteDebouncer (dating_provider.dart:123 already has one for likes)
```
**Rollback:** remove the guard — pure client logic, reversible in minutes. **Risk:** low; worst case a crash loses ≤10 s of swipe state (local copy persists regardless).

### F2 — TTL disabled on ephemeral tables; two tables are write-only

**Evidence:** `describe-time-to-live`: **all 22 tables DISABLED**. 30-day consumption: `rentch-events` W=2,920 / **R=0**; `rentch-property-views` W=3,865 / **R=0** — written, never read. `rentch-search-log` W=9,669 / R=3,851, already 9,842 items / 3.4 MB. `rentch-ws-connections` has no TTL (stale-connection cleanup is a known open issue from the chat-infra review).

**Cost:** storage today ≈ $0.002/mo. At scale, telemetry storage grows unboundedly (search-log alone ≈ ×45 → ~1.5 GB/yr, plus GSI storage doubles parts of it). Real cost is small in dollars but **events + property-views at R=0 are pure waste today**: at scale their writes alone ≈ 300k+ WRU/mo ≈ $0.40/mo... (writes are the cost, not storage — see recommendation 2).

**Recommendation:** (1) Enable TTL (`ttl` attribute, 90 d) on search-log, events, property-views, ws-connections — zero-risk, free, one CLI call per table (written out in 02-quickwins). (2) Decide whether events/property-views are ever going to be read; if not, stop writing them client-side (that's the real saving — the write, not the row). **Rollback:** disable TTL. **Risk:** none for TTL; for stopping writes — confirm no dashboard reads them first (none found in `aws/lambda/router/index.mjs`).

### F3 — REST API where HTTP API would do ($3.50/M vs $1.00/M)

**Evidence:** main API `rentch-api` (g7b9nx11sk) is REST (`get-rest-apis`), billed at USE1-ApiGatewayRequest = $0.34/90d for 97,228 requests — **48% of the account's entire gross bill**. The thumbnail API (`rently-thumb-api`) is already HTTP API, proving the pattern works in this stack. The client's base URL is a single constant (`lib/core/config/app_config.dart:51`).

**Cost:** today $0.11/mo → HTTP API $0.03/mo. **At scale: 1.5M req/mo → $5.25 vs $1.50/mo (H confidence — pure price arithmetic).** Larger benefit is latency: HTTP APIs shave ~10–30 ms of gateway overhead.

**Recommendation:** create an HTTP API with a `$default` route → `rentch-router` + JWT/Lambda authorizer parity, test against a staging stage, then flip `AWS_API_URL` via `--dart-define`. Caveats to verify before cutover: the router relies on REST-style event shape (`event.requestContext.resourcePath` etc.) — HTTP API v2 payload differs; use payload format **1.0** on the integration to keep the Lambda unchanged. **Rollback:** flip the base URL back (old REST API stays up during transition). **Risk:** M — authorizer semantics differ (REST TOKEN authorizer → HTTP API request authorizer); requires an end-to-end auth test. Effort M.

### F4 — Media: 4 MB average objects, raw .mov videos in STANDARD forever

**Evidence:** `rentch-media` = 2.53 GB / 625 objects, **100% STANDARD** (list-objects-v2 StorageClass), no lifecycle rules. Top objects are raw 3D-scan videos: five `.mov` files of 70, 73, 72, 21, 70 MB under `3d-scans/custom-*/` — ≈12% of the bucket in 5 files. These are scan *inputs*; once converted (splat pipeline) the app serves the output, not the source .mov.

**Cost:** today $0.06/mo. At scale (5k MAU, proportional media) ≈ 100+ GB → $2.3/mo STANDARD, plus the real cost: **egress of 4 MB originals on every uncached view** (mitigated only where CloudFront cache hits).

**Recommendation:** (1) Lifecycle rule: `3d-scans/` → Glacier Instant Retrieval after 30 d (source files, rarely re-read) — 68% storage saving on that prefix. (2) Lifecycle rule: abort incomplete multipart uploads after 7 d, bucket-wide (also fixes F6). (3) At upload time, client should ship compressed video (HEVC) — the .mov files look like raw device captures (HYPOTHESIS — requires checking one file's codec). **Rollback:** lifecycle rules are deletable; objects transition back on next PUT. **Risk:** low; GIR retrieval is instant, just pricier per-GB on read.

### F5 — Lambda: all x86_64; three functions worth switching, one mis-sized

**Evidence:** `list-functions`: all 9 functions x86_64. 30-day reality (CloudWatch): router 39,108 inv @ avg 293 ms / p95 893 ms; authorizer 2,841 @ 388 ms; img-resize 69 @ 1.4 s; pano-stitch 13 @ 22.9 s avg (3,008 MB); splat-convert 0 invocations in 30 d.

**Cost:** $0.00 today (free tier). At scale, router+authorizer dominate: ~45× → ~1.9M inv/mo ≈ 140k GB-s ≈ **$2.9/mo x86 → $2.3/mo arm64 (−20%, H confidence on price, M on compatibility)**.

**Recommendation:** arm64 for router/authorizer/ws/broadcaster (pure JS, no native deps in bundles — verify `sharp` in img-resize and OpenCV in pano-stitch have arm64 builds before touching those two). Keep 3,008 MB on pano-stitch (CPU-bound stitching scales with memory). **Not recommended:** shrinking router below 256 MB — avg 293 ms is already CPU-flavored at 256 MB; saving would be ~$1/mo at scale against a p95 regression. Engineering-cost check: this is a 1-line change per function *only if* CI rebuilds bundles for arm64; otherwise defer — $0.6/mo at scale does not justify a toolchain fight.

### F6 — Zombies & hygiene (all measured)

| Item | Evidence | $/mo today | Action |
|---|---|---|---|
| 3 stuck multipart uploads, deploy bucket | `list-multipart-uploads` | ~$0.001 | covered by F4's abort rule |
| 4 empty tables (invoices, reviews, saved-searches, broadcasts) | describe-table ItemCount=0 | $0.00 | keep — on-demand empty tables cost nothing; delete only if features are dead |
| Log retention "Never" on all 9 groups | describe-log-groups | ~$0.001 (23 MB total) | set 30–90 d retention; at scale router ingest (14.3 MB/30d now) ×45 ≈ 650 MB/mo ≈ $0.32 ingest — retention caps storage, not ingest; ingest stays cheap unless DEBUG logging is added |
| CloudFront: main REST API not behind CDN | list-distributions (2 dists: media, thumbs only) | — | fold into F3: put the new HTTP API behind CloudFront or at least enable response compression (see Phase 2) |
| No dev/staging separation | inventory: single set of `rentch-*` | — | risk item, not cost (05-risks.md) |
| Glue catalog (37 req), KMS (4 req) | freetier report | $0.00 | residue, ignore |

### Explicitly not recommended (engineering cost > return)

- **On-demand → provisioned DynamoDB:** breakeven needs sustained >~1.2 WCU/s per table; the busiest table peaks at ~0.03 WCU/s. On-demand is correct today and at 5k MAU for every table except possibly app-state — and F1 removes that load instead. Re-evaluate at 50k MAU.
- **Router monolith decomposition** (7,987 lines, 265 routes): a code-health item, not a cost item — one Lambda with warm starts is *cheaper* than 265 cold-startable functions. Do not split for cost reasons.
- **Multi-region / DR / service mesh:** nothing here justifies it.

---

## PHASE 2 — Client↔server communication

Latency reality check (CloudWatch, 30 d): router avg 293 ms / p95 893 ms; authorizer avg 388 ms / p95 783 ms (TOKEN authorizer, 300 s result cache — so it's off the path for warm sessions). Live probe: unauthenticated request answers in 275 ms round-trip from this machine (401, as designed). End-user p50/p95 per endpoint: **not available — requires client-side RUM or API GW access logs (currently not enabled).**

### C1 — No compression on the main API (the clearest wire win)

**Evidence:** `get-rest-api g7b9nx11sk` → `minimumCompressionSize: null` — API Gateway never compresses responses. The heaviest response is the listings page: default `limit=150` (`aws/lambda/router/index.mjs:2145`), items ~1–2 KB each (media JSON string dominates) → **~150–300 KB of JSON per browse load, uncompressed**. JSON of this shape gzips at roughly 5–8× (estimate, M confidence — repetitive keys and URLs).

**Impact:** ~80% less listing-payload bytes on every browse; faster first paint on cellular; at scale, less API GW/Lambda egress (egress is the dominant per-GB charge once credits lapse). **Fix is one CLI call, reversible instantly:**
```
aws apigateway update-rest-api --rest-api-id g7b9nx11sk \
  --patch-operations op=replace,path=/minimumCompressionSize,value=1024
# + redeploy stage: aws apigateway create-deployment --rest-api-id g7b9nx11sk --stage-name prod
```
Client sends `Accept-Encoding: gzip` already (Dart `http` default). **Rollback:** set value back to null. **Risk:** minimal — verify the app's response parsing after enabling (Dart decodes transparently).

### C2 — Over-fetching: 150 items per page as the default

**Evidence:** `index.mjs:2145` — `limit = query.limit || '150'`, cap 500. The swipe deck consumes items one at a time; a phone screen shows 1–2 cards. The known "search sees only 150" issue is the same constant from the other side: it's simultaneously too big for the wire and too small for full-market search.

**Impact:** every deck refresh moves ~30× more data than the visible UI needs; server-side, each request reads 150 items from DynamoDB (~0.5 RCU each eventually-consistent). At scale: 1.5M requests × over-read = the RRU line (already 745k RRU/90d — the account's #2 usage line) grows linearly with this constant.

**Recommendation:** page the deck at 25 with `lastKey` cursor pagination — **the server already returns `hasMore`/`lastKey` (`pageBody`, index.mjs:3071)**; this is a client-side constant change plus a prefetch-next-page trigger. Server-side search should instead iterate pages internally when filtering (fixes the 150-cap search gap at the same time). **Risk:** low; deck prefetch must fire early enough to avoid visible loading.

### C3 — Embedding bytes: stripped from responses, still paid for in reads

**Evidence:** list/knn/single-item paths all pass through `stripInternal` (index.mjs:3062-3073, 2113-2115 — single-item and knn were patched after shipping raw "forever", per in-code comments). So the *wire* is clean now. But the 768-dim embedding (`EMBED_DIM=768`, index.mjs:161) lives **on the property item itself** (~8–15 KB as DynamoDB number list), so every read of a seeded listing burns 3–4× the RCU of the listing's real payload.

**Impact:** at scale this is the difference between ~$0.4/mo and ~$1.5/mo of RRU (L confidence — depends on cache hit rates), plus slower scans. **Recommendation:** when convenient (not urgent), move embeddings to a side table `rentch-embeddings` keyed by propertyId, read only by the knn path. Note: the 22,497 listings loaded 2026-08-20 have **no embeddings yet** — if/when the re-enrich step runs, write them to the side table instead of inflating 24k property items. **Risk:** knn path touches two tables; M effort.

### C4 — Chat: 3 s polling as the backstop cadence

**Evidence:** `lib/core/services/realtime_chat_service.dart:46-47` — poll every 3 s while active, backing off to 20 s when idle (adaptive poll, shipped 2026-08). A real WebSocket fan-out exists server-side (rentch-ws: 562 invocations, 1,133 WS messages billed /30 d) and carries the push path.

**Impact:** a foregrounded chat screen costs 20 req/min/user against the REST API when the WS is down or unconnected. At 5k MAU with ~5% concurrently in chat: ~250 × 20/min ≈ 7.2M req/mo just from poll — **would dwarf everything else in the account** ($25/mo REST, $7/mo HTTP API — H confidence arithmetic, M on the concurrency guess).

**Recommendation:** poll only while the WS is disconnected, and at 10 s not 3 s; when WS is healthy, poll at 60 s as a reconciliation sweep (the server-id de-dup layer from the chat-infra work already makes this safe). **Risk:** low — WS already carries delivery; the poll is a redundancy layer.

### C5 — Caching posture: good where it exists, absent on the API

**Evidence:** CloudFront media dist uses `Managed-CachingOptimized` (86,400 s TTL, gzip+brotli on); thumb dist `rently-thumb-w` caches 1 year — both correct. The REST API responses carry `Cache-Control` on exactly one route (index.mjs:1138, `public, max-age=300` — the share preview); every JSON API response else is uncacheable. CloudFront cache hit ratio: **not available — requires enabling CloudFront standard logs or the cache-statistics report window.**

**Recommendation:** add `Cache-Control: private, max-age=60` + ETag to the read-mostly public reads (listings browse, nearby layers, market signals). Dart's http client won't cache by itself, but the app's existing SafeImage/cached_network_image layer honors it for media; for JSON, an app-side TTL cache keyed on URL is the practical route (one exists for market signals per the cost-cut work — extend it to browse pages). **Effort:** S–M.

### C6 — Retries, keep-alive, cold starts, SDK chattiness (checked, mostly healthy)

- **Retry storms:** none possible — `aws_client.dart` contains zero retry logic (grep "retry" = 0 matches). Failures surface immediately. That's storm-safe but UX-brittle; a single retry with jitter on idempotent GETs would be strictly better. Not a cost item.
- **HTTP keep-alive:** Dart `http` reuses connections per client instance; router uses AWS SDK v3 (keep-alive default on). No action.
- **Secrets chattiness:** API keys live in Lambda env vars, not Secrets Manager — zero per-request secret reads. (Tradeoff already known: the 2026-07-03 incident wiped them on rollback — that's a risk finding, not a cost one.)
- **Cold starts:** authorizer avg 388 ms on 2.8k inv/30 d (~95/day → most invocations are cold; its result cache of 300 s keeps it off the hot path). Router p95 893 ms includes cold starts of a 16.8 MB bundle. Slimming the bundle (esbuild tree-shake; the AWS SDK v3 clients are the bulk) would cut cold p95 meaningfully; do it opportunistically, not as a project.
- **N+1:** the app's data layer batches via the deck/page endpoints; no per-card API call pattern found in the providers. No BFF warranted at this scale.

---

## PHASE 3 — Scoring

Savings are quoted at the **modeled 5k-MAU base scenario** (today's net bill is $0.00 — see baseline §1; every "Current $/mo" below is the at-scale projection of the *current* design, not today's bill). Score = (savings × confidence H/M/L=1.0/0.6/0.3) ÷ effort S/M/L=1/3/8.

| # | Finding | Evidence | Current $/mo (at scale) | Est. savings $/mo | Conf | Effort | Risk | Blast radius | Score |
|---|---------|----------|------------------------|-------------------|------|--------|------|--------------|-------|
| F1 | app-state 16 KB full-blob write per action, 55 un-debounced call sites | CW: 75,467 WCU/30d on 120 items; local_storage.dart:129 | ~$300 (range 90–1,400) | ~$285 | M | S | Low — client guard, local copy always kept | app-state sync only | **171** |
| C4 | chat 3 s poll alongside healthy WS | realtime_chat_service.dart:46; WS 1,133 msgs/30d billed | ~$25 | ~$20 | M | S | Low — WS already carries delivery | chat freshness | **12** |
| C1 | no compression on main REST API | get-rest-api: minimumCompressionSize=null | ~$9 egress | ~$7 | M | S | Minimal — one patch op, instant rollback | all API responses | **4.2** |
| F3 | REST API ($3.50/M) instead of HTTP API ($1.00/M) | 48% of gross bill; thumb API proves HTTP works here | $5.25 | $3.75 | H | M | M — authorizer semantics differ | every API call | **1.25** |
| C2 | 150-item default page for a 1-card deck | index.mjs:2145; pageBody already returns lastKey | ~$3 RRU+egress | ~$2 | M | S | Low — prefetch timing | browse deck | **1.2** |
| F2 | TTL disabled everywhere; events+views write-only (R=0) | describe-time-to-live ×22; CW R=0 | ~$1.5 | ~$1.4 | H | S | None (TTL) / verify-no-reader (stop writes) | telemetry tables | **1.4** |
| F4 | media lifecycle absent; 70 MB raw .mov ×5 in STANDARD | list-objects: 100% STANDARD; 3 stuck MPUs | ~$2.3 | ~$1.2 | H | S | Low — GIR is instant-retrieval | 3d-scans prefix | **1.2** |
| C5 | no Cache-Control/ETag on read-mostly JSON | index.mjs: 1 cached route of ~265 | ~$1 | ~$0.6 | M | M | Low — staleness ≤60 s | browse/nearby reads | 0.12 |
| F5 | all Lambdas x86_64 | list-functions | $2.9 compute | $0.6 | M | M | M — native deps in img-resize/pano | per function | 0.12 |
| C3 | 768-dim embedding inflates every property read 3–4× | item scan shows embedding list; EMBED_DIM=768 | ~$1.5 | ~$1 | L | M | M — knn path re-plumb | seeded listings reads | 0.1 |
| F6 | log retention "Never" ×9 groups | describe-log-groups | ~$0.4 | ~$0.3 | H | S | None | logs only | 0.3 |

### Quick Wins (meaningful, S-effort, low-risk, reversible in minutes)

1. **F1a** — hash-guard + debounce on `_saveRemoteState` (client, ~15 lines): kills the #1 line item.
2. **F2** — enable TTL on search-log / events / property-views / ws-connections: 4 CLI calls, zero risk.
3. **C1** — `minimumCompressionSize=1024` + stage redeploy: 1 CLI call.
4. **C4** — poll 3 s→10 s, and 60 s while WS healthy (client constants).
5. **F4b** — bucket-wide abort-incomplete-MPU-after-7d lifecycle on both buckets.
6. **F6** — 90 d retention on all 9 log groups: 9 CLI calls.

Everything else is scheduled work (30/60/90 roadmap), led by F3 (REST→HTTP) — worth doing before traffic grows, cheap to test now, and C2/C5 ride along on the same client release as F1/C4.
