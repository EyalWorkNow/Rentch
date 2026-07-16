#!/usr/bin/env bash
# Turn-key activation for the LightGBM rank model.
#   collect (already live) -> /ml/export -> train.py -> S3 -> set Lambda env -> verify
# Safe to run ANY time: if there isn't enough labeled data yet, it trains nothing
# and leaves the Lambda untouched (stays on the pure-linear ranker). Idempotent.
#
# Requires: AWS creds with lambda + s3 access, python3 + the ml/ deps installed
# (pip install -r requirements.txt). Run from anywhere: ./ml/activate.sh
set -euo pipefail

FN="${RANK_FN:-rentch-router}"
REGION="${AWS_REGION:-us-east-1}"
ALPHA="${RANK_MODEL_ALPHA:-0.7}"     # blend weight: finalScore = ALPHA*linear + (1-ALPHA)*model
MIN_ROWS="${RANK_MIN_ROWS:-200}"     # cold-start floor; below this we stay dormant
KEY="${RANK_MODEL_KEY:-models/rank_model.json}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="${PYTHON:-python3}"

echo "==> [1/4] Pulling training rows from /ml/export (admin invoke)"
ADMIN_UID="$(aws lambda get-function-configuration --function-name "$FN" --region "$REGION" \
  --query 'Environment.Variables.NOTIF_ADMIN_UID' --output text 2>/dev/null || true)"
[ -z "$ADMIN_UID" ] || [ "$ADMIN_UID" = "None" ] && ADMIN_UID='dR46Nv6L3mN1cyzXwxrubHpdqZi2'
printf '{"httpMethod":"GET","path":"/ml/export","requestContext":{"authorizer":{"uid":"%s"}}}' "$ADMIN_UID" > /tmp/_ml_ex.json
aws lambda invoke --function-name "$FN" --region "$REGION" --payload fileb:///tmp/_ml_ex.json /tmp/_ml_out.json >/dev/null
N="$("$PY" -c "import json;b=json.loads(json.load(open('/tmp/_ml_out.json'))['body']);r=b.get('rows',[]);open('$HERE/rows.json','w').write(json.dumps(r));print(len(r))")"
echo "    rows exported: $N"

echo "==> [2/4] Training (cold-start floor = $MIN_ROWS rows)"
rm -f "$HERE/model.json"
"$PY" "$HERE/train.py" --input "$HERE/rows.json" --output "$HERE/model.json" \
  --min-rows "$MIN_ROWS" --now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || true

if [ ! -s "$HERE/model.json" ]; then
  echo "==> DORMANT: not enough labeled data yet (< $MIN_ROWS rows or single class)."
  echo "    No model produced. Lambda left UNCHANGED (pure-linear ranker). Re-run when data grows."
  exit 0
fi

echo "==> [3/4] Uploading model + activating (read-merge-write env: preserves all existing vars/secrets)"
BUCKET="$(aws lambda get-function-configuration --function-name "$FN" --region "$REGION" \
  --query 'Environment.Variables.S3_BUCKET' --output text)"
aws s3 cp "$HERE/model.json" "s3://$BUCKET/$KEY" --region "$REGION"
# CRITICAL: update-function-configuration REPLACES Environment.Variables wholesale.
# We read current vars, MERGE our two keys, and write back — so secrets survive.
aws lambda get-function-configuration --function-name "$FN" --region "$REGION" \
  --query 'Environment.Variables' --output json > /tmp/_env.json
"$PY" - "$BUCKET/$KEY" "$ALPHA" <<'PY'
import json,sys
env=json.load(open('/tmp/_env.json'))
env['RANK_MODEL_S3']=sys.argv[1]; env['RANK_MODEL_ALPHA']=sys.argv[2]
json.dump({'Variables':env}, open('/tmp/_env_new.json','w'))
PY
aws lambda update-function-configuration --function-name "$FN" --region "$REGION" \
  --environment file:///tmp/_env_new.json >/dev/null
aws lambda wait function-updated --function-name "$FN" --region "$REGION"
rm -f /tmp/_env.json /tmp/_env_new.json

echo "==> [4/4] Verifying model is live for the treatment A/B bucket"
"$PY" -c "import json;open('/tmp/_v.json','w').write(json.dumps({'httpMethod':'GET','path':'/properties','queryStringParameters':{'limit':'1'},'requestContext':{'authorizer':{'uid':'activation-probe'}}}))"
aws lambda invoke --function-name "$FN" --region "$REGION" --payload fileb:///tmp/_v.json /tmp/_vo.json >/dev/null
"$PY" -c "import json;b=json.loads(json.load(open('/tmp/_vo.json'))['body']);print('    abVariant=',b.get('abVariant'),' rankModel(applied)=',b.get('rankModel'))"
echo "==> ACTIVATED. RANK_MODEL_S3=$BUCKET/$KEY  alpha=$ALPHA  (model blend applies to A/B treatment bucket only)."
echo "    To roll back: ./ml/deactivate.sh"
