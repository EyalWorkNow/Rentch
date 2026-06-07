#!/usr/bin/env bash
# Deploys the Rentch AWS backend: packages Lambdas, uploads to S3, runs CloudFormation.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STACK="rentch-backend"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
CODE_BUCKET="rentch-deploy-${ACCOUNT}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Account: $ACCOUNT  Region: $REGION"

# 1. Deploy bucket for Lambda zips
if ! aws s3api head-bucket --bucket "$CODE_BUCKET" --region "$REGION" 2>/dev/null; then
  echo "==> Creating deploy bucket: $CODE_BUCKET"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$CODE_BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$CODE_BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
fi

# 2. Package Lambdas (no node_modules — runtime provides AWS SDK v3)
echo "==> Zipping Lambdas"
cd "$HERE/lambda/router"     && zip -q -j /tmp/router.zip index.mjs
cd "$HERE/lambda/authorizer" && zip -q -j /tmp/authorizer.zip index.mjs

# 3. Upload zips
echo "==> Uploading code"
aws s3 cp /tmp/router.zip     "s3://$CODE_BUCKET/router.zip"     --region "$REGION"
aws s3 cp /tmp/authorizer.zip "s3://$CODE_BUCKET/authorizer.zip" --region "$REGION"

# 4. Deploy CloudFormation
echo "==> Deploying CloudFormation stack: $STACK"
aws cloudformation deploy \
  --region "$REGION" \
  --stack-name "$STACK" \
  --template-file "$HERE/template.yaml" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides CodeBucket="$CODE_BUCKET"

# 5. Force-refresh Lambda code (deploy only updates if S3 key changed)
echo "==> Updating Lambda code"
aws lambda update-function-code --function-name rentch-router \
  --s3-bucket "$CODE_BUCKET" --s3-key router.zip --region "$REGION" >/dev/null 2>&1 || true
aws lambda update-function-code --function-name rentch-authorizer \
  --s3-bucket "$CODE_BUCKET" --s3-key authorizer.zip --region "$REGION" >/dev/null 2>&1 || true

# 6. Output the API URL
API_URL="$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)"
echo ""
echo "==> DONE. API URL:"
echo "    $API_URL"
echo ""
echo "Run the app with:"
echo "    flutter run \\"
echo "      --dart-define=AWS_API_URL=$API_URL \\"
echo "      --dart-define=AWS_REGION=$REGION \\"
echo "      --dart-define=RENTCH_ENABLE_REMOTE_STATE=true \\"
echo "      --dart-define=RENTCH_ENABLE_CLOUD_STORAGE=true"
