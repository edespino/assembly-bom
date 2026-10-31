#!/usr/bin/env bash
# Meson configure for the cloudberry component. Not used by the autoconf BOM.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/../../../lib/common.sh"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/common.sh"
# shellcheck disable=SC1091
[ -f config/env.sh ] && . config/env.sh

NAME="${NAME:-cloudberry}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/cloudberry}"
BUILD_DIR="$PARTS_DIR/${NAME}"
MESON_SHA="82e8993ffd9056825d938bd6d5b83024123a180c"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk}"
export PATH="${JAVA_HOME}/bin:/usr/bin:${PATH}"

if [[ ! -d "$BUILD_DIR/.git" ]]; then
  echo "[meson-setup] ERROR: $BUILD_DIR is not a git checkout"
  exit 1
fi

cd "$BUILD_DIR"
git checkout --detach "$MESON_SHA"
echo "[meson-setup] HEAD=$(git rev-parse HEAD)"
test "$(git rev-parse HEAD)" = "$MESON_SHA"

setup_xerces
export LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib:${LD_LIBRARY_PATH:-}"

if [[ -f gpMgmt/bin/Makefile ]]; then
  make -C gpMgmt/bin download-python-deps
fi

meson setup build-meson . \
  --prefix="${INSTALL_PREFIX}" \
  --buildtype=release \
  -Dexternal_fts=false \
  -Dorca=enabled \
  -Dorafce=enabled \
  -Dic_proxy=enabled \
  -Dgpfdist=enabled \
  -Dgpcloud=enabled \
  -Ddiskquota=enabled \
  -Dpax=enabled \
  -Dgp_stats_collector=enabled \
  -Dtap_tests=enabled \
  -Dgssapi=enabled \
  -Dldap=enabled \
  -Dlibxml=enabled \
  -Dlz4=enabled \
  -Dzstd=enabled \
  -Dpam=enabled \
  -Dplperl=enabled \
  -Dplpython=enabled \
  -Dssl=openssl \
  -Duuid=e2fs \
  -Dpgport=5432 \
  -Dpythonsrc_ext=true \
  -Dextra_include_dirs=/opt/xerces-c/include \
  -Dextra_lib_dirs="${INSTALL_PREFIX}/lib"
