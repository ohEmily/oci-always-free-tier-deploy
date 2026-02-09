# OCI Deployment Scripts

Modular, well-documented scripts for deploying applications to Oracle Cloud Infrastructure (OCI) using OKE (Oracle Kubernetes Engine).

## Quick Start

1. **Create an OCI account and configure the CLI** (see [Prerequisites](#prerequisites) below)

2. **Set up environment configuration:**
   ```bash
   cp .env.oci-deploy.example .env.oci-deploy
   # Edit .env.oci-deploy with your OCI credentials and configuration
   ```

3. **Run the deployment step-by-step:**
   ```bash
   ./01-verify-cli.sh           # Verify OCI CLI works
   ./02-create-networking.sh    # Create VCN (~2 min)
   ./03-create-cluster.sh       # Create OKE cluster (~10 min)
   ./04-create-nodepool.sh      # Poll for A1 capacity and create nodes
   ./05-configure-kubectl.sh    # Configure kubectl
   ./06-build-push-images.sh    # Build and push images (~20-30 min)
   ./07-setup-kubernetes.sh     # Create namespace and secrets
   ./08-deploy-application.sh   # Deploy application
   ./09-verify-deployment.sh    # Verify deployment
   ```

## Script Structure

### Configuration

All configuration is in **`.env.oci-deploy`** (not version controlled, since it contains secrets).

Copy the example and edit with your values:
```bash
cp .env.oci-deploy.example .env.oci-deploy
```

### Shared Library
- [`lib/common.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/lib/common.sh) - Reusable functions for all scripts
  - Logging and output formatting
  - Environment variable loading
  - OCI/kubectl utility functions
  - Error handling

### Step Scripts (Run Sequentially)

1. [`01-verify-cli.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/01-verify-cli.sh) - Verify OCI CLI is installed and configured
   - Checks OCI CLI credentials work
   - Required: oci-cli installed

2. [`02-create-networking.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/02-create-networking.sh) - Create VCN and networking
   - Creates Virtual Cloud Network (VCN)
   - Creates Internet Gateway for external connectivity
   - Creates Route Table with public routing
   - Creates Public Subnet for Kubernetes nodes

3. [`03-create-cluster.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/03-create-cluster.sh) - Create OKE Kubernetes cluster
   - Creates managed Kubernetes control plane
   - ⏱️ Takes 5-10 minutes

4. [`04-create-nodepool.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/04-create-nodepool.sh) - Create node pool with capacity polling
   - Polls for A1 capacity (free tier ARM instances are often constrained)
   - Creates node pool when capacity is available
   - Use `caffeinate ./04-create-nodepool.sh` to prevent sleep during polling
   - See [`03b-nodepool-cloudfunc/`](https://github.com/ohEmily/oci-always-free-tier-deploy/tree/main/03b-nodepool-cloudfunc) for a Python/GCF alternative

5. [`05-configure-kubectl.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/05-configure-kubectl.sh) - Configure kubectl access
   - Generates kubeconfig file
   - Verifies kubectl can connect to cluster
   - Uses OCI CLI for automatic token refresh

6. [`06-build-push-images.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/06-build-push-images.sh) - Build and push Docker images
   - Logs into OCIR (Oracle Container Registry)
   - Sets up Docker buildx for ARM64 cross-compilation
   - Reads `docker-bake.hcl` from the application repository
   - Builds all images defined in the bake file in parallel
   - Pushes images directly to OCIR
   - Reads `BAKE_FILE` path from `.env.oci-deploy`

7. [`07-setup-kubernetes.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/07-setup-kubernetes.sh) - Set up Kubernetes namespace and secrets
   - Creates application namespace
   - Creates docker-registry secret for OCIR authentication
   - Configures image pull secrets for deployments

8. [`08-deploy-application.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/08-deploy-application.sh) - Deploy application with Kustomize
   - Applies Kustomize manifests from `k8s/overlays/oci/`
   - Creates all Kubernetes resources (Deployments, Services, Jobs, etc.)
   - Watches pod status until ready

9. [`09-verify-deployment.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/09-verify-deployment.sh) - Verify deployment is healthy
   - Checks job logs
   - Lists all pods and their status
   - Lists all services

### Utility Scripts

- [`port-forward.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/port-forward.sh) - Port forward services to localhost
  ```bash
  ./port-forward.sh <service-name>    # Forward to localhost
  ```

- [`cleanup-oci.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/cleanup-oci.sh) - Delete OCI resources to avoid billing
  ```bash
  ./cleanup-oci.sh        # Delete cluster and node pool (keep networking)
  ./cleanup-oci.sh --all  # Delete everything including VCN
  ```

## Environment Configuration

All configuration is in `.env.oci-deploy`. Copy the example and fill in your values:

```bash
cp .env.oci-deploy.example .env.oci-deploy
```

The file includes:
- **OCI Account** - Tenancy/User OCIDs, region, auth token
- **Kubernetes** - Cluster name, namespace, K8s version
- **Node Pool** - Shape, count, CPU/memory (defaults to free-tier ARM)
- **Network** - VCN/subnet names and CIDRs
- **Docker Bake** - Path to your application's `docker-bake.hcl`

See `.env.oci-deploy.example` for all options with comments

## Prerequisites

### Installed Tools
- `oci-cli` - Oracle Cloud CLI
  ```bash
  brew install oci-cli
  ```
- `kubectl` - Kubernetes CLI
  ```bash
  brew install kubectl
  ```
- `docker` - Container runtime
  ```bash
  brew install docker
  ```
- `jq` - JSON processor
  ```bash
  brew install jq
  ```

### OCI Configuration
1. Create an OCI account: https://www.oracle.com/cloud/free/
2. Configure OCI CLI:
   ```bash
   oci setup config
   ```
3. Generate auth token for OCIR:
   - OCI Console → Profile → Auth Tokens
   - Generate Token
   - Copy and save (you'll need it when running `06-build-push-images.sh`)

### Network Requirements
- Internet access (images downloaded during builds)
- Outbound access to OCI API endpoints
- Ability to create VCNs and OKE clusters in your OCI account

## Workflow

```bash
# 1. Verify your OCI CLI is configured
./01-verify-cli.sh

# 2. Create VCN and networking (2 minutes)
./02-create-networking.sh

# 3. Create Kubernetes cluster (5-10 minutes)
./03-create-cluster.sh

# 4. Create node pool (polls for capacity, may take a while)
caffeinate ./04-create-nodepool.sh

# 5. Configure kubectl once cluster is ready
./05-configure-kubectl.sh

# 6. Build and push Docker images (20-30 minutes)
# Uses BAKE_FILE from .env.oci-deploy
./06-build-push-images.sh

# 7. Set up Kubernetes namespace and secrets
./07-setup-kubernetes.sh

# 8. Deploy application
./08-deploy-application.sh

# 9. Verify everything is running
./09-verify-deployment.sh

# 10. Access your application
./port-forward.sh <service-name>
```

## Troubleshooting

### Script fails to find environment variables
```bash
# Make sure .env.oci-deploy exists and is readable
ls -la .env.oci-deploy

# Source it manually
source .env.oci-deploy
```

### OCI CLI not authenticated
```bash
# Reconfigure OCI CLI
oci setup config

# Verify authentication
oci iam region list
```

### Docker buildx issues
```bash
# Create/reset buildx builder
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap
```

### Pod stuck in Pending state
```bash
# Check node resources
kubectl describe nodes

# Check pod events
kubectl describe pod -n <namespace> <pod-name>

# Check pod logs
kubectl logs -n <namespace> <pod-name>
```

### Image pull errors
```bash
# Verify secret is created
kubectl get secrets -n <namespace>

# Check OCIR login
docker login <region-key>.ocir.io

# Verify image exists in OCIR
# (OCI Console → Developer Services → Container Registry)
```

## Costs & Always Free Tier Limits

This deployment is designed to use OCI's Always Free tier:
- **OKE Control Plane** - FREE
- **Compute (Ampere A1)** - 4 OCPUs / 24 GB total across all A1 instances - FREE
- **Block Volume Storage** - 200 GB total (shared between boot volumes and block volumes) - FREE
- **Container Registry (OCIR)** - Storage costs apply (~$0.01/GB/month)
- **Network** - 10 TB/month outbound - FREE

**Total Monthly Cost:** ~$0-5 (mostly OCIR storage)

### Block Volume Budget

The 200 GB free tier block volume storage is shared across **all** boot volumes and block volumes:

- Node boot volumes: ~47 GB each (minimum per OKE node)
- Any PVCs using `oci-bv` StorageClass: 50 GB minimum per volume

The `oci-bv` StorageClass (OCI Block Volume CSI driver) has a **minimum volume size of 50 GB**, regardless of what the PVC requests.

### Region Constraint

Your home region is set at account creation and **cannot be changed** on the free tier. Always Free resources can only be created in the home region. If A1 capacity is unavailable, you must wait and retry — you cannot switch regions without upgrading to a paid account.

If you exceed free tier limits, additional resources will incur charges.

### A1 Instance Availability Tip

**Upgrade from Free Trial to Pay As You Go (PAYG)** to dramatically improve your chances of getting A1 instances.

During the 30-day free trial, you're competing with many other trial accounts for limited A1 capacity. After upgrading to PAYG:
- You still get the same Always Free resources at no cost
- A1 instances become much easier to provision
- You won't be charged unless you exceed free tier limits

To upgrade: OCI Console → Billing → Upgrade to Paid Account

This is the single most effective way to resolve "Out of host capacity" errors for A1 instances.

## Cleanup

To tear down the deployment:

```bash
# Delete Kubernetes resources
kubectl delete namespace <namespace>

# Delete OKE cluster (OCI Console or CLI)
oci ce cluster delete --cluster-id <cluster-ocid>

# Delete VCN resources (OCI Console or CLI)
oci network vcn delete --vcn-id <vcn-ocid>

# Clear saved OCIDs
rm -f /tmp/oci-deploy-ocids.env
```

## What Each Script Teaches You

These scripts are designed to be educational:

- [`01-verify-cli.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/01-verify-cli.sh) - How OCI CLI authentication works
- [`02-create-networking.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/02-create-networking.sh) - VCN architecture, routing, subnets
- [`03-create-cluster.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/03-create-cluster.sh) - Kubernetes managed services
- [`04-create-nodepool.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/04-create-nodepool.sh) - Capacity polling, node pool creation
- [`05-configure-kubectl.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/05-configure-kubectl.sh) - kubeconfig and token-based auth
- [`06-build-push-images.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/06-build-push-images.sh) - Docker Bake, buildx, ARM64 cross-compilation, registry auth
- [`07-setup-kubernetes.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/07-setup-kubernetes.sh) - Kubernetes secrets and image pull authentication
- [`08-deploy-application.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/08-deploy-application.sh) - Kustomize, declarative infrastructure
- [`09-verify-deployment.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/09-verify-deployment.sh) - Kubernetes debugging and troubleshooting
- [`cleanup-oci.sh`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/cleanup-oci.sh) - Resource cleanup and teardown

Each script prints the commands it runs so you can learn by reading the output.

## Documentation

For more information:
- **OCI Documentation**: https://docs.oracle.com/
- **OKE Guide**: https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm
- **OCI Always Free Tier**: https://www.oracle.com/cloud/free/
- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **Kustomize Guide**: https://kustomize.io/

## Docker Bake for Image Builds

This repository uses [Docker Bake](https://docs.docker.com/build/bake/) for building container images. Docker Bake allows application repositories to define their image builds in a declarative `docker-bake.hcl` file.

### How It Works

1. Your application repository contains a `docker-bake.hcl` file defining what images to build
2. The `06-build-push-images.sh` script reads that file and handles:
   - OCIR authentication
   - Docker buildx setup for ARM64 cross-compilation
   - Building all images in parallel
   - Pushing to the OCI Container Registry

### Creating a docker-bake.hcl

See [`docker-bake.hcl.example`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/docker-bake.hcl.example) for a template. The basic structure:

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

group "default" {
  targets = ["api", "worker"]
}

target "api" {
  context    = "./api"
  dockerfile = "Dockerfile"
  tags       = OCIR_PREFIX != "" ? ["${OCIR_PREFIX}/myapp-api:${TAG}"] : ["myapp-api:${TAG}"]
  platforms  = [PLATFORM]
}

target "worker" {
  context    = "./worker"
  dockerfile = "Dockerfile"
  tags       = OCIR_PREFIX != "" ? ["${OCIR_PREFIX}/myapp-worker:${TAG}"] : ["myapp-worker:${TAG}"]
  platforms  = [PLATFORM]
}
```

### Building Images

```bash
# Set BAKE_FILE in .env.oci-deploy, then run:
./06-build-push-images.sh

# Preview what will be built (from the app repo)
cd /path/to/your-app
docker buildx bake --print
```

For detailed instructions for AI agents, see [`AGENTS.md`](https://github.com/ohEmily/oci-always-free-tier-deploy/blob/main/AGENTS.md).
