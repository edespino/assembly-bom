#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "lakehouse" ]]; then
  echo "[lakehouse-publish] ERROR: this step is lakehouse-only" >&2
  exit 1
fi
# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
demo=$(find "$HOME" /usr/local/cloudberry -name gpdemo-env.sh 2>/dev/null | head -1)
# shellcheck disable=SC1090
source "$demo"
if ! command -v python3.11 >/dev/null; then
  sudo dnf install -y python3.11 python3.11-pip
fi
python3.11 -m pip install --user 'pyiceberg==0.12.0' 'pyarrow' 'boto3'
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
python3.11 "$script_dir/publish.py"
echo "[lakehouse-publish] RESULT: PASS"
