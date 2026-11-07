#!/usr/bin/env bash
# From-tarball compile. The validation guide's primary command is
# ./mvnw clean package. That command runs tests. This host has no Docker,
# and the pom declares testcontainers. This step runs the guide's skip
# path and does not claim a test pass.
# pom java.source.version and java.target.version are 11.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "amoro" ]]; then
  echo "[amoro-build] ERROR: this step is amoro-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[amoro-build] ERROR: expected one extracted tree, found ${#trees[@]}"
  exit 1
fi
tree="${trees[0]}"
if [[ ! -f "$tree/pom.xml" || ! -f "$tree/mvnw" ]]; then
  echo "[amoro-build] ERROR: extracted tree is missing pom.xml or mvnw"
  exit 1
fi
if ! grep -q '<java.source.version>11</java.source.version>' "$tree/pom.xml"; then
  echo "[amoro-build] ERROR: pom does not set java.source.version to 11"
  exit 1
fi

java11=""
for candidate in /usr/lib/jvm/java-11-openjdk /usr/lib/jvm/java-11 /usr/lib/jvm/java-11-openjdk-11; do
  if [[ -x "$candidate/bin/java" ]]; then
    java11=$candidate
    break
  fi
done
if [[ -z "$java11" ]]; then
  echo "[amoro-build] ERROR: Java 11 home not found"
  exit 1
fi
export JAVA_HOME="$java11"
export PATH="${JAVA_HOME}/bin:${PATH}"
chmod +x "$tree/mvnw"

echo "[amoro-build] Tree: $tree"
echo "[amoro-build] JAVA_HOME: $JAVA_HOME"
java_line=$(java -version 2>&1 | head -1)
echo "[amoro-build] $java_line"
case "$java_line" in
  *11.*) ;;
  *)
    echo "[amoro-build] ERROR: refusing to build on $java_line. The pom source and target are 11."
    exit 1
    ;;
esac

if command -v docker >/dev/null 2>&1; then
  echo "[amoro-build] docker is present: $(command -v docker)"
else
  echo "[amoro-build] docker is not on this host."
fi
echo "[amoro-build] The validation guide's test command is ./mvnw clean package."
echo "[amoro-build] The pom declares testcontainers. This run is ./mvnw clean package -DskipTests."
echo "[amoro-build] Tests are skipped. This is not a test pass."

cd "$tree"
./mvnw -B -ntp clean package -DskipTests
echo "[amoro-build] RESULT: PASS"
exit 0
