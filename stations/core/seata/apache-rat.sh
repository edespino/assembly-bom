#!/usr/bin/env bash
# Seata RAT. The project pom may declare the plugin. Set Java 17 and Maven 3.9
# so the image default Java 8 and Maven 3.6.3 do not launch the plugin.
# Then run the generic station, which selects the one extracted source tree.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-rat] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${HOME}/opt/apache-maven-3.9.16/bin:${JAVA_HOME}/bin:${PATH}"
if [[ ! -x "$JAVA_HOME/bin/java" || ! -x "${HOME}/opt/apache-maven-3.9.16/bin/mvn" ]]; then
  echo "[seata-rat] ERROR: prepare did not install Java 17 and Maven 3.9.16"
  exit 1
fi

echo "[seata-rat] JAVA_HOME: $JAVA_HOME"
echo "[seata-rat] $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
echo "[seata-rat] $(mvn -version | head -1)"
echo "[seata-rat] RAT 0.18 launches on Java 17. The compile stays on JDK 8."

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec bash "$script_dir/../../generic/apache-rat.sh"
