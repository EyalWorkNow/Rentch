"""AI enhancement of an existing equirectangular 360: generative POLE FILL
(ceiling/floor) + 360 WRAP completion, done on the UNDISTORTED cube faces so the
result is geometrically correct and the wrap seam closes cleanly.

The generative step is injected as `edit_fn(bgr, hole_mask) -> bgr` (OpenAI
gpt-image-2 masked edit in production, a stub in tests), so this module is pure
geometry + compositing and needs no network to unit-test. Depends only on
numpy + OpenCV + cube_ops (all in the pano-stitch zip).
"""
import cv2
import numpy as np

import cube_ops

# Strict prompts live with the caller (app.py) since edit_fn owns the model call;
# these are the geometric guardrails that make "invent nothing" enforceable — the
# mask physically limits the model to the empty region.

FACE_W = 1024


def _feather(mask01, sigma):
    return cv2.GaussianBlur(mask01.astype(np.float32), (0, 0), sigma)[..., None]


def _detect_pole_hole(face):
    """Mask the black/stretched missing-pole blob at a U/D face centre. Empty
    mask when the face already has real content (nothing to fill)."""
    g = cv2.cvtColor(face, cv2.COLOR_BGR2GRAY)
    dark = (g < 55).astype(np.uint8) * 255
    dark = cv2.morphologyEx(dark, cv2.MORPH_CLOSE,
                            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (41, 41)))
    cnts, _ = cv2.findContours(dark, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    h, w = g.shape
    pick = None
    for c in cnts:
        if cv2.pointPolygonTest(c, (w / 2, h / 2), False) >= 0:
            pick = c
            break
    if pick is None:
        return np.zeros((h, w), np.uint8)
    if cv2.contourArea(pick) < 0.02 * h * w:  # negligible → treat as no hole
        return np.zeros((h, w), np.uint8)
    mask = np.zeros((h, w), np.uint8)
    cv2.fillConvexPoly(mask, cv2.convexHull(pick), 255)
    return mask


def fill_poles(equi, edit_fn, face_w=FACE_W):
    """Generatively fill the ceiling (U) and floor (D) if they are missing."""
    faces = cube_ops.e2c(equi, face_w)
    changed = False
    for f in ('U', 'D'):
        hole = _detect_pole_hole(faces[f])
        if not hole.any():
            continue
        filled = edit_fn(faces[f], hole, 'U' if f == 'U' else 'D')
        if filled is None:
            continue
        a = _feather((hole > 0), 18)
        faces[f] = (filled.astype(np.float32) * a +
                    faces[f].astype(np.float32) * (1 - a)).astype(np.uint8)
        changed = True
    if not changed:
        return equi
    return cube_ops.c2e(faces, equi.shape[0], equi.shape[1])


def _missing_columns(equi, thresh=18, frac=0.85):
    """Boolean per-column: True where the column is mostly empty/black (an
    uncaptured wedge). Uses the middle band so pole holes don't count."""
    h = equi.shape[0]
    band = equi[int(h * 0.3):int(h * 0.7)]
    g = cv2.cvtColor(band, cv2.COLOR_BGR2GRAY)
    return (g < thresh).mean(axis=0) >= frac


def complete_wrap(equi, edit_fn, min_deg=8, max_deg=170):
    """Outpaint a single missing vertical wedge to close the 360. Rolls the wedge
    to centre so both captured ends are context and the wrap seam falls INSIDE the
    contiguous fill. No-op when there's no significant gap (or it's too large)."""
    h, w = equi.shape[:2]
    miss = _missing_columns(equi)
    deg = 360.0 * miss.mean()
    if deg < min_deg or deg > max_deg:
        return equi  # nothing to close, or too little captured to trust

    # centre of the missing arc (handle the wrap-around case via circular mean)
    ang = (np.arange(w) + 0.5) / w * 2 * np.pi
    mx = np.average(np.cos(ang), weights=miss)
    my = np.average(np.sin(ang), weights=miss)
    centre = (np.arctan2(my, mx) % (2 * np.pi)) / (2 * np.pi) * w
    shift = int(round(w / 2 - centre))
    rolled = np.roll(equi, shift, axis=1)

    ww = int(round(w * deg / 360.0))
    ctx = max(int(ww * 0.6), 40)
    x0 = max(w // 2 - ww // 2 - ctx, 0)
    x1 = min(w // 2 + ww // 2 + ctx, w)
    win = rolled[:, x0:x1].copy()
    wh, wwin = win.shape[:2]
    canvas = cv2.resize(win, (1024, 1024), interpolation=cv2.INTER_AREA)
    hole = np.zeros((1024, 1024), np.uint8)
    bx0 = int((w // 2 - ww // 2 - x0) / wwin * 1024)
    bx1 = int((w // 2 + ww // 2 - x0) / wwin * 1024)
    hole[:, bx0:bx1] = 255

    filled = edit_fn(canvas, hole, 'W')
    if filled is None:
        return equi
    filled = cv2.resize(filled, (wwin, wh), interpolation=cv2.INTER_LINEAR)
    band = np.zeros((wh, wwin), np.uint8)
    band[:, int(w // 2 - ww // 2 - x0):int(w // 2 + ww // 2 - x0)] = 255
    a = _feather((band > 0), 10)
    rolled[:, x0:x1] = (filled.astype(np.float32) * a +
                        win.astype(np.float32) * (1 - a)).astype(np.uint8)
    return np.roll(rolled, -shift, axis=1)


def enhance(equi, edit_fn, do_wrap=True, do_poles=True):
    """Full Phase-A enhancement: close the 360 first (so poles see complete
    side walls), then fill ceiling/floor."""
    out = equi
    if do_wrap:
        out = complete_wrap(out, edit_fn)
    if do_poles:
        out = fill_poles(out, edit_fn)
    return out
