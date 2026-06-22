# Street-View-style 360° experience — how it works & how we build it

The goal isn't "show a 360 photo" (we already do that). It's the **walking
experience**: you look around, see arrows on the floor, click one, and the world
*rushes forward and dissolves* into the next spot — so it feels like you walked
there. This doc explains how Google Street View does it and the practical way we
reproduce it in Flutter.

---

## 1. How Google Street View actually works

**A) Each spot is a panorama ("pano").**
An equirectangular image (2:1) — or 6 cube faces — texture-mapped onto the inside
of a sphere. The camera sits at the centre; dragging rotates the camera
(yaw=longitude, pitch=latitude). This is the part `panorama_viewer` already gives
us.

**B) Panos form a graph.**
Every pano has a world position (lat/lng) and **links** to neighbouring panos,
each link carrying a **heading** (the compass direction you'd walk). The on-floor
arrows are these links, drawn at the bottom of the sphere pointing along their
heading.

**C) The transition is the magic.**
When you click a link, Street View does NOT cut. It:
  1. Keeps your current heading.
  2. **Dollies forward** — zooms the current pano toward the travel direction
     (foreground rushes past).
  3. **Crossfades** into the destination pano, which appears already facing the
     same heading, starting slightly zoomed-in and settling.
Modern Street View also has a coarse **depth map** per pano and reprojects pixels
during the dolly, giving real parallax (near things move faster than far). The
depth map is what makes it feel 3D rather than a slideshow.

**D) Continuity & preloading.**
Your heading is preserved across the jump, and neighbours are pre-fetched so the
transition is instant.

---

## 2. What's feasible for us (DIY photospheres, no depth data)

We have user-captured photospheres with **no depth maps** and **no compass
alignment**. So:

| Street View feature | Our practical version |
|---------------------|------------------------|
| Sphere render + look-around | `panorama_viewer` (have it) ✅ |
| Pano graph + link headings | node graph; heading from the tapped arrow's longitude |
| Depth-map parallax dolly | **approximated**: zoom-dolly + crossfade (no depth) — still reads as "moving forward" |
| Heading continuity | arrive facing the travel direction (destination's back-link + 180°) |
| On-floor arrows | hotspots at low latitude (pitch ≈ -25°) along link directions |
| Preloading | `precacheImage` on neighbours |
| Mini-map | node-graph overlay (positions optional; else a sequence strip) |

The one thing we can't do without depth is true parallax. The **zoom-dolly +
crossfade** is the well-known fallback (it's what Street View itself uses when a
depth map is missing) and is convincing.

---

## 3. The transition engine (the core), step by step

Implemented snapshot-based for performance (one live GL viewer, not two):

```
navigate(toNode, arrivalHeading):
  1. snapshot = RepaintBoundary(current PanoramaViewer).toImage()   // ui.Image
  2. swap the live PanoramaViewer to `toNode`, initial longitude = arrivalHeading
     (it builds underneath, already facing the right way)
  3. overlay the snapshot on top; animate over ~650ms:
        snapshot:   scale 1.0→1.7 (forward dolly toward centre) , opacity 1→0
        new pano:   scale 1.08→1.0 (emerge)                      , opacity 0→1
  4. on complete: drop the overlay; preload the new node's neighbours
```

`Transform.scale + Opacity` on a captured `RawImage` is cheap (no second GL
context), so the transition is smooth even on mid-range phones.

`arrivalHeading` = longitude of the destination's hotspot that points back to the
origin, **+180°** (so you face away from where you came = forward). Falls back to
the current heading when geometry is unknown.

---

## 4. Build decomposition (6 parts)

1. **Research/arch** (this doc).
2. **Transition engine** — snapshot zoom-dolly + crossfade (`PanoramaExperienceView`).
3. **Heading continuity + preloading** — arrival heading + `precacheImage`.
4. **Ground arrows + reticle** — floor-projected link arrows, face-to-highlight.
5. **Mini-map** — graph overlay + viewing cone + tap-to-jump.
6. **Assembly + wiring + tests** — replace the plain viewer at `openPropertyTour`,
   widget tests, analyze, commit.

Optional later: capture-time **map placement** of points (gives real positions →
accurate arrows + mini-map), and **depth estimation** (monocular ML) for true
parallax.
