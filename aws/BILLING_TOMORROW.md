# Billing — go-live runbook for tomorrow

Everything below the line is DONE and live in prod. Tomorrow = 4 short steps.

## ✅ Already live (done today)
- Router code deployed (billing routes + `/hooks/*` webhook + gate **dormant** via `BILLING_ENFORCE`).
- DynamoDB tables `rentch-subscriptions` + `rentch-invoices` created.
- No-auth webhook endpoints live: IPN `…/prod/hooks/morning`, return `…/prod/hooks/return`.
- Cron `rentch-billing-cron` deployed + scheduled daily 03:00 UTC (dry-run OK).
- Integration verified against the REAL Morning API: token ✓, client ✓, payment form ✓ (returns a Grow/Meshulam checkout URL). Terminal id: `3b456f23-e570-43a5-aae0-0cc3061574fe`.
- Webhook is instrumented to LOG the full raw IPN (`IPN_CAPTURE`) so the first real payment reveals the exact format.

## Tomorrow — 4 steps

### 1. Set the Morning env on the router (Console — you)
Lambda → `rentch-router` → Configuration → Environment variables → add (don't delete existing):
| Key | Value |
|---|---|
| `MORNING_API_BASE` | `https://api.greeninvoice.co.il/api/v1` |
| `MORNING_API_KEY` | `fc4b604d-8f79-4c36-a781-56907a398882` |
| `MORNING_API_SECRET` | *(your Morning secret — rotate first!)* |
| `MORNING_PLUGIN_ID` | `3b456f23-e570-43a5-aae0-0cc3061574fe` |
| `MORNING_WEBHOOK_SECRET` | *(any `openssl rand -hex 32`)* |

Then also add the same 5 to `rentch-billing-cron` (it needs Morning creds to charge renewals).

Tell me when done → I verify checkout returns a live URL (direct invoke).

### 2. Confirm the clearing terminal is active
Terminal `3b456f23` showed `status:0`. Open one checkout URL with a card — if it declines, finish the Grow terminal approval in the Morning dashboard.

### 3. Point the IPN at us (Morning/Grow dashboard — you)
Set the notify/IPN URL to:
`https://g7b9nx11sk.execute-api.us-east-1.amazonaws.com/prod/hooks/morning`

### 4. One test payment → I lock the webhook
Do one real (small) subscription payment from the app or a checkout URL. Then:
- I run `bash aws/billing-ipn-logs.sh` to read the exact IPN Meshulam sent.
- I finalise `verifyWebhook` + `parseWebhook` to that format, redeploy.
- Re-trigger → the subscription activates + invoice is issued. Loop confirmed.

### Then flip the paywall ON (when you're ready)
Add `BILLING_ENFORCE=1` to the router env, and run the grandfather backfill once:
```
aws lambda invoke --region us-east-1 --function-name rentch-billing-cron \
  --payload '{"mode":"grandfather","days":30}' /dev/stdout
```

## Cleanup / security
- Delete the test client "Rently Test (delete me)" in Morning.
- Rotate the Morning secret (it was pasted in chat).
