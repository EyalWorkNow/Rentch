# Billing — deploy runbook (manual, secret-safe)

The landlord subscription engine (Morning/Green-Invoice + Grow). **Do NOT run
`aws/deploy.sh`** for this — its CloudFormation path has wiped live secrets
before. Everything below is targeted CLI / code-only.

Region `us-east-1`, account `543897290879`, table prefix `rentch-`,
router function `rentch-router`.

## 0. Secrets (once) — never in code/git/chat
Rotate the Morning secret first (it was pasted in a chat once). Then store it
+ the API key + a webhook secret you generate:
```
aws ssm put-parameter --type SecureString --name /rentch/MORNING_API_KEY    --value '<api key>'    --overwrite
aws ssm put-parameter --type SecureString --name /rentch/MORNING_API_SECRET --value '<new secret>' --overwrite
aws ssm put-parameter --type SecureString --name /rentch/MORNING_WEBHOOK_SECRET --value "$(openssl rand -hex 32)" --overwrite
```

## 1. Router env vars (read-merge-write — never blast the whole env)
Merge the new keys into the router's existing environment so GEMINI/OPENAI/etc.
are preserved:
```
CUR=$(aws lambda get-function-configuration --function-name rentch-router \
      --query 'Environment.Variables' --output json)
ADD=$(jq -n \
  --arg k "$(aws ssm get-parameter --name /rentch/MORNING_API_KEY --with-decryption --query Parameter.Value --output text)" \
  --arg s "$(aws ssm get-parameter --name /rentch/MORNING_API_SECRET --with-decryption --query Parameter.Value --output text)" \
  --arg w "$(aws ssm get-parameter --name /rentch/MORNING_WEBHOOK_SECRET --with-decryption --query Parameter.Value --output text)" \
  '{MORNING_API_KEY:$k, MORNING_API_SECRET:$s, MORNING_WEBHOOK_SECRET:$w,
    MORNING_API_BASE:"https://api.greeninvoice.co.il/api/v1",
    MORNING_PLUGIN_ID:"<grow terminal/plugin id>",
    MORNING_NOTIFY_URL:"https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/hooks/morning",
    MORNING_RETURN_BASE:"https://<api-id>.execute-api.us-east-1.amazonaws.com/prod"}')
MERGED=$(jq -c -s '.[0] * .[1]' <(echo "$CUR") <(echo "$ADD"))
aws lambda update-function-configuration --function-name rentch-router \
  --environment "Variables=$MERGED"
```
(For sandbox testing set `MORNING_API_BASE=https://sandbox.d.greeninvoice.co.il/api/v1`.)

## 2. Tables (once)
```
REGION=us-east-1 PREFIX=rentch- bash aws/billing-setup.sh
```
Creates `rentch-subscriptions` (pk id) and `rentch-invoices` (pk id, GSI
`ownerUserId-issuedAt`). The router IAM role already grants `rentch-*`.

## 3. Router code (code-only — NOT CloudFormation)
Zip the router (index.mjs + lib/ + node_modules) and push code only:
```
cd aws/lambda/router && zip -qr /tmp/router.zip index.mjs lib node_modules
aws lambda update-function-code --function-name rentch-router --zip-file fileb:///tmp/router.zip
```

## 4. No-auth webhook + return endpoints (once)
```
REGION=us-east-1 ACCOUNT=543897290879 API_ID=<rest-api-id> \
FUNCTION=rentch-router STAGE=prod bash aws/billing-webhook-setup.sh
```
Prints the IPN URL (`/hooks/morning`) and return URL (`/hooks/return`). Put the
IPN URL in `MORNING_NOTIFY_URL` (step 1) and configure it as the notify/IPN URL
in the Morning/Grow dashboard, signing with `MORNING_WEBHOOK_SECRET`
(HMAC-SHA256 of the raw body → `X-Morning-Signature`).

## 5. Recurring cron (once)
```
REGION=us-east-1 ACCOUNT=543897290879 ROUTER=rentch-router \
FUNCTION=rentch-billing-cron ROLE_ARN=<router-role-arn> \
bash aws/build-billing-cron.sh
```
Creates the daily EventBridge schedule (03:00 UTC), copying `TABLE_PREFIX` +
`MORNING_*` env from the router. Dry-run once:
`aws lambda invoke --function-name rentch-billing-cron /dev/stdout`.

## 6. Grandfather existing >3 landlords (once, at launch)
```
aws lambda invoke --function-name rentch-billing-cron \
  --payload '{"mode":"grandfather","days":30}' /dev/stdout
```
Stamps a 30-day grace on every owner already holding >3 active properties.

## 7. Client
Ships in the normal app build (no server step). It calls
`/billing/{subscription,checkout,cancel,resume,invoices}` through the existing
`AwsApiClient` (JWT attached automatically).

## Verify
- `GET /billing/subscription` (as a landlord) → `{status:"none", freeLimit:3, canAddProperty:true, ...}`.
- Publish a 4th property without a sub → `402 subscription_required`.
- `POST /billing/checkout {plan:"monthly"}` → `{url}`; pay in sandbox; IPN activates; `GET /billing/subscription` → `status:"active"`.
- `GET /billing/invoices` → the issued document.

## To CONFIRM against the Green Invoice API docs (centralised in `lib/morning.mjs`)
Exact endpoints/fields for `/payments/form`, token charge, the save-token flag,
the IPN signature header, and the recurring/idempotency field. The client is
structured so finalising these is a one-file change.
