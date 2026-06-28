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
import os
import cv2
import numpy as np


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


def handler(event, _context):
    # Synchronous pole-fill op (router RequestResponse); default = async stitch job.
    if event.get("op") == "poleFill":
        return _handle_pole_fill(event)
    bucket = event["bucket"]
    meta_key = event["metaKey"]
    frame_keys = event["frameKeys"]
    result_key = event["resultKey"]
    region = os.environ.get("AWS_REGION", "eu-central-1")
    s3 = _s3()

    try:
        # Download defensively: skip any frame that wasn't uploaded / won't decode
        # (e.g. a dropped upload) so a partial set still stitches instead of failing.
        images = []
        for k in frame_keys:
            try:
                images.append(_download(s3, bucket, k))
            except Exception:  # noqa: BLE001
                pass
        if len(images) < 2:
            raise RuntimeError(f"only {len(images)} usable frames (need ≥2)")
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
