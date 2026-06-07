#!/usr/bin/env bash
# Seeds rentch-properties from the bundled JSON asset into DynamoDB.
# Run AFTER deploy.sh succeeds. Requires DynamoDB write permission.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
TABLE="rentch-properties"
SRC="$(cd "$(dirname "$0")/.." && pwd)/assets/data/proxy_listings.json"
TMP="$(mktemp -d)"

echo "==> Transforming $SRC → DynamoDB batch files"
python3 - "$SRC" "$TMP" "$TABLE" <<'PY'
import json, sys, os
src, tmp, table = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(src))

def s(v): return {"S": str(v)} if v is not None and str(v) != "" else None
def n(v):
    try:
        return {"N": str(v)}
    except Exception:
        return None

now = "2026-01-01T00:00:00Z"
batch, files = [], 0
def flush():
    global batch, files
    if not batch: return
    out = os.path.join(tmp, f"batch_{files}.json")
    json.dump({table: batch}, open(out, "w"))
    files += 1
    batch = []

for i, p in enumerate(data):
    pid = str(p.get("id") or f"seed-{i}")
    item = {
        "id": {"S": pid},
        "propertyId": {"S": pid},
        "status": {"S": "active"},
        "createdAt": {"S": now},
        "price": n(p.get("price", 0)) or {"N": "0"},
        "rooms": n(p.get("rooms", 0)) or {"N": "0"},
        "sizeM2": n(p.get("sizeM2", 0)) or {"N": "0"},
        "city": s(p.get("city")) or {"S": ""},
        "neighborhood": s(p.get("neighborhood")) or {"S": ""},
        "street": s(p.get("street")) or {"S": ""},
        "propertyType": s(p.get("propertyType")) or {"S": ""},
        "floor": s(p.get("floor")) or {"S": ""},
        "entryDate": s(p.get("entryDate")) or {"S": ""},
        "media": {"S": json.dumps(p.get("media", []), ensure_ascii=False)},
        "features": {"S": json.dumps(p.get("features", []), ensure_ascii=False)},
        "lat": n(p.get("lat", 0)) or {"N": "0"},
        "lon": n(p.get("lon", 0)) or {"N": "0"},
        "sourceUrl": s(p.get("url")) or {"S": ""},
    }
    batch.append({"PutRequest": {"Item": item}})
    if len(batch) == 25:
        flush()
flush()
print(files)
PY

COUNT=$(ls "$TMP"/batch_*.json 2>/dev/null | wc -l | tr -d ' ')
echo "==> Writing $COUNT batches (25 items each) to $TABLE"
i=0
for f in "$TMP"/batch_*.json; do
  aws dynamodb batch-write-item --request-items "file://$f" --region "$REGION" >/dev/null
  i=$((i+1))
  if [ $((i % 10)) -eq 0 ]; then echo "    ...$i/$COUNT batches"; fi
done

rm -rf "$TMP"
echo "==> Seed complete: ~$((COUNT * 25)) properties in $TABLE"
