#!/usr/bin/env bash
# Roll back the LightGBM rank model → pure-linear ranker.
# Removes RANK_MODEL_S3 + RANK_MODEL_ALPHA from the Lambda env via read-merge-write
# (all other vars/secrets preserved). Safe/idempotent.
set -euo pipefail
FN="${RANK_FN:-rentch-router}"
REGION="${AWS_REGION:-us-east-1}"
PY="${PYTHON:-python3}"

echo "==> Removing model env keys (preserving all others)"
aws lambda get-function-configuration --function-name "$FN" --region "$REGION" \
  --query 'Environment.Variables' --output json > /tmp/_env.json
"$PY" - <<'PY'
import json
env=json.load(open('/tmp/_env.json'))
env.pop('RANK_MODEL_S3',None); env.pop('RANK_MODEL_ALPHA',None)
json.dump({'Variables':env}, open('/tmp/_env_new.json','w'))
PY
aws lambda update-function-configuration --function-name "$FN" --region "$REGION" \
  --environment file:///tmp/_env_new.json >/dev/null
aws lambda wait function-updated --function-name "$FN" --region "$REGION"
rm -f /tmp/_env.json /tmp/_env_new.json
echo "==> Deactivated. Ranker is back to pure-linear (cohort weights) for everyone."
