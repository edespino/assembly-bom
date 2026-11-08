#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "amlsim" ]]; then
  echo "[amlsim-generate] ERROR: this step is amlsim-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
tree="$PARTS_DIR/$NAME"
cd "$tree"
python3 scripts/transaction_graph_generator.py conf.json
echo "[amlsim-generate] RESULT: PASS"
