# server/spatial — single-pano room layout → metric floorplan data product

Recover a room's **walls / floor / ceiling planes** from **ONE equirectangular
panorama** plus a **measured camera height**, and emit a metric **room data
product**: a floor polygon, room width/length/height, floor area, wall segments,
and a textured-box geometry spec the viewer uses for clean in-room parallax.

This is the **room-layout** path from `RENTLY_SPATIAL_ARCHITECTURE.md` §1bis point 4
("do NOT ship a depth-displaced sphere for furnished rooms — use room-layout
instead") — the same approach **Zillow 3D Home** uses. It produces both the viewer
geometry and the **sellable floorplan + room-dimensions** data product (§5).

## Why this and not depth

A per-pixel depth-displaced sphere rubber-sheets and tears across furniture — exactly
where furnished rooms live. A room as a **textured polygon-prism** (the walls/floor/
ceiling box) gives clean parallax *and* a measurable floorplan for free. Metric scale
comes from a **MEASURED tripod height** (~1.5 m → ~2–5% dimension error), **not** the
model's internal scale.

## Files

| File | Role |
|------|------|
| `room_layout.py` | **The math.** Converts HorizonNet-style per-column ceiling/floor boundaries + camera height → metric floorplan, dimensions, box geometry. Pure numpy, fully tested, **no weights needed**. Contains the runnable self-check. |
| `adapter.py` | **Neural boundary.** `predict_layout(pano_path)` — documented stub showing exactly where HorizonNet/AtlantaNet inference plugs in, plus `predict_layout_synthetic()` for weight-free runs. |
| `pipeline.py` | **The clean interface.** `run_layout(pano, camera_height) → RoomDataProduct`; an AWS Lambda `handler(event)` and a CLI. The glue behind `POST /spatial/layout`. |
| `requirements.txt` | numpy + pillow (torch/HorizonNet optional, real inference only). |

## The interface

```
pano (equirectangular) + measured_camera_height_m
  → predict_layout()           # HorizonNet/AtlantaNet  (adapter.py)
  → build_room_data_product()  # metric math            (room_layout.py)
  → RoomDataProduct JSON       # floorplan + dims + box geometry
```

### Output (`RoomDataProduct`) JSON shape

```jsonc
{
  "camera_height_m": 1.5,
  "ceiling_height_m": 1.2,        // camera -> ceiling
  "room_height_m": 2.7,           // floor -> ceiling
  "width_m": 4.0,
  "length_m": 6.0,
  "floor_area_m2": 23.95,
  "floor_polygon": [[x,y], ...],          // metric, ordered CCW
  "wall_segments": [{"start":[x,y],"end":[x,y],"length":m}, ...],
  "box_corners_floor":   [[x,y,-1.5], ...],   // 3D, world frame (+Z up)
  "box_corners_ceiling": [[x,y, 1.2], ...],   // viewer prism vertices
  "is_rectangular": true,
  "notes": "..."
}
```

**World frame:** right-handed, camera optical centre at the origin, **+Z up**, floor
plane at `z = -camera_height`. The viewer extrudes `box_corners_floor` →
`box_corners_ceiling` into a polygon prism, textures the walls from the pano by
reprojecting each wall quad, and dollies the camera inside it for genuine parallax.

## The math (column → metric)

Equirectangular column `u` → azimuth `θ`; row `v` → elevation `φ`. For a floor-wall
boundary seen at `(θ, φ_floor<0)` with measured camera height `h`:

```
r = h / tan(-φ_floor)                 # horizontal distance to that wall
floor_pt = (r·cosθ, r·sinθ, -h)
```

The ceiling-wall boundary at the **same column** shares `r` (same wall), so room
height = `h + r·tan(φ_ceil)`. Dense floor corners are reduced to room corners by a
heading-turn test on the **closed** boundary ring (so the column 0 ↔ N wrap is
handled), area via the shoelace formula.

## Run

```bash
PY=/Library/Frameworks/Python.framework/Versions/3.12/bin/python3

# Self-check (synthetic rectangular room, asserts recovered == truth):
$PY room_layout.py            # or: $PY room_layout.py --selfcheck

# End-to-end pipeline, weight-free (synthetic stand-in for the model):
$PY pipeline.py --synthetic --camera-height 1.5

# Real inference (after plugging a license-clean checkpoint into adapter.py):
$PY pipeline.py --pano room.jpg --camera-height 1.5 \
   --model horizonnet --checkpoint clean_weights.pth
```

## ⚠️ Dataset-license trap (read before anything sellable)

HorizonNet (`sunset1995/HorizonNet`) and AtlantaNet (`crs4/AtlantaNet`) **code is
MIT**, but every published **checkpoint is trained on Matterport3D / ZInD /
Structured3D, which are NON-COMMERCIAL**. A model's weights inherit its training
data's license — **an MIT code license does not launder that**. Shipping those
checkpoints in a product that **sells** the derived floorplans/dimensions would
violate the dataset terms (mirrors §7's "code license ≠ weight license" landmine).

**Recommendation:**
1. **Retrain HorizonNet on Rently's OWN captured panos** — the app already collects
   them at volume; that is the whole point of the capture funnel. This is the clean,
   defensible path for the resale business.
2. Or use only **Apache/BSD-trained** layout weights if/when available.
3. Until then, ship the **measurement math** (this repo is original/unencumbered) and
   run inference only **internally / research-only**, never against the sellable
   bucket.

The geometry in `room_layout.py` is original and license-free. **All license risk
lives in the weights loaded by `adapter.py`.** Audit the training mix before a
checkpoint touches a paying customer.

## Wiring into the app & AWS

- **Server:** `POST /spatial/layout` with `{pano_url, camera_height_m, model?,
  checkpoint?}` → `pipeline.handler(event)` → `RoomDataProduct` JSON. Write the JSON
  to the derived S3 bucket and return its URL.
- **App model:** the tour stores per-node layout via a new `PanoramaNode` field —
  see the integration note returned to the central integrator (do **not** edit
  `lib/` from here). Suggested: `String? roomLayoutUrl` pointing at this JSON.
- **Viewer:** the three.js layer builds the prism from `box_corners_floor/ceiling`,
  textures walls from the pano, dollies the camera for parallax; the floorplan UI
  renders `floor_polygon` + dimensions directly.
