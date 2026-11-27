#!/usr/bin/env bash
# Extract only the source archive into the component directory.
# compare-to-tag requires one tree. The binary tar is reviewed later,
# outside that directory.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "bifromq" ]]; then
  echo "[bifromq-extract-source] ERROR: this step is bifromq-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
COMPONENT_DIR="$PARTS_DIR/$NAME"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
expect_src="apache-bifromq-${RELEASE_VERSION}-incubating-src.tar.gz"
archive="$ARTIFACT_PATH/$expect_src"

echo "[bifromq-extract-source] Component: $NAME"
echo "[bifromq-extract-source] Archive: $archive"

if [[ ! -f "$archive" ]]; then
  echo "[bifromq-extract-source] ERROR: source archive not found"
  exit 1
fi

if ! listing=$(tar -tzf "$archive"); then
  echo "[bifromq-extract-source] ERROR: cannot list archive members"
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
      echo "[bifromq-extract-source] ERROR: unsafe archive member"
      exit 1
      ;;
  esac
  top=${member%%/*}
  if [[ "$top" == .* ]]; then
    echo "[bifromq-extract-source] ERROR: archive member is not under one project directory"
    exit 1
  fi
  if [[ -z "$prefix" ]]; then
    prefix=$top
  elif [[ "$top" != "$prefix" ]]; then
    echo "[bifromq-extract-source] ERROR: archive member ${top} is outside ${prefix}"
    exit 1
  fi
done <<< "$listing"
if [[ -z "$prefix" || "$prefix" == .* ]]; then
  echo "[bifromq-extract-source] ERROR: archive has no single project directory"
  exit 1
fi
echo "[bifromq-extract-source] Archive prefix: $prefix"

rm -rf "$COMPONENT_DIR"
mkdir -p "$COMPONENT_DIR"
tar -xzf "$archive" -C "$COMPONENT_DIR"

if ! members=$(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -print); then
  echo "[bifromq-extract-source] ERROR: find failed while listing the extract"
  exit 1
fi
mapfile -t members < <(printf '%s\n' "$members" | sed '/^$/d')
if [[ ${#members[@]} -ne 1 ]]; then
  echo "[bifromq-extract-source] ERROR: expected one extracted entry, found ${#members[@]}"
  exit 1
fi
tree="${members[0]}"
if [[ -L "$tree" || ! -d "$tree" || "$(basename "$tree")" != "$prefix" ]]; then
  echo "[bifromq-extract-source] ERROR: extracted entry is not the archive prefix ${prefix}"
  exit 1
fi
echo "[bifromq-extract-source] Tree: $tree"
echo "[bifromq-extract-source] RESULT: PASS"
exit 0
