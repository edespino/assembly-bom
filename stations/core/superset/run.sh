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
  -e ADMIN_PASSWORD=admin \
  "$image" \
  bash -c 'superset db upgrade && superset fab create-admin --username admin --email admin@superset.com --password "$ADMIN_PASSWORD" --firstname Superset --lastname Admin && superset init && exec /app/docker/entrypoints/run-server.sh'
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if ! command -v python3.11 >/dev/null; then
  sudo dnf install -y python3.11
fi
python3.11 "$script_dir/board.py"
echo "[superset-run] container aml-superset started from $image"
echo "[superset-run] RESULT: PASS"
