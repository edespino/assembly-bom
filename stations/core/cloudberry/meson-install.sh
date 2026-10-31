#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/../../../lib/common.sh"

NAME="${NAME:-cloudberry}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/cloudberry}"
BUILD_DIR="$PARTS_DIR/${NAME}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk}"
export PATH="${JAVA_HOME}/bin:/usr/bin:${PATH}"

cd "$BUILD_DIR"
ninja -C build-meson install
echo "[meson-install] $($INSTALL_PREFIX/bin/postgres --version)"
echo "[meson-install] $($INSTALL_PREFIX/bin/postgres --gp-version)"
