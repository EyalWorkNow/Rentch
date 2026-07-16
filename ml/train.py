#!/usr/bin/env python3
"""Train the Rently listing-ranker and emit a LightGBM dump_model() JSON.

The Node Lambda scorer (lib/model_scorer.mjs, dormant until this runs) loads the
emitted model.json — the artifact format is LightGBM `booster.dump_model()`, no
pickle, no ONNX. This script only PRODUCES that JSON; serving stays inside the
existing Node Lambda. No Fargate, no separate serving service.

Input: the exact shape of `GET /ml/export` → { rows: [{features, rank, score,
label}], count }. Each row.features is an object keyed by RANK_FEATURE_ORDER;
we vectorise in that locked order (missing key → 0.0). y = row.label (1 = a
lead/like-positive outcome).

Cold-start guard: below MIN_ROWS labeled rows, or only one class present, we
print a clear message and emit NOTHING (exit 0). The JS scorer then stays on its
pure-linear cohort weights. That is the intended pre-launch behaviour.

Usage:
    python train.py --input rows.json --output model.json --now 2026-07-16T00:00:00Z
    curl "$ML_EXPORT_URL" -H "Authorization: Bearer $TOK" | python train.py --output model.json
"""
import argparse
import json
import sys

# LOCKED CONTRACT — must byte-for-byte match RANK_FEATURE_ORDER in the JS scorer
# (lib/model_scorer.mjs) and the cohort weight keys in aws/lambda/router/lib/
# ranking.mjs. The trained booster's feature indices are positional, so this
# order is the ABI between trainer and scorer. Do not reorder.
RANK_FEATURE_ORDER = [
    "freshness",
    "popularity",
    "completeness",
    "priceFit",
    "neighborhood",
    "semantic",
    "community_fit",
]

MIN_ROWS = 200  # cold-start floor: below this we do not train (dormant)


def _load(input_path):
    """Read the /ml/export payload from a file or stdin. Returns the rows list."""
    if input_path and input_path != "-":
        with open(input_path, "r", encoding="utf-8") as fh:
            payload = json.load(fh)
    else:
        payload = json.load(sys.stdin)
    if isinstance(payload, list):
        return payload
    return payload.get("rows", []) or []


def vectorize(rows):
    """rows → (X, y). Missing feature key → 0.0, non-numeric → 0.0."""
    import numpy as np

    X, y = [], []
    for r in rows:
        feats = r.get("features") or {}
        vec = []
        for name in RANK_FEATURE_ORDER:
            v = feats.get(name, 0.0)
            try:
                v = float(v)
            except (TypeError, ValueError):
                v = 0.0
            if v != v:  # NaN
                v = 0.0
            vec.append(v)
        X.append(vec)
        try:
            label = int(r.get("label", 0))
        except (TypeError, ValueError):
            label = 0
        y.append(1 if label == 1 else 0)
    return np.asarray(X, dtype="float64"), np.asarray(y, dtype="int32")


def main():
    ap = argparse.ArgumentParser(description="Train Rently ranker → LightGBM dump_model JSON")
    ap.add_argument("--input", default="-", help="rows JSON file (/ml/export shape) or '-' for stdin")
    ap.add_argument("--output", default="model.json", help="path for the dump_model() JSON")
    ap.add_argument("--meta", default=None, help="sidecar meta path (default: <output>.meta.json)")
    ap.add_argument("--now", required=True, help="ISO timestamp for trainedAt (reproducible; no wall clock)")
    ap.add_argument("--min-rows", type=int, default=MIN_ROWS, help="cold-start floor")
    args = ap.parse_args()

    rows = _load(args.input)
    n = len(rows)

    import numpy as np

    X, y = vectorize(rows)
    classes = set(np.unique(y).tolist()) if n else set()

    # ── Cold-start guard: honest dormant behaviour ──────────────────────────
    if n < args.min_rows:
        print(f"[cold-start] {n} rows < {args.min_rows} floor — NOT training. "
              f"JS scorer stays on pure-linear cohort weights.")
        return 0
    if len(classes) < 2:
        print(f"[cold-start] only one class present in labels ({classes}) — NOT "
              f"training. JS scorer stays on pure-linear cohort weights.")
        return 0

    import lightgbm as lgb
    from sklearn.metrics import roc_auc_score
    from sklearn.model_selection import train_test_split

    # Stratified holdout so AUC is honest and both classes appear in valid set.
    X_tr, X_val, y_tr, y_val = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    dtrain = lgb.Dataset(X_tr, label=y_tr, feature_name=list(RANK_FEATURE_ORDER))
    dvalid = lgb.Dataset(X_val, label=y_val, reference=dtrain)

    params = {
        "objective": "binary",
        "metric": "auc",
        "num_leaves": 15,
        "learning_rate": 0.05,
        "feature_fraction": 0.9,
        "bagging_fraction": 0.9,
        "bagging_freq": 1,
        "min_data_in_leaf": 20,
        "verbose": -1,
        "seed": 42,
    }

    booster = lgb.train(
        params,
        dtrain,
        num_boost_round=100,
        valid_sets=[dvalid],
        callbacks=[lgb.early_stopping(stopping_rounds=15, verbose=False)],
    )

    preds = booster.predict(X_val, num_iteration=booster.best_iteration)
    auc = float(roc_auc_score(y_val, preds))
    print(f"[train] rows={n} best_iter={booster.best_iteration} holdout_auc={auc:.4f}")

    # ── Emit LightGBM dump_model() JSON — the LOCKED artifact format ─────────
    model = booster.dump_model()
    with open(args.output, "w", encoding="utf-8") as fh:
        json.dump(model, fh)

    meta_path = args.meta or (args.output.rsplit(".", 1)[0] + ".meta.json")
    meta = {
        "featureOrder": list(RANK_FEATURE_ORDER),
        "trainedAt": args.now,
        "rows": n,
        "auc": auc,
    }
    with open(meta_path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)

    print(f"[emit] {args.output} (dump_model) + {meta_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
