#!/bin/bash
# Test the Cloud Function locally
#
# Prerequisites:
#   - pip install oci
#   - Run scripts 01, 02, 03a first
#   - Have ~/.oci/config set up

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"

# Load existing config
source "${SCRIPTS_DIR}/config.sh"
source "${SCRIPTS_DIR}/.env.oci-deploy"

# Load OCIDs from previous scripts
if [ -f /tmp/oci-deploy-ocids.env ]; then
  source /tmp/oci-deploy-ocids.env
else
  echo "ERROR: /tmp/oci-deploy-ocids.env not found"
  echo "Please run scripts 01, 02, and 03a first"
  exit 1
fi

# Check required OCIDs
if [ -z "${CLUSTER_OCID:-}" ]; then
  echo "ERROR: CLUSTER_OCID not set. Run 03a-create-cluster-only.sh first"
  exit 1
fi

if [ -z "${NODE_SUBNET_OCID:-}" ]; then
  echo "ERROR: NODE_SUBNET_OCID not set. Run 02-create-networking.sh first"
  exit 1
fi

# Get OCI config from ~/.oci/config
OCI_CONFIG_FILE="${HOME}/.oci/config"
OCI_KEY_FILE="${HOME}/.oci/oci_api_key.pem"

if [ ! -f "$OCI_CONFIG_FILE" ]; then
  echo "ERROR: OCI config not found at $OCI_CONFIG_FILE"
  exit 1
fi

# Parse user OCID and fingerprint from OCI config
OCI_USER_OCID=$(grep -A 10 '^\[DEFAULT\]' "$OCI_CONFIG_FILE" | grep '^user=' | cut -d'=' -f2 || echo "")
OCI_FINGERPRINT=$(grep -A 10 '^\[DEFAULT\]' "$OCI_CONFIG_FILE" | grep '^fingerprint=' | cut -d'=' -f2 || echo "")
OCI_KEY_PATH=$(grep -A 10 '^\[DEFAULT\]' "$OCI_CONFIG_FILE" | grep '^key_file=' | cut -d'=' -f2 || echo "$OCI_KEY_FILE")

# Expand ~ in key path
OCI_KEY_PATH="${OCI_KEY_PATH/#\~/$HOME}"

if [ ! -f "$OCI_KEY_PATH" ]; then
  echo "ERROR: OCI private key not found at $OCI_KEY_PATH"
  exit 1
fi

echo "=== Local Test Configuration ==="
echo "TENANCY_OCID:     ${TENANCY_OCID:0:30}..."
echo "REGION:           $REGION"
echo "CLUSTER_OCID:     ${CLUSTER_OCID:0:30}..."
echo "NODE_SUBNET_OCID: ${NODE_SUBNET_OCID:0:30}..."
echo "USER_OCID:        ${OCI_USER_OCID:0:30}..."
echo "FINGERPRINT:      $OCI_FINGERPRINT"
echo "NODE_SHAPE:       $NODE_SHAPE"
echo "NODE_OCPUS:       $NODE_OCPUS"
echo "NODE_MEMORY_GB:   $NODE_MEMORY_GB"
echo "================================"
echo ""

# Export environment variables for the Python script
export OCI_TENANCY_OCID="$TENANCY_OCID"
export OCI_REGION="$REGION"
export OCI_CLUSTER_OCID="$CLUSTER_OCID"
export OCI_NODE_SUBNET_OCID="$NODE_SUBNET_OCID"
export OCI_USER_OCID="$OCI_USER_OCID"
export OCI_FINGERPRINT="$OCI_FINGERPRINT"
export OCI_PRIVATE_KEY="$(cat "$OCI_KEY_PATH")"

export NODE_SHAPE="$NODE_SHAPE"
export NODE_OCPUS="$NODE_OCPUS"
export NODE_MEMORY_GB="$NODE_MEMORY_GB"
export NODE_COUNT="$NODE_COUNT"
export KUBERNETES_VERSION="$KUBERNETES_VERSION"
export NODE_POOL_NAME="$NODE_POOL_NAME"

# Run the function using venv if available, otherwise system python
VENV_PYTHON="${SCRIPT_DIR}/.venv/bin/python3"
if [ -x "$VENV_PYTHON" ]; then
  PYTHON="$VENV_PYTHON"
else
  PYTHON="python3"
fi

echo "Running Cloud Function locally (using $PYTHON)..."
echo ""
"$PYTHON" "${SCRIPT_DIR}/main.py"
