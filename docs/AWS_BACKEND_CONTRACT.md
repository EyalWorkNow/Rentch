# AWS Backend Contract — Rentch

This document is the **API contract** the Flutter client expects after the
Appwrite → AWS migration. The backend team implements API Gateway + Lambda +
DynamoDB + S3 to satisfy these routes.

## Architecture

```
Flutter (AwsApiClient)
  │  Authorization: Bearer <Firebase ID token>
  │  x-api-key: <API Gateway usage-plan key>
  ▼
API Gateway (REST)
  │  Lambda authorizer verifies the Firebase JWT (project: mydatingapp-4c043)
  ▼
Lambda functions  ──▶  DynamoDB tables
                  └─▶  S3 bucket (presigned URLs)
```

**Auth stays Firebase.** The Lambda authorizer validates the Firebase ID token
(`https://securetoken.google.com/mydatingapp-4c043`) and injects `uid` into the
request context. No Cognito.

## Client config (dart-define)

| Var | Example | Purpose |
|---|---|---|
| `AWS_API_URL` | `https://abc.execute-api.eu-central-1.amazonaws.com/prod` | API Gateway base URL |
| `AWS_API_KEY` | `xxxxx` | Usage-plan key → `x-api-key` header |
| `AWS_REGION` | `eu-central-1` | Region |
| `AWS_S3_BUCKET` | `rentch-media` | Media bucket |
| `RENTCH_ENABLE_CLOUD_STORAGE` | `true` | Enables S3 uploads |
| `RENTCH_ENABLE_REMOTE_STATE` | `true` | Enables app-state sync |

When `AWS_API_URL` is empty the app runs fully offline from the bundled JSON
asset (`assets/data/proxy_listings.json`) — same graceful degradation as before.

---

## REST routes

All request/response bodies are JSON. List endpoints return `{ "items": [ ... ] }`.
Every row carries an `id` field (the DynamoDB partition key unless noted).

### Properties — `rentch-properties`

| Method | Path | Query / Body | Notes |
|---|---|---|---|
| GET | `/properties` | `?status=active&limit=150&lastKey=<cursor>` | Cursor-paginated. Omit `lastKey` for the first page. |
| GET | `/properties` | `?ownerUserId=FIREBASE_UID&limit=200` | Landlord-owned listings for profile/dashboard. |
| POST | `/properties` | `{ id, propertyId, ownerUserId, price, rooms, sizeM2, city, ... , status }` | Create. |
| PUT | `/properties/{id}` | full row | Upsert/update. |
| DELETE | `/properties/{id}` | — | Owner-only. |

`status ∈ {draft, active, paused, rented}`. Consent fields (`legal.*`) are
validated client-side; the server should also reject `active` rows missing
consent. Media/feature fields are JSON-encoded strings (see row mapping in
`rental_data_service.dart`).

### Messages — `rentch-messages`

| Method | Path | Query / Body | Notes |
|---|---|---|---|
| GET | `/messages` | `?matchId=X&orderBy=createdAt&order=asc&limit=100&after=<id>` | Chat history. `after` = cursor (exclusive). |
| POST | `/messages` | `{ id, matchId, senderId, senderName, text, createdAt }` | Send. `text` ≤ 2000 chars. |

Polling: the client calls GET every 3 s with `after=<lastSeenId>`. Keep this
endpoint cheap — query on a `matchId-createdAt` GSI.

### Users (discovery profiles) — `rentch-users`

| Method | Path | Query / Body | Notes |
|---|---|---|---|
| GET | `/users` | `?discoverable=true&limit=N` | Discovery feed. |
| PUT | `/users/{id}` | `{ userId, name, bio, photoUrl, photoUrls, budgetMax, desiredRooms, moveInWindow, role, discoverable, updatedAt }` | Upsert. `id` = Firebase UID. |
| DELETE | `/users/{id}` | — | GDPR hard delete. |

### Events (analytics) — `rentch-events`

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/events` | `{ id, userId, eventType, sessionId, createdAt, propertyId?, matchId?, metadata? }` | Append-only. Fire-and-forget; never blocks the client. |

`metadata` is a JSON string ≤ 2 KB. Do **not** retry events server-side.

### Moderation — `rentch-reports`, `rentch-blocks`

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/reports` | `{ id, reporterUserId, propertyId, ownerName, reason, createdAt }` | Apple 1.2 — must reach developer ≤ 24 h. |
| POST | `/blocks` | `{ id, reporterUserId, blockedOwnerName, createdAt }` | Notifies developer + hides content. |

Wire these to an SNS topic / email so reports are actioned within 24 hours
(App Store Guideline 1.2 requirement).

### Reviews — `rentch-reviews`

| Method | Path | Query / Body | Notes |
|---|---|---|---|
| GET | `/reviews` | `?targetKey=property%23PROPERTY_ID&order=desc&limit=50` | Reviews for a property. |
| GET | `/reviews` | `?targetKey=tenant%23TENANT_ID&order=desc&limit=50` | Reviews for a tenant/renter profile. |
| POST | `/reviews` | `{ id, targetType, targetId, targetKey, reviewerUserId, reviewerRole, authorName, rating, text, matchId?, propertyId?, revieweeUserId?, createdAt }` | Create review. |

`targetType ∈ {property, tenant}` and `targetKey = "${targetType}#${targetId}"`.
`rating` is clamped client-side to 1–5 and `text` is limited to 1,000 chars.
The client writes locally first, then posts to AWS so offline/unauthorized
sessions do not lose the review.

### Property analytics (optional) — `rentch-property-views`, `rentch-property-likes`

| Method | Path | Query / Body |
|---|---|---|
| GET | `/property_views` | `?propertyId=X` |
| PUT | `/property_views/{id}` | session row |
| GET | `/property_likes` | `?propertyId=X` |
| PUT | `/property_likes/{id}` | like row |
| DELETE | `/property_likes/{id}` | — |

Only enabled when `DYNAMO_PROPERTY_VIEWS_TABLE` / `DYNAMO_PROPERTY_LIKES_TABLE`
are set.

### App state (per-device blob) — `rentch-app-state`

| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/app_state/{rowId}` | — | `{ payload, schema, updatedAt }`. `payload` is a JSON string. |
| PUT | `/app_state/{rowId}` | `{ payload, schema, updatedAt }` | Upsert. `rowId` is per-device. |

`rowId` is generated client-side and stored in Keychain — never shared across
devices (prevents the old `global_state` overwrite bug).

### Storage (S3 presigned) — Lambda, not DynamoDB

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/storage/presign` | `{ key, contentType }` | `{ uploadUrl, publicUrl }` |
| DELETE | `/storage/{key}` | — | 204 |

The client requests a presigned `PUT` URL, then uploads bytes **directly to S3**
(no Lambda in the data path). `publicUrl` is the final HTTPS object URL stored on
the property/profile row.

### Hosted 3D viewers

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/3d/viewers` | `{ propertyId, title, assets[] }` | `{ data: { viewerUrl, downloadUrl, format, model3d } }` |

`assets[]` contains already-uploaded S3 object URLs for files exported from
Scaniverse or other 3D tools. The router creates a hosted HTML viewer page in
S3 that renders GLB/USDZ through `model-viewer` and OBJ/MTL through Three.js.

---

## DynamoDB table definitions

| Table | PK | SK / GSI | Notes |
|---|---|---|---|
| `rentch-properties` | `id` (S) | GSI: `status-createdAt`, `ownerUserId-createdAt` | active feed and landlord-owned listings |
| `rentch-messages` | `id` (S) | GSI: `matchId-createdAt` for chat history | |
| `rentch-users` | `id` (S) = Firebase UID | GSI: `discoverable-updatedAt` | |
| `rentch-events` | `id` (S) | GSI: `userId-createdAt`, `eventType-createdAt` | TTL on `createdAt` if desired |
| `rentch-reports` | `id` (S) | GSI: `createdAt` | stream → SNS |
| `rentch-blocks` | `id` (S) | GSI: `reporterUserId` | |
| `rentch-reviews` | `id` (S) | GSI: `targetKey-createdAt` | property and tenant/renter reviews |
| `rentch-property-views` | `id` (S) | GSI: `propertyId` | |
| `rentch-property-likes` | `id` (S) | GSI: `propertyId-day` | |
| `rentch-app-state` | `id` (S) = device rowId | — | single-item get/put |

Billing mode: **PAY_PER_REQUEST** (on-demand) for all tables.

## S3 bucket

- Bucket: `rentch-media`, private, block public ACLs.
- Access via presigned URLs only.
- CORS: allow `PUT` from the app origin; `GET` public-read on object URLs (or
  CloudFront in front for caching).
- Lifecycle: optional — transition rarely-accessed media to IA after 90 days.

## IAM (least privilege)

- **Lambda execution role**: `dynamodb:GetItem/PutItem/Query/DeleteItem` scoped
  to the `rentch-*` table ARNs; `s3:PutObject/GetObject/DeleteObject` on
  `rentch-media/*`; `s3:PutObject` presign.
- **Authorizer Lambda**: no data access — only verifies the Firebase JWT via
  Google's public JWKS (`https://www.googleapis.com/...`).

## Rate limiting

Set an API Gateway **usage plan** (e.g. 50 req/s burst, 10k/day per key) to
mirror the client-side token-bucket limits in `rate_limiter.dart`. This is the
server-side enforcement the security audit flagged as missing.
