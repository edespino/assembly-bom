#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "flink" ]]; then
  echo "[flink-build] ERROR: this step is flink-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
pom=$(find "$PARTS_DIR/$NAME" -maxdepth 3 -type f -name pom.xml | head -1)
if [[ -z "$pom" ]]; then
  echo "[flink-build] ERROR: pom.xml not found" >&2
  exit 1
fi
cd "$(dirname "$pom")"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
export MAVEN_OPTS="-Xmx4g"
mvn -B -DskipTests -T 1C package
echo "[flink-build] RESULT: PASS"
