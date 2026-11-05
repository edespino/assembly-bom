#!/usr/bin/env bash
# Seata header check. The tree has pom.xml, but it does not declare
# apache-rat-plugin. mvn apache-rat:check resolves the inherited Apache
# parent plugin 0.12, which does not read .licenserc.yaml. That is not
# the project's header gate. The project runs skywalking-eyes against
# .licenserc.yaml. This step runs that check and counts compiled suffixes
# in the source tree before the build.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-rat] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[seata-rat] ERROR: expected one extracted tree, found ${#trees[@]}"
  exit 1
fi
tree="${trees[0]}"
eye="${HOME}/opt/license-eye"
if [[ ! -x "$eye" ]]; then
  echo "[seata-rat] ERROR: license-eye is not installed. Run prepare first."
  exit 1
fi

echo "[seata-rat] Tree: $tree"
echo "[seata-rat] license-eye: $eye"
echo "[seata-rat] Config: .licenserc.yaml"
echo "[seata-rat] This is the project header check. It is not mvn apache-rat:check."

fail=0
if [[ ! -f "$tree/.licenserc.yaml" ]]; then
  echo "[seata-rat] ERROR: .licenserc.yaml is not in the extracted tree"
  exit 1
fi
set +e
(cd "$tree" && "$eye" header check -c .licenserc.yaml)
eye_rc=$?
set -e
echo "[seata-rat] LICENSE_EYE_EXIT: $eye_rc"
if [[ "$eye_rc" -ne 0 ]]; then
  fail=1
fi

echo "[seata-rat] Compiled suffixes in the source tree, before the build:"
mapfile -t compiled < <(find "$tree" -type f \( -name '*.class' -o -name '*.jar' -o -name '*.so' -o -name '*.o' -o -name '*.a' -o -name '*.exe' -o -name '*.dll' \) | sort)
echo "[seata-rat] COMPILED_COUNT: ${#compiled[@]}"
if [[ ${#compiled[@]} -gt 0 ]]; then
  printf '%s\n' "${compiled[@]#$tree/}" | head -20 | sed 's/^/[seata-rat] COMPILED: /'
  fail=1
else
  echo "[seata-rat] No compiled binaries in the source tree."
fi

if [[ "$fail" -ne 0 ]]; then
  echo "[seata-rat] RESULT: FAIL"
  exit 1
fi
echo "[seata-rat] RESULT: PASS"
exit 0
