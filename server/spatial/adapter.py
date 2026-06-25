#!/usr/bin/env python3
"""adapter.py — neural layout inference boundary (HorizonNet / AtlantaNet).

This is the ONLY place real model inference plugs in. Everything else in
`server/spatial/` is pure numpy geometry that runs and is tested without weights.

`predict_layout(pano_path) -> LayoutPrediction` is a documented STUB. Replace the
body with a real HorizonNet (sunset1995/HorizonNet, MIT code) or AtlantaNet
(crs4/AtlantaNet, MIT code) forward pass. The function contract is fixed: given a
panorama path, return per-column floor-wall and ceiling-wall boundary rows.

=============================================================================
 ⚠️  DATASET-LICENSE TRAP — DO NOT SHIP PUBLISHED WEIGHTS IN THE RESALE PRODUCT
-----------------------------------------------------------------------------
 The HorizonNet / AtlantaNet *code* is MIT, but every published checkpoint is
 trained on Matterport3D / ZInD / Structured3D, all of which carry NON-COMMERCIAL
 dataset licenses. A model's weights inherit the license of its training data;
 an MIT code license does NOT launder that. Using those checkpoints in a product
 that *sells* the derived floorplans/dimensions would violate the dataset terms.

 RECOMMENDATION (RENTLY_SPATIAL_ARCHITECTURE.md §1bis pt 4, §7):
   1. RETRAIN HorizonNet on Rently's OWN captured panoramas. The app already
      collects equirectangular panos at volume — that is the whole point of the
      capture funnel. Labelling = the cuboid/corner boundary per pano; can be
      bootstrapped semi-automatically and human-QA'd.
   2. OR use only Apache/BSD-trained layout weights if/when they exist.
   3. Until then: ship the MEASUREMENT math (this repo) and run inference only in
      an INTERNAL / research context, never against the sellable bucket.
 Audit the training mix of any checkpoint before it touches a paying customer.
=============================================================================
"""
from __future__ import annotations

from typing import Optional

import numpy as np

from room_layout import LayoutPrediction, synthesize_rectangular_room


def predict_layout(
    pano_path: str,
    model: str = "horizonnet",
    checkpoint: Optional[str] = None,
) -> LayoutPrediction:
    """Run room-layout inference on one equirectangular panorama.

    Args:
        pano_path : path to an equirectangular JPG/PNG.
        model     : "horizonnet" (rectangular/cuboid + general) or "atlantanet"
                    (better for L-shaped / non-Manhattan rooms).
        checkpoint: path to model weights. MUST be a commercially-clean / retrained
                    checkpoint for any sellable use (see license trap above).

    Returns:
        LayoutPrediction with per-column floor_v / ceil_v boundary rows.

    --- REAL IMPLEMENTATION (replace the stub below) -----------------------------
    HorizonNet:
        import torch
        from model import HorizonNet                 # sunset1995/HorizonNet
        from dataset import visualize_a_data         # for pano preprocessing
        from PIL import Image

        net = HorizonNet('resnet50', full_size=True)
        net.load_state_dict(torch.load(checkpoint)['state_dict'])
        net.eval()

        img = np.array(Image.open(pano_path).convert('RGB')) / 255.0
        # HorizonNet expects 512x1024, pre-aligned to gravity (panostretch / vp align)
        x = torch.from_numpy(img.transpose(2, 0, 1)[None]).float()
        with torch.no_grad():
            y_bon, y_cor = net(x)                     # y_bon: (1, 2, W) boundaries
        # y_bon[0,0] = ceiling boundary, y_bon[0,1] = floor boundary, in the model's
        # normalized vertical units -> convert to pixel rows v (0..H):
        #   v = (0.5 - bon / pi) * H     (HorizonNet outputs are in radians of phi
        #   offset from horizon; consult the repo's `inference.py` for the exact
        #   denormalization it uses — match it here).
        ceil_v = (0.5 - y_bon[0, 0].numpy() / np.pi) * H
        floor_v = (0.5 - y_bon[0, 1].numpy() / np.pi) * H
        return LayoutPrediction.from_boundaries(floor_v, ceil_v, width=W, height=H)

    AtlantaNet (crs4/AtlantaNet): emits floor & ceiling probability maps; extract the
    boundary row per column (argmax / sub-pixel peak) and feed the same contract.
    -----------------------------------------------------------------------------
    """
    raise NotImplementedError(
        "predict_layout is a stub. Plug in a RETRAINED (commercially-clean) "
        "HorizonNet/AtlantaNet checkpoint here — see the docstring and the "
        "license-trap warning. For testing without weights, use "
        "predict_layout_synthetic()."
    )


def predict_layout_synthetic(
    width_m: float = 4.0,
    length_m: float = 6.0,
    room_height_m: float = 2.7,
    camera_height_m: float = 1.5,
    pano_w: int = 1024,
    pano_h: int = 512,
) -> LayoutPrediction:
    """Weight-free stand-in for `predict_layout`, returning the boundaries a
    perfect model would emit for a known rectangular room. Lets the whole pipeline
    (and `pipeline.py`) run end-to-end with zero downloads."""
    pred, _ = synthesize_rectangular_room(
        width_m=width_m,
        length_m=length_m,
        room_height_m=room_height_m,
        camera_height_m=camera_height_m,
        pano_w=pano_w,
        pano_h=pano_h,
    )
    return pred
