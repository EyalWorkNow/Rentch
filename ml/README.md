# Rently ranker training pipeline (`ml/`)

Phase-1 personalization: turn logged search impressions + outcomes into a small
LightGBM model that the **existing Node Lambda** serves inline. There is **no
Fargate and no separate serving service** — this pipeline only *produces* a JSON
artifact; the scorer lives inside the router Lambda (`lib/model_scorer.mjs`).

## The loop

```
users search/swipe
      │  (impression + outcome rows logged to SEARCH_LOG_TABLE)
      ▼
GET /ml/export   ── admin-only, joins impressions↔outcomes into labeled rows
      │           { rows: [{ features, rank, score, label }], count }
      ▼
ml/train.py      ── vectorize → LightGBM binary classifier → dump_model() JSON
      │           emits model.json (+ model.meta.json)
      ▼
S3 (RANK_MODEL_*) ── uploaded by .github/workflows/train-ranker.yml (cron)
      ▼
Node Lambda scorer reads it via RANK_MODEL_S3 and blends P(like) into ranking
```

## The artifact (LOCKED contract)

- Format: **LightGBM `booster.dump_model()` JSON** — not pickle, not ONNX. The JS
  scorer parses this shape (`tree_info`, split thresholds, leaf values) directly.
- Feature vector order (`RANK_FEATURE_ORDER`, positional ABI between trainer and
  scorer):

  ```
  [freshness, popularity, completeness, priceFit, neighborhood, semantic, community_fit]
  ```

  These are exactly the cohort weight keys in `aws/lambda/router/lib/ranking.mjs`.
  Each training row's `features` is an object keyed by these names; the trainer
  vectorizes in this order, missing key → `0.0`.
- Target: `label` (1 = a lead / like-positive outcome: like, superlike, contact).
- Sidecar `model.meta.json`: `{ featureOrder, trainedAt, rows, auc }`.
  `trainedAt` is passed in via `--now` (no wall clock) for reproducibility.

## Cold-start guard (this is DORMANT at pre-launch — intended)

Before there is enough labeled traffic, training a tree model is dishonest. So
`train.py`:

- emits **nothing** and exits 0 if `rows < 200` (`--min-rows`), or
- emits **nothing** and exits 0 if only one class is present in the labels.

When no `model.json` exists in S3, the JS scorer stays on its **pure-linear
cohort weights**. That is the correct pre-launch state — the pipeline is wired
and CI-green, but produces no model until real data justifies it.

## Run the selfcheck locally

Proves the pipeline end-to-end on separable synthetic data (no real data needed):

```bash
pip install -r ml/requirements.txt
bash ml/selfcheck.sh
```

It generates 2000 synthetic rows (label correlates with priceFit + popularity +
community_fit), trains, and asserts: `model.json` exists, it is a `dump_model()`
artifact with the correct feature order, and holdout **AUC > 0.7**. It also prints
the `model.json` size.

## Run against real data manually

```bash
curl -fsS "$ML_EXPORT_URL" -H "Authorization: Bearer $ML_EXPORT_TOKEN" > rows.json
python ml/train.py --input rows.json --output model.json --now "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
aws s3 cp model.json "s3://$RANK_MODEL_BUCKET/$RANK_MODEL_KEY"
```

## CI

`.github/workflows/train-ranker.yml` runs daily (cron) + on manual dispatch. It
always runs the offline selfcheck, then pulls `/ml/export`, trains, and uploads
to S3. **It is safe to exist un-configured**: every secret-dependent step is
guarded, so with no secrets set the job runs the selfcheck and skips the rest
(green). Wire these repo secrets to arm it:

| secret | purpose |
| --- | --- |
| `ML_EXPORT_URL` | full URL of `GET /ml/export` |
| `ML_EXPORT_TOKEN` | admin bearer token (notif-admin uid) |
| `RANK_MODEL_BUCKET` / `RANK_MODEL_KEY` | S3 destination (key must match the scorer's `RANK_MODEL_S3`) |
| `AWS_ROLE_ARN` / `AWS_REGION` | OIDC role with `s3:PutObject` on the key |

## Files

- `train.py` — load → vectorize → cold-start guard → LightGBM → `dump_model()` JSON + meta
- `gen_synthetic.py` — synthetic rows in `/ml/export` shape (selfcheck only)
- `selfcheck.sh` — end-to-end smoke test with AUC assertion
- `requirements.txt` — lightgbm, numpy, scikit-learn
