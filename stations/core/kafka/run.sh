#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "kafka" ]]; then
  echo "[kafka-run] ERROR: this step is kafka-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
src=$(find "$PARTS_DIR/$NAME" -maxdepth 2 -type f -name gradlew | head -1)
src=$(dirname "$src")
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${JAVA_HOME}/bin:${src}/bin:${PATH}"
if [[ ! -x "$src/bin/kafka-server-start.sh" ]]; then
  echo "[kafka-run] ERROR: broker scripts missing after jar build" >&2
  ls "$src/bin" >&2 || true
  exit 1
fi
mkdir -p "$HOME/kafka-logs"
if ! ss -lnt | grep -q ':9092 '; then
  cluster=$("$src/bin/kafka-storage.sh" random-uuid)
  "$src/bin/kafka-storage.sh" format -t "$cluster" -c "$src/config/kraft/server.properties" --ignore-formatted
  "$src/bin/kafka-server-start.sh" -daemon "$src/config/kraft/server.properties"
fi
ok=0
for _ in $(seq 1 30); do
  if ss -lnt | grep -q ':9092 '; then
    ok=1
    break
  fi
  sleep 2
done
if [[ "$ok" != 1 ]]; then
  echo "[kafka-run] ERROR: broker did not listen on 9092" >&2
  exit 1
fi
echo "[kafka-run] RESULT: PASS"
