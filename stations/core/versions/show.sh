#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "versions" ]]; then
  echo "[versions-show] ERROR: this step is versions-only" >&2
  exit 1
fi
# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
demo=$(find "$HOME" /usr/local/cloudberry -name gpdemo-env.sh 2>/dev/null | head -1)
# shellcheck disable=SC1090
source "$demo"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if ! command -v python3.11 >/dev/null; then
  sudo dnf install -y python3.11
fi
python3.11 "$script_dir/show.py"
echo "[versions-show] RESULT: PASS"
