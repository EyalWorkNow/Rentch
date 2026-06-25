#!/usr/bin/env python3
"""pipeline.py — the clean server interface: pano + camera height -> room JSON.

This is the single entry point an AWS Lambda / Batch handler (or a small Flask/
FastAPI route behind `POST /spatial/layout`) calls. It wires the neural adapter
(`predict_layout`) to the metric geometry kernel (`room_layout`).

    pano (equirectangular) + measured_camera_height_m
        -> predict_layout()            (HorizonNet/AtlantaNet; see adapter.py)
        -> build_room_data_product()   (pure numpy metric math; room_layout.py)
        -> RoomDataProduct JSON        (floorplan + dimensions + box geometry)

The output JSON is BOTH:
  * what the viewer consumes (box_corners_* -> a textured polygon-prism in three.js
    for clean in-room parallax), AND
  * the sellable data product (floor polygon, room dimensions, area, wall lengths)
    per RENTLY_SPATIAL_ARCHITECTURE.md §5.
"""
from __future__ import annotations

import argparse
import json
from typing import Optional

from adapter import predict_layout, predict_layout_synthetic
from room_layout import RoomDataProduct, build_room_data_product


def run_layout(
    pano_path: Optional[str],
    camera_height_m: float,
    model: str = "horizonnet",
    checkpoint: Optional[str] = None,
    synthetic: bool = False,
) -> RoomDataProduct:
    """Full pano -> room data product.

    Set `synthetic=True` (or omit pano_path) to run the weight-free stand-in so the
    pipeline can be exercised end-to-end without downloading any model.
    """
    if synthetic or pano_path is None:
        pred = predict_layout_synthetic(camera_height_m=camera_height_m)
    else:
        pred = predict_layout(pano_path, model=model, checkpoint=checkpoint)
    return build_room_data_product(pred, camera_height=camera_height_m)


def handler(event: dict) -> dict:
    """AWS Lambda-style handler.

    Expected event (mirrors `POST /spatial/layout`):
        {
          "pano_url": "s3://.../pano.jpg",      # or a local path
          "camera_height_m": 1.5,                # MEASURED tripod height
          "model": "horizonnet",                 # optional
          "checkpoint": "s3://.../clean.pth"     # optional, must be license-clean
        }

    Returns the RoomDataProduct as a dict (JSON-serialisable).
    """
    cam_h = float(event["camera_height_m"])
    pano = event.get("pano_url") or event.get("pano_path")
    product = run_layout(
        pano_path=pano,
        camera_height_m=cam_h,
        model=event.get("model", "horizonnet"),
        checkpoint=event.get("checkpoint"),
        synthetic=bool(event.get("synthetic", False)),
    )
    return json.loads(product.to_json())


def _main() -> None:
    ap = argparse.ArgumentParser(description="Single-pano room layout -> metric JSON")
    ap.add_argument("--pano", help="path to equirectangular panorama")
    ap.add_argument("--camera-height", type=float, default=1.5,
                    help="MEASURED camera/tripod height in metres (default 1.5)")
    ap.add_argument("--model", default="horizonnet",
                    choices=["horizonnet", "atlantanet"])
    ap.add_argument("--checkpoint", help="model weights (must be license-clean)")
    ap.add_argument("--synthetic", action="store_true",
                    help="run the weight-free synthetic stand-in")
    ap.add_argument("--out", help="write JSON here instead of stdout")
    args = ap.parse_args()

    product = run_layout(
        pano_path=args.pano,
        camera_height_m=args.camera_height,
        model=args.model,
        checkpoint=args.checkpoint,
        synthetic=args.synthetic or args.pano is None,
    )
    js = product.to_json()
    if args.out:
        with open(args.out, "w") as f:
            f.write(js)
        print(f"wrote {args.out}")
    else:
        print(js)


if __name__ == "__main__":
    _main()
