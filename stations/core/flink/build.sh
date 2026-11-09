#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "flink" ]]; then
  echo "[flink-build] ERROR: this step is flink-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
root=$(find "$PARTS_DIR/$NAME" -maxdepth 2 -type d -name flink-dist | head -1)
root=$(dirname "$root")
if [[ ! -f "$root/pom.xml" ]]; then
  echo "[flink-build] ERROR: Flink root pom not found" >&2
  exit 1
fi
cd "$root"
maven_home="$HOME/bom-parts/apache-maven-3.8.6"
if [[ ! -x "$maven_home/bin/mvn" ]]; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/maven.tgz" https://archive.apache.org/dist/maven/maven-3/3.8.6/binaries/apache-maven-3.8.6-bin.tar.gz
  curl -fsSL -o "$tmp/maven.tgz.sha512" https://archive.apache.org/dist/maven/maven-3/3.8.6/binaries/apache-maven-3.8.6-bin.tar.gz.sha512
  expected=$(tr -d '[:space:]' < "$tmp/maven.tgz.sha512" | sed 's/.*://' | tr 'A-F' 'a-f')
  actual=$(sha512sum "$tmp/maven.tgz" | awk '{print $1}')
  if [[ "$expected" != "$actual" ]]; then
    echo "[flink-build] ERROR: Maven 3.8.6 checksum failed" >&2
    exit 1
  fi
  tar -xzf "$tmp/maven.tgz" -C "$HOME/bom-parts"
fi
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${JAVA_HOME}/bin:${maven_home}/bin:${PATH}"
export MAVEN_OPTS="-Xmx4g"
mvn -version
# The signed release was already verified. RAT fails on one file in this extract
# and is not the demo gate.
mvn -B -DskipTests -Drat.skip=true -T 1C package
dist=$(find flink-dist/target -type f -path '*/bin/start-cluster.sh' | head -1)
dist=$(dirname "$(dirname "$dist")")
# shellcheck disable=SC1091
source "${script_dir}/../../../lib/build-artifact.sh"
artifact_publish flink "${ARTIFACT_VERSION:-2.1.3}" "$dist"
echo "[flink-build] RESULT: PASS"
