#!/usr/bin/env bash
# Tools the Amoro review needs and the image may not have on PATH.
# The project compiles with Java 11. Do not change the image default Java.
# The tree has no .licenserc.yaml. Do not install license-eye.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "amoro" ]]; then
  echo "[amoro-prepare] ERROR: this step is amoro-only (NAME=${NAME})" >&2
  exit 1
fi

echo "[amoro-prepare] Component: $NAME"

install_pkg() {
  local pkg=$1
  local cmd=$2
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[amoro-prepare] $cmd already present: $(command -v "$cmd")"
    return 0
  fi
  echo "[amoro-prepare] Installing $pkg. The image did not have $cmd."
  sudo dnf install -y "$pkg"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[amoro-prepare] ERROR: $pkg did not provide $cmd"
    exit 1
  fi
  echo "[amoro-prepare] Installed after launch: $pkg"
}

install_pkg git git
install_pkg gnupg2 gpg
install_pkg unzip unzip
install_pkg file file
echo "[amoro-prepare] git: $(git --version)"
echo "[amoro-prepare] gpg: $(gpg --version | head -1)"

java11=""
for candidate in /usr/lib/jvm/java-11-openjdk /usr/lib/jvm/java-11 /usr/lib/jvm/java-11-openjdk-11; do
  if [[ -x "$candidate/bin/java" ]]; then
    java11=$candidate
    break
  fi
done
if [[ -z "$java11" ]]; then
  echo "[amoro-prepare] ERROR: Java 11 is not on the image. The project source and target are 11."
  exit 1
fi
echo "[amoro-prepare] Java 11 present: $java11"
echo "[amoro-prepare] $($java11/bin/java -version 2>&1 | head -1)"
echo "[amoro-prepare] Image default Java is unchanged. The build and RAT steps set JAVA_HOME."
echo "[amoro-prepare] RESULT: PASS"
exit 0
