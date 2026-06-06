# Rentch Backend Schema

The current `RENTCH_LAUNCH_MODE=true` path can run a controlled MVP against the existing Appwrite `app_state/global_state` row. It is not the final production backend because user state is not isolated per authenticated user.

Enable property analytics with:

- `APPWRITE_PROPERTY_VIEW_SESSIONS_TABLE_ID`: table ID for detail-page presence, dwell time, and gallery swipe sessions.
- `APPWRITE_PROPERTY_LIKES_TABLE_ID`: table ID for per-user daily property likes.

## Required Tables For Public Launch

`users`

- `userId`: string, primary ID from auth provider.
- `role`: enum string, `tenant` or `landlord`.
- `displayName`: string.
- `phone`: string, optional.
- `email`: string, optional.
- `photoUrl`: string, optional.
- `createdAt`: datetime.
- `updatedAt`: datetime.

`tenant_profiles`

- `userId`: string.
- `bio`: string.
- `budgetMax`: integer.
- `desiredRooms`: double.
- `moveInWindow`: string.
- `importantDetails`: string array or JSON text.
- `photoUrls`: JSON text.

`landlord_profiles`

- `userId`: string.
- `bio`: string.
- `verified`: boolean.
- `ratingAvg`: double.
- `responseTimeMinutes`: integer.

`properties`

- `propertyId`: string.
- `ownerUserId`: string.
- `sourceUrl`: string, optional external import/source link. Empty for owner-uploaded properties.
- `price`: integer.
- `rooms`: double.
- `sizeM2`: integer.
- `floor`: string.
- `totalFloors`: string.
- `city`: string.
- `neighborhood`: string.
- `street`: string.
- `streetNumber`: integer.
- `lat`: double.
- `lon`: double.
- `propertyType`: string.
- `entryDate`: datetime or string.
- `condition`: string.
- `features`: JSON text object with canonical boolean keys such as `balcony`, `parking`, `storage`, `airConditioning`, `mamad`, `accessible`, `petsAllowed`, `renovated`, and the rest of the supported catalog.
- `featureLabels`: JSON text array for display/search compatibility with legacy clients.
- `media`: JSON text array with objects like `{ "url": "...", "type": "image" | "video" }`.
- `model3d`: JSON text object with `viewerUrl`, `glbUrl`, `objUrl`, `textureFolder`, `floorPlanUrl`, `modelQualityScore`, and `scanDate`.
- `legal`: JSON text object with `thirdPartyTransferAllowed`, `commercialSaleAllowed`, `aiTrainingAllowed`, `consentVersion`, `consentTimestamp`, and `consentSource`.
- `priceHistory`: JSON text array with `{ "date": "YYYY-MM-DD", "price": 123, "transactionType": "rent" | "sale" }`.
- `marketSignals`: JSON text object with `views`, `likes`, `saves`, `skips`, `contactRequests`, `avgTimeIn3dSeconds`, `liveViewers`, `likesToday`, `likesTodayDate`, `detailViews`, `gallerySwipes`, `avgDetailStaySeconds`, and `lastViewedAt`.
- `verification`: JSON text object with `verified`, `method`, `videoUrl`, and `capturedAt`. A property is treated as verified only when `verified=true`, `method="camera_video"`, and `videoUrl` is present.
- `verifiedListing`: boolean denormalized from `verification` for server-side filtering and ranking diagnostics.
- `verificationMethod`: string, currently `camera_video` for landlord-captured verification video.
- `verificationVideoUrl`: string, the captured in-app verification video URL/path.
- `verifiedAt`: datetime, when the in-app verification video was captured.
- `virtualTour`: JSON text, optional current 3D tour snapshot.
- `tourStatus`: enum string, `none`, `captured`, `queued`, `uploading`, `processing`, `ready`, `failed`.
- `tourViewerUrl`: string, optional lightweight hosted viewer URL.
- `tourProvider`: string, optional provider key, e.g. `splat3d`.
- `status`: enum string, `draft`, `active`, `paused`, `rented`.
- `createdAt`: datetime.
- `updatedAt`: datetime.

For owner-created properties, require a fresh property-level consent capture before first publish or re-publish with new media/model assets. That consent is stored under `legal` and should not depend only on sign-up acceptance.

`property_3d_tours`

- `tourId`: string.
- `propertyId`: string.
- `ownerUserId`: string.
- `provider`: string, e.g. `splat3d`, `openstrate`, or another video-to-3D backend.
- `status`: enum string, `captured`, `queued`, `uploading`, `processing`, `ready`, `failed`.
- `sourceVideoFileId`: string, optional storage file ID for the raw capture.
- `sourceVideoUrl`: string, optional internal URL. Do not expose publicly by default.
- `viewerUrl`: string, optional public lightweight viewer URL.
- `downloadUrl`: string, optional short-lived or protected model download URL.
- `previewImageUrl`: string, optional thumbnail/poster image.
- `format`: string, e.g. `sog`, `ply`, `glb`, `gltf`.
- `processingStage`: string, optional provider stage.
- `processingProgress`: integer, optional 0-100.
- `qualityScore`: double, optional provider metric.
- `errorMessage`: string, optional sanitized failure reason.
- `createdAt`: datetime.
- `updatedAt`: datetime.

`scan_requests`

- `requestId`: string.
- `propertyId`: string.
- `tenantUserId`: string.
- `ownerUserId`: string.
- `status`: enum string, `requested`, `accepted`, `captured`, `declined`, `expired`.
- `createdAt`: datetime.
- `updatedAt`: datetime.

`swipes`

- `swipeId`: string.
- `tenantUserId`: string.
- `propertyId`: string.
- `direction`: enum string, `like`, `pass`, `superLike`.
- `createdAt`: datetime.

`property_view_sessions`

- `sessionId`: string, deterministic client session ID.
- `propertyId`: string, indexed.
- `userId`: string, indexed.
- `startedAt`: datetime.
- `lastSeenAt`: datetime, indexed.
- `endedAt`: datetime, optional.
- `active`: boolean, indexed.
- `durationSeconds`: integer.
- `photoSwipeCount`: integer, number of gallery image/video transitions inside the property detail page.
- `currentPhotoIndex`: integer, last visible gallery index.

Use this table for `x מסתכלים עכשיו`: count rows for the same `propertyId` where `active=true` and `lastSeenAt` is within the active-viewer window. The Flutter client currently uses a 45-second window and sends a heartbeat while the detail page is open.

`property_likes`

- `propertyId`: string, indexed.
- `userId`: string, indexed.
- `date`: string, `YYYY-MM-DD`, indexed.
- `likedAt`: datetime.

Use row IDs keyed by `propertyId + userId + date` so each user counts once per property per day. `x אהבו היום` is the count of rows for the property where `date` equals the current local day.

`landlord_decisions`

- `decisionId`: string.
- `landlordUserId`: string.
- `tenantUserId`: string.
- `propertyId`: string.
- `decision`: enum string, `approve`, `reject`.
- `createdAt`: datetime.

`matches`

- `matchId`: string.
- `propertyId`: string.
- `tenantUserId`: string.
- `landlordUserId`: string.
- `status`: enum string, `open`, `contractSent`, `closed`, `cancelled`.
- `createdAt`: datetime.
- `updatedAt`: datetime.

`messages`

- `messageId`: string.
- `matchId`: string.
- `senderUserId`: string.
- `text`: string.
- `createdAt`: datetime.
- `readAt`: datetime, optional.

## Permission Model

- Public users can read only `properties` where `status=active`.
- A tenant can create swipes only for their own `tenantUserId`.
- A landlord can manage only properties where `ownerUserId` matches their user ID.
- A landlord can create/update 3D tours only for properties they own.
- Public users can read only 3D tours where the parent property is `active` and the tour status is `ready`.
- Raw scan videos are private to the owner and backend processing service; tenants receive only `viewerUrl`/preview assets.
- A match is readable only by its tenant and landlord.
- Messages are readable and writable only by users on the match.
- Storage files must be owned by the uploading user; property images and videos must be writable only by the property owner.

## Ranking Engine V1

Keep the first algorithm deterministic and server-side:

- Budget fit: 30 points.
- Room fit: 15 points.
- Area fit: 20 points.
- Move-in date fit: 10 points.
- Feature overlap: 15 points.
- Listing quality: 10 points for media coverage, complete address, and active owner profile.

The server should return properties ordered by score, with already-swiped properties excluded for that tenant.
