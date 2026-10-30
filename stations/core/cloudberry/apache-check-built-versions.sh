#!/usr/bin/env bash
# Check versions of binaries built from an Apache Cloudberry release.
# postgres --version is the PostgreSQL base. The release is --gp-version.
# backup and pxf embed the VERSION file, which is the release number without
# "incubating". go-libs has no versioned executable.
set -euo pipefail
IFS=$'\n\t'

if [[ "${NAME:-}" != "cloudberry" ]]; then
  echo "[check-built-versions] ERROR: this step is cloudberry-only (NAME=${NAME:-unset})" >&2
  exit 1
fi

COMPONENT_NAME="$NAME"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"
GOBIN="${GOBIN:-${GOPATH:-$HOME/go}/bin}"
RELEASE_VERSION="${RELEASE_VERSION:-2.2.0}"
EXPECTED_GP_VERSION="${EXPECTED_GP_VERSION:-${RELEASE_VERSION}-incubating}"
EXPECTED_GP_BUILD="${EXPECTED_GP_BUILD:-}"

fail=0
warn=0

note() { echo "[check-built-versions] $*"; }

require_contains() {
  local label="$1" actual="$2" expected="$3"
  note "$label: $actual"
  if [[ "$actual" != *"$expected"* ]]; then
    note "FAIL: $label does not contain $expected"
    fail=1
  fi
}

warn_missing() {
  local label="$1" actual="$2" token="$3"
  if [[ "$actual" != *"$token"* ]]; then
    note "WARN: $label does not contain $token"
    warn=1
  fi
}

note "Component: $COMPONENT_NAME"
note "Release number: $RELEASE_VERSION"

postgres_bin="${INSTALL_PREFIX}/bin/postgres"
if [[ -x "$postgres_bin" ]]; then
  export LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  pg_version="$("$postgres_bin" --version)"
  gp_version="$("$postgres_bin" --gp-version)"
  note "postgres --version: $pg_version"
  require_contains "postgres --gp-version" "$gp_version" "$EXPECTED_GP_VERSION"
  if [[ -n "$EXPECTED_GP_BUILD" ]]; then
    require_contains "postgres --gp-version build" "$gp_version" "$EXPECTED_GP_BUILD"
  fi
else
  note "FAIL: postgres executable not found at $postgres_bin"
  fail=1
fi

for bin in gpbackup gprestore gpbackup_helper; do
  path="$GOBIN/$bin"
  if [[ ! -x "$path" ]]; then
    note "FAIL: $bin not found at $path"
    fail=1
    continue
  fi
  actual="$("$path" --version 2>&1)"
  require_contains "$bin --version" "$actual" "$RELEASE_VERSION"
  warn_missing "$bin --version" "$actual" "incubating"
done

pxf_root=""
for candidate in "$COMPONENT_DIR"/apache-cloudberry-pxf-*; do
  if [[ -d "$candidate" ]]; then
    pxf_root="$candidate"
  fi
done
if [[ -z "$pxf_root" ]]; then
  note "FAIL: pxf source tree not found under $COMPONENT_DIR"
  fail=1
else
  pxf_version="$(tr -d '[:space:]' < "$pxf_root/version")"
  note "pxf version file: $pxf_version"
  require_contains "pxf version file" "$pxf_version" "$RELEASE_VERSION"
  warn_missing "pxf version file" "$pxf_version" "incubating"
  jar="$(find "$pxf_root/server" -path '*/build/libs/pxf-service-*.jar' -type f -print -quit)"
  if [[ -z "$jar" ]]; then
    note "FAIL: pxf-service jar not found"
    fail=1
  else
    note "pxf-service jar: $(basename "$jar")"
    require_contains "pxf-service jar" "$(basename "$jar")" "$RELEASE_VERSION"
    warn_missing "pxf-service jar" "$(basename "$jar")" "incubating"
  fi
fi

golibs_root=""
for candidate in "$COMPONENT_DIR"/apache-cloudberry-go-libs-*; do
  if [[ -d "$candidate" ]]; then
    golibs_root="$candidate"
  fi
done
if [[ -z "$golibs_root" ]]; then
  note "FAIL: go-libs source tree not found under $COMPONENT_DIR"
  fail=1
else
  note "go-libs has no versioned executable. go.mod has no release version."
  note "go-libs module: $(awk '/^module / { print $2; exit }' "$golibs_root/go.mod")"
fi

if [[ "$fail" -ne 0 ]]; then
  note "RESULT: FAIL"
  exit 1
fi
if [[ "$warn" -ne 0 ]]; then
  note "RESULT: PASS with warnings"
  exit 0
fi
note "RESULT: PASS"
exit 0
