#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "pxf" ]]; then
  echo "[pxf-install] ERROR: this step is pxf-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
src=$(find "$PARTS_DIR/$NAME" -maxdepth 2 -type f -name Makefile | head -1)
cd "$(dirname "$src")"
# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
export PXF_HOME=/usr/local/cloudberry-pxf
export PXF_BASE="${HOME}/pxf-base"
sudo mkdir -p "$PXF_HOME"
sudo chown -R "$(id -un):$(id -gn)" "$PXF_HOME"
make -C external-table install
make -C fdw install
make -C cli install
make -C server install-server
echo "[pxf-install] RESULT: PASS"
