#!/bin/bash
# port-forward.sh - Port forward Kubernetes services to localhost
#
# Usage: 
#   ./port-forward.sh backend   # Forward backend to localhost:8000
#   ./port-forward.sh frontend  # Forward frontend to localhost:3000
#   ./port-forward.sh airflow   # Forward Airflow to localhost:8080

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

port_forward_backend() {
  explain "Port forwarding backend to localhost:8000
   localhost:8000 → backend pod:8000
   This is useful for testing without exposing services publicly.
   
   Test with: curl http://localhost:8000/api/ready/"

  run_cmd "Port forwarding backend service" \
    kubectl port-forward -n "$NAMESPACE" svc/backend 8000:8000
}

port_forward_frontend() {
  explain "Port forwarding frontend to localhost:3000
   Open in browser: http://localhost:3000"

  run_cmd "Port forwarding frontend service" \
    kubectl port-forward -n "$NAMESPACE" svc/frontend 3000:3000
}

port_forward_airflow() {
  explain "Port forwarding Airflow UI to localhost:8080
   Open in browser: http://localhost:8080
   Default credentials are in your airflow.env secrets"

  run_cmd "Port forwarding Airflow service" \
    kubectl port-forward -n "$NAMESPACE" svc/airflow-apiserver 8080:8080
}

main() {
  load_env
  verify_requirements

  case "${1:-help}" in
    backend)
      port_forward_backend
      ;;
    frontend)
      port_forward_frontend
      ;;
    airflow)
      port_forward_airflow
      ;;
    *)
      echo "Port Forwarding Utility"
      echo ""
      echo "Usage: $0 <service>"
      echo ""
      echo "Services:"
      echo "  backend   - Django API server (localhost:8000)"
      echo "  frontend  - React/Deno app (localhost:3000)"
      echo "  airflow   - Airflow UI (localhost:8080)"
      ;;
  esac
}

main "$@"
