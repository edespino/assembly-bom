#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "pxf" ]]; then
  echo "[pxf-start] ERROR: this step is pxf-only" >&2
  exit 1
fi
# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/../../../lib/gpdemo-env.sh"
demo=$(gpdemo_env_file) || {
  echo "[pxf-start] ERROR: gpdemo-env.sh not found at ${HOME}/gpdemo/gpdemo-env.sh" >&2
  exit 1
}
# shellcheck disable=SC1090
source "$demo"
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="${JAVA_HOME}/bin:${PXF_HOME:-/usr/local/cloudberry-pxf}/bin:${PATH}"
export PXF_HOME=/usr/local/cloudberry-pxf
export PXF_BASE="${HOME}/pxf-base"
# Segments connect to the private hostname, while pxf start health-checks localhost.
# A private-IP-only bind looks down. Listen on every interface.
props="${PXF_BASE}/conf/pxf-application.properties"
if [[ -f "$props" ]] && ! grep -q '^server.address=' "$props"; then
  echo "server.address=0.0.0.0" >> "$props"
fi
gpstart -a || true
pxf start
psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pxf;"
# The coordinator create does not install the extension on the segments.
# A segment query then returns no rows and does not call PXF.
while read -r port; do
  PGOPTIONS="-c gp_session_role=utility" psql -h 127.0.0.1 -p "$port" -d postgres -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pxf;"
done < <(psql -d postgres -tA -c "SELECT port FROM gp_segment_configuration WHERE content >= 0 AND role = 'p' AND status = 'u'")
echo "[pxf-start] RESULT: PASS"
