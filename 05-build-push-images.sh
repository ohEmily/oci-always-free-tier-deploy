#!/bin/bash
# 05-build-push-images.sh - Build and push Docker images to OCIR
#
# Usage: ./05-build-push-images.sh
#
# This script:
#   1. Logs into OCIR container registry
#   2. Sets up Docker buildx for ARM64 cross-compilation
#   3. Builds all 5 service images for ARM64 (Ampere A1 architecture)
#   4. Pushes images directly to OCIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

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

build_images() {
  explain "OCI's free tier uses Ampere A1 processors (ARM64 architecture).
   Since you might be building on an Intel/AMD Mac, we use 'docker buildx' to cross-compile for ARM64.
   Each image will be built and pushed directly to OCIR."

  PROJECT_ROOT="$(get_project_root)"
  cd "$PROJECT_ROOT"

  log "Working from project root: $(pwd)"

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

  # Build and push each image
  local images=("backend" "frontend" "realtime")
  
  for image in "${images[@]}"; do
    print_section "Building $image image"
    
    run_cmd "Building and pushing ARM64 image for $image
     • Source: ./${image}/Dockerfile
     • Target: ${OCIR_PREFIX}/shouldiwalk-${image}:latest" \
      docker buildx build --platform linux/arm64 \
        -t "${OCIR_PREFIX}/shouldiwalk-${image}:latest" \
        --push "./${image}"
    
    success "${image} image pushed to OCIR"
  done

  # Build special images that need different contexts
  print_section "Building db-migrate image"
  run_cmd "Building and pushing ARM64 image for db-migrate
   • Source: ./migrations/Dockerfile
   • Target: ${OCIR_PREFIX}/shouldiwalk-db-migrate:latest" \
    docker buildx build --platform linux/arm64 \
      -t "${OCIR_PREFIX}/shouldiwalk-db-migrate:latest" \
      --push ./migrations
  success "db-migrate image pushed to OCIR"

  print_section "Building airflow image"
  run_cmd "Building and pushing ARM64 image for airflow
   • Source: ./dags/Dockerfile.airflow (builds from repo root for context)
   • Target: ${OCIR_PREFIX}/shouldiwalk-airflow:latest" \
    docker buildx build --platform linux/arm64 \
      -t "${OCIR_PREFIX}/shouldiwalk-airflow:latest" \
      -f dags/Dockerfile.airflow --push .
  success "airflow image pushed to OCIR"

  explain "All 5 images are now in OCIR! You can verify at:
   OCI Console → Developer Services → Container Registry"
}

main() {
  print_section "Step 5: Build and Push Docker Images to OCIR"

  load_env
  verify_requirements

  # Check for Docker
  if ! command_exists "docker"; then
    error_exit "Docker is not installed. Run: brew install docker"
  fi

  docker_login
  build_images
}

main "$@"
