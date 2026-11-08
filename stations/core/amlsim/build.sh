#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "amlsim" ]]; then
  echo "[amlsim-build] ERROR: this step is amlsim-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PARTS_DIR/$NAME"
# mason:mason:20 is not in Maven Central. The GMU host sends only the leaf
# certificate, so curl cannot verify it on this image. The jar is vendored.
mason_sha='9989c3ecaf288c49b2db01405fc588fb994a39a98656a2434be107f79de83a3e'
mkdir -p jars
cp "$script_dir/vendor/mason.20.jar" jars/mason.20.jar
echo "${mason_sha}  jars/mason.20.jar" | sha256sum -c -
mvn -q install:install-file \
  -Dfile=jars/mason.20.jar \
  -DgroupId=mason \
  -DartifactId=mason \
  -Dversion=20 \
  -Dpackaging=jar \
  -DgeneratePom=true
bash scripts/build_AMLSim.sh
echo "[amlsim-build] RESULT: PASS"
