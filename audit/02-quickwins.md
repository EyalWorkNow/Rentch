# Quick Wins — first ten actions

Ordered by score. Every action is reversible in minutes; rollback given inline. "At scale" = 5k-MAU model from 00-baseline §ASSUMPTIONS.

> **STATUS 2026-08-20 — APPLIED (#1–#8):** TTL enabled ×4 tables; gzip on (minCompressionSize=1024, deployment `ske3sc`); lifecycle rules live on both buckets (MPU-abort 7d + 3d-scans→GIR 30d); log retention 90d ×9 groups. Client: hash-guard in `_saveRemoteState`, WriteDebouncer 800ms→10s + Timer-based cancel(), `flushRemoteState()` on app pause (main.dart). **826/826 tests pass.** NOT committed. Still open: #9 (deck pagination), #10 (telemetry emitters decision), and `ttl` attribute stamping in router writes (needs a router zip-swap deploy — TTL is enabled but inert until rows carry the attribute).

## 1. F1a — stop no-op app-state writes (client)

The single highest-value change in the audit (~$285/mo at scale). `lib/core/services/local_storage.dart`, in `_saveRemoteState`:

```diff
 class LocalStorageService {
   static const String _remoteStateIdKey = 'rentch_remote_state_document_id_v2';
+  int? _lastSyncedStateHash;
```
```diff
   Future<void> _saveRemoteState(
     SharedPreferences preferences,
     Map<String, dynamic> state,
   ) async {
     if (!AppConfig.canUseRemoteState) return;
     final remoteState = _stateForRemoteSync(state);
+
+    final encoded = jsonEncode(remoteState);
+    if (encoded.hashCode == _lastSyncedStateHash) return; // unchanged — skip
 
     final data = {
-      _payloadField: jsonEncode(remoteState),
+      _payloadField: encoded,
       _schemaField: remoteState[_schemaField],
       _updatedAtField: DateTime.now().toUtc().toIso8601String(),
     };
 
     try {
       await tables.upsertRow(
         databaseId: appwriteDatabaseId,
         tableId: appwriteAppStateCollectionId,
         rowId: await _remoteStateDocumentId(preferences),
         data: data,
       );
+      _lastSyncedStateHash = encoded.hashCode;
     } catch (error) {
       _logRemoteError('save', error);
       return;
     }
   }
```

**Rollback:** revert the diff. **Verify:** swipe 20 cards, confirm one write in CloudWatch `ConsumedWriteCapacityUnits` (rentch-app-state), not 20.

## 2. F1b — debounce the remote sync (client)

Same file; wrap the remote save in a 10 s trailing debounce (a `WriteDebouncer` already exists in the codebase — `dating_provider.dart:123`). Flush on app-pause/logout so nothing is lost on exit. Do 1+2 in the same release.

## 3. F2 — TTL on ephemeral tables

```bash
for t in rentch-search-log rentch-events rentch-property-views rentch-ws-connections; do
  aws dynamodb update-time-to-live --table-name $t \
    --time-to-live-specification "Enabled=true, AttributeName=ttl"
done
```
Writers must stamp `ttl` (epoch-seconds, e.g. now + 90 d) — one-line addition per write site in `aws/lambda/router/index.mjs` (search-log, events, views) and the ws connect handler. Existing rows without `ttl` are untouched (acceptable: they're megabytes).
**Rollback:** `Enabled=false`. **Risk:** none — rows without the attribute never expire.

## 4. C1 — gzip on the main API

```bash
aws apigateway update-rest-api --rest-api-id g7b9nx11sk \
  --patch-operations op=replace,path=/minimumCompressionSize,value=1024
aws apigateway create-deployment --rest-api-id g7b9nx11sk --stage-name prod
```
**Rollback:** `op=replace,path=/minimumCompressionSize,value=` (empty) + redeploy. **Verify:** `curl -H "Accept-Encoding: gzip" -s -o /dev/null -w "%{size_download}"` on a listings URL with a valid token — expect ~5–8× smaller.

## 5. C4 — chat poll cadence (client)

`lib/core/services/realtime_chat_service.dart:46-47`:
```diff
-  static const Duration _pollFast = Duration(seconds: 3);
-  static const Duration _pollSlow = Duration(seconds: 20);
+  static const Duration _pollFast = Duration(seconds: 10); // WS carries real-time; poll is reconciliation
+  static const Duration _pollSlow = Duration(seconds: 60);
```
Follow-up (M): poll `_pollFast` only while the WS is disconnected. **Rollback:** revert constants.

## 6. F4b — abort stuck multipart uploads (both buckets)

```bash
for b in rentch-media-543897290879 rentch-deploy-543897290879; do
  aws s3api put-bucket-lifecycle-configuration --bucket $b --lifecycle-configuration '{
    "Rules": [{"ID":"abort-mpu-7d","Status":"Enabled","Filter":{},
      "AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}]}'
done
```
**Rollback:** `delete-bucket-lifecycle`. Clears the 3 stuck MPUs in the deploy bucket within a week.

## 7. F4a — Glacier IR for 3D-scan sources

Extend the media bucket's rule set (merge with #6 — lifecycle PUT replaces the whole config, so ship one JSON with both rules):
```json
{"ID":"scan-sources-gir","Status":"Enabled","Filter":{"Prefix":"3d-scans/"},
 "Transitions":[{"Days":30,"StorageClass":"GLACIER_IR"}]}
```
~68% storage saving on the heaviest prefix (5 objects = 307 MB today). **Rollback:** remove the rule; next uploads land STANDARD again.

## 8. F6 — log retention

```bash
for g in router authorizer ws ws-authorizer img-resize pano-stitch billing-cron broadcaster splat-convert; do
  aws logs put-retention-policy --log-group-name /aws/lambda/rentch-$g --retention-in-days 90
done
```
**Rollback:** `delete-retention-policy` (already-expired events don't come back — at 23 MB total, immaterial).

## 9. C2 — page the deck at 25 (client)

Change the browse fetch to `limit=25` and request the next page via the `lastKey` the server already returns (`pageBody`, index.mjs:3071) when the deck has ≤10 cards left. Client-only; server untouched. **Rollback:** restore `limit=150`.

## 10. F2b — decide the fate of write-only telemetry

`rentch-events` (W=2,920, R=0) and `rentch-property-views` (W=3,865, R=0) are written and never read. If no dashboard is planned this quarter, gate the client-side emitters behind a remote-config flag defaulting to off. The write is the cost, not the storage. **Rollback:** flip the flag. **Prereq:** confirm nothing reads them outside the router (nothing found in-repo).

---

**Deliberately excluded from quick wins:** F3 (REST→HTTP — M effort, needs an auth-parity test plan; roadmap item), F5 (arm64 — blocked on CI toolchain check), C3 (embedding side-table — do it as part of the re-enrich job for the 22.5k new listings, not before).
