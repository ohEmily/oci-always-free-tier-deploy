#!/bin/bash
# 09-verify-deployment.sh - Verify the application deployment is healthy
#
# Usage: ./09-verify-deployment.sh
#
# This script checks:
#   - Database migration job completion
#   - Airflow initialization status
#   - All pods are running
#   - All services are created

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

main() {
  print_section "Step 9: Verify Deployment"

  load_env
  verify_requirements

  explain "Let's check that everything deployed correctly.
   We'll look at Job logs (one-time tasks) and the status of all pods and services."

  echo ""
  run_cmd "Checking Database Migration Job logs - shows SQL migrations that were applied." \
    kubectl logs -n "$NAMESPACE" job/db-migrate 2>/dev/null || echo "ℹ  Job not found or not complete yet"

  echo ""
  run_cmd "Checking Airflow Init Job logs - shows Airflow database setup and admin user creation." \
    kubectl logs -n "$NAMESPACE" job/airflow-init 2>/dev/null || echo "ℹ  Job not found or not complete yet"

  echo ""
  run_cmd "Listing all Pods - these are your running containers.
   • STATUS should be 'Running' for healthy pods, 'Completed' for jobs
   • READY column shows containers ready / total (e.g., 1/1 = healthy)" \
    kubectl get pods -n "$NAMESPACE"

  echo ""
  run_cmd "Listing all Services - these are network endpoints for your pods.
   • ClusterIP = internal only; LoadBalancer = external access
   • PORT(S) shows the mapping (e.g., 8000:30000/TCP)" \
    kubectl get svc -n "$NAMESPACE"

  explain "If pods are Running and services exist, your deployment is healthy!
   Use port-forward commands to access services locally for testing."
}

main "$@"
