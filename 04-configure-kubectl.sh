#!/bin/bash
# 04-configure-kubectl.sh - Configure kubectl to access the OKE cluster
#
# Usage: ./04-configure-kubectl.sh
#
# This script generates a kubeconfig file that allows kubectl to authenticate
# with and manage the OKE cluster.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

main() {
  print_section "Step 4: Configure kubectl Access"

  load_env
  verify_requirements

  explain "kubectl is the CLI for interacting with Kubernetes clusters.
   We need to generate a 'kubeconfig' file that tells kubectl how to authenticate with OKE.
   OCI uses token-based auth (v2.0.0) which automatically refreshes via the OCI CLI."

  # Load cluster OCID from previous step
  if ! load_ocids; then
    error_exit "Cluster OCID not found. Please run 03-create-cluster.sh first"
  fi

  # Create .kube directory if it doesn't exist
  mkdir -p ~/.kube

  log "Generating kubeconfig..."
  run_cmd "Generating kubeconfig - this creates credentials for kubectl to access OKE.
   • Writes to ~/.kube/config (the default kubectl config location)
   • token-version 2.0.0 uses OCI CLI for automatic token refresh" \
    oci ce cluster create-kubeconfig \
      --cluster-id "$CLUSTER_OCID" \
      --file ~/.kube/config \
      --region "$REGION" \
      --token-version 2.0.0 \
      --overwrite

  success "Kubeconfig generated at ~/.kube/config"

  log "Verifying kubectl connection..."
  run_cmd "Verifying kubectl can connect to the cluster.
   • 'kubectl get nodes' lists all worker nodes in the cluster" \
    kubectl get nodes

  success "kubectl is now configured!"

  explain "You can now run any kubectl command against your OKE cluster.
   Try: kubectl get pods --all-namespaces"
}

main "$@"
