# 30 / 60 / 90 Roadmap

Savings targets are the **at-scale (5k MAU) run-rate defused**, since today's net bill is $0.00. "Defused" = the monthly cost the current design would have produced at that scale, eliminated before it ever gets billed. Conservative/base/aggressive figures per line are in savings-model.csv.

## Day 0–30 — Quick wins + client release

| Action | Owner surface | Defused $/mo (base) |
|---|---|---|
| F1a+F1b app-state hash-guard + debounce | client (1 release) | 285 |
| C4 poll cadence 10 s/60 s | same client release | 20 |
| C2 deck pagination limit=25 | same client release | 2 |
| F2 TTL ×4 tables + `ttl` stamping | CLI + router | 1.4 |
| C1 API gzip | CLI | 7 |
| F4a+b lifecycle (GIR + MPU abort) | CLI | 1.2 |
| F6 log retention 90 d | CLI | 0.3 |

**Milestone 1 target: ~$317/mo defused.** Verification: CloudWatch — app-state WCU/day drops >90%; API GW payload sizes down ~5×.

## Day 31–60 — The API migration

| Action | Notes | Defused $/mo |
|---|---|---|
| F3 REST→HTTP API | New HTTP API, payload format 1.0 (router unchanged), request-authorizer port of the Firebase TOKEN authorizer, staging stage, then flip `AWS_API_URL` dart-define. Keep REST API alive 30 d as rollback. | 3.75 |
| C5 Cache-Control + ETag on read-mostly routes | Ride the router deploy that F3's testing already requires | 0.6 |
| F2b telemetry emitters behind flag (if no dashboard planned) | client flag | 1 |

**Milestone 2 target: cumulative ~$322/mo defused** + gateway latency −10–30 ms.

## Day 61–90 — Structural, only-if-cheap

| Action | Gate |
|---|---|
| C3 embeddings → side table | Do **as part of** the pending re-enrich of the 22,497 new listings — same job, zero extra migration. Skip if re-enrich isn't happening. |
| F5 arm64 for router/authorizer/ws/broadcaster | Only if the build pipeline produces arm64 bundles without a toolchain fight; else drop permanently ($0.6/mo does not buy a CI project). |
| Import-to-IaC path | Not a cost item — a risk item (see 05-risks). Start by `aws cloudformation detect-stack-drift` and re-sync template.yaml env-var handling so the 2026-07-03 secret-wipe class of incident can't recur. |
| Guardrails live (04-guardrails) | Budgets + anomaly alerts — do in week 1, listed here as the checkpoint that they're on. |

**Milestone 3: cumulative ~$324/mo defused at 5k MAU; ~$1.4k/mo in the aggressive scenario.** The number that matters more: the account's cost curve becomes ~linear in real usage instead of write-amplified.

## Explicitly not on the roadmap (engineering cost > return)

Router decomposition, provisioned capacity, multi-region, containers/Kubernetes, Savings Plans (no commit-eligible spend). Re-evaluate all at 50k MAU.
