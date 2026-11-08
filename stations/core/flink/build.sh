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
mvn -B -DskipTests -T 1C package
echo "[flink-build] RESULT: PASS"
