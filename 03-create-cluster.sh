#!/bin/bash
# 03-create-cluster.sh - Wrapper to create cluster and node pool
#
# Usage: ./03-create-cluster.sh
#
# This script now delegates to:
#   - 03a-create-cluster-only.sh (control plane)
#   - 03b-create-nodepool-with-capacity-check.sh (node pool with capacity polling)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
  "${SCRIPT_DIR}/03a-create-cluster-only.sh"
  "${SCRIPT_DIR}/03b-create-nodepool-with-capacity-check.sh"
}

main "$@"
