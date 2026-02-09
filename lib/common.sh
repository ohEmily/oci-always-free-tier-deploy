#!/bin/bash
# Common utility functions for OCI deployment scripts
# Source this file in other scripts: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# Print a timestamped log message
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Print an explanation/insight message
explain() {
  echo ""
  echo "💡 $*"
  echo ""
}

# Print a command before running it, with optional explanation
# Usage: run_cmd "explanation" command arg1 arg2 ...
run_cmd() {
  local explanation="$1"
  shift
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📝 $explanation"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ Running: $*"
  echo "───────────────────────────────────────────────────────────────────────────"
  "$@"
}

# Run a command and capture output, with explanation
# Usage: result=$(run_cmd_capture "explanation" command arg1 arg2 ...)
run_cmd_capture() {
  local explanation="$1"
  shift
  echo "" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "📝 $explanation" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "▶ Running: $*" >&2
  echo "───────────────────────────────────────────────────────────────────────────" >&2
  "$@"
}

# Load configuration and environment variables
# First loads non-sensitive defaults from config.sh (version controlled)
# Then loads secrets and overrides from .env.oci-deploy (not version controlled)
load_env() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local scripts_dir="$(dirname "$script_dir")"
  local config_file="${scripts_dir}/config.sh"
  local env_file="${scripts_dir}/.env.oci-deploy"

  # First, load non-sensitive defaults from config.sh
  if [ ! -f "$config_file" ]; then
    echo "ERROR: Configuration file not found: $config_file"
    echo "This should be version controlled - something is wrong!"
    exit 1
  fi
  source "$config_file"
  log "Configuration loaded from $config_file"

  # Then, load secrets and account-specific values from .env.oci-deploy
  if [ ! -f "$env_file" ]; then
    echo "ERROR: Environment file not found: $env_file"
    echo "Please create .env.oci-deploy in the scripts directory"
    echo "You can start from: cp $scripts_dir/.env.oci-deploy.example $env_file"
    exit 1
  fi
  source "$env_file"
  log "Secrets and account config loaded from $env_file"

  # Verify required variables are set (mix of config.sh and .env.oci-deploy)
  local required_vars=(
    # From .env.oci-deploy (secrets/account-specific)
    "TENANCY_OCID"
    "REGION"
    "REGION_KEY"
    "TENANCY_NAMESPACE"
    "OCI_USERNAME"
    # From config.sh (non-sensitive defaults)
    "CLUSTER_NAME"
    "NAMESPACE"
    "NODE_SHAPE"
    "KUBERNETES_VERSION"
  )

  for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
      echo "ERROR: Required environment variable not set: $var"
      exit 1
    fi
  done
}

# Check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Verify required CLI tools are installed
verify_requirements() {
  local required_commands=("oci" "kubectl" "docker" "jq")
  local missing=()

  for cmd in "${required_commands[@]}"; do
    if ! command_exists "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo "ERROR: The following required commands are not installed:"
    printf '  - %s\n' "${missing[@]}"
    echo ""
    echo "Please install them and try again:"
    echo "  - oci: brew install oci-cli"
    echo "  - kubectl: brew install kubectl"
    echo "  - docker: brew install docker"
    echo "  - jq: brew install jq"
    exit 1
  fi

  log "All required tools are installed"
}

# Save resource OCIDs to a temporary file for sharing between scripts
save_ocids() {
  local ocids_file="/tmp/oci-deploy-ocids.env"
  cat > "$ocids_file" << EOF
# Resource OCIDs for this deployment
# Generated at $(date)
EOF

  # Append each variable passed as an argument
  for var_name in "$@"; do
    local var_value="${!var_name:-}"
    if [ -n "$var_value" ]; then
      echo "export $var_name=\"$var_value\"" >> "$ocids_file"
    fi
  done

  log "Resource OCIDs saved to $ocids_file"
}

# Load previously saved resource OCIDs
load_ocids() {
  local ocids_file="/tmp/oci-deploy-ocids.env"
  if [ -f "$ocids_file" ]; then
    source "$ocids_file"
    log "Resource OCIDs loaded from $ocids_file"
    return 0
  else
    return 1
  fi
}

# Get the project root directory
get_project_root() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$(dirname "$(dirname "$script_dir")")"
}

# Print a section header
print_section() {
  echo ""
  echo "████████████████████████████████████████████████████████████████████████████"
  echo "█  $1"
  echo "████████████████████████████████████████████████████████████████████████████"
  echo ""
}

# Print an error message and exit
error_exit() {
  echo "❌ ERROR: $1"
  exit 1
}

# Print a success message
success() {
  echo "✅ $1"
}
