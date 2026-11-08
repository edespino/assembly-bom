#!/usr/bin/env bash
# AMLSim prepare. The shipped conf.json already points at paramFiles/1K.
# Java 11 is for the Maven build. The image default is Java 8.
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "amlsim" ]]; then
  echo "[amlsim-prepare] ERROR: this step is amlsim-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
tree="$PARTS_DIR/$NAME"
cd "$tree"
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
python3 -m pip install --user 'numpy' 'networkx==1.11' 'python-dateutil' 'Faker'
echo "[amlsim-prepare] JAVA_HOME=$JAVA_HOME"
echo "[amlsim-prepare] RESULT: PASS"
