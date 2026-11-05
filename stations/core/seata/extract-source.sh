#!/usr/bin/env bash
# Extract only the source zip into the component directory.
# compare-to-tag requires one tree. The binary tar is reviewed later,
# outside that directory.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-extract-source] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
COMPONENT_DIR="$PARTS_DIR/$NAME"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
expect_src="apache-seata-${RELEASE_VERSION}-incubating-src.zip"
zip="$ARTIFACT_PATH/$expect_src"

echo "[seata-extract-source] Component: $NAME"
echo "[seata-extract-source] Archive: $zip"

if [[ ! -f "$zip" ]]; then
  echo "[seata-extract-source] ERROR: source zip not found"
  exit 1
fi

rm -rf "$COMPONENT_DIR"
mkdir -p "$COMPONENT_DIR"
unzip -q "$zip" -d "$COMPONENT_DIR"

mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[seata-extract-source] ERROR: expected one extracted tree, found ${#trees[@]}"
  printf '%s\n' "${trees[@]:-}"
  exit 1
fi
echo "[seata-extract-source] Tree: ${trees[0]}"
echo "[seata-extract-source] RESULT: PASS"
exit 0
