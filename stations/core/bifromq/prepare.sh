#!/usr/bin/env bash
# Toolchain the BifroMQ review steps need and the image may not ship.
# The vote builds with JDK 17 and mvnw. mvnw downloads the Maven distribution
# named in .mvn/wrapper/maven-wrapper.properties. Do not change the image
# default Java. Later steps set JAVA_HOME.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "bifromq" ]]; then
  echo "[bifromq-prepare] ERROR: this step is bifromq-only (NAME=${NAME})" >&2
  exit 1
fi
echo "[bifromq-prepare] Component: $NAME"

install_pkg() {
  local pkg=$1 cmd=$2
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[bifromq-prepare] $cmd already present: $(command -v "$cmd")"
    return 0
  fi
  echo "[bifromq-prepare] Installing $pkg. The image did not have $cmd."
  sudo dnf install -y "$pkg"
  command -v "$cmd" >/dev/null 2>&1 || { echo "[bifromq-prepare] ERROR: $pkg did not provide $cmd"; exit 1; }
  echo "[bifromq-prepare] Installed after launch: $pkg"
}
install_pkg git git
install_pkg gnupg2 gpg
install_pkg tar tar

JAVA17_HOME=/usr/lib/jvm/java-17-openjdk
if [[ -x "$JAVA17_HOME/bin/java" && -x "$JAVA17_HOME/bin/javac" ]]; then
  echo "[bifromq-prepare] Java 17 already present: $($JAVA17_HOME/bin/java -version 2>&1 | head -1)"
else
  echo "[bifromq-prepare] Installing Java 17. The image does not have a complete $JAVA17_HOME."
  sudo dnf install -y java-17-openjdk-devel
  if [[ ! -x "$JAVA17_HOME/bin/javac" ]]; then
    echo "[bifromq-prepare] ERROR: Java 17 install did not create $JAVA17_HOME"
    exit 1
  fi
  echo "[bifromq-prepare] Installed after launch: java-17-openjdk-devel"
  echo "[bifromq-prepare] $($JAVA17_HOME/bin/java -version 2>&1 | head -1)"
fi

echo "[bifromq-prepare] Image default Java is unchanged."
echo "[bifromq-prepare] RESULT: PASS"
exit 0
