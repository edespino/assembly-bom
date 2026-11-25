#!/usr/bin/env bash
# Docker is already on the rocky9 Cloudberry image. Do not install a second copy.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "texera" ]]; then
  echo "[texera-prepare] ERROR: this step is texera-only (NAME=${NAME})" >&2
  exit 1
fi

echo "[texera-prepare] Component: $NAME"
for cmd in git gpg tar sha512sum docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[texera-prepare] ERROR: $cmd is not on this image"
    exit 1
  fi
  echo "[texera-prepare] $cmd: $(command -v "$cmd")"
done
docker --version
docker compose version
echo "[texera-prepare] RESULT: PASS"
exit 0
