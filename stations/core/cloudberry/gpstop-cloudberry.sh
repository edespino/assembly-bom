#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../generic/common.sh"

component_name="cloudberry"
step_name="gpstop"

log_info "Stopping Cloudberry Database..."

# Source the gpdemo environment if available
GPDEMO_ENV="${PARTS_DIR}/${component_name}/gpAux/gpdemo/gpdemo-env.sh"
if [[ -f "${GPDEMO_ENV}" ]]; then
    log_info "Sourcing gpdemo environment from ${GPDEMO_ENV}"
    source "${GPDEMO_ENV}"
else
    log_error "gpdemo-env.sh not found at ${GPDEMO_ENV}"
    exit 1
fi

# Execute gpstop
log_info "Executing: gpstop -a"
gpstop -a

log_success "Cloudberry Database stopped successfully"
