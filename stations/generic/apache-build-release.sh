#!/usr/bin/env bash
# Build the Apache Cloudberry release from extracted source tarballs.
# Does not clone git. The core tree is apache-cloudberry-<version>-incubating,
# one level under $PARTS_DIR/$NAME. backup, go-libs, and pxf are siblings.
set -euo pipefail
IFS=$'\n\t'

NAME="${NAME:?Missing NAME}"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"
export INSTALL_PREFIX
export GOPATH="${GOPATH:-$HOME/go}"
export GOBIN="${GOBIN:-$GOPATH/bin}"
mkdir -p "$GOBIN"

if [[ -d /usr/lib/jvm/java-11-openjdk ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
fi
export PATH="/opt/go/bin:${JAVA_HOME:+$JAVA_HOME/bin:}${GOBIN}:${PATH}"

note() { echo "[apache-build-release] $*"; }

if [[ ! -d "$COMPONENT_DIR" ]]; then
  note "ERROR: $COMPONENT_DIR does not exist. Run apache-extract-discovered first."
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  note "ERROR: go is not on PATH. The rocky9 image installs it at /opt/go/bin."
  exit 1
fi

if [[ "$(uname -s)" == "Linux" ]] && ! ldconfig -p 2>/dev/null | grep -q 'liburing\.so'; then
  note "ERROR: liburing is required for PAX on Linux."
  note "Rocky 9: sudo dnf install -y --enablerepo=crb liburing-devel"
  exit 1
fi

find_one() {
  local pattern="$1"
  local matches=()
  shopt -s nullglob
  matches=("$COMPONENT_DIR"/$pattern)
  shopt -u nullglob
  if [[ ${#matches[@]} -ne 1 || ! -d "${matches[0]}" ]]; then
    note "ERROR: expected one directory matching $pattern under $COMPONENT_DIR"
    exit 1
  fi
  printf '%s\n' "${matches[0]}"
}

CORE_DIR="$(find_one 'apache-cloudberry-[0-9]*')"
BACKUP_DIR="$(find_one 'apache-cloudberry-backup-*')"
GOLIBS_DIR="$(find_one 'apache-cloudberry-go-libs-*')"
PXF_DIR="$(find_one 'apache-cloudberry-pxf-*')"

note "core: $CORE_DIR"
note "backup: $BACKUP_DIR"
note "go-libs: $GOLIBS_DIR"
note "pxf: $PXF_DIR"

flags="${CONFIGURE_FLAGS:-}"
flags="${flags#null}"
flags="$(printf '%s' "$flags" | tr '\n' ' ')"

if [[ -d /opt/xerces-c ]]; then
  note "Using Xerces-C from /opt/xerces-c"
  sudo chmod a+w /usr/local
  mkdir -p "${INSTALL_PREFIX}/lib"
  cp -P /opt/xerces-c/lib/libxerces-c.so /opt/xerces-c/lib/libxerces-c-3.*.so "${INSTALL_PREFIX}/lib"
  export LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  flags="$flags --with-includes=/opt/xerces-c/include --with-libraries=${INSTALL_PREFIX}/lib"
fi

note "Configuring core with prefix $INSTALL_PREFIX"
(
  cd "$CORE_DIR"
  # shellcheck disable=SC2086
  ./configure --prefix="$INSTALL_PREFIX" $flags
  make -j"$(nproc)"
  if [[ -d contrib ]]; then
    make -j"$(nproc)" -C contrib
  fi
  sudo chmod a+w "$INSTALL_PREFIX" || true
  make -j"$(nproc)" install
  if [[ -d contrib ]]; then
    make -j"$(nproc)" -C contrib install
  fi
)

note "Building go-libs (depend and unit; default make also lints)"
(
  cd "$GOLIBS_DIR"
  make depend
  make unit
)

note "Building backup from the tarball (make depend && make build)"
(
  cd "$BACKUP_DIR"
  make depend
  make build
)

export GPHOME="$INSTALL_PREFIX"
if [[ -f "$GPHOME/cloudberry-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$GPHOME/cloudberry-env.sh"
fi
export PATH="/opt/go/bin:${JAVA_HOME:+$JAVA_HOME/bin:}${GOBIN}:${PATH}"

note "Building pxf against GPHOME=$GPHOME"
(
  cd "$PXF_DIR"
  make -j"$(nproc)"
)

note "Build complete"
