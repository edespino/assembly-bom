#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/cloudberry/common.sh
# Purpose  : Common functions for Apache Cloudberry build scripts
# --------------------------------------------------------------------

# Function to setup Xerces-C environment and libraries
# Sets global variables: xerces_include, xerces_libs
# Exports: LD_LIBRARY_PATH
setup_xerces() {
  if [[ -d /opt/xerces-c ]]; then
    log "Using Xerces-C from /opt/xerces-c"
    sudo chmod a+w /usr/local

    mkdir -p "${INSTALL_PREFIX}/lib"
    cp -P /opt/xerces-c/lib/libxerces-c.so \
          /opt/xerces-c/lib/libxerces-c-3.*.so \
          "${INSTALL_PREFIX}/lib" 2>/dev/null || {
      log "ERROR: Failed to copy Xerces-C libraries"
      exit 1
    }

    export LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib:${LD_LIBRARY_PATH:-}"
    xerces_include="--with-includes=/opt/xerces-c/include"
    xerces_libs="--with-libraries=${INSTALL_PREFIX}/lib"
  else
    log "Using system-installed Xerces-C"
    export LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib:${LD_LIBRARY_PATH:-}"
    xerces_include=""
    xerces_libs=""
  fi
}