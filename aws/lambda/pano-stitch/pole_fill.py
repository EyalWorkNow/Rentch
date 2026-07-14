#!/usr/bin/env python3
"""pole_fill — composite REAL ceiling/floor caps into a phone panorama.

A single horizontal phone panorama (one smooth native-pano sweep) has *no* honest
ceiling or floor: the poles are empty or stretched smear. This tool takes that
horizontal strip plus ONE downward photo (the floor / nadir) and ONE upward photo
(the ceiling / zenith) and composites the two real photos into the pole caps of a
full equirectangular panorama.

Method (the cheap + honest Street-View / Insta360 "nadir-patch" approach — ~$0
compute, REAL pixels, nothing hallucinated):

  1. Place the strip into a full 360x180 equirectangular frame at the correct
     latitude band (haov/vaov), leaving the pole bands empty.
  2. Convert that equirect to a cubemap (py360convert.e2c). The Up and Down cube
     faces *are* the zenith/nadir caps — a single gnomonic photo maps onto a cube
     face with no distortion, which is exactly what a phone ceiling/floor photo is.
  3. Homography-align each pole photo onto its cube face (ORB feature match against
     whatever strip pixels bleed into the cap; gracefully falls back to a centered
     fit when the cap is blank — the common case for a pure horizontal strip).
  4. Feather-blend the pole photo into the cube face (radial mask) so the cap meets
     the strip without a hard seam, and seam-roll the equirect horizontally so the
     360° wrap (left edge == right edge) stays continuous.
  5. Convert the patched cubemap back to equirect (py360convert.c2e) and composite
     ONLY the pole bands back over the original strip (the strip's own pixels are
     never touched — we only fill what was empty).

Libraries: py360convert (MIT) + OpenCV (Apache-2.0) + numpy. No diffusion, no GPU,
no network. Output is a completed equirectangular JPEG/PNG.

CLI:
    python3 pole_fill.py --strip strip.jpg --floor floor.jpg --ceiling ceiling.jpg \
        --out completed.jpg [--vaov 60] [--voffset 0] [--width 4096]

Self-check (synthetic, asserts the composite runs and dimensions are correct):
    python3 pole_fill.py            # no args -> runs the demo / self-check
    python3 pole_fill.py --selfcheck
"""
from __future__ import annotations

import argparse
import os
import sys

import cv2
import numpy as np

try:
    # Real-cap compositing path. py360convert pulls in scipy, whose binary wheels
    # don't fit alongside OpenCV in the 250 MB zip-Lambda limit — so it's optional.
    # When absent, fill_poles falls back to blur-stretch poles (the architecture's
    # documented "honest cheap default"); the uploaded floor/ceiling photos are
    # still preserved for a later container-Lambda (where scipy fits) to composite.
    import py360convert
    _HAS_PY360 = True
except Exception:  # noqa: BLE001
    py360convert = None
    _HAS_PY360 = False


# ─────────────────────────────────────────────────────────────────────────────
# Core geometry
# ─────────────────────────────────────────────────────────────────────────────

def place_strip_in_equirect(strip: np.ndarray, out_w: int, vaov: float,
                            voffset: float) -> tuple[np.ndarray, np.ndarray]:
    """Resize the horizontal strip into a full 360x180 equirect frame, placed at
    the latitude band given by vaov (vertical FOV, deg) / voffset (deg, +down).

    Returns (equirect, valid_mask) where valid_mask is 255 where the strip lives
    and 0 in the empty pole bands.
    """
    out_h = out_w // 2
    equi = np.zeros((out_h, out_w, 3), np.uint8)
    mask = np.zeros((out_h, out_w), np.uint8)

    # The strip spans `vaov` degrees of latitude, centered at `voffset`. Map that
    # to a vertical pixel band in the 180°-tall equirect.
    band_h = int(round(out_h * (vaov / 180.0)))
    band_h = max(1, min(out_h, band_h))
    center = out_h / 2.0 + (voffset / 180.0) * out_h
    top = int(round(center - band_h / 2.0))
    top = max(0, min(out_h - band_h, top))

    resized = cv2.resize(strip, (out_w, band_h), interpolation=cv2.INTER_AREA)
    equi[top:top + band_h] = resized
    mask[top:top + band_h] = 255
    return equi, mask


def _feather_mask(h: int, w: int) -> np.ndarray:
    """Radial 0..1 feather: 1 in the centre, falling to 0 at the cube-face edge so
    the pole photo blends into the strip pixels that ring the cap."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cy, cx = (h - 1) / 2.0, (w - 1) / 2.0
    r = np.sqrt(((xx - cx) / cx) ** 2 + ((yy - cy) / cy) ** 2)
    # full weight inside 0.7 of the radius, linear fall-off to the edge.
    m = np.clip((1.0 - r) / 0.3, 0.0, 1.0)
    return m


def _align_to_face(photo: np.ndarray, face: np.ndarray,
                   face_mask: np.ndarray) -> np.ndarray:
    """Warp `photo` to sit on the cube `face`. If the face already has enough real
    pixels (the cap isn't fully empty) we try an ORB homography so the photo lines
    up with the surrounding strip; otherwise we center-fit the photo to the face.
    """
    fh, fw = face.shape[:2]
    fitted = cv2.resize(photo, (fw, fh), interpolation=cv2.INTER_AREA)

    # Only attempt feature alignment when the cap has real surrounding pixels.
    if face_mask is not None and face_mask.mean() > 12:  # ~>5% of the face filled
        try:
            g1 = cv2.cvtColor(fitted, cv2.COLOR_BGR2GRAY)
            g2 = cv2.cvtColor(face, cv2.COLOR_BGR2GRAY)
            orb = cv2.ORB_create(1500)
            k1, d1 = orb.detectAndCompute(g1, None)
            k2, d2 = orb.detectAndCompute(g2, None)
            if d1 is not None and d2 is not None and len(k1) >= 8 and len(k2) >= 8:
                bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
                matches = sorted(bf.match(d1, d2), key=lambda m: m.distance)[:80]
                if len(matches) >= 8:
                    src = np.float32([k1[m.queryIdx].pt for m in matches]).reshape(-1, 1, 2)
                    dst = np.float32([k2[m.trainIdx].pt for m in matches]).reshape(-1, 1, 2)
                    H, _ = cv2.findHomography(src, dst, cv2.RANSAC, 5.0)
                    if H is not None:
                        warped = cv2.warpPerspective(fitted, H, (fw, fh))
                        if warped.any():
                            return warped
        except cv2.error:
            pass
    return fitted


def composite_pole(face: np.ndarray, face_mask: np.ndarray,
                   photo: np.ndarray) -> np.ndarray:
    """Blend an aligned pole photo into one cube cap face with a radial feather."""
    aligned = _align_to_face(photo, face, face_mask)
    fm = _feather_mask(face.shape[0], face.shape[1])[..., None]
    out = aligned.astype(np.float32) * fm + face.astype(np.float32) * (1.0 - fm)
    return np.clip(out, 0, 255).astype(np.uint8)


def fill_poles(strip: np.ndarray, floor: np.ndarray | None,
               ceiling: np.ndarray | None, *, out_w: int = 4096,
               vaov: float = 60.0, voffset: float = 0.0,
               face_w: int = 512) -> np.ndarray:
    """Return a completed equirect panorama with real floor/ceiling caps.

    `floor` is the nadir (Down) photo, `ceiling` the zenith (Up) photo. Either may
    be None (then that pole keeps a cheap blur-stretch fill from the strip).
    """
    equi, valid = place_strip_in_equirect(strip, out_w, vaov, voffset)

    # Cheap honest default for any missing pole: blur-stretch the nearest strip row
    # up/down into the empty band so the cap reads as soft surface, not a black void.
    equi = _blur_stretch_poles(equi, valid)

    # Real floor/ceiling photos need py360convert (scipy). When it's unavailable
    # (the size-limited zip Lambda) or no pole photo was supplied, the blur-stretch
    # poles above are the result — a complete, honest full-sphere panorama.
    if not _HAS_PY360 or (floor is None and ceiling is None):
        return _heal_wrap_seam(equi)

    # Cubemap: U == zenith (ceiling), D == nadir (floor). Build a mask cubemap the
    # same way so we know which cap pixels are real strip vs. filled.
    cube = py360convert.e2c(equi, face_w=face_w, cube_format='dict')
    mask3 = cv2.cvtColor(valid, cv2.COLOR_GRAY2BGR)
    cube_mask = py360convert.e2c(mask3, face_w=face_w, cube_format='dict')

    if ceiling is not None:
        cube['U'] = composite_pole(cube['U'].astype(np.uint8),
                                   cube_mask['U'][..., 0].astype(np.uint8), ceiling)
    if floor is not None:
        cube['D'] = composite_pole(cube['D'].astype(np.uint8),
                                   cube_mask['D'][..., 0].astype(np.uint8), floor)

    out = py360convert.c2e(cube, h=out_w // 2, w=out_w, cube_format='dict')
    out = np.clip(out, 0, 255).astype(np.uint8)

    # Composite ONLY the empty pole bands back over the untouched strip: `equi`
    # already holds the resized strip in its valid band, so the strip's own pixels
    # are never altered — we only fill what was void.
    pole_band = (valid == 0)[..., None]
    result = np.where(pole_band, out, equi)
    # Seam-roll guard: make the 360 wrap continuous by averaging the first/last cols.
    return _heal_wrap_seam(result)


def _blur_stretch_poles(equi: np.ndarray, valid: np.ndarray) -> np.ndarray:
    """Fallback pole fill: stretch+blur the nearest valid row into the empty band.
    This is the honest cheap default (renderstuff-style) and also the client-side
    offline fallback's server-side mirror."""
    h = equi.shape[0]
    rows = np.where(valid.any(axis=1))[0]
    if rows.size == 0:
        return equi
    top, bot = rows.min(), rows.max()
    out = equi.copy()
    if top > 0:
        edge = cv2.GaussianBlur(equi[top:top + 1], (0, 0), sigmaX=21)
        out[:top] = np.repeat(edge, top, axis=0)
    if bot < h - 1:
        edge = cv2.GaussianBlur(equi[bot:bot + 1], (0, 0), sigmaX=21)
        out[bot + 1:] = np.repeat(edge, h - 1 - bot, axis=0)
    return out


def _vsmooth(col: np.ndarray, sigma: float) -> np.ndarray:
    """Vertical Gaussian smoothing of a (h, C) column, numpy-only (no cv2)."""
    r = max(1, int(round(sigma)))
    xs = np.arange(-3 * r, 3 * r + 1)
    k = np.exp(-0.5 * (xs / r) ** 2)
    k /= k.sum()
    pad = len(k) // 2
    padded = np.pad(col.astype(np.float32), ((pad, pad), (0, 0)), mode='edge')
    out = np.empty_like(col, dtype=np.float32)
    for c in range(col.shape[1]):
        out[:, c] = np.convolve(padded[:, c], k, mode='valid')
    return out


def _heal_wrap_seam(equi: np.ndarray, band: int | None = None) -> np.ndarray:
    """Seamlessly close the 360° horizontal wrap.

    The far-left (longitude −180°) and far-right (+180°) columns are the SAME
    ray, so any difference between them is a capture artifact — dominated by a
    low-frequency EXPOSURE / white-balance drift between the two ends of the
    pano (the tell-tale bright vertical stripe at the wrap), plus a little
    high-frequency misalignment.

    The old heal averaged the outer 4 px and stamped the SAME block on both
    edges — it only shrank the hard step, never removed the exposure stripe and
    left a visible 4 px patch. This does two numpy-only passes instead:

      1) EXPOSURE/COLOUR MATCH — measure each edge's smoothed per-row colour and
         push both edges halfway toward their shared midpoint, with a correction
         that decays into the interior. Kills the brightness stripe, keeps
         texture.
      2) WIDE FEATHER — cross-fade a band on each side toward the (now matched)
         seam value with a linear ramp, so the boundary is a gradient over ~1%
         of the width instead of a 4 px block.
    """
    h, w = equi.shape[:2]
    if w < 16:
        return equi.copy()
    b = int(band) if band else max(8, w // 96)     # ~1% of width
    b = max(4, min(b, w // 4))
    out = equi.astype(np.float32)

    # (1) low-frequency exposure/colour match between the two edges.
    left_lf = _vsmooth(out[:, :b].mean(axis=1), h / 24.0)    # (h, C)
    right_lf = _vsmooth(out[:, -b:].mean(axis=1), h / 24.0)  # (h, C)
    half = (right_lf - left_lf) / 2.0                        # push each side halfway
    ramp = np.linspace(1.0, 0.0, b, dtype=np.float32)[None, :, None]  # (1, b, 1)
    out[:, :b] += half[:, None, :] * ramp
    out[:, -b:] -= half[:, None, :] * ramp[:, ::-1, :]

    # (2) narrow feather toward the matched seam value (residual high-freq step).
    fb = max(3, b // 2)
    mid = (out[:, :1] + out[:, -1:]) / 2.0                   # (h, 1, C)
    a = np.linspace(0.5, 0.0, fb, dtype=np.float32)[None, :, None]    # weight of mid
    out[:, :fb] = out[:, :fb] * (1 - a) + mid * a
    out[:, -fb:] = out[:, -fb:] * (1 - a[:, ::-1, :]) + mid * a[:, ::-1, :]

    # round (not truncate) so an unchanged pixel stays put instead of drifting −1.
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


# ─────────────────────────────────────────────────────────────────────────────
# IO + CLI
# ─────────────────────────────────────────────────────────────────────────────

def _imread(path: str) -> np.ndarray:
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(f"cannot read image: {path}")
    return img


def run_cli(args: argparse.Namespace) -> int:
    strip = _imread(args.strip)
    floor = _imread(args.floor) if args.floor else None
    ceiling = _imread(args.ceiling) if args.ceiling else None
    out = fill_poles(strip, floor, ceiling, out_w=args.width,
                     vaov=args.vaov, voffset=args.voffset)
    cv2.imwrite(args.out, out)
    print(f"wrote {args.out}  ({out.shape[1]}x{out.shape[0]})")
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# Self-check (synthetic, assert-based)
# ─────────────────────────────────────────────────────────────────────────────

def _synth_strip(w: int = 1600, h: int = 400) -> np.ndarray:
    """A fake horizontal pano strip: gradient sky->wall with vertical stripes."""
    img = np.zeros((h, w, 3), np.uint8)
    for x in range(w):
        img[:, x] = (int(120 + 80 * np.sin(x / 40.0)), 110, 90)
    img[: h // 2] += np.array([40, 30, 20], np.uint8)  # brighter upper band
    return img


def _synth_pole(color: tuple[int, int, int], size: int = 600) -> np.ndarray:
    img = np.full((size, size, 3), color, np.uint8)
    cv2.circle(img, (size // 2, size // 2), size // 3, (255, 255, 255), 8)
    cv2.rectangle(img, (40, 40), (size - 40, size - 40), (0, 0, 0), 4)
    return img


def selfcheck() -> int:
    print("pole_fill self-check ...")
    strip = _synth_strip()
    floor = _synth_pole((60, 60, 130))    # reddish floor
    ceiling = _synth_pole((200, 200, 200))  # bright ceiling

    out_w = 1024
    out = fill_poles(strip, floor, ceiling, out_w=out_w, vaov=60.0, face_w=256)

    # 1. dimensions: a valid equirect is exactly 2:1 at the requested width.
    assert out.shape == (out_w // 2, out_w, 3), f"bad shape {out.shape}"
    assert out.dtype == np.uint8

    # 2. the poles must now carry REAL pole pixels, not black void.
    h = out.shape[0]
    top_band = out[: h // 8]
    bot_band = out[-h // 8:]
    assert top_band.mean() > 5, "zenith cap is empty/black"
    assert bot_band.mean() > 5, "nadir cap is empty/black"

    # 3. the ceiling (bright) cap should be brighter than the floor (dark) cap,
    #    proving the right photo landed at the right pole.
    assert top_band.mean() > bot_band.mean(), \
        f"poles swapped? top={top_band.mean():.1f} bot={bot_band.mean():.1f}"

    # 4. the horizontal band (the strip) must be preserved (non-black everywhere).
    mid = out[h // 2 - 5: h // 2 + 5]
    assert mid.min(axis=2).mean() > 5, "strip band lost"

    # 5. the 360 wrap must be (near) seamless: left edge ≈ right edge.
    seam = np.abs(out[:, 0].astype(int) - out[:, -1].astype(int)).mean()
    assert seam < 40, f"wrap seam too large: {seam:.1f}"

    # 6. None-pole path (blur-stretch fallback) must also run and stay 2:1.
    out2 = fill_poles(strip, None, None, out_w=out_w, vaov=60.0, face_w=256)
    assert out2.shape == (out_w // 2, out_w, 3)
    assert out2[: h // 8].mean() > 5, "blur-stretch fallback left empty pole"

    # 5b. wrap heal on a deliberately exposure-DRIFTED pano: the visible
    #     horizontal STEP across the 360° wrap must collapse. The old 4px
    #     average left a hard block edge here (edge-column diff looked fine but
    #     the step didn't); this guards against regressing to that.
    drift = np.clip(
        np.linspace(50, 210, out_w)[None, :, None]
        + np.zeros((out_w // 2, out_w, 3), np.float32), 0, 255).astype(np.uint8)
    healed = _heal_wrap_seam(drift)

    def _seam_step(im, bb=16):
        prof = im.mean(axis=2).mean(axis=0)
        win = np.concatenate([prof[-bb:], prof[:bb]])
        return float(np.abs(np.diff(win)).max())

    step_before, step_after = _seam_step(drift), _seam_step(healed)
    assert step_after < step_before * 0.35, \
        f"wrap-seam step not healed: {step_before:.1f} -> {step_after:.1f}"

    print(f"  output {out.shape[1]}x{out.shape[0]}  "
          f"zenith={top_band.mean():.1f} nadir={bot_band.mean():.1f} "
          f"seam={seam:.1f}  wrap-step {step_before:.0f}->{step_after:.0f}")
    print("ALL ASSERTIONS PASSED")

    # write a visible artifact next to the script for manual inspection.
    demo_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             'selfcheck_output.jpg')
    cv2.imwrite(demo_path, out)
    print(f"  demo image: {demo_path}")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Composite real floor/ceiling caps "
                                            "into a phone panorama.")
    p.add_argument('--strip', help='horizontal pano strip (equirect or cylindrical)')
    p.add_argument('--floor', help='downward nadir photo')
    p.add_argument('--ceiling', help='upward zenith photo')
    p.add_argument('--out', help='output completed pano path')
    p.add_argument('--vaov', type=float, default=60.0,
                   help='vertical FOV of the strip in degrees (default 60)')
    p.add_argument('--voffset', type=float, default=0.0,
                   help='vertical offset of the strip band, +down degrees')
    p.add_argument('--width', type=int, default=4096,
                   help='output equirect width (height = width/2)')
    p.add_argument('--selfcheck', action='store_true',
                   help='run the synthetic self-check and exit')
    args = p.parse_args(argv)

    if args.selfcheck or not args.strip:
        return selfcheck()
    if not args.out:
        p.error('--out is required when --strip is given')
    return run_cli(args)


if __name__ == '__main__':
    sys.exit(main())
