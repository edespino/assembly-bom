#!/usr/bin/env bash
# Install Rust when the image formula does not ship it. Do not change the
# image default Java. Later steps source $HOME/.cargo/env themselves.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "asyncband" ]]; then
  echo "[asyncband-prepare] ERROR: this step is asyncband-only (NAME=${NAME})" >&2
  exit 1
fi

echo "[asyncband-prepare] Component: $NAME"

if command -v cargo >/dev/null 2>&1; then
  echo "[asyncband-prepare] cargo already on PATH: $(command -v cargo)"
else
  echo "[asyncband-prepare] Installing rustup. The image formula does not ship Rust."
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
  echo "[asyncband-prepare] Installed after launch: rustup (stable)"
fi

# shellcheck disable=SC1091
source "$HOME/.cargo/env"
echo "[asyncband-prepare] cargo: $(cargo --version)"
echo "[asyncband-prepare] rustc: $(rustc --version)"

if ! rustup toolchain list | grep -q '^nightly'; then
  echo "[asyncband-prepare] Installing nightly for the project's lint command."
  rustup toolchain install --component rustfmt,clippy nightly
  echo "[asyncband-prepare] Installed after launch: rustup nightly (rustfmt, clippy)"
fi

echo "[asyncband-prepare] RESULT: PASS"
exit 0
