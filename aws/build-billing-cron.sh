#!/usr/bin/env bash
# Build + deploy the billing-cron Lambda and its daily EventBridge schedule.
# Targeted CLI only (NOT CloudFormation). Copies billing.mjs + morning.mjs from
# the router so the domain logic stays single-source. Env (TABLE_PREFIX +
# MORNING_*) is COPIED from the live router config (read-merge-write) so secrets
# are never re-entered here. Requires: awscli, jq, zip.
#
# Usage:
#   REGION=us-east-1 ACCOUNT=543897290879 ROUTER=rentch-router \
#   FUNCTION=rentch-billing-cron ROLE_ARN=arn:aws:iam::543897290879:role/<router-role> \
#   bash aws/build-billing-cron.sh
set -euo pipefail
REGION="${REGION:-us-east-1}"
ACCOUNT="${ACCOUNT:-543897290879}"
ROUTER="${ROUTER:-rentch-router}"
FUNCTION="${FUNCTION:-rentch-billing-cron}"
SCHEDULE="${SCHEDULE:-cron(0 3 * * ? *)}"   # 03:00 UTC daily
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/lambda/billing-cron"
ROUTER_LIB="$HERE/lambda/router/lib"
command -v jq >/dev/null || { echo "jq required"; exit 1; }

echo "==> assembling $FUNCTION"
cp "$ROUTER_LIB/billing.mjs" "$SRC/billing.mjs"
cp "$ROUTER_LIB/morning.mjs" "$SRC/morning.mjs"
cp "$ROUTER_LIB/subscription_engine.mjs" "$SRC/subscription_engine.mjs"
cp "$ROUTER_LIB/ddb_store.mjs" "$SRC/ddb_store.mjs"
( cd "$SRC" && rm -f function.zip && zip -q -r function.zip index.mjs billing.mjs morning.mjs subscription_engine.mjs ddb_store.mjs )
ZIP="$SRC/function.zip"

# ── copy TABLE_PREFIX + MORNING_* env from the live router (read-merge-write) ──
echo "==> copying env from $ROUTER"
ENV_JSON=$(aws lambda get-function-configuration --region "$REGION" --function-name "$ROUTER" \
  --query 'Environment.Variables' --output json)
CRON_ENV=$(echo "$ENV_JSON" | jq -c '{Variables: ({TABLE_PREFIX: (.TABLE_PREFIX // "rentch-")} + (to_entries|map(select(.key|startswith("MORNING_")))|from_entries))}')
echo "    keys: $(echo "$CRON_ENV" | jq -r '.Variables|keys|join(", ")')"

if aws lambda get-function --region "$REGION" --function-name "$FUNCTION" >/dev/null 2>&1; then
  echo "==> updating code"
  aws lambda update-function-code --region "$REGION" --function-name "$FUNCTION" \
    --zip-file "fileb://$ZIP" >/dev/null
  aws lambda wait function-updated --region "$REGION" --function-name "$FUNCTION"
  aws lambda update-function-configuration --region "$REGION" --function-name "$FUNCTION" \
    --environment "$CRON_ENV" --timeout 300 >/dev/null
else
  [ -n "${ROLE_ARN:-}" ] || { echo "ROLE_ARN required to create the function (reuse the router's role)"; exit 1; }
  echo "==> creating function"
  aws lambda create-function --region "$REGION" --function-name "$FUNCTION" \
    --runtime nodejs20.x --handler index.handler --role "$ROLE_ARN" \
    --timeout 300 --memory-size 256 --zip-file "fileb://$ZIP" \
    --environment "$CRON_ENV" >/dev/null
  aws lambda wait function-active --region "$REGION" --function-name "$FUNCTION"
fi

# ── daily EventBridge schedule ────────────────────────────────────────────────
RULE="${FUNCTION}-daily"
echo "==> schedule $RULE ($SCHEDULE)"
aws events put-rule --region "$REGION" --name "$RULE" \
  --schedule-expression "$SCHEDULE" --state ENABLED >/dev/null
aws lambda add-permission --region "$REGION" --function-name "$FUNCTION" \
  --statement-id "${RULE}-invoke" --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn "arn:aws:events:${REGION}:${ACCOUNT}:rule/${RULE}" >/dev/null 2>&1 || echo "    permission exists"
aws events put-targets --region "$REGION" --rule "$RULE" \
  --targets "Id=1,Arn=arn:aws:lambda:${REGION}:${ACCOUNT}:function:${FUNCTION}" >/dev/null

echo "Done. $FUNCTION scheduled '$SCHEDULE'."
echo "Dry-run once:  aws lambda invoke --region $REGION --function-name $FUNCTION /dev/stdout"
