#!/usr/bin/env python3
"""Emit N synthetic training rows in the exact /ml/export shape, on stdout.

The label carries a learnable-but-noisy signal (mostly priceFit + popularity,
with a community_fit nudge) so the whole pipeline is testable end-to-end without
any real logged data. This is ONLY for selfcheck/CI smoke — never a data source
for a real model.

Usage:  python gen_synthetic.py 2000 > rows.json
"""
import json
import random
import sys

RANK_FEATURE_ORDER = [
    "freshness",
    "popularity",
    "completeness",
    "priceFit",
    "neighborhood",
    "semantic",
    "community_fit",
]


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 42
    rng = random.Random(seed)

    rows = []
    for i in range(n):
        feats = {name: round(rng.random(), 4) for name in RANK_FEATURE_ORDER}
        # Learnable signal: a like is driven mostly by price fit + popularity,
        # with a small community_fit contribution. Logistic-ish with noise so
        # the classes overlap (AUC is high but not a trivial 1.0).
        z = (2.6 * feats["priceFit"]
             + 1.8 * feats["popularity"]
             + 0.9 * feats["community_fit"]
             - 2.4
             + rng.gauss(0, 0.45))
        p = 1.0 / (1.0 + pow(2.718281828, -z))
        label = 1 if rng.random() < p else 0
        rows.append({
            "features": feats,
            "rank": i % 20,
            "score": round(sum(feats.values()) / len(feats), 4),
            "label": label,
        })

    json.dump({"rows": rows, "count": len(rows)}, sys.stdout)


if __name__ == "__main__":
    main()
