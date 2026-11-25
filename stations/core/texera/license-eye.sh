#!/usr/bin/env bash
# The project's header checker is license-eye, configured by .licenserc.yaml
# in the signed source archive. This is not the generic RAT scan.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "texera" ]]; then
  echo "[texera-license-eye] ERROR: this step is texera-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
EYE_BIN="${HOME}/opt/license-eye-0.9.0/license-eye"
out="$PARTS_DIR/review-output/$NAME"
mkdir -p "$out"

if [[ ! -x "$EYE_BIN" ]]; then
  echo "[texera-license-eye] ERROR: license-eye missing. Run prepare first."
  exit 1
fi
mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[texera-license-eye] ERROR: expected one extracted tree, found ${#trees[@]}"
  exit 1
fi
tree="${trees[0]}"
cfg="$tree/.licenserc.yaml"
if [[ ! -f "$cfg" ]]; then
  echo "[texera-license-eye] ERROR: archive extract has no .licenserc.yaml"
  exit 1
fi
echo "[texera-license-eye] Config: $cfg"
log="$out/license-eye-header.log"
set +e
(cd "$tree" && "$EYE_BIN" header check -c "$cfg" -v info) 2>&1 | tee "$log"
eye_rc=${PIPESTATUS[0]}
set -e
echo "[texera-license-eye] LICENSE_EYE_EXIT: $eye_rc"
grep -E 'Totally checked|valid|invalid|ignored' "$log" | tail -5 | sed 's/^/[texera-license-eye] /' || true
if [[ "$eye_rc" -ne 0 ]]; then
  echo "[texera-license-eye] RESULT: FAIL"
  exit 1
fi
echo "[texera-license-eye] RESULT: PASS"
exit 0
