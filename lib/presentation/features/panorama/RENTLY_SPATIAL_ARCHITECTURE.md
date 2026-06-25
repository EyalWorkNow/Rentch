# Rently Spatial Capture & Data Architecture (June 2026)

> Supersedes the capture/quality parts of `STREETVIEW_ARCHITECTURE.md`. That doc
> stays valid for the *viewer/transition* logic; this one defines **capture,
> processing, the walkable-3D experience, the data product, and the legal gate**.

---

## 0. The three goals (in the user's words)

1. **Collect high-quality spatial data at volume** — this is the master goal; the
   app's features are the data-collection funnel.
2. **Walkable apartments** — seekers move through a unit "like a computer game".
3. **Street-View-style 360 tours** — landlords stand at real points, rotate with
   on-screen guidance to capture a genuine high-quality 360, then pick the next
   point and walk there. Repeat → a linked tour.

We serve all three with **one capture session** that produces both a tour *and* a
walkable scan *and* the raw data we resell. Capture once, derive many.

---

## 1. Why the current 360 is "terrible" — root cause, not tuning

Current pipeline: handheld camera **sweep** → gyro-triggered frames → AWS
**OpenCV stitch** → equirectangular → Pannellum.

The failure is **physical, not a parameter to tweak**: a handheld phone rotates
about your wrist/spine, **not about the lens nodal point**. Every frame sees
foreground furniture from a slightly different position → **parallax** that no
2D stitcher can warp away → ghosting, broken edges, doubled chair legs. OpenCV
also *guesses* geometry from feature matches, which **fails exactly on interiors**:
blank walls (no features), repeating tiles/blinds (false matches), big near-object
parallax. Auto-exposure drift between a dim hall and a bright window adds seams.

**Conclusion:** "better stitching software" is the wrong fix. The fix is **better
capture constraint** — either remove parallax at the source (single-shot 360
camera) or *measure* the camera pose (ARKit/ARCore) and stitch against known
geometry instead of guessing.

---

## 1bis. REVISED capture (2026-06-24, after user feedback) — the renderstuff insight

**User feedback that overrides §2 below:** the current capture forces **42 frames
over 3 horizontal passes** (`panorama_sweep_capture.dart`) — effectively spinning
3× — then reinvents stitching with OpenCV, badly. The user took ONE normal phone
panorama (native pano mode, single sweep, a few seconds), dropped it into the free
**renderstuff.com** "panorama→360" tool, and got a **far better** result. Flaws
were only: no real ceiling/floor, and depth/distances off.

**What renderstuff does = nothing clever:** it textures a cylindrical/partial pano
onto a sphere (partial vertical FOV; poles absent or stretched). The win is that a
**single smooth sweep has no parallax stitch seams** — so it beats our 42-frame
OpenCV result on the horizontal, and just lacks honest poles.

**The lazy, higher-quality replacement (do this instead of §2's multi-frame):**

1. **Capture = one fast pano, not 42 frames.**
   - Best & zero-code: let the user shoot a pano in their **own Camera app**
     (native pano mode is years of tuned stitching, a few seconds) and **import it
     via the system photo picker** Rently already uses. (No public API to trigger
     native pano mode programmatically — import is the path.)
   - In-app controlled: a single **3–5s horizontal sweep video** → OpenCV
     `Stitcher` PANORAMA mode (one cylindrical pano), guided by an arc + "pan
     slowly" overlay. Kill the 3-row/42-frame ratchet.
2. **Display = feed the pano DIRECTLY to a partial-FOV viewer. No stitching, no
   conversion.** The `PanoramaNode` model **already has `haov`/`vaov` fields** for
   exactly this. **Pannellum** (MIT): `haov:360, vaov:~60, vOffset:0` places the
   strip at the correct latitude band with *honest* empty poles instead of smear.
   **Photo Sphere Viewer** (MIT): `panoData` cropped-pano support + reads XMP crop
   metadata automatically. This is the single highest-leverage change and it's
   almost no code. Add a soft top/bottom gradient mask so the void reads as intent.
   - FOV inference is the fragile bit (phone EXIF rarely states true vertical FOV)
     → default `vaov≈60°` and expose a small slider to level the horizon.
3. **Poles (ceiling/floor) — cheap & honest beats AI for a listing.** Default
   **blur-stretch cap**; offer a **one-tap "point down, now up"** that composites
   real floor/ceiling into the nadir/zenith (`py360convert` + homography align +
   feather) — the Street View / Insta360 nadir-patch method, ~$0 compute, **real**
   not hallucinated. AI pole-fill only when poles are busy: **LaMa** (Apache-2.0)
   on the reprojected **cubemap cap face** (`ProGamerGov/ComfyUI_pytorch360convert`)
   with seam-rolling, ~$0.004/pano on **CPU SageMaker Serverless** ($0 idle). Avoid
   diffusion pole-gen (DiT360 etc.) for listings — it invents ceiling fixtures &
   floor that won't match furniture, plus FLUX.1-dev base is non-commercial.
4. **Depth/distances — do NOT ship a depth-displaced sphere for furnished rooms**
   (that's exactly where it rubber-sheets and tears). Use **room-layout** instead:
   **HorizonNet** (MIT code) → textured polygon-prism in three.js → clean in-room
   parallax + a **free floorplan + room-dimensions data product**. Add **AtlantaNet**
   (MIT) for L-shaped/non-rectangular rooms. This is what **Zillow 3D Home** does.
   Metric scale from a **measured tripod height** (~1.5m → ~2–5% dimension error),
   not the model's scale. Sell **depth maps** (DA² Apache / Depth-Anything-v2 Small
   Apache / Metric3D-v2 BSD) as a *separate* data artifact, not the renderer.
   - ⚠️ **Dataset-license trap:** layout/depth model *weights* trained on
     Matterport3D / ZInD / Structured3D are **non-commercial** even when the code is
     MIT. For the resale business, **retrain on Rently's own captured panos** (the
     app already captures them) or use only Apache/BSD-trained weights. Code license
     ≠ weight license — audit the training mix.

**Net:** capture one fast pano → show it in Pannellum/PSV with correct `haov/vaov`
→ honest poles (cheap composite) → optional HorizonNet box for parallax + floorplan.
This matches renderstuff on day one, beats it on the poles, and is *less* code than
the current 42-frame pipeline. The pose-assisted multi-frame design in §2 becomes a
**later, optional high-end tier**, not the default. Repos: `mpetroff/pannellum`
(MIT) · `mistic100/Photo-Sphere-Viewer` (MIT) · `sunset1995/py360convert` (MIT) ·
`advimman/lama` (Apache-2.0) · `ProGamerGov/ComfyUI_pytorch360convert` ·
`sunset1995/HorizonNet` (MIT) · `crs4/AtlantaNet` (MIT) · `EnVision-Research/DA-2`
(Apache-2.0) · `YvanYin/Metric3D` (BSD-2).

---

## 2. Capture strategy — three tiers, one funnel
*(Superseded as the DEFAULT by §1bis; keep as the higher-effort premium tier.)*

Tier by device/landlord, all feeding the same upload contract. Higher tiers =
higher quality **and** more valuable resale data.

| Tier | Who | Capture | Quality | Data value |
|------|-----|---------|---------|-----------|
| **T0 — 360 camera ingest** | landlords with / willing to buy an Insta360-class cam (~$300) | connect cam, import equirectangular JPG | **Highest** (one nodal point, zero stitch) | high (clean equirect + optional depth) |
| **T1 — Pose-assisted phone 360** | any modern phone | guided "align-the-dot" rotation, **ARKit/ARCore pose tagged per frame** | good (pose-constrained stitch ≫ today) | **highest** (raw frames + 6DoF pose + IMU) |
| **T2 — Walkthrough video → splat** | any phone | slow walk-through video sweep | photoreal walkable scene | very high (video + pose track) |

**Key reframing for the data business:** T1/T2 are *more* valuable than T0 even
though T0 looks better, because **raw frames + 6DoF pose + IMU cannot be
recomputed once discarded** and their value compounds as reconstruction models
improve (this is exactly why Apple's ARKitScenes preserves them). So: **push T1/T2
as the default, offer T0 as the premium "best looking" path.**

### 2.1 The capture upgrade that fixes everything: pose tagging

The single highest-leverage change. Tag every captured frame/video timestamp with
the device's **6-DoF camera pose** from visual-inertial odometry:

- **iOS:** `arkit_plugin` (actively maintained, v1.5.0 ~Jun 2026) exposes pose
  directly — `ARKitController.cameraPosition()`, `getCameraEulerAngles()`,
  `cameraProjectionMatrix()`. **Build iOS first.**
- **Android:** the Flutter ARCore plugins are **stale** — write a **platform
  channel** over ARCore `Frame`/`Camera.getDisplayOrientedPose()` to get raw frame
  + pose together. Gate Android behind this.

Pose unlocks: (a) precise "align-the-dot" guidance, (b) **pose-constrained
stitching** (refine, not guess), (c) the camera trajectory that is itself prime
resale data, (d) COLMAP pose seeding for splats (skip/accelerate SfM).

> Lock **AE/AWB at capture start** (one exposure across the sweep). This removes
> most exposure-seam problems for free — more impactful than any blender.

---

## 3. Processing pipeline (AWS)

```
 phone/cam ──upload──> S3 (raw bucket)
   frames/video + pose.json + IMU + intrinsics + (LiDAR depth if available)
        │
        ├─ S3 event ─> Step Functions / AWS Batch (scale-to-zero)
        │       ├── [360]  pose-constrained stitch  ─> equirectangular + GPano XMP
        │       │           OpenSfM(BSD)/OpenMVG(MPL2) pose graph + OpenCV(Apache) multiband
        │       ├── [depth] per-pano depth map (EGformer MIT / Metric3D v2 BSD)
        │       └── [splat] COLMAP/GLOMAP(BSD) poses ─> gsplat/Brush(Apache) train ─> .spz
        │
        └─> S3 (derived) ─> CloudFront ─> app
            + PII-redaction pass (fail-closed) before anything enters the "sellable" bucket
```

- **360 stitch:** no GPU needed — EC2 compute-optimized or Lambda (within 15-min/
  10-GB). **License-safe set only:** OpenSfM (BSD) or OpenMVG (MPL2) for the pose
  graph, OpenCV (Apache-2.0) multiband blend, emit `GPano` XMP. **NEVER Hugin /
  panotools / enblend (GPL)** — copyleft poisons a product that sells imagery.
- **Splat training:** GPU. **AWS Batch** with **g6/g6e (L4/L40S) spot +
  checkpointing**. ~30–60 min wall-clock, **~$0.20–0.35/apartment on spot** GPU-only;
  budget **$1–3 fully loaded** (re-runs, egress, ops). **MVP: don't build this —
  use the Luma AI API** (only managed option with a clean "you own it,
  commercial-resale-OK" posture). Bring in-house once volume justifies it.
- **Depth (for real parallax):** one-time per-pano preprocess on g5/g6.

---

## 4. The two viewer experiences

### 4.1 Linked 360 tour (replace Pannellum)

Move to **Photo Sphere Viewer v5 + VirtualTourPlugin + MarkersPlugin** (MIT,
actively maintained, TypeScript). It is the only OSS viewer shipping **native 3D
ground-plane "walk-forward" arrows** (the exact Street-View look) with zero custom
rendering, plus a node graph and rich markers. Embed in **`flutter_inappwebview`**.
Keep Pannellum only if webview memory is a hard limit. **Avoid Marzipano** —
Google archived the repo (read-only) April 2026.

**Real parallax (kills the fake crossfade):** precompute a depth map per pano
(**EGformer**, MIT, 360-native — or **Metric3D v2**, BSD, metric+normals), ship it
with the pano, and in a small custom **three.js** layer displace a sphere mesh by
depth and dolly the camera along the link vector → near geometry sweeps faster than
far walls = genuine parallax. Add LDI inpainting (`vt-vl-lab/3d-photo-inpainting`)
later for clean disocclusions. PSV handles static viewing + arrow UI; drop into
three.js only for the walk animation (PSV's crossfade can't express depth parallax).

### 4.2 Walkable scan (the "computer game" experience)

**3D Gaussian Splatting** is the 2026 answer (NeRF lost on runtime; mesh only where
you need measurements). Pipeline: capture video → splat → deliver **`.spz`**
(Niantic, Apache-2.0, ~10×, keeps spherical harmonics) → render with **PlayCanvas
engine + SuperSplat** (MIT, best mobile ecosystem: SOG/SOGS compression, LOD, splat
budget) inside `flutter_inappwebview`. **Native Flutter splat renderers are not
production-grade in 2026** — WebView is the realistic path.

- **Mobile budget:** target **~500K–1M splats, capped DPR, ~30 FPS**, with an LOD
  downgrade fallback. The 100+ FPS papers are flagship native renderers, not
  JS-in-WebView — validate on real mid-range Android.
- **Navigation = the hard part** (a splat has no surfaces; a free camera flies
  through walls). **Ship Tier-0/1 navigation: authored teleport waypoints + smooth
  spline transitions** (Matterport-style). No collision system, low motion
  sickness, multi-floor "just works", never wanders into capture voids. True
  free-walk (voxel flood-fill collision mesh via PlayCanvas `splat-transform`) is a
  later premium tier for validated spaces only.
- **Floor lock:** gravity-align from IMU, RANSAC plane-fit on COLMAP sparse points,
  lock camera to `floor_y + eye_height`.

---

## 5. The data product (the actual business)

### 5.1 Preserve raw, regenerate derived

**PRESERVE AT ALL COSTS (cannot be recomputed):** full-res source frames/video
(pre-stitch, highest bitrate), camera intrinsics/EXIF, **6-DoF pose tracks**, raw
**IMU**, **LiDAR depth + confidence** (iPhone Pro — consumer ground-truth metric
depth, the core of ARKitScenes' value), raw point clouds, precise cross-sensor
timestamps. **One derived exception worth keeping:** hand-curated semantic/instance
labels (what makes ScanNet++ premium).

**Regenerate on demand:** meshes, RoomPlan/ARCore geometry, floorplans, equirect
stitches — value decays because any future better model re-derives them.

### 5.2 Formats (sell open masters, deliver light)

| Need | Master / sell | Deliver | Never sell |
|------|---------------|---------|-----------|
| Point cloud | **LAZ** (LAS 1.4) / **E57** | 3D Tiles | PCD |
| Mesh | **glTF/GLB** (Draco+KTX2) | glTF/GLB | FBX |
| Apple room scan | **USDZ + `CapturedRoom` JSON** | USDZ | — |
| SfM | **COLMAP sparse** (the NeRF/3DGS input contract) | — | — |
| Splat | **PLY** master | **SPZ** → glTF `KHR_gaussian_splatting` (RC Feb 2026) | raw `.splat` |
| RGBD pano | equirect + 16-bit depth | same | — |

### 5.3 Who buys & the moat

AI-training data licensing **$4.8B (2025) → ~$22.6B (2034)**; robotics fastest.
Highest ceiling = **AI / 3D-vision / world-model training** (NVIDIA Cosmos, Scale
AI "Physical AI", Meta Aria). **The structural gap Rently can fill:** nearly every
premium indoor-scan dataset (ScanNet++, Matterport3D, ARKitScenes, Replica,
Hypersim) is **research-only / non-commercial**. A **commercially-clean,
consent-licensed indoor-scan dataset is genuinely scarce** — that is the moat, and
it is a *legal/consent* moat as much as a data moat. (Weaker buyers: proptech
self-captures; insurers/appraisers want standards-compliant measurements, not raw
clouds.) Marketplaces: Datarade, AWS Data Exchange, Snowflake, Defined.ai.

---

## 6. ⚠️ Legal & privacy gate — read before building any "sell" feature

**This is the highest-risk part of the entire plan and it is structurally fragile,
not fixable with paperwork.** You are stacking the **highest-risk data type**
(interior scans = PII-dense + special-category-dense: faces, mail with name+address,
screens, religious/medical/orientation objects) onto the **highest-risk purpose**
(sale of personal data).

**Hard blockers:**
- **A landlord cannot consent for a tenant.** You need (1) owner consent to
  commercialize the space **and** (2) **each adult occupant's separate, explicit,
  unbundled, revocable consent** to sell data depicting them. Hard-block sale of any
  unit missing any occupant opt-in. Vacant ≠ PII-free.
- **Apple §5.1.2(vi)** — data from depth/AR/Camera APIs **"may not be used for
  marketing, advertising or use-based data mining, including by third parties."**
  This may simply **forbid the resale model**; probability of passing Apple review
  unmodified is candidly low. Google Play parallel: prohibition on selling
  personal/sensitive data + Data-safety form (tightening 15 Apr 2026).
- **GDPR:** only defensible basis for selling is **explicit Art. 6(1)(a)+9(2)(a)
  consent**; purpose-limitation bars repurposing service data; erasure/withdrawal
  must **propagate to every buyer**; non-EEA transfer needs SCCs (Israel's EU
  adequacy is under 2025 challenge — don't architect around it).
- **Israeli Privacy Protection Law Amendment 13** (effective 14 Aug 2025): selling
  scans makes you a **data broker** (registration, records, opt-out, broker number
  in comms); fines with **per-subject multipliers**, statutory damages up to
  ILS 100,000 without proof of harm, up to 3 years imprisonment.

**Mandatory guardrails (all required before selling anything):**
1. Tenant opt-in, separate & unbundled, **fail-closed** (default = NOT sellable).
2. Automated **PII-redaction pipeline + human QA, fail-closed**: faces
   (`ORB-HD/deface`, MIT), 360 faces+plates (`openwanderer/anon`), OCR text/mail
   (`microsoft/presidio`, MIT). Redaction is necessary but **not sufficient**
   (misses reflections, partial faces, religious/medical objects).
3. Anonymize/aggregate + **de-link from address**.
4. **DPA with every buyer**: purpose limitation, no re-identification, deletion
   propagation, audit rights.
5. Purpose limitation — no resale of service-collected data without fresh consent.
6. Israeli data-broker registration + DPO + records.
7. In-app withdrawal + deletion that propagates to buyers.
8. Geographic restrictions with SCCs ready.
9. Honest store disclosures, purpose strings, App Privacy / Data-safety labels
   marking data as **collected AND sold/shared**.

> **Get specialized GDPR + Amendment-13 counsel and an Apple pre-review before
> shipping any sale feature.** Treat the data-sale layer as a separate, gated
> workstream — the capture/viewer product can ship and create value on its own
> while the legal foundation is built.

---

## 7. Tech stack — license summary (resale-critical)

| Layer | Pick | License | Commercial-resale |
|-------|------|---------|-------------------|
| iOS pose | `arkit_plugin` | MIT | ✅ |
| Android pose | custom platform channel / ARCore | Apache | ✅ |
| 360 stitch geometry | OpenSfM / OpenMVG | BSD / MPL2 | ✅ |
| 360 blend | OpenCV `stitching` | Apache-2.0 | ✅ |
| 360 stitch (DO NOT USE) | **Hugin / enblend** | **GPL** | ❌ copyleft |
| Pano depth | EGformer / Metric3D v2 | MIT / BSD | ✅ |
| Depth (avoid big weights) | Depth-Anything-V2 L/G | **CC-BY-NC** | ❌ NC |
| SfM for splats | COLMAP / GLOMAP | BSD | ✅ |
| Splat training | **gsplat / Brush** | Apache-2.0 | ✅ clean-room |
| Splat training (DO NOT USE) | **graphdeco-inria 3DGS**, **Naver Dust3r/Mast3r** | **non-commercial** | ❌ voids resale |
| Splat (self-host, copyleft) | OpenSplat | AGPLv3 | ⚠️ network-source clause |
| Managed splat (MVP) | **Luma AI API** | commercial-OK | ✅ clearest posture |
| Splat delivery | `.spz` (Niantic) | Apache-2.0 | ✅ |
| Splat viewer | PlayCanvas + SuperSplat / `mkkellogg/GaussianSplats3D` | MIT | ✅ |
| 360 tour viewer | Photo Sphere Viewer v5 | MIT | ✅ |
| Flutter embed | `flutter_inappwebview` | misc OSS | ✅ |
| PII redaction | deface / openwanderer-anon / Presidio | MIT / LGPL / MIT | ✅ (avoid OpenALPR AGPL) |

**Two license landmines that void the data-resale business if touched:**
`graphdeco-inria/gaussian-splatting` (+ its CUDA rasterizer, + Taming-3DGS core)
and Naver **Dust3r/Mast3r** family (CC-BY-NC-SA, code *and* weights). Build splats
only on **COLMAP/GLOMAP → gsplat/Brush**.

---

## 8. Build plan (phased, laziest-first)

**Phase 1 — Fix 360 quality (weeks):**
- iOS guided "align-the-dot" capture with `arkit_plugin` pose tagging; lock AE/AWB.
- Upload contract = frames + `pose.json` + intrinsics (+ LiDAR depth if present).
- AWS pose-constrained stitch (OpenSfM/OpenCV, license-safe), emit GPano.
- Swap viewer to Photo Sphere Viewer v5 (native floor arrows).
- *(Premium, near-free quality win:)* T0 360-camera ingest path.

**Phase 2 — Walkable scan MVP (weeks):**
- T2 video capture + coaching.
- **Luma AI API** reconstruction (no GPU pipeline yet) → `.spz`.
- PlayCanvas viewer in WebView, **teleport-waypoint navigation**.

**Phase 3 — Real parallax (incremental):**
- Per-pano depth (EGformer) → three.js depth-mesh dolly transitions.

**Phase 4 — Own the data pipeline (when volume justifies):**
- In-house COLMAP/GLOMAP → gsplat/Brush on AWS Batch g6 spot.
- Preserve full raw-data archive (frames/pose/IMU/LiDAR) in masters (LAZ/E57/PLY/COLMAP).

**Phase 5 — Data-sale layer (gated, parallel, lawyer-first):**
- Consent system (per-occupant, unbundled, fail-closed) → PII redaction + human QA
  → DPAs → broker registration → marketplace listing. **Do not ship without
  counsel + Apple pre-review.**

---

## 9. Self-criticism (honest bottom line)

- **Pose-assisted phone 360 still won't match a $300 360 camera** — pose *hides*
  parallax, doesn't remove it, and VIO **drifts on the exact blank-wall interiors
  you shoot**. Position T0 camera ingest as the quality benchmark; T1 as the
  "no extra hardware, better than today" tier.
- **Splat quality dies on white walls, mirrors, glass, motion blur, exposure
  drift** — engineering effort goes into surviving these, not into picking a GS
  variant. Capture coaching beats algorithms.
- **Mobile splat FPS is optimistic** — WebView-in-Flutter on mid-range Android is
  the real constraint; build the LOD fallback from day one.
- **In-house GPU cost is understated** at "$0.30/scan" — budget $1–3 loaded;
  CloudFront egress on popular listings can exceed training cost.
- **The data-sale business is the fragile part, and it's legal, not technical.**
  Consent leaks, Apple §5.1.2(vi), and Amendment-13 broker liability are each
  capable of killing it. The capture/viewer product stands on its own; treat
  resale as a gated bet, not a baked-in assumption.

---

### Source anchors
ARKitScenes (raw-data preservation) · RealEstate10K (video+pose value) · Niantic
SPZ (Apache-2.0) · gsplat/Brush (Apache-2.0) · COLMAP/GLOMAP (BSD) · Photo Sphere
Viewer v5 / Pannellum (MIT) · EGformer (MIT) / Metric3D v2 (BSD) · Luma AI API ·
Apple Guidelines §5.1.2 · GDPR Art. 5/6/9/17 · Israeli PPL Amendment 13.
