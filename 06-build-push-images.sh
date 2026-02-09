#!/bin/bash
# 06-build-push-images.sh - Build and push Docker images to OCIR using Docker Bake
#
# Usage: ./06-build-push-images.sh
#
# This script:
#   1. Logs into OCIR container registry
#   2. Sets up Docker buildx for ARM64 cross-compilation
#   3. Reads the docker-bake.hcl file specified by BAKE_FILE in .env.oci-deploy
#   4. Builds all images defined in the bake file for ARM64 (Ampere A1 architecture)
#   5. Pushes images directly to OCIR
#
# Required in .env.oci-deploy:
#   BAKE_FILE - Path to your application's docker-bake.hcl file
#
# The bake file must define:
#   - Image targets (context, dockerfile, tags)
#   - Variables for OCIR_PREFIX, TAG, and PLATFORM
#
# See docker-bake.hcl.example for a template.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

resolve_bake_file() {
  if [[ -z "${BAKE_FILE:-}" ]]; then
    error_exit "BAKE_FILE not set in .env.oci-deploy

Please add to your .env.oci-deploy:
  export BAKE_FILE=\"/path/to/your-app/docker-bake.hcl\"

See docker-bake.hcl.example for a template."
  fi

  # Verify file exists
  if [[ ! -f "$BAKE_FILE" ]]; then
    error_exit "Bake file not found: $BAKE_FILE"
  fi

  # Resolve to absolute path
  echo "$(cd "$(dirname "$BAKE_FILE")" && pwd)/$(basename "$BAKE_FILE")"
}

docker_login() {
  explain "OCIR (Oracle Cloud Infrastructure Registry) is OCI's container registry - like Docker Hub but private.
   We need to authenticate Docker to push images to OCIR.
   The username format is: <tenancy-namespace>/<oci-username>
   The password is an Auth Token (NOT your OCI password)."

  if [[ -n "${OCIR_AUTH_TOKEN:-}" ]]; then
    log "Using OCIR_AUTH_TOKEN from environment"
    echo "$OCIR_AUTH_TOKEN" | docker login "$OCIR_URL" -u "${TENANCY_NAMESPACE}/${OCI_USERNAME}" --password-stdin
  else
    run_cmd "Logging into OCIR container registry.
     • Registry URL: $OCIR_URL
     • Username: ${TENANCY_NAMESPACE}/${OCI_USERNAME}
     • Password: Your Auth Token (generate at OCI Console → Profile → Auth Tokens)" \
      docker login "$OCIR_URL" -u "${TENANCY_NAMESPACE}/${OCI_USERNAME}"
  fi

  success "Docker logged into OCIR"
}

setup_buildx() {
  explain "OCI's free tier uses Ampere A1 processors (ARM64 architecture).
   Since you might be building on an Intel/AMD Mac, we use 'docker buildx' to cross-compile for ARM64.
   Docker Bake will use this builder to build all images in parallel."

  # Setup buildx builder
  if ! docker buildx inspect multiarch > /dev/null 2>&1; then
    run_cmd "Creating Docker buildx builder for multi-architecture builds.
     • buildx uses QEMU emulation to build ARM64 images on x86 machines" \
      docker buildx create --name multiarch --use

    docker buildx inspect --bootstrap
  else
    docker buildx use multiarch
    log "Using existing 'multiarch' buildx builder"
  fi
}

build_images() {
  log "Using bake file: $BAKE_FILE"

  # Show what will be built
  print_section "Build Plan"
  explain "Docker Bake reads the docker-bake.hcl file and builds all defined targets in parallel.
   The OCIR_PREFIX variable is set to tag images for your OCI registry.
   Use --print to preview the build plan without actually building."

  run_cmd "Previewing build plan from docker-bake.hcl" \
    docker buildx bake -f "$BAKE_FILE" --print

  # Build and push all images
  print_section "Building and Pushing Images"

  run_cmd "Building and pushing all images defined in docker-bake.hcl
   • Registry prefix: ${OCIR_PREFIX}
   • Platform: linux/arm64 (for OCI Ampere A1 free tier)
   • All targets will be built in parallel" \
    docker buildx bake -f "$BAKE_FILE" --push

  success "All images built and pushed to OCIR"

  explain "All images are now in OCIR! You can verify at:
   OCI Console → Developer Services → Container Registry"
}

main() {
  print_section "Step 6: Build and Push Docker Images to OCIR"

  load_env
  verify_requirements

  # Check for Docker
  if ! command_exists "docker"; then
    error_exit "Docker is not installed. Run: brew install docker"
  fi

  # Resolve bake file from env var
  BAKE_FILE="$(resolve_bake_file)"

  # Export OCIR_PREFIX for docker-bake.hcl to use
  export OCIR_PREFIX

  log "Bake file: $BAKE_FILE"

  docker_login
  setup_buildx
  build_images
}

main "$@"
