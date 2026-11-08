#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "pxf" ]]; then
  echo "[pxf-start] ERROR: this step is pxf-only" >&2
  exit 1
fi
# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
demo=$(find "$HOME" /usr/local/cloudberry -name gpdemo-env.sh 2>/dev/null | head -1)
if [[ -z "$demo" ]]; then
  echo "[pxf-start] ERROR: gpdemo-env.sh not found" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$demo"
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="${JAVA_HOME}/bin:${PXF_HOME:-/usr/local/cloudberry-pxf}/bin:${PATH}"
export PXF_HOME=/usr/local/cloudberry-pxf
export PXF_BASE="${HOME}/pxf-base"
gpstart -a || true
pxf start
psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pxf;"
echo "[pxf-start] RESULT: PASS"
