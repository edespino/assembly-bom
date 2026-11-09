#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
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
# shellcheck disable=SC1091
source "${script_dir}/../../../lib/gradle-wrapper.sh"
gradle_use_reachable_distribution gradle/wrapper/gradle-wrapper.properties
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
./gradlew jar -x test --no-daemon
echo "[kafka-build] RESULT: PASS"
