#!/bin/bash
# 07-deploy-application.sh - Deploy the Should I Walk application to OKE
#
# Usage: ./07-deploy-application.sh
#
# This script deploys all Kubernetes resources using Kustomize, which includes:
#   - Database migration job
#   - PostgreSQL database with PostGIS
#   - Airflow scheduler and DAGs
#   - Django backend API
#   - Deno frontend
#   - Real-time WebSocket server
#   - Services and ingress

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

main() {
  print_section "Step 7: Deploy Application with Kustomize"

  load_env
  verify_requirements

  explain "Kustomize is a Kubernetes-native configuration management tool.
   The 'k8s/overlays/oci' directory contains OCI-specific configs that layer on top of the base manifests.
   'kubectl apply -k' renders and applies all the Kubernetes resources at once."

  PROJECT_ROOT="$(get_project_root)"
  cd "$PROJECT_ROOT"

  log "Deploying all Kubernetes resources using Kustomize..."
  run_cmd "Applying Kustomize configuration for OCI deployment.
   • This creates: Deployments, Services, ConfigMaps, Secrets, Jobs, etc.
   • Resources are applied in dependency order automatically" \
    kubectl apply -k k8s/overlays/oci

  success "Kubernetes resources applied"

  explain "Watching pod status - pods go through Pending → ContainerCreating → Running
   Press Ctrl+C when all pods are Running.
   If a pod stays in 'Pending' or 'CrashLoopBackOff', check logs with:
     kubectl logs -n $NAMESPACE <pod-name>"

  run_cmd "Monitoring pod status in realtime" \
    kubectl get pods -n "$NAMESPACE" -w
}

main "$@"
