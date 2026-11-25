#!/usr/bin/env bash
# Extract only the source tar. compare-to-tag requires one tree.
# The compose bundle is extracted by deploy-compose, outside this directory.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "texera" ]]; then
  echo "[texera-extract-source] ERROR: this step is texera-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
COMPONENT_DIR="$PARTS_DIR/$NAME"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
expect_src="apache-texera-${RELEASE_VERSION}-incubating-src.tar.gz"
archive="$ARTIFACT_PATH/$expect_src"

echo "[texera-extract-source] Archive: $archive"
if [[ ! -f "$archive" ]]; then
  echo "[texera-extract-source] ERROR: source archive not found"
  exit 1
fi

if ! listing=$(tar -tzf "$archive"); then
  echo "[texera-extract-source] ERROR: cannot list archive members"
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
      echo "[texera-extract-source] ERROR: unsafe archive member"
      exit 1
      ;;
  esac
  top=${member%%/*}
  if [[ "$top" == .* ]]; then
    echo "[texera-extract-source] ERROR: archive member is not under one project directory"
    exit 1
  fi
  if [[ -z "$prefix" ]]; then
    prefix=$top
  elif [[ "$top" != "$prefix" ]]; then
    echo "[texera-extract-source] ERROR: archive member ${top} is outside ${prefix}"
    exit 1
  fi
done <<< "$listing"
if [[ -z "$prefix" ]]; then
  echo "[texera-extract-source] ERROR: archive has no single project directory"
  exit 1
fi
echo "[texera-extract-source] Archive prefix: $prefix"

rm -rf "$COMPONENT_DIR"
mkdir -p "$COMPONENT_DIR"
tar -xzf "$archive" -C "$COMPONENT_DIR"

mapfile -t members < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -print)
if [[ ${#members[@]} -ne 1 ]]; then
  echo "[texera-extract-source] ERROR: expected one extracted entry, found ${#members[@]}"
  exit 1
fi
tree="${members[0]}"
if [[ -L "$tree" || ! -d "$tree" || "$(basename "$tree")" != "$prefix" ]]; then
  echo "[texera-extract-source] ERROR: extracted entry is not the archive prefix ${prefix}"
  exit 1
fi
echo "[texera-extract-source] Tree: $tree"
echo "[texera-extract-source] RESULT: PASS"
exit 0
