#!/usr/bin/env bash
# From-tarball build. The vote names this command:
#   ./mvnw clean package -DskipTests=true
# build/pom.xml sets java.version to 1.8. Use JDK 8.
# That command skips tests. This step does not claim a test pass.
# Maven publication of loom and jackson3 modules needs JDK 21. This step
# does not publish and does not claim that publication.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-build] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[seata-build] ERROR: expected one extracted tree, found ${#trees[@]}"
  printf '%s\n' "${trees[@]:-}"
  exit 1
fi
tree="${trees[0]}"

if [[ ! -f "$tree/pom.xml" || ! -x "$tree/mvnw" ]]; then
  echo "[seata-build] ERROR: extracted tree is missing pom.xml or executable mvnw: $tree"
  exit 1
fi
if ! grep -q '<java.version>1.8</java.version>' "$tree/build/pom.xml"; then
  echo "[seata-build] ERROR: build/pom.xml does not set java.version to 1.8"
  exit 1
fi

if [[ -d /usr/lib/jvm/java-1.8.0-openjdk ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
elif [[ -d /usr/lib/jvm/java-1.8.0 ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-1.8.0
else
  echo "[seata-build] ERROR: JDK 8 home not found"
  exit 1
fi
export PATH="${JAVA_HOME}/bin:${PATH}"

java_line=$(java -version 2>&1 | head -1)
echo "[seata-build] Tree: $tree"
echo "[seata-build] JAVA_HOME: $JAVA_HOME"
echo "[seata-build] $java_line"
case "$java_line" in
  *1.8.*|*\"8.*) ;;
  *)
    echo "[seata-build] ERROR: refusing to build on $java_line. The vote compiles with JDK 8."
    exit 1
    ;;
esac

echo "[seata-build] Documented command: ./mvnw clean package -DskipTests=true"
echo "[seata-build] Tests are skipped by that command. This is not a test pass."
echo "[seata-build] This run does not publish to the staging repository."

cd "$tree"
./mvnw -B -ntp clean package -DskipTests=true
echo "[seata-build] RESULT: PASS"
exit 0
