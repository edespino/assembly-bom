#!/usr/bin/env bash
# Build Superset 6.1.0 from the cloned tag. Do not pull a published image.
# The 6.1.0 Dockerfile production stage is lean, not superset.
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "superset" ]]; then
  echo "[superset-build] ERROR: this step is superset-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
image="${SUPERSET_IMAGE:-aml-superset:6.1.0}"
cd "$PARTS_DIR/$NAME"
docker build --target lean -t "$image" .
# The lean stage does not install the PostgreSQL driver. The demo connects
# to the Cloudberry coordinator, so add the extra the ci stage installs.
cat > /tmp/superset-postgres.Dockerfile << EOF
FROM ${image}
USER root
RUN uv pip install '.[postgres]'
USER superset
EOF
docker build -t "$image" -f /tmp/superset-postgres.Dockerfile "$PARTS_DIR/$NAME"
# shellcheck disable=SC1091
source "${script_dir}/../../../lib/build-artifact.sh"
artifact_publish superset "${ARTIFACT_VERSION:-6.1.0}" "$image"
echo "[superset-build] RESULT: PASS image=$image"
