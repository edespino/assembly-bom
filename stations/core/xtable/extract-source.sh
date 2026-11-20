#!/usr/bin/env bash
# Extract the signed .src.tgz. Generic discover files that name as a binary,
# and generic extract would then treat the source archive as a binary extract.
# Require one archive prefix. Reject a symlink member before any content test.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "xtable" ]]; then
  echo "[xtable-extract-source] ERROR: this step is xtable-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
COMPONENT_DIR="$PARTS_DIR/$NAME"

mapfile -t artifacts < <(find "$ARTIFACT_PATH" -maxdepth 1 -type f -name '*.src.tgz' -printf '%f\n' | sort)
if [[ ${#artifacts[@]} -ne 1 ]]; then
  echo "[xtable-extract-source] ERROR: expected one .src.tgz, found ${#artifacts[@]}"
  exit 1
fi
artifact="${artifacts[0]}"
tarball="$ARTIFACT_PATH/$artifact"
echo "[xtable-extract-source] Archive: $artifact"

if tar -tvzf "$tarball" | awk 'substr($0,1,1)=="l" { found=1 } END { exit found?0:1 }'; then
  echo "[xtable-extract-source] ERROR: archive contains a symlink member"
  tar -tvzf "$tarball" | awk 'substr($0,1,1)=="l" { print }'
  exit 1
fi

mapfile -t prefixes < <(tar -tzf "$tarball" | sed 's|^\./||' | awk -F/ 'NF && $1 != "" { print $1 }' | sort -u)
if [[ ${#prefixes[@]} -ne 1 ]]; then
  echo "[xtable-extract-source] ERROR: expected one top-level prefix, found ${#prefixes[@]}"
  printf '%s\n' "${prefixes[@]:-}"
  exit 1
fi
prefix="${prefixes[0]}"
echo "[xtable-extract-source] PREFIX: $prefix"

rm -rf "$COMPONENT_DIR"
mkdir -p "$COMPONENT_DIR"
tar -xzf "$tarball" -C "$COMPONENT_DIR"

mapfile -t entries < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -print | sort)
if [[ ${#entries[@]} -ne 1 ]]; then
  echo "[xtable-extract-source] ERROR: expected one top-level entry, found ${#entries[@]}"
  printf '%s\n' "${entries[@]:-}"
  exit 1
fi
tree="${entries[0]}"
if [[ -L "$tree" ]]; then
  echo "[xtable-extract-source] ERROR: top-level entry is a symlink"
  exit 1
fi
if [[ ! -d "$tree" ]]; then
  echo "[xtable-extract-source] ERROR: top-level entry is not a directory"
  exit 1
fi
if [[ ! -r "$tree" || ! -x "$tree" ]]; then
  echo "[xtable-extract-source] ERROR: owner cannot read and search $tree"
  exit 1
fi
echo "[xtable-extract-source] TREE: $tree"
echo "[xtable-extract-source] RESULT: PASS"
exit 0
