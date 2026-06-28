# Rently panorama stitcher — OpenCV cv2.Stitcher (BSD), in a container Lambda.
#
# The router invokes this async with a job: a set of overlapping frames the user
# shot by rotating the phone in place. We download them, stitch a wide horizontal
# panorama (spherical warp), upload the result, and write the job's status back to
# the same S3 meta JSON the router/poller read.
#
# Coverage is a horizontal 360° *strip*: full pan left/right, limited vertical FOV
# (a phone sweep doesn't see straight up/down). Pannellum renders it as a partial
# panorama via haov/vaov — exactly what the app's PanoramaNode already supports.

import json
import math
import os
import numpy as np

try:
    import cv2  # present in the Lambda container; absent in a numpy-only --selfcheck
except ImportError:  # pragma: no cover — only the cv2-free self-check hits this
    cv2 = None


def _s3():
    import boto3  # lazy: keeps stitch()/FOV math importable without the AWS SDK
    return boto3.client("s3")

# We assume the user swept a (near-)full turn. There's no reliable per-frame FOV
# from a phone without calibration, so haov is an assumption (knob), and vaov is
# derived from the stitched aspect ratio. Tune ASSUMED_HAOV per device if the 360
# wrap shows a seam.  # ponytail: fixed haov assumption; upgrade = per-device FOV calibration.
ASSUMED_HAOV = float(os.environ.get("ASSUMED_HAOV", "360"))
# A stitched pano can be huge; Pannellum/WebGL caps texture size at 4096.
MAX_W = int(os.environ.get("MAX_PANO_WIDTH", "4096"))


def _download(s3, bucket, key):
    obj = s3.get_object(Bucket=bucket, Key=key)
    buf = np.frombuffer(obj["Body"].read(), dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"could not decode {key}")
    return img


def _put_meta(s3, bucket, meta_key, meta):
    s3.put_object(
        Bucket=bucket,
        Key=meta_key,
        Body=json.dumps(meta).encode(),
        ContentType="application/json",
    )


def _crop_black(pano):
    """A spherical-warp stitch is a curved/banana strip: its canvas corners and
    concave arcs are pure black (0,0,0) padding. Ship that uncropped and the
    viewer stretches black across the sphere. So: (1) bbox-crop to the non-black
    region, then (2) inpaint any black that survives *inside* that bbox (the
    concave top/bottom arcs), so no zero pixel reaches the JPEG. Returns the
    cleaned pano; raises if the frame is entirely black."""
    gray = cv2.cvtColor(pano, cv2.COLOR_BGR2GRAY)
    ys, xs = np.where(gray > 0)
    if ys.size == 0:
        raise RuntimeError("stitched pano is entirely black")
    y0, y1 = int(ys.min()), int(ys.max())
    x0, x1 = int(xs.min()), int(xs.max())
    pano = pano[y0:y1 + 1, x0:x1 + 1]

    # Interior black (the concave arcs left after a rectangular bbox crop). Mask
    # the zeros and inpaint them from surrounding real pixels so nothing black
    # survives to encode.
    gray = cv2.cvtColor(pano, cv2.COLOR_BGR2GRAY)
    holes = (gray == 0).astype(np.uint8)
    if holes.any():
        pano = cv2.inpaint(pano, holes, 3, cv2.INPAINT_TELEA)
    return pano


def stitch(images):
    """Stitch overlapping frames into one wide panorama. Returns (pano, haov, vaov)
    or raises on failure. Pure-ish (no S3) so it can be unit-tested locally."""
    if len(images) < 2:
        raise ValueError("need at least 2 frames")
    stitcher = cv2.Stitcher_create(cv2.Stitcher_PANORAMA)
    status, pano = stitcher.stitch(images)
    if status != cv2.Stitcher_OK:
        raise RuntimeError(f"stitch failed (status {status})")

    # Strip the black warp-padding *before* deriving FOV — otherwise vaov is
    # measured off a black-inflated bounding box and the viewer stretches emptiness.
    pano = _crop_black(pano)

    h, w = pano.shape[:2]
    if w > MAX_W:
        scale = MAX_W / w
        pano = cv2.resize(pano, (MAX_W, int(round(h * scale))),
                          interpolation=cv2.INTER_AREA)
        h, w = pano.shape[:2]

    # Honest FOV from the *cropped* pixels. Equirectangular degrees-per-pixel is
    # equal on both axes, so once we fix the horizontal span we get the vertical
    # span from the pixel aspect ratio. The cropped strip rarely spans a true
    # 360°; cap haov at the assumption but never claim more pan than the aspect
    # ratio can carry given the (clamped) vaov, so the returned haov/vaov always
    # match the cropped pixels.
    haov = min(ASSUMED_HAOV, 360.0)
    vaov = haov * (h / w)
    if vaov > 180.0:
        # Aspect ratio implies more vertical than a sphere holds: clamp vaov and
        # re-derive haov so the pair stays consistent with the pixel ratio.
        vaov = 180.0
        haov = min(haov, vaov * (w / h))
    return pano, haov, vaov


# ─────────────────────────────────────────────────────────────────────────────
# Pose-assisted direct projection
# ─────────────────────────────────────────────────────────────────────────────
#
# When the app sends KNOWN per-frame poses we skip feature-matching entirely and
# build the equirectangular output by DIRECT PROJECTION — deterministic, immune
# to the "black hole" failure on blank walls (no features to match needed).
#
# Geometry / conventions (all angles in DEGREES on input):
#   • World frame: right-handed. +Y is up. A direction is built from
#     (lon, lat):  longitude λ ∈ [−180,180] is the heading (yaw) measured from
#     the +Z axis, increasing toward +X; latitude φ ∈ [−90,90] is the elevation.
#         d = ( cosφ·sinλ ,  sinφ ,  cosφ·cosλ )
#     so λ=0,φ=0 → +Z (forward), λ=+90 → +X (right), φ=+90 → +Y (up).
#   • A frame's pose is (yaw, pitch, hfov, vfov). yaw rotates about +Y (heading),
#     pitch rotates about the camera's right axis (tilt up = positive). A pixel in
#     the frame looks along the camera's forward (+Z_cam) axis; hfov/vfov are the
#     full horizontal/vertical fields of view.
#   • To test whether a world direction d falls inside frame i, rotate d INTO the
#     camera frame: undo yaw (rotate −yaw about Y), then undo pitch (rotate −pitch
#     about the camera X axis). In-camera coords (xc, yc, zc) with zc>0 (in front)
#     project to normalized image offsets:
#         u = (xc/zc) / tan(hfov/2)        ∈ [−1,1] inside the frame
#         v = (yc/zc) / tan(vfov/2)        ∈ [−1,1] inside the frame
#     pixel = ((u+1)/2·(W−1), (1−(v+1)/2)·(H−1))   (v up → row down).


def _dir_from_lonlat(lon_deg, lat_deg):
    """Unit world direction(s) for longitude/latitude grids (degrees).
    Accepts scalars or numpy arrays of matching shape; returns (dx, dy, dz)."""
    lon = np.radians(lon_deg)
    lat = np.radians(lat_deg)
    cos_lat = np.cos(lat)
    dx = cos_lat * np.sin(lon)
    dy = np.sin(lat)
    dz = cos_lat * np.cos(lon)
    return dx, dy, dz


def _project_into_frame(dx, dy, dz, yaw_deg, pitch_deg, hfov_deg, vfov_deg):
    """Rotate world direction(s) into a frame's camera space and project to
    normalized image coords. Returns (u, v, infront) where u,v ∈ [−1,1] map to the
    frame interior and `infront` marks directions on the camera's +Z hemisphere.
    Vectorized: dx/dy/dz may be arrays of identical shape."""
    yaw = math.radians(yaw_deg)
    pitch = math.radians(pitch_deg)
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)

    # Undo yaw (rotate −yaw about +Y): heading-align the direction with the camera.
    #   x' =  cy·x − sy·z ;  z' =  sy·x + cy·z ;  y' = y
    x1 = cy * dx - sy * dz
    y1 = dy
    z1 = sy * dx + cy * dz

    # Undo pitch (rotate −pitch about the camera X axis): level the tilt, so a
    # world direction at the frame's pitch lands on the camera's forward (+Z) axis.
    #   y'' =  cp·y' − sp·z' ;  z'' =  sp·y' + cp·z'
    xc = x1
    yc = cp * y1 - sp * z1
    zc = sp * y1 + cp * z1

    infront = zc > 1e-6
    # Guard division; off-camera entries get pushed far outside [−1,1] and culled.
    safe_z = np.where(infront, zc, 1.0)
    th = math.tan(math.radians(hfov_deg) * 0.5)
    tv = math.tan(math.radians(vfov_deg) * 0.5)
    u = (xc / safe_z) / th
    v = (yc / safe_z) / tv
    return u, v, infront


def project_poses(images, poses, out_w=4096):
    """Direct equirectangular re-projection from KNOWN poses.

    For every output equirect pixel we reverse-map: for each frame, if the pixel's
    world direction falls within that frame's FOV, bilinear-sample the frame and
    accumulate with a cosine edge-feather weight (→0 at the frame border) for
    smooth overlap blending; the result is the weight-normalized average. Pixels
    no frame covers stay black and are filled afterward by the pole blur-stretch so
    nothing ships as a hard hole.

    Returns (pano, haov, vaov, covered_fraction). haov/vaov reflect the actual
    covered arc derived from the poses (yaw span + half-fov margins, pitch span +
    half-fov margins). Raises if nothing projected."""
    out_w = int(out_w)
    out_h = out_w // 2
    lon = (np.arange(out_w, dtype=np.float32) / out_w) * 360.0 - 180.0
    lat = 90.0 - (np.arange(out_h, dtype=np.float32) / out_h) * 180.0
    lon_grid, lat_grid = np.meshgrid(lon, lat)  # (out_h, out_w)
    dx, dy, dz = _dir_from_lonlat(lon_grid, lat_grid)

    acc = np.zeros((out_h, out_w, 3), dtype=np.float32)
    wsum = np.zeros((out_h, out_w), dtype=np.float32)

    for img, pose in zip(images, poses):
        fh, fw = img.shape[:2]
        u, v, infront = _project_into_frame(
            dx, dy, dz, pose["yaw"], pose["pitch"], pose["hfov"], pose["vfov"])
        inside = infront & (np.abs(u) <= 1.0) & (np.abs(v) <= 1.0)
        if not inside.any():
            continue

        # Cosine edge-feather: full weight at frame center, →0 at any border, so
        # overlapping frames cross-fade instead of hard-seaming.
        weight = (np.cos(u * (math.pi / 2.0)) * np.cos(v * (math.pi / 2.0)))
        weight = np.where(inside, np.clip(weight, 0.0, None), 0.0).astype(np.float32)

        # Frame pixel coords (v up → row down). Sample only covered pixels.
        px = ((u + 1.0) * 0.5) * (fw - 1)
        py = ((1.0 - (v + 1.0) * 0.5)) * (fh - 1)
        ys, xs = np.where(inside)
        sampled = _bilinear_sample(img, px[ys, xs], py[ys, xs])
        w_sel = weight[ys, xs][:, None]
        acc[ys, xs] += sampled * w_sel
        wsum[ys, xs] += weight[ys, xs]

    covered = wsum > 1e-6
    if not covered.any():
        raise RuntimeError("pose projection covered no pixels")
    pano = np.zeros((out_h, out_w, 3), dtype=np.uint8)
    safe_w = np.where(covered, wsum, 1.0)[..., None]
    blended = (acc / safe_w)
    pano[covered] = np.clip(blended[covered], 0, 255).astype(np.uint8)

    # Fill any uncovered pixels (poles / gaps) so nothing ships as a hard hole.
    # Reuse the strip→pole blur-stretch (per-column nearest valid row) used by the
    # pole-fill path, then heal the 360 wrap seam.
    try:
        import pole_fill as pf
        valid = (covered.astype(np.uint8) * 255)
        pano = pf._blur_stretch_poles(pano, valid)
        pano = pf._heal_wrap_seam(pano)
    except Exception:  # noqa: BLE001 — pole-fill is a nicety; honest holes if absent
        pass

    haov, vaov = _arc_from_poses(poses)
    return pano, haov, vaov, float(covered.mean())


def _bilinear_sample(img, px, py):
    """Bilinear-sample img (H,W,3 uint8) at float coords px,py (1-D arrays).
    Returns (N,3) float32. Coords are clamped to the image bounds."""
    fh, fw = img.shape[:2]
    px = np.clip(px, 0, fw - 1)
    py = np.clip(py, 0, fh - 1)
    x0 = np.floor(px).astype(np.int64)
    y0 = np.floor(py).astype(np.int64)
    x1 = np.clip(x0 + 1, 0, fw - 1)
    y1 = np.clip(y0 + 1, 0, fh - 1)
    wx = (px - x0)[:, None]
    wy = (py - y0)[:, None]
    imf = img.astype(np.float32)
    top = imf[y0, x0] * (1 - wx) + imf[y0, x1] * wx
    bot = imf[y1, x0] * (1 - wx) + imf[y1, x1] * wx
    return top * (1 - wy) + bot * wy


def _arc_from_poses(poses):
    """Covered horizontal/vertical arc (degrees) implied by the poses.
    haov = yaw span widened by each end frame's half-hfov (clamped 0..360).
    vaov = pitch span widened by each end frame's half-vfov (clamped 0..180).
    A full yaw wrap (span + margins ≥ 360) reports 360."""
    yaws = [p["yaw"] % 360.0 for p in poses]
    half_h = max(p["hfov"] for p in poses) * 0.5
    # Horizontal: edges of each frame on the 0..360 circle; if they blanket the
    # circle, it's a full 360. Otherwise the covered span is max−min of edges.
    edges = []
    for p in poses:
        c = p["yaw"] % 360.0
        edges.append((c - p["hfov"] * 0.5) % 360.0)
        edges.append((c + p["hfov"] * 0.5) % 360.0)
    if _covers_full_circle(yaws, half_h):
        haov = 360.0
    else:
        lo = min(p["yaw"] - p["hfov"] * 0.5 for p in poses)
        hi = max(p["yaw"] + p["hfov"] * 0.5 for p in poses)
        haov = min(360.0, max(0.0, hi - lo))

    pitch_lo = min(p["pitch"] - p["vfov"] * 0.5 for p in poses)
    pitch_hi = max(p["pitch"] + p["vfov"] * 0.5 for p in poses)
    vaov = min(180.0, max(0.0, pitch_hi - pitch_lo))
    return haov, vaov


def _covers_full_circle(yaws, half_fov):
    """True if frame centers (each ±half_fov) with no gap blanket the 0..360 yaw
    circle — i.e. the sweep is a full panorama."""
    if not yaws:
        return False
    ys = sorted(y % 360.0 for y in yaws)
    prev = ys[-1] - 360.0
    for y in ys:
        if (y - half_fov) > (prev + half_fov) + 1e-6:
            return False  # a gap wider than the two adjoining half-FOVs
        prev = y
    return True


def _handle_pose_stitch(images, poses):
    """Build the pano from known poses, mirroring stitch()'s post-processing
    (width cap to MAX_W). Returns (pano, haov, vaov)."""
    pano, haov, vaov, _covered = project_poses(images, poses, out_w=MAX_W)
    h, w = pano.shape[:2]
    if w > MAX_W:
        scale = MAX_W / w
        pano = cv2.resize(pano, (MAX_W, int(round(h * scale))),
                          interpolation=cv2.INTER_AREA)
    return pano, haov, vaov


def _valid_poses(poses, n_frames):
    """True only when `poses` is a list aligned 1:1 with the frames and every entry
    carries finite yaw/pitch/hfov/vfov (hfov/vfov > 0). Otherwise we fall back to
    the cv2.Stitcher path. (The router already validates, but the stitcher must be
    self-defending since it's invoked async with whatever payload arrives.)"""
    if not isinstance(poses, list) or len(poses) != n_frames or not poses:
        return False
    for p in poses:
        if not isinstance(p, dict):
            return False
        try:
            yaw = float(p["yaw"]); pitch = float(p["pitch"])
            hfov = float(p["hfov"]); vfov = float(p["vfov"])
        except (KeyError, TypeError, ValueError):
            return False
        if not all(math.isfinite(x) for x in (yaw, pitch, hfov, vfov)):
            return False
        if hfov <= 0 or vfov <= 0:
            return False
    return True


def _handle_pole_fill(event):
    """op=poleFill: download the strip (+ optional floor/ceiling photos), composite
    real floor/ceiling caps via pole_fill.fill_poles, upload the completed
    equirectangular pano, return its URL. Invoked synchronously by the router."""
    import pole_fill as pf
    bucket = event["bucket"]
    region = os.environ.get("AWS_REGION", "eu-central-1")
    s3 = _s3()
    try:
        strip = _download(s3, bucket, event["stripKey"])
        floor = _download(s3, bucket, event["floorKey"]) if event.get("floorKey") else None
        ceiling = (_download(s3, bucket, event["ceilingKey"])
                   if event.get("ceilingKey") else None)
        out = pf.fill_poles(strip, floor, ceiling,
                            out_w=MAX_W, vaov=float(event.get("vaov", 60)))
        ok, buf = cv2.imencode(".jpg", out, [cv2.IMWRITE_JPEG_QUALITY, 90])
        if not ok:
            raise RuntimeError("encode failed")
        result_key = event["resultKey"]
        s3.put_object(Bucket=bucket, Key=result_key, Body=buf.tobytes(),
                      ContentType="image/jpeg", CacheControl="public, max-age=31536000")
        return {"status": "ready",
                "imageUrl": f"https://{bucket}.s3.{region}.amazonaws.com/{result_key}"}
    except Exception as e:  # noqa: BLE001
        return {"status": "failed", "error": str(e)}


# ─────────────────────────────────────────────────────────────────────────────
# Video frame source
# ─────────────────────────────────────────────────────────────────────────────
#
# The app records ONE mp4 while rotating in place and a gyro pose timeline
# [{tMs, yaw, pitch}]. We decode the video, interpolate each frame's pose from
# the timeline by its timestamp, score sharpness (variance of the Laplacian),
# bucket frames by yaw, and keep only the SHARPEST frame per bucket. The chosen
# frames + their poses then feed the EXISTING project_poses() projector — the
# video is just a better frame source for the pose-assisted stitcher.

# 24 yaw buckets → 15° each: dense enough that adjacent frames overlap given a
# typical phone hfov (~60°), coarse enough to keep the projector cheap.
VIDEO_YAW_BUCKETS = int(os.environ.get("VIDEO_YAW_BUCKETS", "24"))
# Drop frames blurrier than this (Laplacian variance). Motion blur during a sweep
# tanks this score; a low floor still rejects the truly smeared frames while
# keeping usable ones on textured walls.
VIDEO_SHARPNESS_FLOOR = float(os.environ.get("VIDEO_SHARPNESS_FLOOR", "12.0"))
# Don't Laplacian every frame at 30–60fps — step through to keep runtime bounded.
VIDEO_FRAME_STEP = int(os.environ.get("VIDEO_FRAME_STEP", "3"))
# Need a usable frame in at least this many buckets or the sweep is too sparse.
VIDEO_MIN_BUCKETS = int(os.environ.get("VIDEO_MIN_BUCKETS", "6"))


def _interp_pose(timeline, t_ms):
    """Linearly interpolate (yaw, pitch) from the gyro `timeline` (list of
    {tMs, yaw, pitch}, assumed time-sorted) at time `t_ms`. yaw is interpolated
    on the shortest arc so the 360→0 wrap doesn't spin the result the long way.
    Clamps to the endpoints outside the timeline range. Returns (yaw, pitch) with
    yaw normalized to [0,360)."""
    n = len(timeline)
    if n == 0:
        return 0.0, 0.0
    if t_ms <= timeline[0]["tMs"]:
        return timeline[0]["yaw"] % 360.0, float(timeline[0]["pitch"])
    if t_ms >= timeline[-1]["tMs"]:
        return timeline[-1]["yaw"] % 360.0, float(timeline[-1]["pitch"])
    # Find the bracketing pair [a, b] with a.tMs <= t_ms <= b.tMs.
    lo, hi = 0, n - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if timeline[mid]["tMs"] <= t_ms:
            lo = mid
        else:
            hi = mid
    a, b = timeline[lo], timeline[hi]
    span = b["tMs"] - a["tMs"]
    f = 0.0 if span <= 0 else (t_ms - a["tMs"]) / span
    # Shortest-arc yaw interpolation (handle the 360 wrap).
    dyaw = ((b["yaw"] - a["yaw"] + 180.0) % 360.0) - 180.0
    yaw = (a["yaw"] + f * dyaw) % 360.0
    pitch = a["pitch"] + f * (b["pitch"] - a["pitch"])
    return yaw, float(pitch)


def _select_video_keyframes(scored, n_buckets):
    """Given `scored` = list of (yaw, pitch, sharpness, frame_or_index), keep only
    the SHARPEST entry per yaw bucket whose sharpness clears the floor. Returns a
    dict {bucket_index: best_entry}. Pure (no cv2) so it's self-checkable."""
    best = {}
    bucket_w = 360.0 / n_buckets
    for entry in scored:
        yaw, _pitch, sharp, _payload = entry
        if sharp < VIDEO_SHARPNESS_FLOOR:
            continue
        b = int((yaw % 360.0) / bucket_w) % n_buckets
        if b not in best or sharp > best[b][2]:
            best[b] = entry
    return best


def _handle_video_stitch(event):
    """captureMode='video': decode the mp4, pick the sharpest keyframe per yaw
    bucket with its interpolated pose, then run the existing project_poses path.
    Returns {status:'ready', imageUrl, haov, vaov} or {status:'failed', error}."""
    bucket = event["bucket"]
    meta_key = event["metaKey"]
    result_key = event["resultKey"]
    region = os.environ.get("AWS_REGION", "eu-central-1")
    s3 = _s3()

    timeline = event.get("poseTimeline") or []
    # Defend: keep only well-formed, finite samples, time-sorted.
    clean = []
    for p in timeline:
        try:
            t = float(p["tMs"]); y = float(p["yaw"]); pi = float(p["pitch"])
        except (KeyError, TypeError, ValueError):
            continue
        if all(math.isfinite(x) for x in (t, y, pi)):
            clean.append({"tMs": t, "yaw": y, "pitch": pi})
    clean.sort(key=lambda p: p["tMs"])

    hfov = float(event.get("hfov") or 0)
    vfov = float(event.get("vfov") or 0)

    try:
        if len(clean) < 2:
            raise RuntimeError("pose timeline too short (need >=2 gyro samples)")
        if hfov <= 0 or vfov <= 0:
            raise RuntimeError("missing hfov/vfov for video projection")

        # Download the recorded video to /tmp and open it.
        vid_path = "/tmp/pano_video.mp4"
        obj = s3.get_object(Bucket=bucket, Key=event["videoKey"])
        with open(vid_path, "wb") as fh:
            fh.write(obj["Body"].read())
        cap = cv2.VideoCapture(vid_path)
        if not cap.isOpened():
            raise RuntimeError("could not open recorded video")

        # Walk frames (subsampled), interpolate pose by timestamp, score sharpness,
        # and keep the sharpest frame per yaw bucket.
        bucket_w = 360.0 / VIDEO_YAW_BUCKETS
        best = {}  # bucket -> (yaw, pitch, sharpness, frame)
        i = 0
        try:
            while True:
                ok, frame = cap.read()
                if not ok:
                    break
                if i % VIDEO_FRAME_STEP != 0:
                    i += 1
                    continue
                i += 1
                t_ms = cap.get(cv2.CAP_PROP_POS_MSEC)
                yaw, pitch = _interp_pose(clean, t_ms)
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                sharp = float(cv2.Laplacian(gray, cv2.CV_64F).var())
                if sharp < VIDEO_SHARPNESS_FLOOR:
                    continue
                b = int((yaw % 360.0) / bucket_w) % VIDEO_YAW_BUCKETS
                if b not in best or sharp > best[b][2]:
                    best[b] = (yaw, pitch, sharp, frame)
        finally:
            cap.release()

        if len(best) < VIDEO_MIN_BUCKETS:
            raise RuntimeError(
                f"only {len(best)} usable yaw buckets (need >={VIDEO_MIN_BUCKETS}); "
                "sweep too sparse or too blurry — rotate slower for a full turn")

        images, poses = [], []
        for b in sorted(best):
            yaw, pitch, _sharp, frame = best[b]
            images.append(frame)
            poses.append({"yaw": yaw, "pitch": pitch, "hfov": hfov, "vfov": vfov})

        # Feed the EXISTING deterministic projector + pole-fill (same as photos).
        pano, haov, vaov = _handle_pose_stitch(images, poses)

        ok, buf = cv2.imencode(".jpg", pano, [cv2.IMWRITE_JPEG_QUALITY, 90])
        if not ok:
            raise RuntimeError("encode failed")
        s3.put_object(
            Bucket=bucket, Key=result_key, Body=buf.tobytes(),
            ContentType="image/jpeg", CacheControl="public, max-age=31536000",
        )
        image_url = f"https://{bucket}.s3.{region}.amazonaws.com/{result_key}"
        _put_meta(s3, bucket, meta_key, {
            **event.get("meta", {}),
            "status": "ready", "imageUrl": image_url,
            "haov": round(haov, 2), "vaov": round(vaov, 2),
        })
        return {"status": "ready", "imageUrl": image_url}
    except Exception as e:  # noqa: BLE001 — record any failure for the poller
        _put_meta(s3, bucket, meta_key, {
            **event.get("meta", {}), "status": "failed", "error": str(e),
        })
        return {"status": "failed", "error": str(e)}


def handler(event, _context):
    # Synchronous pole-fill op (router RequestResponse); default = async stitch job.
    if event.get("op") == "poleFill":
        return _handle_pole_fill(event)
    # Video capture: recorded mp4 + gyro pose timeline → sharpest keyframe per
    # yaw bucket → existing pose-assisted projector.
    if event.get("captureMode") == "video":
        return _handle_video_stitch(event)
    bucket = event["bucket"]
    meta_key = event["metaKey"]
    frame_keys = event["frameKeys"]
    result_key = event["resultKey"]
    region = os.environ.get("AWS_REGION", "eu-central-1")
    s3 = _s3()

    # Optional KNOWN-pose path: a `poses` array parallel to frame_keys lets us
    # project deterministically instead of feature-matching. We must keep frames
    # and poses index-aligned, so download per-frame and drop the matching pose
    # whenever a frame is missing/undecodable. If poses are absent or don't line up
    # (post-download), we fall back to the cv2.Stitcher path below — fully
    # backward-compatible.
    poses_in = event.get("poses")
    use_poses = _valid_poses(poses_in, len(frame_keys))

    try:
        images = []
        kept_poses = []
        for i, k in enumerate(frame_keys):
            try:
                img = _download(s3, bucket, k)
            except Exception:  # noqa: BLE001 — dropped upload; skip frame (+ its pose)
                continue
            images.append(img)
            if use_poses:
                kept_poses.append(poses_in[i])
        if len(images) < 2:
            raise RuntimeError(f"only {len(images)} usable frames (need ≥2)")

        if use_poses and len(kept_poses) == len(images) and len(kept_poses) >= 2:
            # Deterministic pose-assisted projection (the real fix for blank-wall
            # stitch failures). Any unexpected failure falls back to cv2.Stitcher.
            try:
                pano, haov, vaov = _handle_pose_stitch(images, kept_poses)
            except Exception as pe:  # noqa: BLE001
                print(f"pose projection failed, falling back to Stitcher: {pe}")
                pano, haov, vaov = stitch(images)
        else:
            pano, haov, vaov = stitch(images)

        ok, buf = cv2.imencode(".jpg", pano, [cv2.IMWRITE_JPEG_QUALITY, 90])
        if not ok:
            raise RuntimeError("encode failed")
        s3.put_object(
            Bucket=bucket, Key=result_key, Body=buf.tobytes(),
            ContentType="image/jpeg", CacheControl="public, max-age=31536000",
        )
        image_url = f"https://{bucket}.s3.{region}.amazonaws.com/{result_key}"
        _put_meta(s3, bucket, meta_key, {
            **event.get("meta", {}),
            "status": "ready", "imageUrl": image_url,
            "haov": round(haov, 2), "vaov": round(vaov, 2),
        })
        return {"status": "ready", "imageUrl": image_url}
    except Exception as e:  # noqa: BLE001 — record any failure for the poller
        _put_meta(s3, bucket, meta_key, {
            **event.get("meta", {}), "status": "failed", "error": str(e),
        })
        return {"status": "failed", "error": str(e)}


def _selfcheck():
    """Pure lon/lat→frame projection sanity checks (numpy only — no cv2/boto3).
    Run with:  python3 app.py --selfcheck"""
    def proj(lon, lat, yaw, pitch, hfov, vfov):
        dx, dy, dz = _dir_from_lonlat(np.float32(lon), np.float32(lat))
        u, v, infront = _project_into_frame(
            np.array(dx), np.array(dy), np.array(dz), yaw, pitch, hfov, vfov)
        return float(u), float(v), bool(infront)

    # 1) A direction straight along a frame's axis lands at its center (u≈v≈0).
    u, v, f = proj(30, 0, 30, 0, 90, 60)
    assert f and abs(u) < 1e-5 and abs(v) < 1e-5, ("center", u, v, f)

    # 2) The right edge of a frame's hfov maps to u≈+1, still centered vertically.
    u, v, f = proj(45, 0, 0, 0, 90, 60)  # yaw 0, hfov 90 → edge at lon=+45
    assert f and abs(u - 1.0) < 1e-4 and abs(v) < 1e-4, ("right edge", u, v, f)

    # 3) The top edge of vfov maps to v≈+1 (looking up), u≈0.
    u, v, f = proj(0, 30, 0, 0, 90, 60)  # vfov 60 → top edge at lat=+30
    assert f and abs(u) < 1e-4 and abs(v - 1.0) < 1e-4, ("top edge", u, v, f)

    # 4) A direction behind the camera is culled (not in front).
    _, _, f = proj(180, 0, 0, 0, 90, 60)
    assert not f, "rear direction should be behind camera"

    # 5) Pitch tilt: looking up 30°, a direction at lat=+30 lands at the center.
    u, v, f = proj(0, 30, 0, 30, 90, 60)
    assert f and abs(u) < 1e-4 and abs(v) < 1e-4, ("pitched center", u, v, f)

    # 6) Arc derivation: three frames at yaw 0/120/240, hfov 150 → full 360 wrap;
    #    pitch 0, vfov 60 → vaov 60.
    poses = [{"yaw": y, "pitch": 0, "hfov": 150, "vfov": 60} for y in (0, 120, 240)]
    haov, vaov = _arc_from_poses(poses)
    assert haov == 360.0 and abs(vaov - 60.0) < 1e-6, ("arc full", haov, vaov)

    # 7) Partial sweep: two frames at yaw 0/30, hfov 40 → span 0±20..30±20 = 70.
    poses = [{"yaw": 0, "pitch": 0, "hfov": 40, "vfov": 50},
             {"yaw": 30, "pitch": 0, "hfov": 40, "vfov": 50}]
    haov, vaov = _arc_from_poses(poses)
    assert abs(haov - 70.0) < 1e-6 and abs(vaov - 50.0) < 1e-6, ("arc partial", haov, vaov)

    # ── Video pipeline (numpy-only: no cv2/boto3) ────────────────────────────
    tl = [{"tMs": 0, "yaw": 0, "pitch": -5},
          {"tMs": 1000, "yaw": 90, "pitch": 5}]
    # 8) Midpoint interpolation: half-way in time → half-way in yaw/pitch.
    y, p = _interp_pose(tl, 500)
    assert abs(y - 45.0) < 1e-6 and abs(p - 0.0) < 1e-6, ("interp mid", y, p)
    # 9) Clamp before/after the timeline to the endpoints.
    y, _ = _interp_pose(tl, -100); assert abs(y - 0.0) < 1e-6, ("clamp lo", y)
    y, _ = _interp_pose(tl, 9999); assert abs(y - 90.0) < 1e-6, ("clamp hi", y)
    # 10) Shortest-arc wrap: 350° → 10° midpoint is 0°, not 180°.
    wrap = [{"tMs": 0, "yaw": 350, "pitch": 0}, {"tMs": 100, "yaw": 10, "pitch": 0}]
    y, _ = _interp_pose(wrap, 50)
    assert abs(((y + 180.0) % 360.0) - 180.0) < 1e-6, ("wrap mid", y)
    # 11) Yaw-bucket selection: keep the sharpest per bucket, drop below floor.
    floor = VIDEO_SHARPNESS_FLOOR
    scored = [
        (5.0, 0.0, floor + 10, "a"),   # bucket 0, sharp
        (6.0, 0.0, floor + 50, "b"),   # bucket 0, sharper → wins
        (20.0, 0.0, floor - 1, "c"),   # bucket 1, below floor → dropped
        (200.0, 0.0, floor + 5, "d"),  # another bucket, kept
    ]
    sel = _select_video_keyframes(scored, VIDEO_YAW_BUCKETS)
    b0 = int((5.0) / (360.0 / VIDEO_YAW_BUCKETS))
    assert sel[b0][3] == "b", ("bucket sharpest", sel.get(b0))
    assert len(sel) == 2, ("bucket count", sorted(sel))

    print("selfcheck OK")


if __name__ == "__main__":
    import sys
    if "--selfcheck" in sys.argv:
        _selfcheck()
