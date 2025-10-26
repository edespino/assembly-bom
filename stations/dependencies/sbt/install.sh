#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../generic/common.sh"

log_header "Installing sbt"

# Detect the platform
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS_ID="${ID}"
    OS_ID_LIKE="${ID_LIKE:-}"
else
    log_error "Cannot detect OS - /etc/os-release not found"
    exit 1
fi

log_info "Detected OS: ${OS_ID} (like: ${OS_ID_LIKE})"

# Install based on platform
if [[ "$OS_ID" =~ (rhel|centos|fedora|rocky|almalinux) ]] || [[ "$OS_ID_LIKE" =~ (rhel|fedora) ]]; then
    log_step "Installing sbt using yum/dnf"
    sudo yum install sbt -y

elif [[ "$OS_ID" =~ (ubuntu|debian) ]] || [[ "$OS_ID_LIKE" =~ (ubuntu|debian) ]]; then
    log_step "Installing sbt using apt-get"
    sudo apt-get install sbt -y

else
    log_error "Unsupported OS: ${OS_ID} (like: ${OS_ID_LIKE})"
    exit 1
fi

# Verify installation
log_info "Verifying sbt installation"
if command -v sbt >/dev/null 2>&1; then
    SBT_VERSION=$(sbt --version 2>&1 | grep "sbt version" || echo "unknown")
    log_success "sbt installed successfully: ${SBT_VERSION}"
else
    log_error "sbt installation verification failed"
    exit 1
fi

log_success "sbt installation complete"
