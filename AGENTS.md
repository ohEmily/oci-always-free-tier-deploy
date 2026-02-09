# Agent Instructions for OCI Deploy Scripts

This document provides instructions for AI agents working with this repository and related application repositories.

## Overview

This repository (`oci-deploy-scripts`) contains deployment scripts for Oracle Cloud Infrastructure (OCI). It is designed to be **separate from application source code** — the application repository contains the code and Dockerfiles, while this repository handles the deployment infrastructure.

## Docker Bake for Image Builds

The `06-build-push-images.sh` script uses **Docker Bake** (`docker buildx bake`) to build and push container images. Docker Bake is the standard Docker mechanism for defining multi-image builds.

### How It Works

1. **Application repository** contains a `docker-bake.hcl` file that defines what images to build
2. **oci-deploy-scripts** reads that file and handles authentication, buildx setup, and pushing to OCIR

This separation allows:
- Application repos to own their image definitions (what to build)
- Deploy scripts to own the infrastructure (how to build and where to push)

## Creating a docker-bake.hcl in an Application Repository

When working with an application repository that will be deployed using these scripts, create a `docker-bake.hcl` file in the repository root.

### Required Structure

```hcl
# docker-bake.hcl

# Variables - these are set by oci-deploy-scripts at build time
variable "OCIR_PREFIX" {
  default = ""
  description = "Container registry prefix (e.g., iad.ocir.io/namespace)"
}

variable "TAG" {
  default = "latest"
  description = "Image tag"
}

variable "PLATFORM" {
  default = "linux/arm64"
  description = "Target platform (linux/arm64 for OCI free tier)"
}

# Group that defines which targets to build by default
group "default" {
  targets = ["target1", "target2"]  # List all image targets
}

# One target block per Docker image
target "target1" {
  context    = "./path/to/context"      # Directory containing Dockerfile
  dockerfile = "Dockerfile"              # Dockerfile name (relative to context)
  tags       = OCIR_PREFIX != "" ? ["${OCIR_PREFIX}/image-name:${TAG}"] : ["image-name:${TAG}"]
  platforms  = [PLATFORM]
}
```

### Key Points

1. **Variables**: Always include `OCIR_PREFIX`, `TAG`, and `PLATFORM` variables
   - `OCIR_PREFIX` is set by the deploy script to point to the OCI registry
   - These allow the same bake file to work locally (no prefix) and in CI/CD (with prefix)

2. **Default group**: List all targets that should be built during deployment

3. **Target blocks**: One per Docker image, with:
   - `context`: Build context directory
   - `dockerfile`: Dockerfile path (relative to context, or absolute with `-f`)
   - `tags`: Conditional tags that work with or without registry prefix
   - `platforms`: Target architecture (use `linux/arm64` for OCI free tier)

### Example: Multi-Service Application

```hcl
variable "OCIR_PREFIX" {
  default = ""
}

variable "TAG" {
  default = "latest"
}

variable "PLATFORM" {
  default = "linux/arm64"
}

variable "PROJECT" {
  default = "myapp"
}

group "default" {
  targets = ["api", "worker", "frontend", "migrations"]
}

target "api" {
  context    = "./api"
  dockerfile = "Dockerfile"
  tags       = OCIR_PREFIX != "" ? ["${OCIR_PREFIX}/${PROJECT}-api:${TAG}"] : ["${PROJECT}-api:${TAG}"]
  platforms  = [PLATFORM]
}

target "worker" {
  context    = "./worker"
  dockerfile = "Dockerfile"
  tags       = OCIR_PREFIX != "" ? ["${OCIR_PREFIX}/${PROJECT}-worker:${TAG}"] : ["${PROJECT}-worker:${TAG}"]
  platforms  = [PLATFORM]
}

target "frontend" {
  context    = "./frontend"
  dockerfile = "Dockerfile"
  tags       = OCIR_PREFIX != "" ? ["${OCIR_PREFIX}/${PROJECT}-frontend:${TAG}"] : ["${PROJECT}-frontend:${TAG}"]
  platforms  = [PLATFORM]
}

target "migrations" {
  context    = "./migrations"
  dockerfile = "Dockerfile"
  tags       = OCIR_PREFIX != "" ? ["${OCIR_PREFIX}/${PROJECT}-migrations:${TAG}"] : ["${PROJECT}-migrations:${TAG}"]
  platforms  = [PLATFORM]
}
```

### Special Cases

**Dockerfile in a different location than context:**
```hcl
target "special" {
  context    = "."                        # Use repo root as context
  dockerfile = "docker/Dockerfile.special" # Dockerfile elsewhere
  tags       = OCIR_PREFIX != "" ? ["${OCIR_PREFIX}/special:${TAG}"] : ["special:${TAG}"]
  platforms  = [PLATFORM]
}
```

**Build arguments:**
```hcl
target "with-args" {
  context    = "./app"
  dockerfile = "Dockerfile"
  tags       = OCIR_PREFIX != "" ? ["${OCIR_PREFIX}/app:${TAG}"] : ["app:${TAG}"]
  platforms  = [PLATFORM]
  args = {
    NODE_ENV = "production"
    VERSION  = TAG
  }
}
```

## Using the Deploy Scripts

### Building Images from an Application Repository

```bash
# From within oci-deploy-scripts directory
./06-build-push-images.sh --bake-file /path/to/app-repo/docker-bake.hcl

# Or with the short flag
./06-build-push-images.sh -f /path/to/app-repo/docker-bake.hcl
```

### Environment Requirements

The deploy scripts require:
1. `.env.oci-deploy` file with OCI credentials (see `.env.oci-deploy.example`)
2. `config.sh` with deployment configuration
3. Docker with buildx support

### Preview Without Building

To see what would be built without actually building:
```bash
cd /path/to/app-repo
docker buildx bake --print
```

## Updating Kustomize Overlays

When images are built, Kubernetes manifests need to reference the correct image names. In Kustomize overlays, use the `images` section:

```yaml
# k8s/overlays/oci/kustomization.yaml
images:
  - name: myapp-api           # Original name in base manifests
    newName: iad.ocir.io/namespace/myapp-api
    newTag: latest
  - name: myapp-worker
    newName: iad.ocir.io/namespace/myapp-worker
    newTag: latest
```

The image names in `kustomization.yaml` should match the tags defined in `docker-bake.hcl`.

## Reference

- [Docker Bake Documentation](https://docs.docker.com/build/bake/)
- [Docker Bake File Reference](https://docs.docker.com/build/bake/reference/)
- [docker-bake.hcl.example](./docker-bake.hcl.example) in this repository
