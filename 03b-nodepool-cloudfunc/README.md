# 03b-nodepool-cloudfunc

Cloud Function replacement for `03b-create-nodepool-with-capacity-check.sh`.

Polls OCI for compute capacity and creates the node pool when available. Runs on GCP free tier.

## Prerequisites

1. Run scripts `01`, `02`, and `03a` locally first to create:
   - VCN and subnets (get `NODE_SUBNET_OCID` from `/tmp/oci-deploy-ocids.env`)
   - OKE cluster (get `CLUSTER_OCID` from `/tmp/oci-deploy-ocids.env`)

2. Have an OCI API key (the private key PEM content, not the file path)

## Deploy to Google Cloud Functions

```bash
# Set your GCP project
gcloud config set project YOUR_PROJECT_ID

# Load environment variables in a subshell (avoids polluting your shell)
(
  set -a
  source ../.env.oci-deploy
  source /tmp/oci-deploy-ocids.env
  set +a

  # Deploy the function using inline env vars
  gcloud functions deploy oci-nodepool-checker \
    --gen2 \
    --runtime=python311 \
    --region=us-central1 \
    --source=. \
    --entry-point=main \
    --trigger-http \
    --allow-unauthenticated \
    --set-env-vars="OCI_TENANCY_OCID=${TENANCY_OCID},OCI_REGION=${REGION},OCI_CLUSTER_OCID=${CLUSTER_OCID},OCI_NODE_SUBNET_OCID=${NODE_SUBNET_OCID},OCI_USER_OCID=${OCI_USER_OCID},OCI_FINGERPRINT=${OCI_FINGERPRINT},NODE_SHAPE=${NODE_SHAPE},NODE_OCPUS=${NODE_OCPUS},NODE_MEMORY_GB=${NODE_MEMORY_GB},NODE_COUNT=${NODE_COUNT},KUBERNETES_VERSION=${KUBERNETES_VERSION},NODE_POOL_NAME=${NODE_POOL_NAME}"
)

# Set the private key separately (it's multiline)
gcloud functions deploy oci-nodepool-checker \
  --update-env-vars="OCI_PRIVATE_KEY=$(cat ~/.oci/oci_api_key.pem)"
```

## Set up Cloud Scheduler (to run every minute)

```bash
# Create a scheduler job
gcloud scheduler jobs create http oci-capacity-poller \
  --location=us-central1 \
  --schedule="* * * * *" \
  --uri="https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/oci-nodepool-checker" \
  --http-method=GET
```

## Environment Variables

**Required:**
| Variable | Description |
|----------|-------------|
| `OCI_TENANCY_OCID` | Your tenancy OCID |
| `OCI_REGION` | e.g., `us-phoenix-1` |
| `OCI_CLUSTER_OCID` | From script 03a output |
| `OCI_NODE_SUBNET_OCID` | From script 02 output |
| `OCI_USER_OCID` | Your user OCID |
| `OCI_FINGERPRINT` | API key fingerprint |
| `OCI_PRIVATE_KEY` | Full PEM content of your API private key |

**Optional:**
| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_SHAPE` | `VM.Standard.A1.Flex` | Instance shape |
| `NODE_OCPUS` | `2` | OCPUs per node |
| `NODE_MEMORY_GB` | `12` | Memory per node |
| `NODE_COUNT` | `2` | Number of nodes |
| `KUBERNETES_VERSION` | `v1.32.1` | K8s version |
| `NODE_POOL_NAME` | `my-nodes` | Node pool name |
| `NOTIFICATION_URL` | (none) | Webhook URL for success notification |

## Monitoring

Check logs:
```bash
gcloud functions logs read oci-nodepool-checker --gen2 --region=us-central1
```

## Cleanup

Once the node pool is created, disable or delete the scheduler:
```bash
gcloud scheduler jobs delete oci-capacity-poller --location=us-central1
gcloud functions delete oci-nodepool-checker --gen2 --region=us-central1
```

## Return Values

The function returns JSON:
- `{"status": "exists", "nodepool_id": "..."}` - Node pool already exists
- `{"status": "no_capacity"}` - Capacity not available, will retry next invocation
- `{"status": "creating", "work_request_id": "..."}` - Creation started!
- `{"status": "error", "message": "..."}` - Error occurred
