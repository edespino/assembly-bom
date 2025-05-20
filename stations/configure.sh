#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/configure.sh
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

cd "parts/$NAME" || {
  echo "Error: Directory 'parts/$NAME' not found"
  exit 1
}

INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"

echo "==> Configuring $NAME..."
echo "    INSTALL_PREFIX=$INSTALL_PREFIX"
echo "    CONFIGURE_FLAGS:"
echo "$CONFIGURE_FLAGS"

# Build command
CMD="./configure --prefix=$INSTALL_PREFIX $CONFIGURE_FLAGS"

echo "    Running: $CMD"
# shellcheck disable=SC2086
eval $CMD 2>&1 | tee "configure-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ configure step complete for $NAME"
