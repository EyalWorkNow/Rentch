# Risks — what could break, what must not be touched

## Must not be touched

1. **`aws/deploy.sh` full-stack deploy — DO NOT RUN.** Proven incident (2026-07-03): a CloudFormation rollback wiped every Lambda env secret on `rentch-router` (GEMINI/LUMA/TELEPORT/KIRI keys). `template.yaml` has drifted hard from prod since. Until the template is re-synced (roadmap day 61–90), all server changes go out as code-only zip swaps, which is the established working path. Any recommendation in this audit that says "CLI call" means exactly that — direct CLI, never a stack update.
2. **The REST API (g7b9nx11sk) must stay up throughout the F3 migration** — it is the hardcoded default in every shipped app build (`app_config.dart:51`). Killing it strands every installed client that hasn't updated. Decommission only after store-version analytics show the old default is dead (months, not weeks).
3. **Lambda env vars are the secret store.** Anything that replaces/redeploys a function config wholesale (as opposed to code-only `update-function-code`) can silently drop keys. Snapshot env vars (`get-function-configuration`) to a local encrypted note before any config-touching change.
4. **`rentch-app-state` rows are user data**, not cache — the remote state is the cross-device source of truth for profiles and custom properties. F1 changes *when* it's written, never *what*. No TTL on this table, ever.

## Changes that need a test first

| Change | Required test | Failure mode if skipped |
|---|---|---|
| F3 REST→HTTP API | End-to-end auth against a staging stage: Firebase JWT through the ported request-authorizer; verify `event` shape with payload format 1.0 on ~10 representative routes (list, single-item, POST /messages, share preview) | Silent 403s for all users, or routes reading `requestContext.resourcePath` getting `undefined` |
| C1 gzip | One authed request per response type (JSON list, single item, HTML share page) confirming client decode | Broken share-preview HTML if content-encoding double-applied by CloudFront thumb path (unlikely — different API) |
| F1 debounce | Kill the app mid-swipe-burst; relaunch on a second device; confirm ≤10 s of state loss and no corruption | Lost likes/profile edits → user-visible data loss (the one thing this audit must not cause) |
| C4 poll change | Two-device chat with WS forcibly disconnected (airplane-mode flap) — measure worst-case message latency = new poll interval | Chat feels dead for up to 60 s if WS-health gating ships buggy |
| F4a GIR transition | Confirm the splat/stitch pipelines never re-read `3d-scans/` sources after conversion (code says no; verify with S3 server-access logs for a week before enabling) | Pipeline re-reads pay GIR retrieval $0.03/GB — trivial cost, but surfaces as latency |
| Load test (only one needed) | Before any marketing push: 100 concurrent users against browse+chat for 10 min. Watch router p95, DDB throttles, WS connection churn | The 300 s router timeout + on-demand tables will absorb a lot, but the authorizer (cold-start heavy) is the likely first bottleneck |

## Structural risks (not cost, but found while auditing)

- **No dev/staging environment** — every experiment runs against production tables. Cheapest fix: a `TABLE_PREFIX=dev-` clone of the router + tables (on-demand empty tables are free). Do before the next risky schema change, not after it.
- **Single IAM user with broad rights doing everything** (deploys, audits, bulk loads). At minimum, enable MFA and create a read-only profile for analysis work like this audit.
- **22,497 scraped listings now in prod** (loaded 2026-08-20): sourced from yad2 with contact names/phones in the source file. The loader dropped contact fields (verified: item schema has no phone/contact attributes), but `sourceUrl` links remain. If listings display publicly, confirm the product/legal position on scraped inventory before scale marketing.
- **ItemCount-based features** (dashboard counts, "X listings" badges) will jump ~15× when DynamoDB's stale ItemCount catches up to the bulk load — cosmetic, but expect it.

## Rollback summary (fastest path per change)

Every quick win: single CLI call or one-line client revert — under 5 minutes each, all listed inline in 02-quickwins.md. F3 is the only change with a real rollback window: keep the REST API warm and flip `AWS_API_URL` back via a client hotfix release.
