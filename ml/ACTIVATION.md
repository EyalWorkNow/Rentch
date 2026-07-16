# Activating the learned ranker

The rank model is **dormant by design** until we have enough real labeled data.
Everything downstream is already built and verified; activation is one command.

## The loop
```
users → /interactions, /search/log, /search/outcome   (collecting now)
      → GET /ml/export        (labeled rows: features + label)
      → ml/train.py           (LightGBM → model.json, dump_model format)
      → S3  s3://$S3_BUCKET/models/rank_model.json
      → rentch-router env RANK_MODEL_S3  → lib/model_scorer.mjs serves it
      → finalScore = α·linear + (1−α)·model   (α = RANK_MODEL_ALPHA, default 0.7)
                                                (treatment A/B bucket only)
```
No model set → **exactly today's pure-linear cohort ranker** (zero behaviour change).

## Readiness threshold
`train.py` refuses to emit a model below **200 labeled rows** or with a single
class present (cold-start guard). Until then, `./activate.sh` reports `DORMANT`
and leaves the Lambda untouched. This is the honest pre-launch state.

## Commands
```bash
pip install -r ml/requirements.txt        # once
./ml/activate.sh                          # pull → train → (if enough data) upload + set env + verify
./ml/deactivate.sh                        # roll back to pure-linear for everyone
RANK_MODEL_ALPHA=0.85 ./ml/activate.sh    # more conservative blend (more linear)
```
Both scripts set Lambda env via **read-merge-write** so existing secrets
(GEMINI/OPENAI/…) are never wiped.

## Automated retrain
`.github/workflows/train-ranker.yml` runs the same pipeline on a daily cron and
uploads `model.json` to S3; the Lambda picks it up on the next cold start (or set
env once via `activate.sh`). Configure the repo secrets it references first.

## Safety notes
- The blend is gated to the **A/B treatment bucket** (`abVariant === 1`), so you
  can measure lift (lead conversion) against the pure-linear control before
  raising exposure.
- Start with a **high α** (more linear) and lower it as the model proves out.
- `model.json` is small (tens–hundreds of KB) and served **inside the Node
  Lambda** — no separate service, no Fargate.
