#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/generic/configure.sh
# Purpose  : Default configure step for components with standard autotools
# Inputs   :
#   - NAME              : component name
#   - CONFIGURE_FLAGS   : flags from bom.yaml
#   - INSTALL_PREFIX    : defaults to /usr/local/$NAME
# --------------------------------------------------------------------

set -e

[ -f config/env.sh ] && . config/env.sh

# Validate input
if [ -z "$NAME" ]; then
  echo "Error: NAME is not set"
  exit 1
fi

cd "$PARTS_DIR/$NAME" || {
  echo "Error: Directory '$PARTS_DIR/$NAME' not found"
  exit 1
}

# Find the actual source directory (handle extracted tarballs)
if [ ! -f "./configure" ]; then
  # Look for configure in subdirectories (common for tarballs)
  SUBDIR=$(find . -maxdepth 2 -name "configure" -type f | head -1 | xargs dirname)
  if [ -n "$SUBDIR" ] && [ -f "$SUBDIR/configure" ]; then
    echo "Found configure in: $SUBDIR"
    cd "$SUBDIR" || exit 1
  else
    echo "Error: No configure script found in $PARTS_DIR/$NAME"
    exit 1
  fi
fi

INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"

echo "==> Configuring $NAME..."
echo "    INSTALL_PREFIX=$INSTALL_PREFIX"
echo "    CONFIGURE_FLAGS:"
echo "$CONFIGURE_FLAGS"

# Build command
CMD="./configure --prefix=$INSTALL_PREFIX $CONFIGURE_FLAGS"

echo "    Running: $CMD"
# shellcheck disable=SC2086
eval $CMD 2>&1 | tee "$PARTS_DIR/$NAME/configure-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ configure step complete for $NAME"
