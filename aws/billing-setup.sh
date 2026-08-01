#!/usr/bin/env bash
# One-time creation of the billing DynamoDB tables — OUT OF BAND (targeted CLI,
# NOT CloudFormation). We deliberately avoid `deploy.sh`/CFN here because the
# full-stack path has wiped live secrets before. Safe to re-run: create-table
# is a no-op ("ResourceInUseException") once the table exists.
#
# Usage:  AWS_PROFILE=... REGION=us-east-1 PREFIX=rentch- bash aws/billing-setup.sh
set -uo pipefail
REGION="${REGION:-us-east-1}"
PREFIX="${PREFIX:-rentch-}"
SUBS="${PREFIX}subscriptions"
INV="${PREFIX}invoices"

echo "Region=$REGION  Prefix=$PREFIX"

# ── subscriptions: pk id (S) = landlord uid, one row per landlord ────────────
aws dynamodb create-table \
  --region "$REGION" \
  --table-name "$SUBS" \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --deletion-protection-enabled \
  2>&1 | grep -v "ResourceInUseException" || echo "  $SUBS already exists (ok)"

# ── invoices: pk id (S) = invoiceId; GSI ownerUserId-issuedAt for per-owner list
aws dynamodb create-table \
  --region "$REGION" \
  --table-name "$INV" \
  --attribute-definitions \
      AttributeName=id,AttributeType=S \
      AttributeName=ownerUserId,AttributeType=S \
      AttributeName=issuedAt,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --global-secondary-indexes \
      '[{"IndexName":"ownerUserId-issuedAt","KeySchema":[{"AttributeName":"ownerUserId","KeyType":"HASH"},{"AttributeName":"issuedAt","KeyType":"RANGE"}],"Projection":{"ProjectionType":"ALL"}}]' \
  --billing-mode PAY_PER_REQUEST \
  --deletion-protection-enabled \
  2>&1 | grep -v "ResourceInUseException" || echo "  $INV already exists (ok)"

echo "Done. Tables: $SUBS , $INV (GSI ownerUserId-issuedAt)."
echo "Note: the router IAM role already grants DynamoDB on ${PREFIX}* — no policy change needed."
