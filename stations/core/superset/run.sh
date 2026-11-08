#!/usr/bin/env bash
# Run the image built from the 6.1.0 tag. Host network so it can reach
# the demo-cluster coordinator on this machine. Do not pull a published image.
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "superset" ]]; then
  echo "[superset-run] ERROR: this step is superset-only" >&2
  exit 1
fi
image="${SUPERSET_IMAGE:-aml-superset:6.1.0}"
docker rm -f aml-superset >/dev/null 2>&1 || true
docker run -d --name aml-superset --network host \
  -e SUPERSET_SECRET_KEY=aml-spike-demo \
  "$image"
echo "[superset-run] container aml-superset started from $image"
echo "[superset-run] RESULT: PASS"
