#!/usr/bin/env bash
# Deploys the OpenCV panorama stitcher (zip-based Python Lambda — no Docker) and
# the router's new /panorama routes. Run after deploy.sh, or standalone.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STACK="rentch-backend"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
CODE_BUCKET="rentch-deploy-${ACCOUNT}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Account: $ACCOUNT  Region: $REGION"

# 1. Build the stitcher zip (Python + linux opencv/numpy)
bash "$HERE/build-pano-zip.sh"

# 2. Package the router (carries the new /panorama routes)
zip -q -j /tmp/router.zip "$HERE/lambda/router/index.mjs"

# 3. Upload both
aws s3 cp /tmp/pano-stitch.zip "s3://$CODE_BUCKET/pano-stitch.zip" --region "$REGION"
aws s3 cp /tmp/router.zip "s3://$CODE_BUCKET/router.zip" --region "$REGION"

# 4. Deploy CloudFormation (creates the stitcher Lambda + role, wires the router)
aws cloudformation deploy \
  --region "$REGION" \
  --stack-name "$STACK" \
  --template-file "$HERE/template.yaml" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides CodeBucket="$CODE_BUCKET"

# 5. Force-refresh code (deploy only updates if the S3 key changed)
aws lambda update-function-code --function-name rentch-pano-stitch \
  --s3-bucket "$CODE_BUCKET" --s3-key pano-stitch.zip --region "$REGION" >/dev/null
aws lambda update-function-code --function-name rentch-router \
  --s3-bucket "$CODE_BUCKET" --s3-key router.zip --region "$REGION" >/dev/null

echo "==> DONE. Stitcher live: rentch-pano-stitch"
