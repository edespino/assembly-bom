#!/usr/bin/env bash
# Inspect each convenience binary the vote staged. Extract outside the
# source tree so compare-to-tag and RAT do not treat distribution jars
# as source. Jars in these tars are the binary distribution, not the
# Maven staging repository.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "amoro" ]]; then
  echo "[amoro-review-binary] ERROR: this step is amoro-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
fail=0

review_one() {
  local label=$1
  local archive_name=$2
  local tar_file="$ARTIFACT_PATH/$archive_name"
  local out="$PARTS_DIR/review-output/$NAME/bin-$label"
  echo "[amoro-review-binary] Archive: $archive_name"
  if [[ ! -f "$tar_file" ]]; then
    echo "[amoro-review-binary] ERROR: binary tar not found: $archive_name"
    fail=1
    return
  fi
  rm -rf "$out"
  mkdir -p "$out"
  tar -xzf "$tar_file" -C "$out"
  mapfile -t trees < <(find "$out" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
  if [[ ${#trees[@]} -ne 1 ]]; then
    echo "[amoro-review-binary] ERROR: expected one tree in $archive_name, found ${#trees[@]}"
    fail=1
    return
  fi
  local tree="${trees[0]}"
  echo "[amoro-review-binary] Tree: $tree"
  case "$(basename "$tree")" in
    *incubating*) echo "[amoro-review-binary] incubating in directory name: $(basename "$tree")" ;;
    *)
      echo "[amoro-review-binary] ERROR: directory name lacks incubating: $(basename "$tree")"
      fail=1
      ;;
  esac
  local legal
  for legal in LICENSE NOTICE DISCLAIMER; do
    if [[ -f "$tree/$legal" ]]; then
      echo "[amoro-review-binary] present: $label $legal"
    else
      echo "[amoro-review-binary] ERROR: missing $legal at $label binary root"
      fail=1
    fi
  done
  local jar_count
  jar_count=$(find "$tree" -type f -name '*.jar' | wc -l | tr -d ' ')
  echo "[amoro-review-binary] JAR_COUNT $label: $jar_count"
  echo "[amoro-review-binary] Compiled jars in this tar are the convenience binary, not unexpected source files."
}

review_one hadoop2 "apache-amoro-${RELEASE_VERSION}-incubating-bin-hadoop2.tar.gz"
review_one hadoop3 "apache-amoro-${RELEASE_VERSION}-incubating-bin-hadoop3.tar.gz"

if [[ "$fail" -ne 0 ]]; then
  echo "[amoro-review-binary] RESULT: FAIL"
  exit 1
fi
echo "[amoro-review-binary] RESULT: PASS"
exit 0
