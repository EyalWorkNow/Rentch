# Guardrails — how to not end up here again

Sized for a one-person shop on a ~$0 bill. Everything here is < 1 hour total; skip nothing — these exist precisely because the bill is invisible today (credits) and will not announce itself when it stops being $0.

## 1. Budgets with alerts (the credit-expiry tripwire)

The single most important guardrail: **credits currently mask 100% of spend.** When they lapse, nothing will tell you unless a budget does.

```bash
aws budgets create-budget --account-id 543897290879 --budget '{
  "BudgetName":"rently-monthly","BudgetLimit":{"Amount":"10","Unit":"USD"},
  "TimeUnit":"MONTHLY","BudgetType":"COST",
  "CostTypes":{"IncludeCredit":false,"IncludeRefund":false}}' \
 --notifications-with-subscribers '[
  {"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":50,"ThresholdType":"PERCENTAGE"},
   "Subscribers":[{"SubscriptionType":"EMAIL","Address":"<billing-email>"}]},
  {"Notification":{"NotificationType":"FORECASTED","ComparisonOperator":"GREATER_THAN","Threshold":100,"ThresholdType":"PERCENTAGE"},
   "Subscribers":[{"SubscriptionType":"EMAIL","Address":"<billing-email>"}]}]'
```

Note `IncludeCredit:false` — the budget watches **gross** usage, so it fires while credits still cover the bill, not after. $10/mo threshold ≈ 40× today's run rate: quiet until something real changes (scale, a leak, credit expiry), then loud.

## 2. Cost Anomaly Detection — **already configured, verified working**

Evidence: `ce get-anomaly-monitors` → `Default-Services-Monitor` (created 2026-06-30, evaluated daily) with a DAILY email subscription to the account owner's address. **No action needed.** One caveat: anomaly detection learns from *net* spend patterns; with credits flattening the bill to $0, its signal is weak until real billing starts — which is why the gross-spend budget in §1 is the guardrail that actually fires first. This is what catches "someone shipped a 1 s poll loop" in days instead of at month-end — once there's a spend baseline to deviate from.

## 3. Tagging policy — right-sized version

Full SCP-enforced tagging is org-tooling this account doesn't have (no AWS Organizations detected) and doesn't need at 40 resources. The right-sized rule: **every new resource gets `app=rently` and `component=<router|media|chat|billing|3d>`**, applied in template.yaml's Globals when IaC is re-synced. Then activate the tags as cost-allocation tags (Billing console, one click) so Cost Explorer can group by component. Revisit SCP enforcement if/when a second product or teammate shows up.

## 4. Monthly cost ritual (10 minutes, first of the month)

1. `ce get-cost-and-usage` month-to-date, gross (Usage record type), grouped by SERVICE — compare to last month.
2. CloudWatch: `rentch-app-state` consumed WCU/day (the canary for F1 regressing) and API GW request count.
3. `freetier get-free-tier-usage` — anything >50% of a free-tier limit gets a line in the notes.
4. One question: "did any number move ~2× without a matching product reason?"

Worth automating later as a scheduled Lambda posting to email/Slack; do it manually first — the point is the habit, not the plumbing.

## 5. Cost-per-feature tracking

Premature as a system at this scale. The lightweight substitute: when shipping a feature that adds a **recurring** network/write path (a poll, a sync, a telemetry emitter), add one line to its PR description: expected requests/user/day × payload. The F1 app-state design and the 3 s chat poll would both have been caught at review time by exactly that line.

## 6. Design-review tripwires (the patterns that produced this audit's findings)

- Any client write on a per-gesture path (swipe/scroll/keystroke) → must be debounced or diffed before merge (F1).
- Any `Timer.periodic` against the API → must state its at-scale req/mo in the PR (C4).
- Any new DynamoDB table → TTL decision (on/off + why) required at creation, not later (F2).
- Any new S3 prefix → lifecycle decision at creation (F4).
- Any new log group → retention set in the same deploy (F6).
