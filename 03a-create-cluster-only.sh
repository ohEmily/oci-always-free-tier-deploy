#!/bin/bash
# 03a-create-cluster-only.sh - Create OKE cluster control plane only
#
# Usage: ./03a-create-cluster-only.sh
#
# This script creates only the OKE cluster (control plane), without the node pool.
# The control plane is managed infrastructure and doesn't have capacity issues.
#
# Use this with 03b-create-nodepool-with-capacity-check.sh when dealing with
# free-tier capacity constraints.
#
# Prerequisites:
#   - Script 01 and 02 must have completed successfully

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

main() {
  print_section "Step 3a: Create OKE Cluster (Control Plane Only)"

  load_env
  verify_requirements

  explain "This creates only the OKE control plane (API server, etcd, etc.).
   The control plane is FREE and managed by OCI - no capacity issues here.
   Node pool creation is handled separately by 03b-create-nodepool-with-capacity-check.sh"

  # Load network OCIDs from previous step
  if ! load_ocids; then
    error_exit "Network OCIDs not found. Please run 02-create-networking.sh first"
  fi

  # Check if cluster already exists
  log "Checking for existing cluster..."
  EXISTING_CLUSTER=$(oci ce cluster list \
    --compartment-id "$TENANCY_OCID" \
    --name "$CLUSTER_NAME" \
    --lifecycle-state ACTIVE \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || echo "")

  if [ -n "$EXISTING_CLUSTER" ] && [ "$EXISTING_CLUSTER" != "null" ]; then
    log "Cluster already exists: $EXISTING_CLUSTER"
    CLUSTER_OCID="$EXISTING_CLUSTER"
  else
    log "Creating OKE cluster (this may take 5-10 minutes)..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Creating OKE Kubernetes cluster control plane"
    echo "   • The control plane manages the cluster (API server, etcd, scheduler)"
    echo "   • This is FREE on OCI (unlike GKE/EKS which charge ~\$70/month)"
    echo "   • Kubernetes version: ${KUBERNETES_VERSION}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Start the cluster creation (returns work request)
    WORK_REQUEST=$(oci ce cluster create \
      --compartment-id "$TENANCY_OCID" \
      --name "$CLUSTER_NAME" \
      --vcn-id "$VCN_OCID" \
      --kubernetes-version "$KUBERNETES_VERSION" \
      --service-lb-subnet-ids "[\"$SUBNET_OCID\"]" \
      --endpoint-subnet-id "$SUBNET_OCID" \
      --endpoint-public-ip-enabled true \
      --query 'data.id' \
      --raw-output 2>&1)

    if [ -z "$WORK_REQUEST" ] || [ "$WORK_REQUEST" = "null" ]; then
      error_exit "Failed to start cluster creation"
    fi

    log "Cluster creation started. Work request: $WORK_REQUEST"
    log "Waiting for work request to complete (this takes 5-10 minutes)..."

    # Wait for the work request to complete and get the cluster OCID
    CLUSTER_OCID=""
    MAX_WAIT=900  # 15 minutes
    ELAPSED=0
    while true; do
      sleep 30
      ELAPSED=$((ELAPSED + 30))
      
      if [ $ELAPSED -ge $MAX_WAIT ]; then
        error_exit "Timed out after ${MAX_WAIT}s waiting for cluster creation"
      fi
      
      # Check work request status
      WR_STATUS=$(oci ce work-request get \
        --work-request-id "$WORK_REQUEST" \
        --query 'data.status' \
        --raw-output 2>/dev/null || echo "")
      
      log "  Work request status: $WR_STATUS (${ELAPSED}s elapsed)"
      
      if [ "$WR_STATUS" = "SUCCEEDED" ]; then
        # Get cluster OCID from work request resources
        CLUSTER_OCID=$(oci ce work-request get \
          --work-request-id "$WORK_REQUEST" \
          --query 'data.resources[?"action-type"==`CREATED`].identifier | [0]' \
          --raw-output 2>/dev/null || echo "")
        
        if [ -n "$CLUSTER_OCID" ] && [ "$CLUSTER_OCID" != "null" ]; then
          break
        fi
      elif [ "$WR_STATUS" = "FAILED" ]; then
        error_exit "Cluster creation failed"
      fi
      
      # Fallback: check if cluster is already ACTIVE (in case work request tracking is stale)
      ACTIVE_CLUSTER=$(oci ce cluster list \
        --compartment-id "$TENANCY_OCID" \
        --name "$CLUSTER_NAME" \
        --lifecycle-state ACTIVE \
        --query 'data[0].id' \
        --raw-output 2>/dev/null || echo "")
      
      if [ -n "$ACTIVE_CLUSTER" ] && [ "$ACTIVE_CLUSTER" != "null" ]; then
        log "  Cluster detected as ACTIVE via fallback check"
        CLUSTER_OCID="$ACTIVE_CLUSTER"
        break
      fi
    done
    
    success "Cluster created: $CLUSTER_OCID"
  fi

  # Save cluster OCID (append to existing OCIDs file)
  echo "export CLUSTER_OCID=\"$CLUSTER_OCID\"" >> /tmp/oci-deploy-ocids.env
  log "Cluster OCID saved to /tmp/oci-deploy-ocids.env"

  echo ""
  echo "Summary:"
  echo "  CLUSTER_OCID=$CLUSTER_OCID"
  echo ""
  echo "Next step: Run ./03b-create-nodepool-with-capacity-check.sh"
  echo "           (This will poll for capacity and create the node pool when available)"
}

main "$@"
