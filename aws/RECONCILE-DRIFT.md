# Safe template-drift reconciliation runbook

The deployed `rentch-backend` stack drifted from `aws/template.yaml`:

- The **deployed** template does NOT manage the API-key secrets; the 9 live
  Lambda env vars (incl. GEMINI/OPENAI/KIRI keys) were set **out-of-band** via
  the CLI. So **any** CFN update that touches RouterFunction re-applies the
  template's env and **wipes the out-of-band secrets** — this is what happened
  on 2026-07-03 (stack left in `UPDATE_ROLLBACK_COMPLETE`).
- The on-disk `aws/template.yaml` is a newer, never-successfully-deployed
  variant whose secret params have empty defaults → deploying it silently wipes.
- Several tables (persona, matches, search-log, interactions, …) exist in prod
  but are **out-of-band** (not in the CFN stack). CFN won't touch them — they are
  safe as long as the template doesn't try to create them.

`aws/template.reconciled.yaml` fixes this. It is the **deployed template**
(ground truth) plus three surgical safety changes ONLY:

1. **Secret params `GeminiApiKey` / `OpenAiApiKey` / `KiriApiKey`** — `NoEcho`,
   **no `Default`** → a deploy without them **fails loudly instead of wiping**.
2. **RouterFunction env owns all 9 live vars** (secrets via `!Ref` those params)
   → CFN owns the full env, so no more out-of-band drift / silent drops.
3. **`DeletionPolicy: Retain` + `UpdateReplacePolicy: Retain` on all 12 data
   resources** (11 tables + MediaBucket) → CFN can **never delete data**.

Nothing else changed. Out-of-band tables stay out of the template (safe).

---

## ⚠️ Before anything — capture current secret values

The reconciled env is driven by the SSM values you set below, so they MUST equal
the **current live** secret values (else the deploy changes the keys). Grab them
from wherever you keep them (password manager / the `/tmp/restore_gemini_key.sh`
from the incident). Do NOT proceed with guessed values.

## Step 1 — Put the current secrets into SSM (SecureString), once

```bash
aws ssm put-parameter --region us-east-1 --type SecureString --overwrite \
  --name /rentch/GEMINI_API_KEY --value '<CURRENT GEMINI KEY>'
aws ssm put-parameter --region us-east-1 --type SecureString --overwrite \
  --name /rentch/OPENAI_API_KEY --value '<CURRENT OPENAI KEY>'
aws ssm put-parameter --region us-east-1 --type SecureString --overwrite \
  --name /rentch/KIRI_API_KEY   --value '<CURRENT KIRI KEY>'
```

## Step 2 — Create a CHANGE SET (does NOT apply anything yet)

```bash
cd aws
GEMINI=$(aws ssm get-parameter --region us-east-1 --with-decryption --name /rentch/GEMINI_API_KEY --query Parameter.Value --output text)
OPENAI=$(aws ssm get-parameter --region us-east-1 --with-decryption --name /rentch/OPENAI_API_KEY --query Parameter.Value --output text)
KIRI=$(aws ssm get-parameter --region us-east-1 --with-decryption --name /rentch/KIRI_API_KEY   --query Parameter.Value --output text)
CS="drift-fix-$(date +%s)"

aws cloudformation create-change-set --region us-east-1 \
  --stack-name rentch-backend --change-set-name "$CS" \
  --template-body file://template.reconciled.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters \
    ParameterKey=GeminiApiKey,ParameterValue="$GEMINI" \
    ParameterKey=OpenAiApiKey,ParameterValue="$OPENAI" \
    ParameterKey=KiriApiKey,ParameterValue="$KIRI" \
    ParameterKey=FirebaseProjectId,UsePreviousValue=true \
    ParameterKey=CodeBucket,UsePreviousValue=true \
    ParameterKey=RouterKey,UsePreviousValue=true \
    ParameterKey=AuthorizerKey,UsePreviousValue=true \
    ParameterKey=WsKey,UsePreviousValue=true \
    ParameterKey=BroadcasterKey,UsePreviousValue=true \
    ParameterKey=WsAuthorizerKey,UsePreviousValue=true \
    ParameterKey=TablePrefix,UsePreviousValue=true \
    ParameterKey=PanoStitchKey,UsePreviousValue=true
echo "$CS"
```

## Step 3 — REVIEW the change set (the safety gate)

```bash
aws cloudformation describe-change-set --region us-east-1 \
  --stack-name rentch-backend --change-set-name "$CS" \
  --query 'Changes[].ResourceChange.{Action:Action,Res:LogicalResourceId,Type:ResourceType,Replace:Replacement}' \
  --output table
```

**Only execute if ALL of these hold:**
- No `Action: Remove` on any table/bucket.
- No `Replacement: True` (or `Conditional`) on any `AWS::DynamoDB::Table` /
  `AWS::S3::Bucket` — data resources must be `Modify` with `Replacement: False`
  (the Retain-policy add is metadata-only).
- The only `Modify` on `RouterFunction` is the env-var change.
- No unexpected resources being created (would collide with out-of-band tables).

If anything looks off → **do not execute**; delete the change set:
`aws cloudformation delete-change-set --region us-east-1 --stack-name rentch-backend --change-set-name "$CS"`

## Step 4 — Execute (only after review passes)

```bash
aws cloudformation execute-change-set --region us-east-1 \
  --stack-name rentch-backend --change-set-name "$CS"
aws cloudformation wait stack-update-complete --region us-east-1 --stack-name rentch-backend
```

## Step 5 — Verify

```bash
# all 9 env keys still present (secrets intact)
aws lambda get-function-configuration --function-name rentch-router --region us-east-1 \
  --query 'keys(Environment.Variables)' --output json
# stack healthy
aws cloudformation describe-stacks --stack-name rentch-backend --region us-east-1 \
  --query 'Stacks[0].StackStatus' --output text
# smoke the router
aws lambda invoke --function-name rentch-router --region us-east-1 \
  --payload '{"httpMethod":"GET","path":"/p/smoke","headers":{"User-Agent":"Mozilla/5.0"},"requestContext":{"identity":{}}}' /tmp/o.json \
  --query 'StatusCode' && head -c 60 /tmp/o.json
```

Then: `mv template.reconciled.yaml template.yaml` and update `deploy.sh` to pass
the 3 secret params from SSM (same `get-parameter` lines) so future deploys stay
safe. `git commit` the reconciled template as the new source of truth.

---

## Notes

- **Out-of-band tables** (persona, matches, device-tokens, notifications,
  broadcasts, search-log, saved-searches, broker-data, interactions, contracts):
  left out of CFN on purpose — CFN never touches what it doesn't declare, so
  they're safe. To bring one under CFN later, use an **IMPORT** change set
  (`--change-set-type IMPORT --resources-to-import ...`); never add it to the
  template and plain-deploy (that tries to CREATE → name-collision → rollback).
- **`rentch-interactions`** was created via CLI this session; same handling.
- **`RANK_MODEL_S3` / `RANK_MODEL_ALPHA`** (the LightGBM activation vars) are set
  out-of-band by `ml/activate.sh`. This reconcile does not manage them, so after
  executing the change set, if the model was activated, re-run `ml/activate.sh`.
- **Never** run the old `deploy.sh` against the pre-reconcile `template.yaml` — it
  wipes secrets. Until reconciled, ship router code with
  `aws lambda update-function-code` (code-only, safe).
