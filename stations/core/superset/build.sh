#!/usr/bin/env bash
# Build Superset 6.1.0 from the cloned tag. Do not pull a published image.
# The 6.1.0 Dockerfile production stage is lean, not superset.
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "superset" ]]; then
  echo "[superset-build] ERROR: this step is superset-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
image="${SUPERSET_IMAGE:-aml-superset:6.1.0}"
cd "$PARTS_DIR/$NAME"
docker build --target lean -t "$image" .
echo "[superset-build] RESULT: PASS image=$image"
