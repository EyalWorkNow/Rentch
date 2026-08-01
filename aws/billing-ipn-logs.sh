#!/usr/bin/env bash
# Fetch the captured raw IPN (headers + body) from the router logs after a test
# payment, so the exact Meshulam/Green-Invoice webhook format can be finalised.
# Usage:  bash aws/billing-ipn-logs.sh
set -uo pipefail
REGION="${REGION:-us-east-1}"
LG=/aws/lambda/rentch-router
SINCE=$(( ($(date +%s) - 3600) * 1000 ))   # last hour
echo "IPN_CAPTURE entries in the last hour:"
aws logs filter-log-events --region "$REGION" --log-group-name "$LG" \
  --start-time "$SINCE" --filter-pattern 'IPN_CAPTURE' \
  --query 'events[].message' --output text 2>/dev/null || echo "(none yet — do a test payment first)"
