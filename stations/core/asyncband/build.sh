#!/usr/bin/env bash
# The tarball's own commands are cargo x build, cargo x test, and cargo x lint.
# lint needs nightly. A failure in one command does not skip the others.
# The step exits non-zero if any command failed.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "asyncband" ]]; then
  echo "[asyncband-build] ERROR: this step is asyncband-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"

if [[ ! -f "$HOME/.cargo/env" ]]; then
  echo "[asyncband-build] ERROR: rustup env missing. Run prepare first."
  exit 1
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env"

mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[asyncband-build] ERROR: expected one extracted tree, found ${#trees[@]}"
  printf '%s\n' "${trees[@]:-}"
  exit 1
fi
tree="${trees[0]}"
echo "[asyncband-build] Tree: $tree"
cd "$tree"

fail=0
run_one() {
  local label=$1
  shift
  echo "[asyncband-build] ===== $label ====="
  echo "[asyncband-build] Command: $*"
  set +e
  "$@"
  local rc=$?
  set -e
  echo "[asyncband-build] ${label}_EXIT=$rc"
  if [[ "$rc" -ne 0 ]]; then
    fail=1
  fi
}

run_one BUILD cargo x build
run_one TEST cargo x test
run_one LINT cargo x lint

if [[ "$fail" -ne 0 ]]; then
  echo "[asyncband-build] RESULT: FAIL"
  exit 1
fi
echo "[asyncband-build] RESULT: PASS"
exit 0
