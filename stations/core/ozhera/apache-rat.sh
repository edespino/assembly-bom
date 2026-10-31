#!/usr/bin/env bash
# The project pom declares apache-rat-plugin. Parent apache 31 pins 0.15.
# Use that plugin. Set Java 21 and Maven 3.9 so the image defaults do not win.
# Then run the generic station, which selects top-level extracted directories.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "ozhera" ]]; then
  echo "[ozhera-rat] ERROR: this step is ozhera-only (NAME=${NAME})" >&2
  exit 1
fi

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH="${HOME}/opt/apache-maven-3.9.16/bin:${JAVA_HOME}/bin:${PATH}"
if [[ ! -x "$JAVA_HOME/bin/java" || ! -x "${HOME}/opt/apache-maven-3.9.16/bin/mvn" ]]; then
  echo "[ozhera-rat] ERROR: prepare did not install Java 21 and Maven 3.9.16"
  exit 1
fi

echo "[ozhera-rat] JAVA_HOME: $JAVA_HOME"
echo "[ozhera-rat] $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
echo "[ozhera-rat] $(mvn -version | head -1)"
echo "[ozhera-rat] Using the project pom plugin via stations/generic/apache-rat.sh"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec bash "$script_dir/../../generic/apache-rat.sh"
