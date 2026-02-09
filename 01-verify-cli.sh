#!/bin/bash
# 01-verify-cli.sh - Verify OCI CLI is properly configured
# 
# Usage: ./01-verify-cli.sh
#
# This script verifies that the OCI CLI is installed and configured with valid credentials.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

main() {
  print_section "Step 1: Verify OCI CLI Configuration"

  explain "The OCI CLI needs to be configured with your credentials before we can create resources.
   If this fails, run 'oci setup config' to set up your API key and configuration."

  # Check if OCI CLI is installed
  if ! command_exists "oci"; then
    error_exit "OCI CLI is not installed. Run: brew install oci-cli"
  fi

  # Verify CLI access
  log "Verifying OCI CLI configuration..."
  run_cmd "Listing OCI regions to verify CLI authentication works" \
    oci iam region list --output table

  success "OCI CLI is properly configured!"
}

main "$@"
