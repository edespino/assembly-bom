#!/usr/bin/env bash
# Inspect the binary tar the vote staged. Extract it outside the source tree
# so compare-to-tag and RAT do not treat distribution jars as source.
# Jars in this tar are the convenience binary, not unexpected source binaries.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-review-binary] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
expect_bin="apache-seata-${RELEASE_VERSION}-incubating-bin.tar.gz"
tar_file="$ARTIFACT_PATH/$expect_bin"
out="$PARTS_DIR/review-output/$NAME/bin"

echo "[seata-review-binary] Archive: $tar_file"
if [[ ! -f "$tar_file" ]]; then
  echo "[seata-review-binary] ERROR: binary tar not found"
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"
tar -xzf "$tar_file" -C "$out"

mapfile -t trees < <(find "$out" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[seata-review-binary] ERROR: expected one extracted binary tree, found ${#trees[@]}"
  printf '%s\n' "${trees[@]:-}"
  exit 1
fi
tree="${trees[0]}"
echo "[seata-review-binary] Tree: $tree"
echo "[seata-review-binary] Top level:"
ls -la "$tree" | sed 's/^/[seata-review-binary]   /'

fail=0
for legal in LICENSE NOTICE DISCLAIMER; do
  if [[ -f "$tree/$legal" ]]; then
    echo "[seata-review-binary] present: $legal"
  else
    echo "[seata-review-binary] ERROR: missing $legal at binary tar root"
    fail=1
  fi
done

echo "[seata-review-binary] Compiled suffixes in the binary distribution are expected. They are not the source-archive binary line."
find "$tree" -type f \( -name '*.jar' -o -name '*.class' -o -name '*.so' -o -name '*.exe' \) | sed 's|^'"$tree"'/||' | sort | head -40 | sed 's/^/[seata-review-binary] jar-or-binary: /'

if [[ "$fail" -ne 0 ]]; then
  echo "[seata-review-binary] RESULT: FAIL"
  exit 1
fi
echo "[seata-review-binary] RESULT: PASS"
exit 0
