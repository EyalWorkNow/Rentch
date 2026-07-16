#!/usr/bin/env bash
# End-to-end smoke test: generate separable synthetic data, train, and assert the
# pipeline produced a real LightGBM dump_model JSON with a decent holdout AUC.
# Proves train.py works without any real logged data. Run from anywhere.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON:-python3}"
ROWS="$(mktemp -t rently_rows.XXXXXX.json)"
MODEL="$(mktemp -t rently_model.XXXXXX.json)"
trap 'rm -f "$ROWS" "$MODEL" "${MODEL%.json}.meta.json"' EXIT

echo "== generating 2000 synthetic rows =="
"$PY" "$DIR/gen_synthetic.py" 2000 > "$ROWS"

echo "== training =="
OUT="$("$PY" "$DIR/train.py" --input "$ROWS" --output "$MODEL" \
        --now "2026-01-01T00:00:00Z" 2>&1)"
echo "$OUT"

# 1) model.json must exist and be non-empty
if [ ! -s "$MODEL" ]; then
  echo "FAIL: model.json was not emitted"; exit 1
fi

# 2) it must be a LightGBM dump_model() JSON (has tree_info + feature_names)
"$PY" - "$MODEL" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
assert "tree_info" in m, "missing tree_info — not a dump_model() artifact"
assert m.get("feature_names") == [
    "freshness","popularity","completeness","priceFit",
    "neighborhood","semantic","community_fit"], "feature order mismatch"
print("OK: dump_model format + feature order verified")
PY

# 3) holdout AUC must clear 0.7 on the separable synthetic data
AUC="$(printf '%s\n' "$OUT" | sed -n 's/.*holdout_auc=\([0-9.]*\).*/\1/p' | tail -1)"
if [ -z "$AUC" ]; then echo "FAIL: no AUC reported"; exit 1; fi
"$PY" - "$AUC" <<'PY'
import sys
auc = float(sys.argv[1])
assert auc > 0.7, f"FAIL: holdout AUC {auc} <= 0.7"
print(f"OK: holdout AUC {auc} > 0.7")
PY

SIZE="$(wc -c < "$MODEL" | tr -d ' ')"
echo "== model.json size: ${SIZE} bytes =="

# Cross-language loop: the JS Lambda scorer must read this Python-trained model.
if command -v node >/dev/null 2>&1; then
  node "$(dirname "$0")/_scorer_check.mjs" "$MODEL"
else
  echo "WARN: node not found — skipping JS scorer cross-check"
fi

echo "SELFCHECK PASSED"
