# Rentch AWS Backend

Serverless backend: **API Gateway → Lambda (Firebase JWT auth) → DynamoDB + S3**.
Implements the contract in [`docs/AWS_BACKEND_CONTRACT.md`](../docs/AWS_BACKEND_CONTRACT.md).

## 🟢 LIVE — deployed & verified

- **API URL:** `https://g7b9nx11sk.execute-api.us-east-1.amazonaws.com/prod`
- **Region:** `us-east-1`  ·  **Account:** `543897290879`
- **Data:** 1,548 properties seeded into `rentch-properties`
- **Set as the default** in `lib/core/config/app_config.dart` — the app talks to
  AWS out of the box (no dart-define needed).

End-to-end verified: auth rejects missing/invalid tokens (401); valid Firebase
token returns live data; messages/events/users/app_state CRUD; S3 presigned
upload + public read round-trip. Redeploy any time with `./deploy.sh`.

```
aws/
├── template.yaml          CloudFormation: 10 DynamoDB tables, S3, IAM, Lambdas, API Gateway
├── lambda/
│   ├── router/index.mjs       all CRUD + S3 presign (one Lambda, runtime SDK v3)
│   └── authorizer/index.mjs   Firebase ID-token verification (zero deps)
├── deploy.sh              package + upload + deploy  →  prints AWS_API_URL
├── seed.sh               loads 1,548 properties from the JSON asset into DynamoDB
├── deploy-policy.json     IAM permissions the deploying user needs
└── README.md
```

## Prerequisites — one-time IAM grant

The deploying IAM user needs permissions for CloudFormation/DynamoDB/Lambda/
API Gateway/S3/IAM. The current user `eyalatiyawork@gmail.com` has **none** yet.

In the AWS Console (as account root or an admin):
**IAM → Users → eyalatiyawork@gmail.com → Add permissions →**
- Quickest: attach the managed policy **`AdministratorAccess`**, or
- Least-privilege: **Create inline policy** and paste `aws/deploy-policy.json`.

## Deploy

```bash
cd aws
AWS_REGION=us-east-1 ./deploy.sh      # ~3–5 min (creates all resources)
AWS_REGION=us-east-1 ./seed.sh        # loads property data into DynamoDB
```

`deploy.sh` prints the `AWS_API_URL`. Run the app against it:

```bash
flutter run \
  --dart-define=AWS_API_URL=https://xxxx.execute-api.us-east-1.amazonaws.com/prod \
  --dart-define=AWS_REGION=us-east-1 \
  --dart-define=RENTCH_ENABLE_REMOTE_STATE=true \
  --dart-define=RENTCH_ENABLE_CLOUD_STORAGE=true
```

## Cost

All tables are **PAY_PER_REQUEST** and Lambda/API Gateway are pay-per-call —
**no idle cost**. At low volume this stays within / near the AWS free tier.

## Architecture notes

- **Auth stays Firebase.** The authorizer Lambda verifies the Firebase ID token
  (RS256) against Google's public certs using Node's built-in `crypto` — no
  Cognito, no external npm packages.
- **One router Lambda** handles every table via path → table mapping, plus S3
  presigned uploads. Adding a table = one line in `TABLES` (router) + one
  `AWS::DynamoDB::Table` in the template.
- **Reviews** are stored in `rentch-reviews` and queried by
  `targetKey` (`property#...` or `tenant#...`) so property and renter feedback
  stay separate but use one table.
- **Chat** uses 3-second HTTP polling (`GET /messages?matchId=…&after=…`) — no
  WebSocket. Upgrade path: API Gateway WebSocket + a connections table.
- **Throttling**: API Gateway stage caps 25 req/s (burst 50), mirroring the
  client-side token-bucket limits.

## Tear down

```bash
aws cloudformation delete-stack --stack-name rentch-backend --region us-east-1
```

(Empty the `rentch-media-*` and `rentch-deploy-*` buckets first if deletion blocks.)
