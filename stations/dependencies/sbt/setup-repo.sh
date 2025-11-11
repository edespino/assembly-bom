#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../generic/common.sh"

log_header "Setting up sbt repository"

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

# Determine if RPM-based or Debian-based
if [[ "$OS_ID" =~ (rhel|centos|fedora|rocky|almalinux) ]] || [[ "$OS_ID_LIKE" =~ (rhel|fedora) ]]; then
    log_step "Setting up sbt repository for RPM-based system"

    # Remove old Bintray repo file if it exists
    if [[ -f /etc/yum.repos.d/bintray-rpm.repo ]]; then
        log_info "Removing old Bintray repo file"
        sudo rm -f /etc/yum.repos.d/bintray-rpm.repo
    fi

    # Download and install sbt repo file
    log_info "Downloading sbt RPM repository configuration"
    curl -L https://www.scala-sbt.org/sbt-rpm.repo > sbt-rpm.repo

    log_info "Installing repository configuration to /etc/yum.repos.d/"
    sudo mv sbt-rpm.repo /etc/yum.repos.d/

    log_success "sbt repository configured for RPM-based system"

elif [[ "$OS_ID" =~ (ubuntu|debian) ]] || [[ "$OS_ID_LIKE" =~ (ubuntu|debian) ]]; then
    log_step "Setting up sbt repository for Debian-based system"

    # Install prerequisites
    log_info "Installing apt-transport-https, curl, and gnupg"
    sudo apt-get update
    sudo apt-get install apt-transport-https curl gnupg -yqq

    # Add sbt repository
    log_info "Adding sbt repository to sources.list.d"
    echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
    echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | sudo tee /etc/apt/sources.list.d/sbt_old.list

    # Import GPG key
    log_info "Importing sbt GPG key"
    curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | \
        sudo -H gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/scalasbt-release.gpg --import
    sudo chmod 644 /etc/apt/trusted.gpg.d/scalasbt-release.gpg

    # Update package cache
    log_info "Updating package cache"
    sudo apt-get update

    log_success "sbt repository configured for Debian-based system"

else
    log_error "Unsupported OS: ${OS_ID} (like: ${OS_ID_LIKE})"
    log_error "This script supports RPM-based (RHEL, CentOS, Fedora, Rocky, AlmaLinux) and Debian-based (Ubuntu, Debian) systems"
    exit 1
fi

log_success "sbt repository setup complete"
