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

EYE_BIN="${HOME}/opt/license-eye-0.9.0/license-eye"
EYE_SHA512="b5c65aa94f7aafd43509a86379ca2d82fbcd7856f7a5fdfb2962985ecd99965d7b1e2e7f576df22c981c89c60c352eef7d9ca64966d26437fa41c1cd575dd316"
if [[ -x "$EYE_BIN" ]]; then
  echo "[bifromq-prepare] license-eye already present: $EYE_BIN"
else
  # The 0.9.0 bin tgz ships an aarch64 binary under bin/linux. Build from the
  # source tarball. Pin its digest. Go is at /opt/go/bin on the image.
  export PATH=/opt/go/bin:/usr/local/bin:$PATH
  command -v go >/dev/null 2>&1 || { echo "[bifromq-prepare] ERROR: go not found"; exit 1; }
  echo "[bifromq-prepare] Building license-eye 0.9.0 from source with $(go version)"
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  base="https://downloads.apache.org/skywalking/eyes/0.9.0/skywalking-license-eye-0.9.0-src.tgz"
  curl -fsSL -o "$work/src.tgz" "$base"
  curl -fsSL -o "$work/src.tgz.sha512" "${base}.sha512"
  published=$(awk '{print $1}' "$work/src.tgz.sha512")
  actual=$(sha512sum "$work/src.tgz" | awk '{print $1}')
  if [[ "$actual" != "$published" || "$actual" != "$EYE_SHA512" ]]; then
    echo "[bifromq-prepare] ERROR: license-eye source SHA-512 mismatch"
    exit 1
  fi
  echo "[bifromq-prepare] SHA-512 matched the published file and the pinned digest"
  mkdir -p "$work/src" "${HOME}/opt/license-eye-0.9.0"
  tar -xzf "$work/src.tgz" -C "$work/src"
  (cd "$work/src" && CGO_ENABLED=0 go build -o "$EYE_BIN" ./cmd/license-eye)
  [[ -x "$EYE_BIN" ]] || { echo "[bifromq-prepare] ERROR: build did not create $EYE_BIN"; exit 1; }
  echo "[bifromq-prepare] Built after launch: license-eye 0.9.0 ($(file -b "$EYE_BIN" | cut -c1-40))"
fi
echo "[bifromq-prepare] Image default Java is unchanged."
echo "[bifromq-prepare] RESULT: PASS"
exit 0
