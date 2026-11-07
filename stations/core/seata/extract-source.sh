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

if ! listing=$(unzip -Z1 "$zip"); then
  echo "[seata-extract-source] ERROR: cannot list archive members"
  exit 1
fi
prefix=""
while IFS= read -r member; do
  [[ -z "$member" ]] && continue
  member=${member#./}
  member=${member%/}
  [[ -z "$member" ]] && continue
  case "$member" in
    /*|..|../*|*/..|*/../*)
      echo "[seata-extract-source] ERROR: unsafe archive member"
      exit 1
      ;;
  esac
  top=${member%%/*}
  if [[ "$top" == .* ]]; then
    echo "[seata-extract-source] ERROR: archive member is not under one project directory"
    exit 1
  fi
  if [[ -z "$prefix" ]]; then
    prefix=$top
  elif [[ "$top" != "$prefix" ]]; then
    echo "[seata-extract-source] ERROR: archive member ${top} is outside ${prefix}"
    exit 1
  fi
done <<< "$listing"
if [[ -z "$prefix" || "$prefix" == .* ]]; then
  echo "[seata-extract-source] ERROR: archive has no single project directory"
  exit 1
fi
echo "[seata-extract-source] Archive prefix: $prefix"

rm -rf "$COMPONENT_DIR"
mkdir -p "$COMPONENT_DIR"
unzip -q "$zip" -d "$COMPONENT_DIR"

if ! members=$(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -print); then
  echo "[seata-extract-source] ERROR: find failed while listing the extract"
  exit 1
fi
mapfile -t members < <(printf '%s\n' "$members" | sed '/^$/d')
if [[ ${#members[@]} -ne 1 ]]; then
  echo "[seata-extract-source] ERROR: expected one extracted entry, found ${#members[@]}"
  exit 1
fi
tree="${members[0]}"
if [[ -L "$tree" || ! -d "$tree" || "$(basename "$tree")" != "$prefix" ]]; then
  echo "[seata-extract-source] ERROR: extracted entry is not the archive prefix ${prefix}"
  exit 1
fi
echo "[seata-extract-source] Tree: $tree"
echo "[seata-extract-source] RESULT: PASS"
exit 0
