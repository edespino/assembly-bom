#!/usr/bin/env bash
# The staged "binary" is a Docker Compose bundle, not a jar tar.
# Record that LICENSE, NOTICE, and DISCLAIMER are at its root.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "texera" ]]; then
  echo "[texera-review-binary] ERROR: this step is texera-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
archive="$ARTIFACT_PATH/apache-texera-${RELEASE_VERSION}-incubating-docker-compose.tar.gz"
review_dir="$PARTS_DIR/${NAME}-compose"

echo "[texera-review-binary] Archive: $archive"
rm -rf "$review_dir"
mkdir -p "$review_dir"
tar -xzf "$archive" -C "$review_dir"
mapfile -t tops < <(find "$review_dir" -mindepth 1 -maxdepth 1 -type d -print)
if [[ ${#tops[@]} -ne 1 ]]; then
  echo "[texera-review-binary] ERROR: expected one top directory, found ${#tops[@]}"
  exit 1
fi
root="${tops[0]}"
fail=0
for legal in LICENSE NOTICE DISCLAIMER; do
  if [[ -f "$root/$legal" ]]; then
    echo "[texera-review-binary] present: $legal ($(wc -c < "$root/$legal") bytes)"
  else
    echo "[texera-review-binary] ERROR: missing $legal"
    fail=1
  fi
done
if [[ ! -f "$root/docker-compose.yml" ]]; then
  echo "[texera-review-binary] ERROR: missing docker-compose.yml"
  fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "[texera-review-binary] RESULT: FAIL"
  exit 1
fi
echo "[texera-review-binary] RESULT: PASS"
exit 0
