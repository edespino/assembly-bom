#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# List of required tools
REQUIRED_TOOLS=(yq git)

for TOOL in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$TOOL" &> /dev/null; then
    echo "[bootstrap] Missing: $TOOL"

    case "$TOOL" in
      yq)
        echo "[bootstrap] Installing yq..."
        sudo curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
        ;;

      git)
        echo "[bootstrap] Installing git..."
        sudo dnf install -y git
        ;;

      *)
        echo "[bootstrap] ERROR: No installer defined for: $TOOL"
        exit 1
        ;;
    esac
  fi
done
