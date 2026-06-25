# Walkable 3D-Splat viewer (self-hosted)

Phase-2 MVP viewer for the "walkable scan" experience
(`RENTLY_SPATIAL_ARCHITECTURE.md` §4.2). Loaded by
`lib/presentation/features/panorama/panorama_splat_view.dart` inside a WebView,
served from a tiny on-device loopback HTTP server (same pattern as the Pannellum
panorama tour) so there are no CORS / mixed-content issues.

## Files

| File | What | License | Vendored? |
|------|------|---------|-----------|
| `index.html` | viewer shell + teleport-waypoint navigation | (ours) | n/a |
| `gaussian-splats-3d.js` | `@mkkellogg/gaussian-splats-3d` v0.4.6 ESM bundle (minified) | **MIT** | ✅ downloaded |
| `three.module.js` | three.js r160 (peer dependency, ESM, minified) | **MIT** | ✅ downloaded |
| `README.md` | this file | — | — |

Both JS files were fetched from jsDelivr:
- `https://cdn.jsdelivr.net/npm/@mkkellogg/gaussian-splats-3d@0.4.6/build/gaussian-splats-3d.module.min.js`
- `https://cdn.jsdelivr.net/npm/three@0.160.1/build/three.module.min.js`

They are wired together with an HTML `<script type="importmap">` mapping the bare
`three` specifier to `/three.module.js`. **No network is used for the viewer code
at runtime** — only the remote splat asset itself is streamed by the WebView.

> If these files ever need to be re-vendored, re-run the two `curl` commands
> above into this directory (keep the local filenames `gaussian-splats-3d.js` and
> `three.module.js`, which is what the Flutter HTTP server serves).

## Splat format — IMPORTANT (.spz caveat)

The doc specifies **`.spz`** (Niantic, Apache-2.0) as the delivery format. However
**GaussianSplats3D 0.4.x does NOT load `.spz` natively** — it loads `.ply`,
`.splat`, and `.ksplat` (`.ksplat` is its own compact runtime format).

Two ways to close this gap (pick one when wiring the backend):
1. **Convert `.spz` → `.ksplat` server-side** (the AWS derived-asset Lambda) and
   deliver `.ksplat` to the app. Best runtime perf + smallest download.
2. **Request a `.ply` from Luma** and deliver that. Simplest; larger file.

`index.html` already detects the format from the URL extension and picks the
right loader; an unrecognised extension (e.g. `.spz`) surfaces a clear Hebrew
error instead of silently failing. Keep `.spz`/`.ply` as the **master** in S3
(per §5.2) and deliver `.ksplat` to the client.

## Mobile performance (§4.2 budget)

Targets: **~500K–1M splats, capped DPR, ~30 FPS**, with an LOD fallback.

Implemented in `index.html`:
- **DPR cap** at 1.5 (no full-retina render).
- **`splatAlphaRemovalThreshold: 5`** prunes near-invisible splats to keep the
  sort budget down.
- **`sphericalHarmonicsDegree: 0`** — drops view-dependent SH to save memory/GPU
  on mid-range mobile.
- **`RenderMode.OnChange`** — only redraws when the camera moves, so standing
  still at a waypoint costs nothing (the cheapest possible FPS cap).
- **`progressiveLoad: true`** — scene streams in instead of a long stall.

**LOD fallback (not yet implemented — note for the next tier):** GaussianSplats3D
0.4.x has no built-in LOD. For real LOD/splat-budgeting, move to **PlayCanvas +
SuperSplat** (SOG/SOGS compression + LOD) per the doc, or pre-decimate the splat
server-side into a low / high `.ksplat` pair and pick by device class. Validate
FPS on a real mid-range Android before relying on these caps.

## Navigation

Teleport-waypoint only (Matterport-style, no collision system). Flutter calls
`window.rentlyStep(+1 | -1)` to move between preset camera poses
(`SplatWaypoint`s) with a smooth-stepped transition. Orbit is allowed at each
stop; there is no free-fly so the camera never flies through walls or into
capture voids.
