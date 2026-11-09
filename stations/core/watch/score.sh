#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "watch" ]]; then
  echo "[watch-score] ERROR: this step is watch-only" >&2
  exit 1
fi
# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/../../../lib/gpdemo-env.sh"
demo=$(gpdemo_env_file) || {
  echo "[watch-score] ERROR: gpdemo-env.sh not found at ${HOME}/gpdemo/gpdemo-env.sh" >&2
  exit 1
}
# shellcheck disable=SC1090
source "$demo"
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if ! command -v python3.11 >/dev/null; then
  sudo dnf install -y python3.11
fi
python3.11 "$script_dir/score.py"
echo "[watch-score] RESULT: PASS"
