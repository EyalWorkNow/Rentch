#!/usr/bin/env bash
# Create the NO-AUTH provider-callback endpoints on the existing REST API:
#   POST /hooks/morning  → router Lambda (Green Invoice/Grow IPN; HMAC-verified)
#   GET  /hooks/return   → router Lambda (post-payment redirect page)
#
# Targeted API-Gateway CLI only — deliberately NOT CloudFormation (the full-stack
# deploy has wiped secrets before). Idempotent: re-running reuses existing
# resources/methods. Requires: awscli, jq.
#
# Usage:
#   REGION=us-east-1 ACCOUNT=543897290879 API_NAME=rentch-api \
#   FUNCTION=rentch-router STAGE=prod bash aws/billing-webhook-setup.sh
set -uo pipefail
REGION="${REGION:-us-east-1}"
ACCOUNT="${ACCOUNT:-543897290879}"
FUNCTION="${FUNCTION:-rentch-router}"
STAGE="${STAGE:-prod}"
API_ID="${API_ID:-}"

command -v jq >/dev/null || { echo "jq required"; exit 1; }

# ── locate the REST API ──────────────────────────────────────────────────────
if [ -z "$API_ID" ]; then
  API_NAME="${API_NAME:-}"
  APIS=$(aws apigateway get-rest-apis --region "$REGION" --output json)
  if [ -n "$API_NAME" ]; then
    API_ID=$(echo "$APIS" | jq -r --arg n "$API_NAME" '.items[]|select(.name==$n)|.id' | head -1)
  fi
  if [ -z "$API_ID" ] || [ "$API_ID" = "null" ]; then
    echo "Could not auto-find the REST API. Available:"
    echo "$APIS" | jq -r '.items[]|"  \(.id)\t\(.name)"'
    echo "Re-run with API_ID=<id>."
    exit 1
  fi
fi
echo "REST API: $API_ID   Function: $FUNCTION   Stage: $STAGE"

FN_ARN="arn:aws:lambda:${REGION}:${ACCOUNT}:function:${FUNCTION}"
INTEG_URI="arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${FN_ARN}/invocations"

ROOT_ID=$(aws apigateway get-resources --region "$REGION" --rest-api-id "$API_ID" --output json \
  | jq -r '.items[]|select(.path=="/")|.id')

# get-or-create a child resource; echoes its id
resource() { # parent_id  path_part  full_path
  local parent="$1" part="$2" full="$3"
  local id
  id=$(aws apigateway get-resources --region "$REGION" --rest-api-id "$API_ID" --limit 500 --output json \
    | jq -r --arg p "$full" '.items[]|select(.path==$p)|.id')
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    id=$(aws apigateway create-resource --region "$REGION" --rest-api-id "$API_ID" \
      --parent-id "$parent" --path-part "$part" --output json | jq -r '.id')
    echo "  created $full ($id)" >&2
  else
    echo "  reuse   $full ($id)" >&2
  fi
  echo "$id"
}

HOOKS_ID=$(resource "$ROOT_ID" "hooks" "/hooks")
MORNING_ID=$(resource "$HOOKS_ID" "morning" "/hooks/morning")
RETURN_ID=$(resource "$HOOKS_ID" "return" "/hooks/return")

# put a NONE-auth method + AWS_PROXY integration (idempotent via || true)
wire() { # resource_id  http_method
  local rid="$1" verb="$2"
  aws apigateway put-method --region "$REGION" --rest-api-id "$API_ID" \
    --resource-id "$rid" --http-method "$verb" --authorization-type NONE \
    >/dev/null 2>&1 || echo "  method $verb exists"
  aws apigateway put-integration --region "$REGION" --rest-api-id "$API_ID" \
    --resource-id "$rid" --http-method "$verb" --type AWS_PROXY \
    --integration-http-method POST --uri "$INTEG_URI" >/dev/null
  echo "  wired $verb → router"
}
wire "$MORNING_ID" POST
wire "$RETURN_ID" GET

# allow API Gateway to invoke the router for these paths
aws lambda add-permission --region "$REGION" --function-name "$FUNCTION" \
  --statement-id "apigw-hooks-morning" --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT}:${API_ID}/*/POST/hooks/morning" \
  >/dev/null 2>&1 || echo "  perm morning exists"
aws lambda add-permission --region "$REGION" --function-name "$FUNCTION" \
  --statement-id "apigw-hooks-return" --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT}:${API_ID}/*/GET/hooks/return" \
  >/dev/null 2>&1 || echo "  perm return exists"

# publish
aws apigateway create-deployment --region "$REGION" --rest-api-id "$API_ID" \
  --stage-name "$STAGE" --description "billing hooks" >/dev/null
echo "Deployed to stage '$STAGE'."
echo "  IPN URL   : https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE}/hooks/morning"
echo "  Return URL: https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE}/hooks/return"
