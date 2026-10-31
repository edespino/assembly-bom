#!/usr/bin/env bash
# Build from the extracted tarball, not from git.
# The tarball build.sh runs: mvn clean package -DskipTests=true
# That command skips tests. This step does not claim a test pass.
# The build.sh comment mentions a Docker image. The script does not build one.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "ozhera" ]]; then
  echo "[ozhera-build] ERROR: this step is ozhera-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[ozhera-build] ERROR: expected one extracted tree, found ${#trees[@]}"
  printf '%s\n' "${trees[@]:-}"
  exit 1
fi
tree="${trees[0]}"
if [[ ! -f "$tree/pom.xml" || ! -f "$tree/build.sh" ]]; then
  echo "[ozhera-build] ERROR: extracted tree is missing pom.xml or build.sh: $tree"
  exit 1
fi
if ! grep -q 'mvn clean package -DskipTests=true' "$tree/build.sh"; then
  echo "[ozhera-build] ERROR: build.sh does not contain the documented command"
  exit 1
fi

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH="${HOME}/opt/apache-maven-3.9.16/bin:${JAVA_HOME}/bin:${PATH}"
if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
  echo "[ozhera-build] ERROR: Java 21 is not at $JAVA_HOME. Run prepare first."
  exit 1
fi
if [[ ! -x "${HOME}/opt/apache-maven-3.9.16/bin/mvn" ]]; then
  echo "[ozhera-build] ERROR: Maven 3.9.16 is not installed. Run prepare first."
  exit 1
fi

echo "[ozhera-build] Tree: $tree"
echo "[ozhera-build] JAVA_HOME: $JAVA_HOME"
echo "[ozhera-build] $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
echo "[ozhera-build] $(mvn -version | head -1)"
echo "[ozhera-build] Documented command: mvn clean package -DskipTests=true"
echo "[ozhera-build] Tests are skipped by that command. This is not a test pass."
echo "[ozhera-build] build.sh does not build a Docker image. This run does not claim one."

cd "$tree"
mvn -B -ntp clean package -DskipTests=true
echo "[ozhera-build] RESULT: PASS"
exit 0
