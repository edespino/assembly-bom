#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "polaris" ]]; then
  echo "[polaris-build] ERROR: this step is polaris-only" >&2
  exit 1
fi
if [[ ! -x /usr/lib/jvm/java-21-openjdk/bin/java ]]; then
  sudo dnf install -y java-21-openjdk-devel
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
gradlew=$(find "$PARTS_DIR/$NAME" -maxdepth 3 -type f -name gradlew | head -1)
if [[ -z "$gradlew" ]]; then
  echo "[polaris-build] ERROR: gradlew not found under $PARTS_DIR/$NAME" >&2
  exit 1
fi
cd "$(dirname "$gradlew")"
chmod +x ./gradlew
# shellcheck disable=SC1091
source "${script_dir}/../../../lib/gradle-wrapper.sh"
gradle_use_reachable_distribution gradle/wrapper/gradle-wrapper.properties
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
# The documented distribution task. Skip unit tests; the chapter proof is the
# running server and a query, not the upstream suite. Do not build a container.
./gradlew :polaris-server:build -x test -Dquarkus.container-image.build=false --no-daemon
test -n "$(find runtime/server/build -name quarkus-run.jar | head -1)"
# shellcheck disable=SC1091
source "${script_dir}/../../../lib/build-artifact.sh"
artifact_publish polaris "${ARTIFACT_VERSION:-1.8.0}" "$(find runtime/server/build -type d -name quarkus-app | head -1)"
echo "[polaris-build] RESULT: PASS"
