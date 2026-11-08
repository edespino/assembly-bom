#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "kafka" ]]; then
  echo "[kafka-build] ERROR: this step is kafka-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
gradlew=$(find "$PARTS_DIR/$NAME" -maxdepth 3 -type f -name gradlew | head -1)
if [[ -z "$gradlew" ]]; then
  echo "[kafka-build] ERROR: gradlew not found" >&2
  exit 1
fi
cd "$(dirname "$gradlew")"
chmod +x ./gradlew
if [[ -f gradle/wrapper/gradle-wrapper.properties ]]; then
  sed -i 's/networkTimeout=10000/networkTimeout=180000/' gradle/wrapper/gradle-wrapper.properties
fi
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
./gradlew jar -x test --no-daemon
echo "[kafka-build] RESULT: PASS"
