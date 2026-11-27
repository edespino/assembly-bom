#!/usr/bin/env bash
# From-tarball build. README says use Java 11 and ./mvnw clean package.
# That command runs the unit tests. Do not pass -DskipTests.
# ./mvnw clean verify is the integration command and is not this step.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "xtable" ]]; then
  echo "[xtable-build] ERROR: this step is xtable-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
logdir="$PARTS_DIR/review-output/$NAME"
mkdir -p "$logdir"

mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[xtable-build] ERROR: expected one extracted tree, found ${#trees[@]}"
  exit 1
fi
tree="${trees[0]}"
if [[ ! -f "$tree/pom.xml" || ! -f "$tree/mvnw" ]]; then
  echo "[xtable-build] ERROR: extracted tree has no pom.xml and mvnw"
  exit 1
fi

if [[ -x /usr/lib/jvm/java-11-openjdk/bin/java ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
elif [[ -x /usr/lib/jvm/java-11/bin/java ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-11
else
  echo "[xtable-build] ERROR: Java 11 home not found. README requires Java 11."
  exit 1
fi
export PATH="$JAVA_HOME/bin:$PATH"
echo "[xtable-build] JAVA_HOME=$JAVA_HOME"
java -version
echo "[xtable-build] COMMAND: bash ./mvnw -B -ntp clean package -Dmaven.build.cache.enabled=false"
echo "[xtable-build] TREE: $tree"

cd "$tree"
set +e
bash ./mvnw -B -ntp clean package -Dmaven.build.cache.enabled=false > "$logdir/build.log" 2>&1
mvn_rc=$?
set -e
echo "[xtable-build] MAVEN_EXIT: $mvn_rc"
if grep -q 'BUILD SUCCESS' "$logdir/build.log"; then
  echo "[xtable-build] BUILD_LINE: BUILD SUCCESS"
else
  echo "[xtable-build] BUILD_LINE: not success"
fi
grep -E 'Tests run:|BUILD ' "$logdir/build.log" | tail -30 | sed 's/^/[xtable-build] /'
if [[ "$mvn_rc" -ne 0 ]]; then
  echo "[xtable-build] RESULT: FAIL"
  tail -50 "$logdir/build.log"
  exit 1
fi
echo "[xtable-build] RESULT: PASS"
exit 0
