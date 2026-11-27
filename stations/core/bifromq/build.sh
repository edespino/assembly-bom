#!/usr/bin/env bash
# From-tarball build. The vote names these commands, from the extracted
# directory, with JDK 17:
#   ./mvnw install -pl testsuites -am -DskipTests
#   ./mvnw clean verify -Pbuild-release
# The first skips tests. The second is the release-profile verify. This step
# reports which commands ran and does not claim more than they do.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "bifromq" ]]; then
  echo "[bifromq-build] ERROR: this step is bifromq-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[bifromq-build] ERROR: expected one extracted tree, found ${#trees[@]}"
  printf '%s\n' "${trees[@]:-}"
  exit 1
fi
tree="${trees[0]}"
if [[ ! -f "$tree/pom.xml" || ! -x "$tree/mvnw" ]]; then
  echo "[bifromq-build] ERROR: tree is missing pom.xml or executable mvnw: $tree"
  exit 1
fi

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
java_line=$(java -version 2>&1 | head -1)
echo "[bifromq-build] Tree: $tree"
echo "[bifromq-build] JAVA_HOME: $JAVA_HOME"
echo "[bifromq-build] $java_line"
case "$java_line" in
  *\"17.*) ;;
  *) echo "[bifromq-build] ERROR: the vote builds with JDK 17, got $java_line"; exit 1 ;;
esac

cd "$tree"
echo "[bifromq-build] Command 1: ./mvnw install -pl testsuites -am -DskipTests (tests skipped)"
./mvnw -B -ntp install -pl testsuites -am -DskipTests
echo "[bifromq-build] COMMAND1_EXIT: 0"
echo "[bifromq-build] Command 2: ./mvnw clean verify -Pbuild-release"
./mvnw -B -ntp clean verify -Pbuild-release
echo "[bifromq-build] COMMAND2_EXIT: 0"
echo "[bifromq-build] RESULT: PASS"
exit 0
