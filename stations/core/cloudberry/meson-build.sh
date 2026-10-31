#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/../../../lib/common.sh"

NAME="${NAME:-cloudberry}"
BUILD_DIR="$PARTS_DIR/${NAME}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk}"
export PATH="${JAVA_HOME}/bin:/usr/bin:${PATH}"

cd "$BUILD_DIR"
# Frontend common library first. The meson port builds src/common twice, and
# ninja may compile the frontend copy before generated backend headers exist.
ninja -C build-meson src/common/libpgcommon_shlib.a
ninja -C build-meson -j"$(nproc)"
