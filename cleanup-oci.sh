#!/bin/bash
# cleanup-oci.sh - Delete OCI resources to avoid billing
#
# Usage: ./cleanup-oci.sh [--all]
#
# This script deletes OCI resources in the correct order:
#   1. Kubernetes resources (deployments, services, etc.)
#   2. Node pool (the billable VMs)
#   3. OKE cluster
#   4. Networking (VCN, subnet, etc.) - ONLY if --all flag is passed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

delete_k8s_resources() {
  print_section "Deleting Kubernetes Resources"
  
  if kubectl get namespace shouldiwalk &>/dev/null; then
    log "Deleting all resources in shouldiwalk namespace..."
    kubectl delete all,secrets,configmaps,pvc --all -n shouldiwalk || true
    
    log "Deleting namespace..."
    kubectl delete namespace shouldiwalk || true
    
    success "Kubernetes resources deleted"
  else
    log "Namespace 'shouldiwalk' not found, skipping..."
  fi
}

delete_node_pool() {
  print_section "Deleting Node Pool"
  
  load_ocids || true
  
  if [ -z "${CLUSTER_OCID:-}" ]; then
    log "No cluster OCID found, checking for cluster..."
    CLUSTER_OCID=$(oci ce cluster list \
      --compartment-id "$TENANCY_OCID" \
      --name "$CLUSTER_NAME" \
      --query 'data[0].id' \
      --raw-output 2>/dev/null || echo "")
  fi
  
  if [ -n "$CLUSTER_OCID" ] && [ "$CLUSTER_OCID" != "null" ]; then
    log "Finding node pool..."
    NODEPOOL_OCID=$(oci ce node-pool list \
      --compartment-id "$TENANCY_OCID" \
      --cluster-id "$CLUSTER_OCID" \
      --name "$NODE_POOL_NAME" \
      --query 'data[0].id' \
      --raw-output 2>/dev/null || echo "")
    
    if [ -n "$NODEPOOL_OCID" ] && [ "$NODEPOOL_OCID" != "null" ]; then
      log "Deleting node pool: $NODEPOOL_OCID (this takes 5-10 minutes)..."
      oci ce node-pool delete \
        --node-pool-id "$NODEPOOL_OCID" \
        --force 2>/dev/null || true
      
      success "Node pool deletion initiated (check OCI Console to monitor progress)"
    else
      log "No node pool found"
    fi
  else
    log "No cluster found, skipping node pool deletion"
  fi
}

delete_cluster() {
  print_section "Deleting OKE Cluster"
  
  if [ -z "${CLUSTER_OCID:-}" ]; then
    log "Finding cluster..."
    CLUSTER_OCID=$(oci ce cluster list \
      --compartment-id "$TENANCY_OCID" \
      --name "$CLUSTER_NAME" \
      --query 'data[0].id' \
      --raw-output 2>/dev/null || echo "")
  fi
  
  if [ -n "$CLUSTER_OCID" ] && [ "$CLUSTER_OCID" != "null" ]; then
    log "Deleting cluster: $CLUSTER_OCID (this takes 5-10 minutes)..."
    oci ce cluster delete \
      --cluster-id "$CLUSTER_OCID" \
      --force 2>/dev/null || true
    
    success "Cluster deletion initiated (check OCI Console to monitor progress)"
  else
    log "No cluster found"
  fi
}

delete_networking() {
  print_section "Deleting Networking Resources"
  
  load_ocids || true
  
  # Delete subnet
  if [ -n "${SUBNET_OCID:-}" ] && [ "$SUBNET_OCID" != "null" ]; then
    log "Deleting subnet: $SUBNET_OCID"
    oci network subnet delete \
      --subnet-id "$SUBNET_OCID" \
      --force \
      --wait-for-state TERMINATED || true
    success "Subnet deleted"
  fi
  
  # Delete route table
  if [ -n "${ROUTE_TABLE_OCID:-}" ] && [ "$ROUTE_TABLE_OCID" != "null" ]; then
    log "Deleting route table: $ROUTE_TABLE_OCID"
    oci network route-table delete \
      --rt-id "$ROUTE_TABLE_OCID" \
      --force \
      --wait-for-state TERMINATED || true
    success "Route table deleted"
  fi
  
  # Delete security list
  if [ -n "${SECURITY_LIST_OCID:-}" ] && [ "$SECURITY_LIST_OCID" != "null" ]; then
    log "Deleting security list: $SECURITY_LIST_OCID"
    oci network security-list delete \
      --security-list-id "$SECURITY_LIST_OCID" \
      --force \
      --wait-for-state TERMINATED || true
    success "Security list deleted"
  fi
  
  # Delete internet gateway
  if [ -n "${IGW_OCID:-}" ] && [ "$IGW_OCID" != "null" ]; then
    log "Deleting internet gateway: $IGW_OCID"
    oci network internet-gateway delete \
      --ig-id "$IGW_OCID" \
      --force \
      --wait-for-state TERMINATED || true
    success "Internet gateway deleted"
  fi
  
  # Delete VCN last
  if [ -n "${VCN_OCID:-}" ] && [ "$VCN_OCID" != "null" ]; then
    log "Deleting VCN: $VCN_OCID"
    oci network vcn delete \
      --vcn-id "$VCN_OCID" \
      --force \
      --wait-for-state TERMINATED || true
    success "VCN deleted"
  fi
}

main() {
  print_section "OCI Resource Cleanup"
  
  load_env
  verify_requirements
  
  explain "This will delete your OCI resources to stop billing.
   The cleanup happens in this order:
   1. Kubernetes resources (deployments, services, PVCs)
   2. Node pool (the compute VMs - the billable part!)
   3. OKE cluster (control plane)
   4. Networking (VCN, subnet, etc.) - only if you pass --all flag"
  
  # Delete K8s resources first
  delete_k8s_resources
  
  # Delete node pool (the billable part!)
  delete_node_pool
  
  # Delete cluster
  delete_cluster
  
  # Optionally delete networking
  if [[ "${1:-}" == "--all" ]]; then
    delete_networking
  else
    explain "Networking resources (VCN, subnet) were preserved.
     To delete everything including networking, run: ./cleanup-oci.sh --all"
  fi
  
  # Clean up saved OCIDs
  rm -f /tmp/oci-deploy-ocids.env
  
  success "Cleanup complete! Billable resources (node pool) have been deleted."
  
  if [[ "${1:-}" == "--all" ]]; then
    explain "To redeploy everything from scratch:
     ./02-create-networking.sh
     ./03-create-cluster.sh
     ./04-create-nodepool.sh
     ./05-configure-kubectl.sh
     ./06-build-push-images.sh
     ./07-setup-kubernetes.sh
     ./08-deploy-application.sh"
  else
    explain "Networking was preserved. To redeploy with free-tier A1 instances:
     ./03-create-cluster.sh
     ./04-create-nodepool.sh
     ./05-configure-kubectl.sh
     ./06-build-push-images.sh
     ./07-setup-kubernetes.sh
     ./08-deploy-application.sh"
  fi
}

main "$@"
