#!/bin/bash
# Poll the cloud function locally every 60 seconds until capacity is found
# Usage: bash poll_local.sh
# Stop with Ctrl+C

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLL_INTERVAL="${POLL_INTERVAL:-60}"

echo "=== Starting capacity polling (every ${POLL_INTERVAL}s) ==="
echo "    Press Ctrl+C to stop"
echo ""
echo "💡 TIP: If you're on the 30-day free trial and A1 capacity is scarce,"
echo "   upgrade to Pay As You Go (PAYG) - you still get the same free tier"
echo "   resources, but A1 instances become much easier to provision."
echo "   OCI Console → Billing → Upgrade to Paid Account"
echo ""

ATTEMPT=0
while true; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempt #${ATTEMPT}"
  
  RESULT=$(bash "${SCRIPT_DIR}/test_local.sh" 2>&1)
  STATUS=$(echo "$RESULT" | tail -1 | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('status','unknown'))" 2>/dev/null || echo "unknown")
  
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Status: ${STATUS}"
  
  case "$STATUS" in
    active)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] NODE POOL IS ACTIVE! Done."
      exit 0
      ;;
    creating)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Node pool is being created, will check again..."
      ;;
    no_capacity)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] No capacity yet, retrying in ${POLL_INTERVAL}s..."
      ;;
    stuck_deleted)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stuck pool deleted, will retry..."
      ;;
    deleting)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Previous pool still deleting, waiting..."
      ;;
    *)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Unexpected status: ${STATUS}"
      echo "$RESULT" | tail -5
      ;;
  esac
  
  echo ""
  sleep $POLL_INTERVAL
done
