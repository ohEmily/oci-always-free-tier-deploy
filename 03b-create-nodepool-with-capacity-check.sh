#!/bin/bash
# 03b-create-nodepool-with-capacity-check.sh - Wrapper for cloud function polling
#
# Usage: ./03b-create-nodepool-with-capacity-check.sh
#
# This script delegates to the Cloud Function implementation (03b-nodepool-cloudfunc)
# for capacity polling and node pool creation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
  "${SCRIPT_DIR}/03b-nodepool-cloudfunc/poll_local.sh"
}

main "$@"
