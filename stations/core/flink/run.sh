#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "flink" ]]; then
  echo "[flink-run] ERROR: this step is flink-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
home=$(find "$PARTS_DIR/$NAME" -type f -path '*/bin/start-cluster.sh' | head -1)
if [[ -z "$home" ]]; then
  echo "[flink-run] ERROR: start-cluster.sh not found after the source build" >&2
  exit 1
fi
home=$(dirname "$(dirname "$home")")
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
if ! ss -lnt | grep -q ':8081 '; then
  "$home/bin/start-cluster.sh"
fi
echo "[flink-run] RESULT: PASS"
