#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "amlsim" ]]; then
  echo "[amlsim-run] ERROR: this step is amlsim-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
cd "$PARTS_DIR/$NAME"
bash scripts/run_AMLSim.sh conf.json
echo "[amlsim-run] outputs:"
ls -l outputs
echo "[amlsim-run] RESULT: PASS"
