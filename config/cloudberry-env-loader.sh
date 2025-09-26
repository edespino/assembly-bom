#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : config/cloudberry-env-loader.sh
# Purpose  : Load Cloudberry environment with fallback logic
# Usage    : source_cloudberry_env /path/to/cloudberry/installation
# --------------------------------------------------------------------

source_cloudberry_env() {
    local CLOUDBERRY_PREFIX="${1:-/usr/local/cloudberry}"
    local CLOUDBERRY_ENV_SH="$CLOUDBERRY_PREFIX/cloudberry-env.sh"
    local GREENPLUM_PATH_SH="$CLOUDBERRY_PREFIX/greenplum_path.sh"

    # Try cloudberry-env.sh first
    if [[ -f "$CLOUDBERRY_ENV_SH" ]]; then
        echo "[cloudberry-env] Loading $CLOUDBERRY_ENV_SH"
        # shellcheck disable=SC1090
        source "$CLOUDBERRY_ENV_SH"
        return 0
    fi

    # Fallback to greenplum_path.sh
    if [[ -f "$GREENPLUM_PATH_SH" ]]; then
        echo "[cloudberry-env] Loading $GREENPLUM_PATH_SH (fallback)"
        # shellcheck disable=SC1090
        source "$GREENPLUM_PATH_SH"
        return 0
    fi

    # Neither found
    echo "[cloudberry-env] ERROR: Neither cloudberry-env.sh nor greenplum_path.sh found in $CLOUDBERRY_PREFIX"
    return 1
}