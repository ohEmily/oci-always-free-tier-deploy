#!/bin/bash
# 07-setup-kubernetes.sh - Set up Kubernetes namespace and image pull secrets
#
# Usage: ./07-setup-kubernetes.sh
#
# This script:
#   1. Creates the Kubernetes namespace for the application
#   2. Creates a docker-registry secret for pulling images from OCIR
#   3. Configures RBAC roles if needed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

main() {
  print_section "Step 7: Set Up Kubernetes Namespace and Secrets"

  load_env
  verify_requirements

  explain "Kubernetes uses 'namespaces' to isolate resources (like folders for your cluster).
   We also need an 'imagePullSecret' so Kubernetes can authenticate with OCIR to pull our images."

  # Create namespace
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📝 Creating 'shouldiwalk' namespace in Kubernetes."
  echo "   • All our pods, services, and secrets will live in this namespace"
  echo "   • --dry-run=client -o yaml | kubectl apply -f - is idempotent (safe to re-run)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ Running: kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
  echo "───────────────────────────────────────────────────────────────────────────"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  success "Kubernetes namespace created/verified"

  # Create OCIR pull secret
  explain "Creating OCIR pull secret - allows Kubernetes to pull images from your private registry.
   • Type: docker-registry (standard K8s secret type for container registries)
   • This secret will be referenced in pod specs as 'imagePullSecrets'"

  # Use AUTH_TOKEN from environment, or prompt if not set
  if [ -z "${OCIR_AUTH_TOKEN:-}" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Enter your Auth Token for OCIR (it will be hidden):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -s -p "Auth Token: " OCIR_AUTH_TOKEN
    echo ""
  else
    log "Using OCIR_AUTH_TOKEN from environment"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📝 Creating docker-registry secret for OCIR authentication."
  echo "   • Server: $OCIR_URL"
  echo "   • Username: ${TENANCY_NAMESPACE}/${OCI_USERNAME}"
  echo "   • Secret name: ocir-secret (referenced by deployments)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ Running: kubectl create secret docker-registry ocir-secret ... | kubectl apply -f -"
  echo "───────────────────────────────────────────────────────────────────────────"
  kubectl create secret docker-registry ocir-secret \
    --docker-server="$OCIR_URL" \
    --docker-username="${TENANCY_NAMESPACE}/${OCI_USERNAME}" \
    --docker-password="$OCIR_AUTH_TOKEN" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

  success "OCIR pull secret created"

  explain "Kubernetes is ready to pull images from OCIR and deploy your application!
   Next step: deploy the application with Kustomize"
}

main "$@"
