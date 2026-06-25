# pole_fill — honest ceiling/floor caps for phone panoramas

A single horizontal phone panorama (one native-pano-mode sweep) has **no real
ceiling or floor** — the poles are empty or stretched smear. `pole_fill` composites
**real** floor + ceiling photos into the pole caps, producing a completed
equirectangular panorama. No diffusion, no GPU, no hallucination — the
Street-View / Insta360 "nadir-patch" method at ~$0 compute.

This is the server side of the optional **"שפר רצפה ותקרה"** step in the Rently
panorama capture flow (`lib/presentation/features/panorama/panorama_capture_screen.dart`
→ `panorama_pole_capture.dart`). The app sends three images — the horizontal strip,
one downward (floor) photo, one upward (ceiling) photo — and gets back a full pano.

## How it works

1. Place the strip into a full 360×180 equirect frame at the correct latitude band
   (`vaov` / `voffset`), leaving the pole bands empty.
2. Default-fill the empty poles with a **blur-stretch** of the nearest strip row
   (honest soft cap, the renderstuff look — also the app's offline fallback).
3. Convert to a cubemap (`py360convert.e2c`). The **U** face *is* the zenith cap and
   **D** *is* the nadir cap — a flat phone ceiling/floor photo maps onto a cube face
   with no distortion.
4. Homography-align (ORB + RANSAC) each pole photo onto its cube face when the cap
   has surrounding strip pixels to match; otherwise center-fit. Feather-blend with a
   radial mask so the cap meets the strip without a seam.
5. Convert back to equirect (`py360convert.c2e`), composite **only** the empty pole
   bands over the untouched strip, and heal the 360° wrap seam.

The strip's own pixels are never altered — only the empty poles are filled.

## Install

```bash
/Library/Frameworks/Python.framework/Versions/3.12/bin/python3 -m pip install -r requirements.txt
```

Libraries: **py360convert** (MIT) · **OpenCV** (Apache-2.0) · **numpy**. All
commercial-resale-safe (matches the license policy in `RENTLY_SPATIAL_ARCHITECTURE.md` §7).

## Run

```bash
python3 pole_fill.py \
  --strip strip.jpg --floor floor.jpg --ceiling ceiling.jpg \
  --out completed.jpg \
  --vaov 60 --voffset 0 --width 4096
```

- `--floor` / `--ceiling` are optional; omit either to keep the cheap blur-stretch
  cap for that pole.
- `--vaov` = the strip's vertical field of view in degrees (default 60 — same default
  the app uses). `--voffset` levels the horizon (+down).
- `--width` = output equirect width; height is always width/2.

## Self-check

Runs a synthetic, assert-based composite proving the pipeline runs and the output
dimensions / pole placement / wrap seam are correct. Writes `selfcheck_output.jpg`.

```bash
python3 pole_fill.py              # no args -> self-check
python3 pole_fill.py --selfcheck
```

Expected:

```
ALL ASSERTIONS PASSED
```

## Wiring into the AWS pipeline

Drop `fill_poles()` into a Lambda / Batch handler: read the three S3 objects, call
`fill_poles(strip, floor, ceiling, out_w=4096, vaov=..., voffset=...)`, write the
result back to the derived bucket, and return its URL (the equirect can then be fed
straight to Pannellum / Photo Sphere Viewer with `haov:360, vaov:180`).
