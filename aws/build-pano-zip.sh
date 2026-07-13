#!/usr/bin/env bash
# Builds the pano-stitch Lambda zip (Python + linux opencv/numpy wheels) WITHOUT
# Docker, by fetching manylinux wheels. Output: /tmp/pano-stitch.zip
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
B=/tmp/panobuild
rm -rf "$B" && mkdir -p "$B/pkg"

# linux x86_64 wheels for the Lambda python3.12 runtime (cross-downloaded on mac).
# Override the host interpreter with PYTHON=... if `python3` on PATH is broken
# (e.g. a Homebrew build with a mismatched libexpat).
PYBIN="${PYTHON:-python3}"
"$PYBIN" -m pip download --platform manylinux2014_x86_64 --python-version 312 \
  --only-binary=:all: --no-deps -d "$B/wheels" \
  opencv-python-headless==4.10.0.84 numpy==1.26.4
# requests (+ deps) for the AI-enhance OpenAI call from Python. Pure/py3 wheels
# except charset-normalizer (has a manylinux wheel); all fit the zip.
"$PYBIN" -m pip download --platform manylinux2014_x86_64 --python-version 312 \
  --only-binary=:all: -d "$B/wheels" requests
# NOTE: real floor/ceiling cap compositing (pole_fill.py) needs py360convert+scipy,
# whose wheels don't fit the 250 MB zip-Lambda limit alongside OpenCV. pole_fill
# imports them optionally and falls back to blur-stretch poles when absent. To
# enable real-cap compositing, move pano-stitch to a container-image Lambda and add
# py360convert + scipy==1.13.1 here.
for w in "$B"/wheels/*.whl; do unzip -q -o "$w" -d "$B/pkg"; done

# app.py (stitch + pole-fill + enhance ops) + pole_fill.py + cube_ops.py (numpy
# equirect<->cubemap) + enhance.py (AI pole-fill + 360 wrap pipeline)
cp "$HERE/lambda/pano-stitch/app.py" "$HERE/lambda/pano-stitch/pole_fill.py" \
   "$HERE/lambda/pano-stitch/cube_ops.py" "$HERE/lambda/pano-stitch/enhance.py" "$B/pkg/"
find "$B/pkg" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
rm -rf "$B"/pkg/*.dist-info 2>/dev/null || true

rm -f /tmp/pano-stitch.zip  # zip -r APPENDS — a stale file would smuggle old deps in
( cd "$B/pkg" && zip -q -r -X /tmp/pano-stitch.zip . )
echo "==> built /tmp/pano-stitch.zip ($(du -h /tmp/pano-stitch.zip | cut -f1)); unzipped $(du -sm "$B/pkg" | cut -f1) MB"
