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

# 2. Package the router (carries the new /panorama + /scan3d routes). The router
#    now has a runtime dependency (adm-zip, to unzip KIRI's model bundle), so we
#    bundle the WHOLE router dir — index.mjs + package.json + node_modules — with
#    index.mjs at the zip root (handler stays index.handler), instead of zipping
#    the single file. Re-create the zip fresh each time.
rm -f /tmp/router.zip
( cd "$HERE/lambda/router" && zip -q -r -X /tmp/router.zip index.mjs lib package.json node_modules )
unzip -l /tmp/router.zip | grep -q 'lib/ranking.mjs' \
  || { echo "FATAL: router.zip missing lib/ — aborting deploy"; exit 1; }

# 3. Upload both
aws s3 cp /tmp/pano-stitch.zip "s3://$CODE_BUCKET/pano-stitch.zip" --region "$REGION"
aws s3 cp /tmp/router.zip "s3://$CODE_BUCKET/router.zip" --region "$REGION"

# 3b. Preserve router secrets across the CFN deploy. The template now declares
#     GEMINI_API_KEY etc. as NoEcho params (default ''); without this, a deploy
#     would reset the router env to '' and wipe a manually-set key (which is
#     exactly what took the assistant offline). Carry the LIVE value forward, and
#     let a shell env var override it. Set the key ONCE (shell env on the next
#     deploy, or `aws lambda update-function-configuration`) and it survives.
live_secret() {  # $1 = env var name → current live value on rentch-router ('' if unset)
  local v
  v="$(aws lambda get-function-configuration --region "$REGION" \
        --function-name rentch-router \
        --query "Environment.Variables.$1" --output text 2>/dev/null || true)"
  [ "$v" = "None" ] && v=""
  printf '%s' "$v"
}
GEMINI_API_KEY="${GEMINI_API_KEY:-$(live_secret GEMINI_API_KEY)}"
GEMINI_LIVE_API_KEY="${GEMINI_LIVE_API_KEY:-$(live_secret GEMINI_LIVE_API_KEY)}"
LUMA_API_KEY="${LUMA_API_KEY:-$(live_secret LUMA_API_KEY)}"
TELEPORT_CLIENT_ID="${TELEPORT_CLIENT_ID:-$(live_secret TELEPORT_CLIENT_ID)}"
TELEPORT_CLIENT_SECRET="${TELEPORT_CLIENT_SECRET:-$(live_secret TELEPORT_CLIENT_SECRET)}"
KIRI_API_KEY="${KIRI_API_KEY:-$(live_secret KIRI_API_KEY)}"
[ -z "$GEMINI_API_KEY" ] && echo "WARNING: GEMINI_API_KEY is empty — the assistant + /assistant/explain will be offline. Set it in your shell before deploying or via update-function-configuration." >&2

# 4. Deploy CloudFormation (creates the stitcher Lambda + role, wires the router)
aws cloudformation deploy \
  --region "$REGION" \
  --stack-name "$STACK" \
  --template-file "$HERE/template.yaml" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides CodeBucket="$CODE_BUCKET" \
    GeminiApiKey="$GEMINI_API_KEY" \
    GeminiLiveApiKey="$GEMINI_LIVE_API_KEY" \
    LumaApiKey="$LUMA_API_KEY" \
    TeleportClientId="$TELEPORT_CLIENT_ID" \
    TeleportClientSecret="$TELEPORT_CLIENT_SECRET" \
    KiriApiKey="$KIRI_API_KEY"

# 5. Force-refresh code (deploy only updates if the S3 key changed)
aws lambda update-function-code --function-name rentch-pano-stitch \
  --s3-bucket "$CODE_BUCKET" --s3-key pano-stitch.zip --region "$REGION" >/dev/null
aws lambda update-function-code --function-name rentch-router \
  --s3-bucket "$CODE_BUCKET" --s3-key router.zip --region "$REGION" >/dev/null

echo "==> DONE. Stitcher live: rentch-pano-stitch"
