#!/bin/bash
# 02-create-networking.sh - Create VCN (Virtual Cloud Network) and related network resources
#
# Usage: ./02-create-networking.sh
#
# This script creates:
#   - Virtual Cloud Network (VCN) with CIDR 10.0.0.0/16
#   - Internet Gateway for external connectivity
#   - Route Table with route to Internet Gateway
#   - Public Subnet with CIDR 10.0.1.0/24

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

main() {
  print_section "Step 2: Create Networking Resources (VCN)"

  load_env
  verify_requirements

  explain "A Virtual Cloud Network (VCN) is OCI's software-defined network - similar to an AWS VPC.
   It provides an isolated network where your Kubernetes cluster will run.
   We'll create: VCN → Internet Gateway → Route Table → Subnet"

  # Check if VCN already exists
  log "Checking for existing VCN..."
  EXISTING_VCN=$(oci network vcn list \
    --compartment-id "$TENANCY_OCID" \
    --display-name "$VCN_NAME" \
    --lifecycle-state AVAILABLE \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || echo "")

  if [ -n "$EXISTING_VCN" ] && [ "$EXISTING_VCN" != "null" ]; then
    log "VCN already exists: $EXISTING_VCN"
    VCN_OCID="$EXISTING_VCN"
  else
    # Create VCN
    log "Creating VCN..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Creating VCN (Virtual Cloud Network) - the foundation of your cloud network."
    echo "   • CIDR ${VCN_CIDR} gives us IP addresses to work with"
    echo "   • DNS label enables internal DNS resolution"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    VCN_OCID=$(oci network vcn create \
      --compartment-id "$TENANCY_OCID" \
      --display-name "$VCN_NAME" \
      --cidr-block "$VCN_CIDR" \
      --dns-label "${CLUSTER_NAME//[^a-z0-9]/}" \
      --wait-for-state AVAILABLE \
      --query 'data.id' \
      --raw-output)
    
    success "VCN created: $VCN_OCID"
  fi

  # Check if Internet Gateway already exists
  log "Checking for existing Internet Gateway..."
  EXISTING_IGW=$(oci network internet-gateway list \
    --compartment-id "$TENANCY_OCID" \
    --vcn-id "$VCN_OCID" \
    --lifecycle-state AVAILABLE \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || echo "")

  if [ -n "$EXISTING_IGW" ] && [ "$EXISTING_IGW" != "null" ]; then
    log "Internet Gateway already exists: $EXISTING_IGW"
    IGW_OCID="$EXISTING_IGW"
  else
    # Create Internet Gateway
    log "Creating Internet Gateway..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Creating Internet Gateway - allows resources in the VCN to access the internet."
    echo "   • Without this, your cluster nodes couldn't pull container images or receive traffic"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    IGW_OCID=$(oci network internet-gateway create \
      --compartment-id "$TENANCY_OCID" \
      --vcn-id "$VCN_OCID" \
      --display-name "${VCN_NAME}-igw" \
      --is-enabled true \
      --wait-for-state AVAILABLE \
      --query 'data.id' \
      --raw-output)
    
    success "Internet Gateway created: $IGW_OCID"
  fi

  # Check if Route Table already exists (besides the default one)
  log "Checking for existing Route Table..."
  EXISTING_RT=$(oci network route-table list \
    --compartment-id "$TENANCY_OCID" \
    --vcn-id "$VCN_OCID" \
    --display-name "${VCN_NAME}-route-table" \
    --lifecycle-state AVAILABLE \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || echo "")

  if [ -n "$EXISTING_RT" ] && [ "$EXISTING_RT" != "null" ]; then
    log "Route Table already exists: $EXISTING_RT"
    RT_OCID="$EXISTING_RT"
  else
    # Create Route Table
    log "Creating Route Table..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Creating Route Table - defines how traffic flows in/out of the VCN."
    echo "   • The rule '0.0.0.0/0 → Internet Gateway' sends all external traffic through the gateway"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    RT_OCID=$(oci network route-table create \
      --compartment-id "$TENANCY_OCID" \
      --vcn-id "$VCN_OCID" \
      --display-name "${VCN_NAME}-route-table" \
      --route-rules "[{\"destination\": \"0.0.0.0/0\", \"networkEntityId\": \"$IGW_OCID\"}]" \
      --wait-for-state AVAILABLE \
      --query 'data.id' \
      --raw-output)
    
    success "Route Table created: $RT_OCID"
  fi

  # Check if Subnet already exists
  log "Checking for existing Subnet..."
  EXISTING_SUBNET=$(oci network subnet list \
    --compartment-id "$TENANCY_OCID" \
    --vcn-id "$VCN_OCID" \
    --display-name "$SUBNET_NAME" \
    --lifecycle-state AVAILABLE \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || echo "")

  if [ -n "$EXISTING_SUBNET" ] && [ "$EXISTING_SUBNET" != "null" ]; then
    log "Subnet already exists: $EXISTING_SUBNET"
    SUBNET_OCID="$EXISTING_SUBNET"
  else
    # Create Subnet
    log "Creating Subnet..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Creating Subnet - a subdivision of the VCN where your K8s nodes will live."
    echo "   • CIDR ${SUBNET_CIDR} gives us 256 IP addresses for nodes"
    echo "   • DNS label 'nodes' makes pods addressable on internal DNS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    SUBNET_OCID=$(oci network subnet create \
      --compartment-id "$TENANCY_OCID" \
      --vcn-id "$VCN_OCID" \
      --display-name "$SUBNET_NAME" \
      --cidr-block "$SUBNET_CIDR" \
      --route-table-id "$RT_OCID" \
      --dns-label "nodes" \
      --wait-for-state AVAILABLE \
      --query 'data.id' \
      --raw-output)
    
    success "Subnet created: $SUBNET_OCID"
  fi

  # Update security list to allow K8s API and NodePort access
  log "Updating security list for Kubernetes access..."
  SECLIST_OCID=$(oci network security-list list \
    --compartment-id "$TENANCY_OCID" \
    --vcn-id "$VCN_OCID" \
    --query 'data[0].id' \
    --raw-output)

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📝 Updating Security List - controls which traffic can enter/exit the subnet."
  echo "   • Port 22: SSH access to nodes"
  echo "   • Port 6443: Kubernetes API Server (kubectl access)"
  echo "   • Ports 30000-32767: NodePort Services (for app access before LoadBalancer)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  oci network security-list update \
    --security-list-id "$SECLIST_OCID" \
    --ingress-security-rules '[
      {"source": "0.0.0.0/0", "protocol": "6", "tcpOptions": {"destinationPortRange": {"min": 22, "max": 22}}, "description": "SSH"},
      {"source": "0.0.0.0/0", "protocol": "1", "icmpOptions": {"type": 3, "code": 4}},
      {"source": "10.0.0.0/16", "protocol": "1", "icmpOptions": {"type": 3}},
      {"source": "0.0.0.0/0", "protocol": "6", "tcpOptions": {"destinationPortRange": {"min": 6443, "max": 6443}}, "description": "Kubernetes API Server"},
      {"source": "0.0.0.0/0", "protocol": "6", "tcpOptions": {"destinationPortRange": {"min": 30000, "max": 32767}}, "description": "NodePort Services"},
      {"source": "10.0.0.0/16", "protocol": "all", "description": "Allow all VCN traffic for K8s communication"},
      {"source": "10.244.0.0/16", "protocol": "all", "description": "Allow Kubernetes pod CIDR traffic"}
    ]' \
    --force > /dev/null

  success "Security list updated: $SECLIST_OCID"

  # Check if Node Subnet already exists (separate subnet for worker nodes)
  log "Checking for existing Node Subnet..."
  EXISTING_NODE_SUBNET=$(oci network subnet list \
    --compartment-id "$TENANCY_OCID" \
    --vcn-id "$VCN_OCID" \
    --display-name "${CLUSTER_NAME}-node-subnet" \
    --lifecycle-state AVAILABLE \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || echo "")

  if [ -n "$EXISTING_NODE_SUBNET" ] && [ "$EXISTING_NODE_SUBNET" != "null" ]; then
    log "Node Subnet already exists: $EXISTING_NODE_SUBNET"
    NODE_SUBNET_OCID="$EXISTING_NODE_SUBNET"
  else
    # Create Node Subnet (separate from service LB subnet)
    log "Creating Node Subnet..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Creating Node Subnet - OKE requires separate subnets for nodes and service LBs."
    echo "   • CIDR 10.0.2.0/24 for worker nodes"
    echo "   • Service LB subnet uses 10.0.1.0/24 (created earlier)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    NODE_SUBNET_OCID=$(oci network subnet create \
      --compartment-id "$TENANCY_OCID" \
      --vcn-id "$VCN_OCID" \
      --display-name "${CLUSTER_NAME}-node-subnet" \
      --cidr-block "10.0.2.0/24" \
      --route-table-id "$RT_OCID" \
      --dns-label "nodesubnet" \
      --wait-for-state AVAILABLE \
      --query 'data.id' \
      --raw-output)
    
    success "Node Subnet created: $NODE_SUBNET_OCID"
  fi

  # Save OCIDs for next steps
  save_ocids VCN_OCID IGW_OCID RT_OCID SUBNET_OCID SECLIST_OCID NODE_SUBNET_OCID

  explain "Networking setup complete! Resource OCIDs saved to /tmp/oci-deploy-ocids.env
   These OCIDs are unique identifiers for each resource - we'll need them for the next steps."
  
  echo ""
  echo "Summary:"
  echo "  VCN_OCID=$VCN_OCID"
  echo "  IGW_OCID=$IGW_OCID"
  echo "  RT_OCID=$RT_OCID"
  echo "  SUBNET_OCID=$SUBNET_OCID (Service LB subnet)"
  echo "  NODE_SUBNET_OCID=$NODE_SUBNET_OCID (Worker node subnet)"
}

main "$@"
