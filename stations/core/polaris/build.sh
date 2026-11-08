#!/usr/bin/env bash
set -euo pipefail
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
wrapper_props="gradle/wrapper/gradle-wrapper.properties"
if [[ -f "$wrapper_props" ]]; then
  sed -i 's/networkTimeout=10000/networkTimeout=180000/' "$wrapper_props"
fi
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
# The documented distribution task. Skip unit tests; the chapter proof is the
# running server and a query, not the upstream suite. Do not build a container.
./gradlew :polaris-server:build -x test -Dquarkus.container-image.build=false --no-daemon
test -n "$(find runtime/server/build/distributions -name 'polaris-server-*.zip' | head -1)"
echo "[polaris-build] RESULT: PASS"
