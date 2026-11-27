#!/usr/bin/env bash
# RAT 0.18 needs Java 17 or newer. The image default is Java 8. This step
# sets JAVA_HOME for the scan only. It does not change the image default.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "asyncband" ]]; then
  echo "[asyncband-rat] ERROR: this step is asyncband-only (NAME=${NAME})" >&2
  exit 1
fi

java_home=""
for d in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-21-openjdk-* /usr/lib/jvm/java-17-openjdk /usr/lib/jvm/java-17-openjdk-*; do
  if [[ -x "$d/bin/java" ]]; then
    java_home=$d
    break
  fi
done
if [[ -z "$java_home" ]]; then
  echo "[asyncband-rat] ERROR: Java 17 or 21 home not found. RAT will not start on the image default."
  exit 1
fi

export JAVA_HOME="$java_home"
export PATH="/usr/local/bin:${JAVA_HOME}/bin:${PATH}"
echo "[asyncband-rat] JAVA_HOME=${JAVA_HOME}"
echo "[asyncband-rat] java: $(java -version 2>&1 | head -1)"
echo "[asyncband-rat] mvn: $(mvn -version | head -1)"

root=$(cd "$(dirname "$0")/../../.." && pwd)
exec bash "$root/stations/generic/apache-rat.sh"
