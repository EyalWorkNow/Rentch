# Rentch 3D Apartment Tours

## Goal

Add video-to-3D apartment tours without making Rentch heavy:

- Landlords capture one guided walkthrough from the phone.
- Tenants see a clear 3D badge and open the tour only when they want it.
- The app stores metadata and lightweight viewer links, not raw models in the main browsing feed.
- Provider API keys stay on a backend proxy/Appwrite Function, never in the Flutter client.

## Product Flow

### Landlord Capture

1. In the add-property media step, the owner can attach normal photos/videos and a separate 3D scan video.
2. The scan guide favors a 45-75 second steady walkthrough with good lighting and one pass through each room.
3. Publishing is not blocked by processing. If the backend proxy is unavailable, the scan is saved as a local draft with `captured` status.
4. When `RENTCH_3D_SCAN_PROXY_URL` is configured, the app submits the capture through the proxy and saves the returned scan status.
5. Owners can also import exported `Scaniverse` model files (`.glb`, `.obj`, `.mtl`, `.usdz`, textures, and related assets). The app uploads them to S3, then asks the backend to create a hosted viewer page.

### Tenant Discovery

1. Swipe cards show a compact `3D` badge only when `virtualTour.status == ready`.
2. Property details distinguish between ready, processing, captured-but-not-uploaded, and unavailable tours.
3. The tour button opens a hosted viewer link in an in-app browser view. The main app shell does not embed a 3D engine by default.

## Technical Architecture

### Flutter Client

- `RentalProperty.virtualTour`: current tour snapshot for fast browsing.
- `PropertyVirtualTour`: provider, status, viewer URL, download URL, preview URL, format, progress, quality, and error metadata.
- `Property3dScanService`: backend-proxy contract for creating a scan, uploading to a presigned URL, starting processing, and refreshing status.
- `PropertyRepository`: dual-writes landlord properties into the `properties` table when Appwrite is configured, while preserving the existing local state path.

### Backend Proxy Contract

The Flutter client expects this proxy shape:

```http
POST /scans
{
  "propertyId": "custom-...",
  "title": "Dizengoff, Tel Aviv",
  "contentType": "video/mp4",
  "fileSize": 52428800,
  "provider": "splat3d",
  "preset": "standard",
  "output": { "formats": ["sog"] }
}
```

Response:

```json
{
  "data": {
    "scanId": "provider-scene-id",
    "uploadUrl": "https://presigned-upload-url"
  }
}
```

Then:

```http
PUT {uploadUrl}
POST /scans/{scanId}/process
GET /scans/{scanId}
```

For imported 3D assets, the Flutter client also uses:

```http
POST /3d/viewers
{
  "propertyId": "custom-...",
  "title": "Dizengoff, Tel Aviv",
  "assets": [
    {
      "kind": "glb",
      "url": "https://rentch-media-.../3d-assets/custom-.../box.glb",
      "fileName": "box.glb",
      "contentType": "model/gltf-binary"
    }
  ]
}
```

Response:

```json
{
  "data": {
    "viewerUrl": "https://rentch-media-.../3d-viewers/custom-.../viewer.html",
    "downloadUrl": "https://rentch-media-.../3d-assets/custom-.../box.glb",
    "format": "glb"
  }
}
```

Status responses should normalize provider fields to:

```json
{
  "data": {
    "id": "provider-scene-id",
    "status": "processing",
    "processing_stage": "training",
    "processing_pct": 65,
    "viewer_url": null,
    "download_url": null,
    "format": "sog"
  }
}
```

## Data Strategy

Keep the current MVP blob path for compatibility, but move marketplace data toward table ownership:

- `properties`: searchable marketplace records and current `virtualTour` snapshot.
- `property_3d_tours`: full scan/tour lifecycle.
- `scan_requests`: tenant requests for landlords to add a scan.
- Raw scan videos: private storage with short retention.
- Ready viewer assets: public/CDN-friendly or provider-hosted.

## Weight Control

- Do not load 3D assets in the swipe feed.
- Use only tour status and optional preview image in cards.
- Prefer hosted viewer URLs or web-optimized formats for tenants.
- Store raw PLY/GLB downloads only for owner/admin workflows.
- Keep mobile capture duration short and compress before upload in a future native pass.

## Rollout

1. Current: data model, local capture draft, proxy contract, lazy viewer UI, dual-write property repository.
2. Next: Appwrite Function/proxy with provider API key and polling job.
3. Then: landlord dashboard status/retry controls and tenant "request 3D scan" action.
4. Later: capture coach overlays, ARKit camera poses where available, thumbnail generation, analytics on tour open-to-lead conversion.
