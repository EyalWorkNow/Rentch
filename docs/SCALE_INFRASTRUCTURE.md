# Rentch — Scale Infrastructure Guide

**Target:** 10,000+ concurrent active users  
**Backend:** Appwrite (self-hosted or Cloud)  
**Auth:** Firebase Auth + Google Sign-In  
**Storage:** Appwrite Storage  
**Real-time:** Appwrite Realtime (WebSocket)

---

## 1. Appwrite Collections Schema

### 1.1 `app_state` collection

Stores per-device serialized app state (tenant/landlord profiles, filters, matches).

| Field | Type | Required | Max Length | Notes |
|-------|------|----------|------------|-------|
| `payload` | String | Yes | 64,000 | JSON-encoded state blob |
| `schema` | String | Yes | 32 | e.g. `rental_match_v1` |
| `updatedAt` | DateTime | Yes | — | UTC ISO-8601 |

**Collection Permissions:**  
- Create: Users  
- Read: Document owner only (`user:{userId}`)  
- Update: Document owner only  
- Delete: Document owner only  

**Indexes:**  
- `updatedAt` DESC (for stale cleanup jobs)

**Document ID strategy:**  
Each device generates `rentch_state_{timestamp}_{random}` — never the legacy `global_state` shared ID. See `LocalStorageService._generateUniqueDocId()`.

---

### 1.2 `messages` collection

Stores individual chat messages for real-time delivery.

| Field | Type | Required | Max Length | Notes |
|-------|------|----------|------------|-------|
| `matchId` | String | Yes | 64 | Foreign key to match |
| `senderId` | String | Yes | 64 | Firebase UID |
| `senderName` | String | Yes | 100 | Display name, sanitized |
| `text` | String | Yes | 2,000 | Sanitized message body |
| `createdAt` | DateTime | Yes | — | UTC ISO-8601 |

**Collection Permissions:**  
- Create: Users (any authenticated user)  
- Read: Users in same match only (enforce via Appwrite Functions if needed)  
- Update: Never (messages are immutable)  
- Delete: Admin only  

**Indexes:**  
- `matchId` + `createdAt` ASC (for paginated message history)  
- `createdAt` DESC (for recent messages query)

**Realtime channel:** `databases.[dbId].collections.[collectionId].documents`  
Filter client-side by `matchId`.

**Build-time config:**  
```
--dart-define=APPWRITE_MESSAGES_COLLECTION_ID=<your-collection-id>
```

---

### 1.3 `property_images` bucket

Stores landlord-uploaded property photos.

| Setting | Value |
|---------|-------|
| Max file size | 10 MB |
| Allowed extensions | jpg, jpeg, png, webp, heic, heif |
| Encryption | Appwrite-managed at rest |
| Antivirus | Enable if on Appwrite Cloud Pro |

**Permissions:**  
- Create: Authenticated users  
- Read: Any (public — images are displayed to all tenants browsing)  
- Update: Owner only  
- Delete: Owner only  

---

### 1.4 `tenant_verification` collection (future)

| Field | Type | Notes |
|-------|------|-------|
| `userId` | String | Firebase UID |
| `idVerifiedAt` | DateTime | KYC verification timestamp |
| `creditScoreVerifiedAt` | DateTime | Credit check timestamp |
| `level` | Enum | `none`, `id`, `full` |

---

## 2. Client-Side Rate Limiting

All limits are enforced in `RateLimiter` (token bucket, reset every 60s):

| Action | Limit | Class Method |
|--------|-------|--------------|
| State writes to Appwrite | 15 / minute | `allowStateWrite()` |
| Card swipes | 60 / minute | `allowSwipe()` |
| Chat messages | 30 / minute | `allowMessage()` |
| Property adds | 10 / hour | `allowPropertyAdd()` |
| Image uploads | 20 / hour | `allowImageUpload()` |

`WriteDebouncer` (800ms window) batches rapid successive `_persist()` calls so a single user action chain (e.g. 5 filter taps in 2 seconds) produces one Appwrite write instead of five.

**Why client-side only isn't enough:** These limits protect the Appwrite API from a single device hammering it. Server-side limits (Appwrite rate-limit rules or an API Gateway) are required for adversarial clients.

---

## 3. Appwrite Server-Side Configuration

### 3.1 Rate limit rules (Appwrite Console → Project → Settings → Rate Limits)

```
Rule: Documents Create
  Scope: user
  Limit: 30 requests / 60 seconds
  Collections: messages, app_state

Rule: Storage Upload
  Scope: user
  Limit: 20 requests / 3600 seconds
  Buckets: property_images

Rule: Realtime Connections
  Scope: user
  Limit: 3 connections / user (close old on new connect)
```

### 3.2 Functions (Appwrite Functions)

| Function | Trigger | Purpose |
|----------|---------|---------|
| `cleanup-stale-state` | CRON `0 3 * * *` (3am UTC daily) | Delete `app_state` docs not updated in 90 days |
| `message-retention` | CRON `0 4 * * 0` (weekly) | Archive or delete messages older than 1 year |
| `validate-message` | `databases.messages.documents.create` | Server-side re-validate: strip XSS, enforce length |

**`validate-message` function (Node.js):**
```javascript
export default async ({ req, res, log }) => {
  const doc = req.body;
  const text = (doc.text || '').trim().slice(0, 2000);
  // Strip HTML tags
  const clean = text.replace(/<[^>]*>/g, '');
  if (clean !== text) {
    // Update document with sanitized version
    await databases.updateDocument(dbId, collectionId, doc.$id, { text: clean });
  }
  return res.json({ ok: true });
};
```

---

## 4. Firebase Auth Configuration

### 4.1 Auth Providers
- Google Sign-In (primary)
- Anonymous (for onboarding preview — disable before production)

### 4.2 Security Rules (Firestore if used)
Since app state is in Appwrite, not Firestore, Firebase is auth-only. No Firestore security rules needed unless analytics events are stored there.

### 4.3 Token Refresh
Firebase ID tokens expire every 1 hour. The Appwrite SDK refreshes them transparently. Ensure:
- Session is initialized before any Appwrite call
- `firebase_auth: ^6.0.2` is pinned (current)

---

## 5. CDN and Image Delivery

### 5.1 Appwrite Storage CDN
Appwrite Cloud includes CDN automatically. For self-hosted:

```nginx
# nginx caching for Appwrite storage
location /v1/storage/buckets/property_images/files/ {
    proxy_pass http://appwrite:80;
    proxy_cache_valid 200 24h;
    add_header Cache-Control "public, max-age=86400";
    proxy_cache_key "$scheme$host$request_uri";
}
```

### 5.2 Image Transformation
Use Appwrite's built-in image transformation for thumbnails:
```
GET /v1/storage/buckets/{bucketId}/files/{fileId}/preview?width=400&height=300&quality=80
```

In `StorageService.getImageUrl()`, always request preview endpoint for display, not the raw file.

---

## 6. Horizontal Scaling Plan

### Phase 1 — 0 to 1,000 users (Appwrite Cloud Starter)
- Single Appwrite instance
- Firebase Auth free tier (up to 10k/month Google sign-ins)
- Realtime: up to 500 concurrent WebSocket connections included
- Cost estimate: ~$25/month

### Phase 2 — 1,000 to 10,000 users (Appwrite Cloud Pro)
- Multi-region Appwrite deployment
- Realtime: 5,000 concurrent connections
- Storage: 150 GB
- Enable Appwrite Functions for server-side validation
- Cost estimate: ~$199/month

### Phase 3 — 10,000+ users (Self-Hosted on Kubernetes)

```yaml
# docker-compose.yml scaling hints
services:
  appwrite:
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '2'
          memory: 4G
  appwrite-realtime:
    deploy:
      replicas: 2   # WebSocket server scales separately
  appwrite-worker-databases:
    deploy:
      replicas: 3
  mariadb:
    deploy:
      replicas: 1   # Primary + read replicas via Galera
  redis:
    deploy:
      replicas: 3   # Redis Sentinel for HA
```

**Key bottlenecks at scale:**
1. **Realtime WebSocket connections** — each active chat = 1 persistent WebSocket. At 10k concurrent users with 20% in active chat = 2,000 connections. Appwrite Realtime server handles ~10k connections per instance.
2. **`app_state` document writes** — with debouncing + rate limiting, expect max 150 writes/minute per 1,000 active users = 1,500 writes/minute at 10k users. MariaDB handles this easily.
3. **Image storage** — budget 5MB average per property × 3 photos × 1,000 properties = 15GB minimum. Use Cloudflare R2 or Backblaze B2 as Appwrite storage adapter at scale.

---

## 7. Monitoring and Alerting

### 7.1 Metrics to Watch

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Appwrite API latency P99 | > 500ms | > 2000ms | Add read replica |
| Realtime connection count | > 8,000 | > 9,500 | Scale realtime service |
| `app_state` write rate | > 1,000/min | > 3,000/min | Increase debounce window |
| Message delivery latency | > 1s | > 5s | Investigate WebSocket backpressure |
| Firebase Auth error rate | > 1% | > 5% | Check token refresh flow |

### 7.2 Appwrite Webhooks → Monitoring

Configure webhook to POST to your monitoring endpoint on:
- `databases.*.documents.create` failures
- `storage.files.create` failures (storage full?)
- Function execution failures

### 7.3 Flutter-side Crash Reporting
Add `firebase_crashlytics` to catch client-side errors. Key events to log:
- `RateLimiter` blocks (indicates UX friction)
- Realtime reconnect loops
- State save failures

---

## 8. Security Hardening Checklist

### Appwrite Console
- [ ] Disable "Guest" session creation
- [ ] Set session expiry to 30 days max
- [ ] Enable email confirmation for non-Google signup
- [ ] Restrict CORS to `*.rentch.co.il` (or your domain)
- [ ] Enable Appwrite audit logs
- [ ] Review API key scopes — app client key should be read-only for collections

### Flutter App
- [x] SEC-1: `flutter_secure_storage` added for sensitive data (see `SecureStorageService`)
- [x] SEC-2: Input sanitization on all user inputs (`InputSanitizer`)
- [x] SEC-3: Per-device Appwrite state document IDs (no shared `global_state`)
- [x] SEC-4: Role field validated server-to-enum (`sanitizeRole()`)
- [x] SEC-9: Path traversal prevention in image file loading (`isValidLocalPathSync()`)
- [x] SEC-10: Message length + rate limiting in chat (`SecurityConfig.maxMessageLength`)
- [ ] SEC-5: Migrate `SharedPreferences` session token to `SecureStorageService` (see `clearOnLogout()`)
- [ ] SEC-6: Certificate pinning via `http_certificate_pinning` package for Appwrite API calls
- [ ] SEC-7: Obfuscate release builds: `flutter build apk --obfuscate --split-debug-info=build/debug-info`
- [ ] SEC-8: Remove all `debugPrint()` statements in release — or gate on `kDebugMode` (already done in new files)
- [ ] SEC-11: Android `minSdkVersion 23` required for `encryptedSharedPreferences` (edit `android/app/build.gradle`)

### Android-specific
```gradle
// android/app/build.gradle
android {
    defaultConfig {
        minSdkVersion 23  // Required for flutter_secure_storage AES-256
        targetSdkVersion 35
    }
}
```

### iOS-specific
Add to `ios/Runner/Info.plist` to prevent screenshots in app switcher:
```xml
<key>UIApplicationExitsOnSuspend</key>
<false/>
```

And in `AppDelegate.swift`:
```swift
override func applicationWillResignActive(_ application: UIApplication) {
    window?.isHidden = true
}
override func applicationDidBecomeActive(_ application: UIApplication) {
    window?.isHidden = false
}
```

---

## 9. Deployment Runbook

### First Deployment

1. Create Appwrite project
2. Create `app_state` collection with fields and permissions above
3. Create `messages` collection with fields and permissions above
4. Create `property_images` bucket
5. Set up Firebase project, enable Google Sign-In
6. Download `google-services.json` → `android/app/`
7. Download `GoogleService-Info.plist` → `ios/Runner/`
8. Set build defines:
   ```bash
   flutter build apk \
     --dart-define=APPWRITE_MESSAGES_COLLECTION_ID=<id> \
     --dart-define=APPWRITE_ENDPOINT=https://your-appwrite.com \
     --obfuscate \
     --split-debug-info=build/debug-info
   ```
9. Deploy `validate-message` Appwrite Function
10. Set up `cleanup-stale-state` CRON function

### Rolling Update (no downtime)
- Appwrite Cloud: zero-downtime by default
- Self-hosted: use `docker service update --update-parallelism 1 --update-delay 30s`

### Database Migrations
When changing `app_state` payload schema:
1. Bump `schema` field value (e.g. `rental_match_v1` → `rental_match_v2`)
2. Add migration logic in `DatingProvider._loadFromState()` to handle old schema
3. Never delete fields from old schema — add new optional fields only

---

## 10. Cost Optimization

| Optimization | Savings |
|---|---|
| `WriteDebouncer` 800ms window | ~60% fewer `app_state` writes |
| Client-side rate limiter | Prevents runaway write storms |
| Image preview endpoint instead of raw | ~70% bandwidth reduction |
| Stale doc cleanup CRON | Keeps MariaDB index size bounded |
| Message pagination (50/page) | Reduces initial load by 90% for active matches |
| Realtime unsubscribe on screen pop | Frees WebSocket connections immediately |
