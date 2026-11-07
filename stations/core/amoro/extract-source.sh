#!/usr/bin/env bash
# Extract only the source tar into the component directory.
# compare-to-tag requires one tree. The binary tars are reviewed later,
# outside that directory.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "amoro" ]]; then
  echo "[amoro-extract-source] ERROR: this step is amoro-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
COMPONENT_DIR="$PARTS_DIR/$NAME"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
expect_src="apache-amoro-${RELEASE_VERSION}-incubating-src.tar.gz"
archive="$ARTIFACT_PATH/$expect_src"

echo "[amoro-extract-source] Archive: $archive"
if [[ ! -f "$archive" ]]; then
  echo "[amoro-extract-source] ERROR: source tar not found"
  exit 1
fi

rm -rf "$COMPONENT_DIR"
mkdir -p "$COMPONENT_DIR"
tar -xzf "$archive" -C "$COMPONENT_DIR"

mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[amoro-extract-source] ERROR: expected one extracted tree, found ${#trees[@]}"
  printf '%s\n' "${trees[@]:-}"
  exit 1
fi
echo "[amoro-extract-source] Tree: ${trees[0]}"
echo "[amoro-extract-source] RESULT: PASS"
exit 0
