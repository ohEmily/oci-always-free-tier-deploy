#!/bin/bash
# 04-create-nodepool.sh - Create node pool with capacity polling
#
# Usage: ./04-create-nodepool.sh
#
# This script delegates to the Cloud Function implementation (03b-nodepool-cloudfunc)
# for capacity polling and node pool creation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
  "${SCRIPT_DIR}/03b-nodepool-cloudfunc/poll_local.sh"
}

main "$@"
