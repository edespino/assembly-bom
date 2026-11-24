#!/usr/bin/env bash
# Toolchain the BifroMQ review steps need and the image may not ship.
# The vote builds with JDK 17 and mvnw. mvnw downloads the Maven distribution
# named in .mvn/wrapper/maven-wrapper.properties. Do not change the image
# default Java. Later steps set JAVA_HOME.
# license-eye 0.9.0 is the project's configured header checker.
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

EYE_HOME="${HOME}/opt/skywalking-license-eye-0.9.0-bin"
EYE_BIN="$EYE_HOME/bin/linux/license-eye"
EYE_SHA512="eb601818ff2cf8d3d4bda7551d5e6e113f799045411b6c52c4a9120cbc259b966498fcbf4778ded252364bed6a1ca1c5d59b1055e25589f74163131913f242b4"
if [[ -x "$EYE_BIN" ]]; then
  echo "[bifromq-prepare] license-eye already present: $EYE_BIN"
else
  if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "[bifromq-prepare] ERROR: pinned license-eye binary check covers linux; arch $(uname -m) not handled"
    exit 1
  fi
  echo "[bifromq-prepare] Installing license-eye 0.9.0 under $EYE_HOME"
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  base="https://downloads.apache.org/skywalking/eyes/0.9.0/skywalking-license-eye-0.9.0-bin.tgz"
  curl -fsSL -o "$work/eye.tgz" "$base"
  curl -fsSL -o "$work/eye.tgz.sha512" "${base}.sha512"
  published=$(awk '{print $1}' "$work/eye.tgz.sha512")
  actual=$(sha512sum "$work/eye.tgz" | awk '{print $1}')
  if [[ "$actual" != "$published" || "$actual" != "$EYE_SHA512" ]]; then
    echo "[bifromq-prepare] ERROR: license-eye SHA-512 mismatch"
    exit 1
  fi
  echo "[bifromq-prepare] SHA-512 matched the published file and the pinned digest"
  mkdir -p "${HOME}/opt"
  tar -xzf "$work/eye.tgz" -C "${HOME}/opt"
  [[ -x "$EYE_BIN" ]] || { echo "[bifromq-prepare] ERROR: install did not create $EYE_BIN"; exit 1; }
  echo "[bifromq-prepare] Installed after launch: skywalking-license-eye 0.9.0"
fi
echo "[bifromq-prepare] Image default Java is unchanged."
echo "[bifromq-prepare] RESULT: PASS"
exit 0
