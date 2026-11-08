#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "amlsim" ]]; then
  echo "[amlsim-build] ERROR: this step is amlsim-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
cd "$PARTS_DIR/$NAME"
bash scripts/build_AMLSim.sh
echo "[amlsim-build] RESULT: PASS"
