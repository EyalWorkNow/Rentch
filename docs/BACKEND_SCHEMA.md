# Rentch Backend Schema

The current `RENTCH_LAUNCH_MODE=true` path can run a controlled MVP against the existing Appwrite `app_state/global_state` row. It is not the final production backend because user state is not isolated per authenticated user.

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
- `features`: JSON text.
- `media`: JSON text array with objects like `{ "url": "...", "type": "image" | "video" }`.
- `status`: enum string, `draft`, `active`, `paused`, `rented`.
- `createdAt`: datetime.
- `updatedAt`: datetime.

`swipes`

- `swipeId`: string.
- `tenantUserId`: string.
- `propertyId`: string.
- `direction`: enum string, `like`, `pass`, `superLike`.
- `createdAt`: datetime.

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
