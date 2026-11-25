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
EYE_BIN="${HOME}/opt/license-eye-0.9.0/license-eye"
EYE_SHA512="b5c65aa94f7aafd43509a86379ca2d82fbcd7856f7a5fdfb2962985ecd99965d7b1e2e7f576df22c981c89c60c352eef7d9ca64966d26437fa41c1cd575dd316"
if [[ -x "$EYE_BIN" ]]; then
  echo "[texera-prepare] license-eye already present: $EYE_BIN"
else
  export PATH=/opt/go/bin:/usr/local/bin:$PATH
  command -v go >/dev/null 2>&1 || { echo "[texera-prepare] ERROR: go not found"; exit 1; }
  echo "[texera-prepare] Building license-eye 0.9.0 from source with $(go version)"
  work=$(mktemp -d)
  base="https://downloads.apache.org/skywalking/eyes/0.9.0/skywalking-license-eye-0.9.0-src.tgz"
  curl -fsSL -o "$work/src.tgz" "$base"
  curl -fsSL -o "$work/src.tgz.sha512" "${base}.sha512"
  published=$(awk '{print $1}' "$work/src.tgz.sha512")
  actual=$(sha512sum "$work/src.tgz" | awk '{print $1}')
  if [[ "$actual" != "$published" || "$actual" != "$EYE_SHA512" ]]; then
    echo "[texera-prepare] ERROR: license-eye source SHA-512 mismatch"
    exit 1
  fi
  echo "[texera-prepare] SHA-512 matched the published file and the pinned digest"
  mkdir -p "$work/src" "${HOME}/opt/license-eye-0.9.0"
  tar -xzf "$work/src.tgz" -C "$work/src"
  (cd "$work/src" && CGO_ENABLED=0 go build -o "$EYE_BIN" ./cmd/license-eye)
  rm -rf "$work"
  [[ -x "$EYE_BIN" ]] || { echo "[texera-prepare] ERROR: build did not create $EYE_BIN"; exit 1; }
  echo "[texera-prepare] Built after launch: license-eye 0.9.0"
fi
echo "[texera-prepare] RESULT: PASS"
exit 0
