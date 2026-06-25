#!/usr/bin/env python3
"""room_layout.py — single-panorama room layout -> metric floorplan data product.

Input : ONE equirectangular panorama  + a MEASURED camera height (metres).
Output: a JSON "room data product":
        - floor polygon in metric (x, y) coordinates
        - room width / length / height / floor area
        - wall segments (with length)
        - ceiling height
        - a textured-box geometry spec (3D corner positions) the viewer can
          use for clean in-room parallax.

The math here converts HorizonNet-style boundary predictions (a ceiling-wall and a
floor-wall boundary row per image column — the standard HorizonNet output) into a
metric floorplan, given the camera height. This part is fully implemented and
self-tested with numpy; it needs NO multi-GB model weights to run.

The actual neural inference is isolated behind `predict_layout()` (see
`adapter.py`), so this module stays a pure, testable geometry kernel.

=============================================================================
 ⚠️  DATASET-LICENSE TRAP  (read RENTLY_SPATIAL_ARCHITECTURE.md §1bis point 4 & §7)
-----------------------------------------------------------------------------
 HorizonNet (sunset1995/HorizonNet) and AtlantaNet (crs4/AtlantaNet) CODE is MIT,
 but the published WEIGHTS are trained on Matterport3D / ZInD / Structured3D, which
 are NON-COMMERCIAL. Code license != weight license. For the Rently resale business
 you must EITHER retrain on Rently's OWN captured panos (the app already collects
 them) OR use only Apache/BSD-trained weights. The geometry in THIS file is original
 and unencumbered; the license risk lives entirely in the weights loaded by the
 adapter. Audit the training mix before shipping anything sellable.
=============================================================================
"""
from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass, field
from typing import List, Optional, Sequence, Tuple

import numpy as np

# -----------------------------------------------------------------------------
# Coordinate conventions (documented once, used everywhere)
# -----------------------------------------------------------------------------
# Equirectangular image, width W, height H, pixel (u, v) with origin top-left.
#
#   azimuth   theta(u) = (u / W) * 2*pi          in [0, 2*pi)   (0 = +X axis)
#   elevation phi(v)   = (0.5 - v / H) * pi       in [+pi/2 .. -pi/2]
#                        v=0   -> +pi/2 (straight up / zenith)
#                        v=H/2 ->   0   (horizon)
#                        v=H   -> -pi/2 (straight down / nadir)
#
# World frame: right-handed, camera at origin.
#   +X, +Y horizontal (the floor plane is Z = -camera_height)
#   +Z up.  The camera optical centre is at Z = 0, height `camera_height`
#   above the floor.
#
# For a floor-wall boundary seen at (theta, phi_floor<0):
#   the ray hits the floor (Z = -h). Horizontal distance to that wall point:
#       r = h / tan(-phi_floor)          (phi_floor is negative -> -phi>0)
#   floor point = (r*cos(theta), r*sin(theta), -h)
#
# The ceiling-wall boundary at the SAME column shares the horizontal distance r
# (it is the same wall). Ceiling height above the camera:
#       c = r * tan(phi_ceil)            (phi_ceil > 0)
#   total room height H_room = h + c
# -----------------------------------------------------------------------------


@dataclass
class LayoutPrediction:
    """Raw per-column boundary prediction (HorizonNet-style).

    `cols_u`     : image column indices (0 .. W-1), one per sampled azimuth.
    `floor_v`    : floor-wall boundary row (pixels) for each column.
    `ceil_v`     : ceiling-wall boundary row (pixels) for each column.
    `width` / `height` : panorama dimensions in pixels.

    Columns are assumed to wrap: column 0 and column W are the same azimuth.
    """

    cols_u: np.ndarray
    floor_v: np.ndarray
    ceil_v: np.ndarray
    width: int
    height: int

    @classmethod
    def from_boundaries(
        cls,
        floor_v: Sequence[float],
        ceil_v: Sequence[float],
        width: int,
        height: int,
        cols_u: Optional[Sequence[float]] = None,
    ) -> "LayoutPrediction":
        floor_v = np.asarray(floor_v, dtype=np.float64)
        ceil_v = np.asarray(ceil_v, dtype=np.float64)
        if cols_u is None:
            # boundaries given densely, one per column slot across the full width
            n = len(floor_v)
            cols_u = np.linspace(0, width, n, endpoint=False)
        cols_u = np.asarray(cols_u, dtype=np.float64)
        return cls(cols_u=cols_u, floor_v=floor_v, ceil_v=ceil_v,
                   width=int(width), height=int(height))


@dataclass
class WallSegment:
    start: Tuple[float, float]   # metric (x, y) of one floor corner
    end: Tuple[float, float]     # metric (x, y) of the next floor corner
    length: float                # metres


@dataclass
class RoomDataProduct:
    """The sellable / viewer-consumable room data product (see §5)."""

    camera_height_m: float
    ceiling_height_m: float          # camera -> ceiling
    room_height_m: float             # floor -> ceiling
    width_m: float                   # bounding extent along X
    length_m: float                  # bounding extent along Y
    floor_area_m2: float
    floor_polygon: List[Tuple[float, float]] = field(default_factory=list)
    wall_segments: List[WallSegment] = field(default_factory=list)
    # box geometry the three.js / viewer layer consumes for parallax:
    # 8 corner positions (4 floor + 4 ceiling) in metres, world frame.
    box_corners_floor: List[Tuple[float, float, float]] = field(default_factory=list)
    box_corners_ceiling: List[Tuple[float, float, float]] = field(default_factory=list)
    is_rectangular: bool = False
    notes: str = ""

    def to_json(self, indent: int = 2) -> str:
        return json.dumps(asdict(self), indent=indent)


# -----------------------------------------------------------------------------
# Pixel <-> angle helpers
# -----------------------------------------------------------------------------
def col_to_theta(u: np.ndarray, width: int) -> np.ndarray:
    return (np.asarray(u, dtype=np.float64) / width) * 2.0 * math.pi


def row_to_phi(v: np.ndarray, height: int) -> np.ndarray:
    return (0.5 - np.asarray(v, dtype=np.float64) / height) * math.pi


def theta_to_col(theta: float, width: int) -> float:
    return (theta / (2.0 * math.pi)) * width


def phi_to_row(phi: float, height: int) -> float:
    return (0.5 - phi / math.pi) * height


# -----------------------------------------------------------------------------
# Core: boundaries -> metric floor & ceiling points
# -----------------------------------------------------------------------------
def floor_points_metric(pred: LayoutPrediction, camera_height: float) -> np.ndarray:
    """Per-column floor-wall corner positions in metres -> (N, 3) array."""
    theta = col_to_theta(pred.cols_u, pred.width)
    phi_f = row_to_phi(pred.floor_v, pred.height)

    # floor is below the horizon: phi_f must be < 0.
    # r = h / tan(-phi_f).  Guard against numerical noise near the horizon.
    tan_down = np.tan(-phi_f)
    tan_down = np.where(tan_down <= 1e-6, 1e-6, tan_down)
    r = camera_height / tan_down

    x = r * np.cos(theta)
    y = r * np.sin(theta)
    z = np.full_like(x, -camera_height)
    return np.stack([x, y, z], axis=1)


def ceiling_height_per_column(pred: LayoutPrediction, camera_height: float) -> np.ndarray:
    """Room height (floor->ceiling) estimated independently per column."""
    theta = col_to_theta(pred.cols_u, pred.width)
    phi_f = row_to_phi(pred.floor_v, pred.height)
    phi_c = row_to_phi(pred.ceil_v, pred.height)

    tan_down = np.tan(-phi_f)
    tan_down = np.where(tan_down <= 1e-6, 1e-6, tan_down)
    r = camera_height / tan_down

    c = r * np.tan(phi_c)                 # camera -> ceiling
    return camera_height + c              # floor -> ceiling


# -----------------------------------------------------------------------------
# Floor polygon simplification (corners of the room)
# -----------------------------------------------------------------------------
def _polygon_area(poly: np.ndarray) -> float:
    """Shoelace area of an (M, 2) polygon. Always non-negative."""
    x = poly[:, 0]
    y = poly[:, 1]
    return 0.5 * abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def detect_corners(floor_xy: np.ndarray, angle_thresh_deg: float = 25.0) -> np.ndarray:
    """Reduce a dense, wrap-around floor boundary to room corners.

    A corner is a column where the heading of the boundary turns by more than
    `angle_thresh_deg`. This naturally handles the column 0 <-> N wrap because we
    treat the boundary as a closed ring (np.roll).
    """
    n = len(floor_xy)
    if n < 4:
        return floor_xy.copy()

    prev_pts = np.roll(floor_xy, 1, axis=0)
    next_pts = np.roll(floor_xy, -1, axis=0)
    incoming = floor_xy - prev_pts
    outgoing = next_pts - floor_xy

    def _angle(a: np.ndarray, b: np.ndarray) -> np.ndarray:
        na = np.linalg.norm(a, axis=1)
        nb = np.linalg.norm(b, axis=1)
        denom = np.where(na * nb < 1e-9, 1e-9, na * nb)
        cosang = np.einsum("ij,ij->i", a, b) / denom
        cosang = np.clip(cosang, -1.0, 1.0)
        return np.degrees(np.arccos(cosang))

    turn = _angle(incoming, outgoing)
    corner_mask = turn > angle_thresh_deg
    corners = floor_xy[corner_mask]
    if len(corners) < 4:
        # fall back: pick the 4 extreme points (rectangle assumption)
        idx = [
            int(np.argmax(floor_xy[:, 0])),
            int(np.argmax(floor_xy[:, 1])),
            int(np.argmin(floor_xy[:, 0])),
            int(np.argmin(floor_xy[:, 1])),
        ]
        corners = floor_xy[sorted(set(idx))]
    return corners


def _order_ccw(poly: np.ndarray) -> np.ndarray:
    """Order polygon vertices counter-clockwise by angle about the centroid."""
    c = poly.mean(axis=0)
    ang = np.arctan2(poly[:, 1] - c[1], poly[:, 0] - c[0])
    return poly[np.argsort(ang)]


# -----------------------------------------------------------------------------
# Top-level builder
# -----------------------------------------------------------------------------
def build_room_data_product(
    pred: LayoutPrediction,
    camera_height: float,
    angle_thresh_deg: float = 25.0,
) -> RoomDataProduct:
    """Convert a HorizonNet-style prediction + measured camera height into the
    full metric room data product."""
    floor_xyz = floor_points_metric(pred, camera_height)
    floor_xy = floor_xyz[:, :2]

    room_h_per_col = ceiling_height_per_column(pred, camera_height)
    room_height = float(np.median(room_h_per_col))
    ceiling_height = room_height - camera_height

    corners_xy = detect_corners(floor_xy, angle_thresh_deg=angle_thresh_deg)
    corners_xy = _order_ccw(corners_xy)

    area = float(_polygon_area(corners_xy))

    xs = corners_xy[:, 0]
    ys = corners_xy[:, 1]
    width_m = float(xs.max() - xs.min())
    length_m = float(ys.max() - ys.min())

    # wall segments around the closed floor ring
    walls: List[WallSegment] = []
    m = len(corners_xy)
    for i in range(m):
        a = corners_xy[i]
        b = corners_xy[(i + 1) % m]
        walls.append(
            WallSegment(
                start=(float(a[0]), float(a[1])),
                end=(float(b[0]), float(b[1])),
                length=float(np.linalg.norm(b - a)),
            )
        )

    # textured-box geometry: floor corners at z=-h, ceiling corners at z=ceil
    z_floor = -camera_height
    z_ceil = ceiling_height
    box_floor = [(float(p[0]), float(p[1]), z_floor) for p in corners_xy]
    box_ceiling = [(float(p[0]), float(p[1]), z_ceil) for p in corners_xy]

    is_rect = m == 4

    return RoomDataProduct(
        camera_height_m=float(camera_height),
        ceiling_height_m=float(ceiling_height),
        room_height_m=float(room_height),
        width_m=width_m,
        length_m=length_m,
        floor_area_m2=area,
        floor_polygon=[(float(p[0]), float(p[1])) for p in corners_xy],
        wall_segments=walls,
        box_corners_floor=box_floor,
        box_corners_ceiling=box_ceiling,
        is_rectangular=is_rect,
        notes=(
            "Metric scale derived from MEASURED camera height (not the model's "
            "internal scale). Expect ~2-5% dimension error per "
            "RENTLY_SPATIAL_ARCHITECTURE.md §1bis. World frame: +Z up, camera "
            "optical centre at origin, floor at z=-camera_height."
        ),
    )


# -----------------------------------------------------------------------------
# Synthetic generator (used by the self-check) — the inverse of the math above.
# -----------------------------------------------------------------------------
def synthesize_rectangular_room(
    width_m: float,
    length_m: float,
    room_height_m: float,
    camera_height_m: float,
    cam_xy: Tuple[float, float] = (0.0, 0.0),
    pano_w: int = 1024,
    pano_h: int = 512,
    n_cols: Optional[int] = None,
) -> Tuple[LayoutPrediction, dict]:
    """Render the floor/ceiling boundary rows a perfect HorizonNet would output
    for a known rectangular room, so the recovery math can be checked against
    ground truth.

    Returns (LayoutPrediction, ground_truth_dict).
    """
    if n_cols is None:
        n_cols = pano_w
    cols = np.arange(n_cols, dtype=np.float64) * (pano_w / n_cols)
    theta = col_to_theta(cols, pano_w)

    cx, cy = cam_xy
    # rectangle spans [x0,x1] x [y0,y1], camera somewhere inside.
    x0, x1 = -width_m / 2.0, width_m / 2.0
    y0, y1 = -length_m / 2.0, length_m / 2.0

    floor_v = np.empty(n_cols)
    ceil_v = np.empty(n_cols)
    ceil_above = room_height_m - camera_height_m  # camera -> ceiling

    for i, th in enumerate(theta):
        dx = math.cos(th)
        dy = math.sin(th)
        # distance to the rectangle wall along ray (dx, dy) from (cx, cy)
        ts = []
        if dx > 1e-12:
            ts.append((x1 - cx) / dx)
        elif dx < -1e-12:
            ts.append((x0 - cx) / dx)
        if dy > 1e-12:
            ts.append((y1 - cy) / dy)
        elif dy < -1e-12:
            ts.append((y0 - cy) / dy)
        ts = [t for t in ts if t > 1e-9]
        r = min(ts)  # nearest wall hit = the actual wall in that direction

        phi_floor = -math.atan2(camera_height_m, r)
        phi_ceil = math.atan2(ceil_above, r)
        floor_v[i] = phi_to_row(phi_floor, pano_h)
        ceil_v[i] = phi_to_row(phi_ceil, pano_h)

    pred = LayoutPrediction(
        cols_u=cols, floor_v=floor_v, ceil_v=ceil_v, width=pano_w, height=pano_h
    )
    gt = {
        "width_m": width_m,
        "length_m": length_m,
        "room_height_m": room_height_m,
        "camera_height_m": camera_height_m,
        "floor_area_m2": width_m * length_m,
        "ceiling_height_m": room_height_m - camera_height_m,
    }
    return pred, gt


# -----------------------------------------------------------------------------
# Self-check
# -----------------------------------------------------------------------------
def _selfcheck() -> None:
    print("=" * 70)
    print("room_layout.py self-check — synthetic rectangular room")
    print("=" * 70)

    # Ground-truth room: camera centred.
    W, L, RH, CH = 4.0, 6.0, 2.7, 1.5
    pred, gt = synthesize_rectangular_room(
        width_m=W, length_m=L, room_height_m=RH, camera_height_m=CH,
        cam_xy=(0.0, 0.0), pano_w=1024, pano_h=512,
    )
    prod = build_room_data_product(pred, camera_height=CH)

    def rep(name, got, truth, tol):
        err = abs(got - truth)
        rel = err / truth * 100 if truth else 0.0
        status = "OK " if err <= tol else "FAIL"
        print(f"  [{status}] {name:16s} got={got:8.4f}  truth={truth:8.4f}  "
              f"abs_err={err:7.4f}  rel={rel:5.2f}%  tol={tol}")
        return err <= tol

    print("\nCentred camera:")
    ok = True
    ok &= rep("ceiling_height", prod.ceiling_height_m, gt["ceiling_height_m"], 0.02)
    ok &= rep("room_height",    prod.room_height_m,    gt["room_height_m"],    0.02)
    ok &= rep("floor_area",     prod.floor_area_m2,    gt["floor_area_m2"],    0.3)
    # width/length may swap depending on corner ordering; compare as a set.
    got_dims = sorted([prod.width_m, prod.length_m])
    truth_dims = sorted([W, L])
    ok &= rep("dim_small", got_dims[0], truth_dims[0], 0.1)
    ok &= rep("dim_large", got_dims[1], truth_dims[1], 0.1)

    assert prod.is_rectangular, "expected a 4-corner rectangular room"
    assert len(prod.floor_polygon) == 4, "expected 4 floor corners"
    assert len(prod.box_corners_floor) == 4 and len(prod.box_corners_ceiling) == 4
    # box corner z planes
    assert all(abs(c[2] - (-CH)) < 1e-9 for c in prod.box_corners_floor)
    assert all(abs(c[2] - (RH - CH)) < 1e-9 for c in prod.box_corners_ceiling)

    # ---- Off-centre camera (corner positions differ, but DIMENSIONS must hold) ----
    print("\nOff-centre camera (cam at (1.0, -2.0)):")
    pred2, gt2 = synthesize_rectangular_room(
        width_m=W, length_m=L, room_height_m=RH, camera_height_m=CH,
        cam_xy=(1.0, -2.0), pano_w=1024, pano_h=512,
    )
    prod2 = build_room_data_product(pred2, camera_height=CH)
    ok &= rep("ceiling_height", prod2.ceiling_height_m, gt2["ceiling_height_m"], 0.02)
    ok &= rep("floor_area",     prod2.floor_area_m2,    gt2["floor_area_m2"],    0.5)
    got_dims2 = sorted([prod2.width_m, prod2.length_m])
    ok &= rep("dim_small", got_dims2[0], truth_dims[0], 0.15)
    ok &= rep("dim_large", got_dims2[1], truth_dims[1], 0.15)

    # ---- Wrap-around handling: column 0 and column N must be the same azimuth ----
    print("\nWrap-around (column 0 <-> N) check:")
    theta0 = col_to_theta(np.array([0.0]), pred.width)[0]
    thetaN = col_to_theta(np.array([float(pred.width)]), pred.width)[0]
    wrap_ok = abs((thetaN % (2 * math.pi)) - theta0) < 1e-9
    print(f"  [{'OK ' if wrap_ok else 'FAIL'}] theta(0)={theta0:.4f}  "
          f"theta(W) mod 2pi={thetaN % (2*math.pi):.4f}")
    ok &= wrap_ok
    # corner detection must treat the ring as closed (first/last not double-counted)
    assert prod.is_rectangular, "wrap-around broke corner detection"

    print("\n" + "=" * 70)
    if ok:
        print("ALL ASSERTIONS PASSED")
    else:
        print("SELF-CHECK FAILED")
        raise SystemExit(1)
    print("=" * 70)


if __name__ == "__main__":
    import sys

    # `python room_layout.py` or `--selfcheck` both run the self-check.
    if len(sys.argv) == 1 or "--selfcheck" in sys.argv:
        _selfcheck()
    else:
        print("Usage: python room_layout.py [--selfcheck]")
