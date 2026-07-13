"""Equirectangular <-> cubemap conversion in pure numpy + cv2.remap.

Replaces py360convert (which needs scipy and blows the 250 MB zip-Lambda limit).
Only depends on numpy + OpenCV, both already in the pano-stitch zip. Self-consistent
convention: e2c then c2e reconstructs the horizon band faithfully. Used to run 2D
AI ops (pole inpaint / wrap outpaint) on the UNDISTORTED cube faces, then fold the
result back to a seam-correct equirectangular 360.

Faces dict keys: F (+z front), B (-z back), R (+x right), L (-x left),
U (+y up / ceiling), D (-y down / floor). Local face coords a,b in [-1,1],
a = left->right, b = top->bottom.
"""
import cv2
import numpy as np


# face -> direction vector as a function of local (a, b).
def _face_dir(face, a, b):
    ones = np.ones_like(a)
    if face == 'F':
        return a, -b, ones
    if face == 'B':
        return -a, -b, -ones
    if face == 'R':
        return ones, -b, -a
    if face == 'L':
        return -ones, -b, a
    if face == 'U':
        return a, ones, b
    if face == 'D':
        return a, -ones, -b
    raise ValueError(face)


def e2c(equi, face_w):
    """Equirectangular (H,2H,3) -> dict of 6 (face_w,face_w,3) cube faces."""
    h, w = equi.shape[:2]
    j = (np.arange(face_w) + 0.5) / face_w * 2 - 1  # a (cols)
    i = (np.arange(face_w) + 0.5) / face_w * 2 - 1  # b (rows)
    a, b = np.meshgrid(j, i)  # (face_w, face_w)
    faces = {}
    for f in ('F', 'B', 'R', 'L', 'U', 'D'):
        dx, dy, dz = _face_dir(f, a, b)
        norm = np.sqrt(dx * dx + dy * dy + dz * dz)
        dx, dy, dz = dx / norm, dy / norm, dz / norm
        lon = np.arctan2(dx, dz)          # [-pi, pi]
        lat = np.arcsin(np.clip(dy, -1, 1))  # [-pi/2, pi/2]
        ex = (lon + np.pi) / (2 * np.pi) * w - 0.5
        ey = (np.pi / 2 - lat) / np.pi * h - 0.5
        faces[f] = cv2.remap(equi, ex.astype(np.float32), ey.astype(np.float32),
                             cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP)
    return faces


def c2e(faces, out_h, out_w):
    """Dict of 6 cube faces -> equirectangular (out_h, out_w, 3)."""
    face_w = faces['F'].shape[0]
    y, x = np.meshgrid(np.arange(out_h), np.arange(out_w), indexing='ij')
    lon = (x + 0.5) / out_w * 2 * np.pi - np.pi
    lat = np.pi / 2 - (y + 0.5) / out_h * np.pi
    dx = np.cos(lat) * np.sin(lon)
    dy = np.sin(lat)
    dz = np.cos(lat) * np.cos(lon)
    ax, ay, az = np.abs(dx), np.abs(dy), np.abs(dz)
    ch = 1 if faces['F'].ndim == 2 else faces['F'].shape[2]
    out = np.zeros((out_h, out_w) + ((ch,) if ch > 1 else ()), faces['F'].dtype)

    def place(face, a, b, m):
        fx = ((a + 1) / 2 * face_w - 0.5).astype(np.float32)
        fy = ((b + 1) / 2 * face_w - 0.5).astype(np.float32)
        rem = cv2.remap(faces[face], fx, fy, cv2.INTER_LINEAR,
                        borderMode=cv2.BORDER_REPLICATE)
        out[m] = rem[m]

    xdom = (ax >= ay) & (ax >= az)
    ydom = (ay >= ax) & (ay >= az) & ~xdom
    zdom = ~xdom & ~ydom
    eps = 1e-9
    # R/L: x dominant.  c = dir/|x|.
    mR = xdom & (dx > 0)
    place('R', -(dz / (ax + eps)), -(dy / (ax + eps)), mR)
    mL = xdom & (dx <= 0)
    place('L', (dz / (ax + eps)), -(dy / (ax + eps)), mL)
    # U/D: y dominant.
    mU = ydom & (dy > 0)
    place('U', (dx / (ay + eps)), (dz / (ay + eps)), mU)
    mD = ydom & (dy <= 0)
    place('D', (dx / (ay + eps)), -(dz / (ay + eps)), mD)
    # F/B: z dominant.
    mF = zdom & (dz > 0)
    place('F', (dx / (az + eps)), -(dy / (az + eps)), mF)
    mB = zdom & (dz <= 0)
    place('B', -(dx / (az + eps)), -(dy / (az + eps)), mB)
    return out
