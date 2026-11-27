#!/usr/bin/env bash
# The project's configured header checker is skywalking-eyes (.licenserc.yaml).
# The signed source archive does not contain that file (export-ignored). The
# config used here is the tag's copy, from the clone apache-compare-to-tag
# made. The archive contents are the files checked.
# paths-ignore files were not checked. The dependency section is a different
# command and is not run here. This step is separate from the RAT scan.
# license-eye is built from the 0.9.0 source tarball in prepare: the 0.9.0
# bin tgz has an aarch64 binary under bin/linux.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "bifromq" ]]; then
  echo "[bifromq-license-eye] ERROR: this step is bifromq-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
archive="$PARTS_DIR/${NAME}-artifacts/apache-bifromq-${RELEASE_VERSION}-incubating-src.tar.gz"
out="$PARTS_DIR/review-output/$NAME"
fresh="$out/eye-extract"
EYE_BIN="${HOME}/opt/license-eye-0.9.0/license-eye"
TAG_CLONE="$out/git-tag"

if [[ ! -x "$EYE_BIN" ]]; then
  echo "[bifromq-license-eye] ERROR: license-eye missing. Run prepare first."
  exit 1
fi
echo "[bifromq-license-eye] $("$EYE_BIN" --version 2>&1 | head -1)"
if [[ ! -f "$archive" ]]; then
  echo "[bifromq-license-eye] ERROR: source archive not found: $archive"
  exit 1
fi
if ! listing=$(tar -tzf "$archive"); then
  echo "[bifromq-license-eye] ERROR: cannot list archive members"
  exit 1
fi
prefix=""
while IFS= read -r member; do
  member=${member#./}; member=${member%/}
  [[ -z "$member" ]] && continue
  case "$member" in
    /*|..|../*|*/..|*/../*) echo "[bifromq-license-eye] ERROR: unsafe archive member"; exit 1 ;;
  esac
  top=${member%%/*}
  if [[ -z "$prefix" ]]; then prefix=$top
  elif [[ "$top" != "$prefix" ]]; then
    echo "[bifromq-license-eye] ERROR: archive member ${top} is outside ${prefix}"; exit 1
  fi
done <<< "$listing"
if [[ -z "$prefix" || "$prefix" == .* ]]; then
  echo "[bifromq-license-eye] ERROR: archive has no single project directory"
  exit 1
fi

rm -rf "$fresh"
mkdir -p "$fresh"
tar -xzf "$archive" -C "$fresh"
tree="$fresh/$prefix"
if [[ -L "$tree" || ! -d "$tree" ]]; then
  echo "[bifromq-license-eye] ERROR: extracted tree is not a directory: $tree"
  exit 1
fi
if [[ -f "$tree/.licenserc.yaml" ]]; then
  echo "[bifromq-license-eye] NOTE: archive has .licenserc.yaml; using it"
  cfg="$tree/.licenserc.yaml"
else
  cfg="$TAG_CLONE/.licenserc.yaml"
  if [[ ! -f "$cfg" ]]; then
    echo "[bifromq-license-eye] ERROR: no .licenserc.yaml in the archive or the tag clone ($TAG_CLONE)"
    exit 1
  fi
  if [[ "$(git -C "$TAG_CLONE" rev-parse HEAD)" != "${RELEASE_COMMIT:?Missing RELEASE_COMMIT}" ]]; then
    echo "[bifromq-license-eye] ERROR: tag clone is not RELEASE_COMMIT"
    exit 1
  fi
  echo "[bifromq-license-eye] NOTE: the signed archive has no .licenserc.yaml. Config is the tag's copy at $RELEASE_COMMIT."
fi
echo "[bifromq-license-eye] Config: $cfg"
echo "[bifromq-license-eye] Command: license-eye header check -c $cfg"
log="$out/license-eye-header.log"
set +e
(cd "$tree" && "$EYE_BIN" header check -c "$cfg" -v info) 2>&1 | tee "$log"
pipe_status=("${PIPESTATUS[@]}")
set -e
eye_rc=${pipe_status[0]}
tee_rc=${pipe_status[1]}
echo "[bifromq-license-eye] LICENSE_EYE_EXIT: $eye_rc"
if [[ "$tee_rc" -ne 0 ]]; then
  echo "[bifromq-license-eye] ERROR: could not write the log"
  exit 1
fi
set +e
grep -E 'Totally checked|valid|invalid|ignored|fixed' "$log" | tail -5 | sed 's/^/[bifromq-license-eye] /'
set -e
if [[ "$eye_rc" -ne 0 ]]; then
  echo "[bifromq-license-eye] RESULT: FAIL"
  exit 1
fi
echo "[bifromq-license-eye] RESULT: PASS"
exit 0
