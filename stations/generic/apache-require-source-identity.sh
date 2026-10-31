#!/usr/bin/env bash
# First review step. The vote request must already have set SOURCE_REPO and
# SOURCE_TAG. Look them up on the remote before discover, extract, or build.
# A missing or unresolved identity stops the run. Later steps do not start.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=apache-source-identity.sh
source "$HERE/apache-source-identity.sh"

echo "[source-identity] Component: $NAME"
apache_require_source_identity
