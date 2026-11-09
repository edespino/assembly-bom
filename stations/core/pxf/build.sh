#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "pxf" ]]; then
  echo "[pxf-build] ERROR: this step is pxf-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
src=$(find "$PARTS_DIR/$NAME" -maxdepth 2 -type f -name Makefile | head -1)
if [[ -z "$src" ]]; then
  echo "[pxf-build] ERROR: extracted Makefile not found under $PARTS_DIR/$NAME" >&2
  exit 1
fi
cd "$(dirname "$src")"
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/gradle-wrapper.sh"
while IFS= read -r props; do
  gradle_use_reachable_distribution "$props"
done < <(find . -name gradle-wrapper.properties)
# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
export PXF_HOME=/usr/local/cloudberry-pxf
make -C external-table
make -C fdw
make -C cli
make -C server
echo "[pxf-build] RESULT: PASS"
