#!/usr/bin/env bash
# Print the files an earlier Seata candidate was asked to fix.
# This step records that they are in the tree. It does not judge LICENSE accuracy.
# A missing named file fails. The vote text is the source of the names.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-review-named-files] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[seata-review-named-files] ERROR: expected one extracted tree, found ${#trees[@]}"
  exit 1
fi
tree="${trees[0]}"

RELEASE_COMMIT="${RELEASE_COMMIT:?Missing RELEASE_COMMIT}"
clone="$PARTS_DIR/review-output/$NAME/git-tag"
if [[ ! -d "$clone/.git" ]]; then
  echo "[seata-review-named-files] ERROR: tag clone missing at $clone"
  exit 1
fi
head=$(git -C "$clone" rev-parse HEAD)
echo "[seata-review-named-files] CLONE_HEAD: $head"
echo "[seata-review-named-files] RELEASE_COMMIT: $RELEASE_COMMIT"
if [[ "$head" != "$RELEASE_COMMIT" ]]; then
  echo "[seata-review-named-files] ERROR: tag $SOURCE_TAG does not point at the hash the vote names"
  exit 1
fi
echo "[seata-review-named-files] Tag points at the vote hash."

show_hits() {
  local label=$1
  local pattern=$2
  echo "[seata-review-named-files] ---- $label ----"
  mapfile -t hits < <(find "$tree" -iname "$pattern" -print | sort)
  if [[ ${#hits[@]} -eq 0 ]]; then
    echo "[seata-review-named-files] ERROR: no file matching $pattern"
    return 1
  fi
  local hit
  for hit in "${hits[@]}"; do
    echo "[seata-review-named-files] FILE: ${hit#$tree/}"
    # License-relevant lines only. Do not dump the file.
    grep -n -E -i 'license|copyright|apache|mit |lgpl|gpl|disclaimer|permission' "$hit" | head -20 | sed 's/^/[seata-review-named-files]   /' || true
  done
  return 0
}

fail=0
show_hits "PathMap.js" "PathMap.js" || fail=1
show_hits "LatencyUtils" "*LatencyUtils*" || fail=1
show_hits "tiny-svg" "*tiny-svg*" || fail=1
show_hits "normalize.css" "*normalize.css*" || fail=1
show_hits "ANTLR MySQL grammar" "*MySQL*.g4" || fail=1
show_hits "NOTICE-server" "NOTICE-server" || fail=1

echo "[seata-review-named-files] ---- saga LICENSE ----"
mapfile -t saga_license < <(find "$tree/saga" -name 'LICENSE*' -print | sort)
if [[ ${#saga_license[@]} -eq 0 ]]; then
  echo "[seata-review-named-files] ERROR: no LICENSE file under saga/"
  fail=1
else
  printf '[seata-review-named-files] FILE: %s\n' "${saga_license[@]#$tree/}"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "[seata-review-named-files] RESULT: FAIL"
  exit 1
fi
echo "[seata-review-named-files] RESULT: PASS"
echo "[seata-review-named-files] Presence is not a license-accuracy pass."
exit 0
