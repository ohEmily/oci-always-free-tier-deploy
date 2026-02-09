"""
03b-nodepool-cloudfunc - Google Cloud Function replacement for 03b-create-nodepool-with-capacity-check.sh

Polls OCI for compute capacity and creates node pool when available.
Deploy to GCF and trigger with Cloud Scheduler every 1-2 minutes.

Environment variables required:
  OCI_TENANCY_OCID      - Your tenancy OCID
  OCI_REGION            - e.g., us-phoenix-1
  OCI_CLUSTER_OCID      - Cluster OCID from 03a script
  OCI_NODE_SUBNET_OCID  - Node subnet OCID from 02 script
  OCI_USER_OCID         - Your user OCID
  OCI_FINGERPRINT       - API key fingerprint
  OCI_PRIVATE_KEY       - API private key (PEM content, not path)

Optional:
  NODE_SHAPE            - Default: VM.Standard.A1.Flex
  NODE_OCPUS            - Default: 2
  NODE_MEMORY_GB        - Default: 12
  NODE_COUNT            - Default: 2
  KUBERNETES_VERSION    - Default: v1.32.1
  NODE_POOL_NAME        - Default: my-nodes
  NOTIFICATION_URL      - Webhook URL to notify on success (optional)

Return statuses:
  active         - Node pool is ACTIVE. Stop polling.
  creating       - Node pool creation is in progress (either just started or ongoing). Wait.
  no_capacity    - Capacity not available. Will retry on next invocation.
  stuck_deleted  - Stuck/failed node pool was deleted. Next invocation will retry.
  deleting       - A previous stuck pool is still being deleted. Wait.
  error          - Unexpected error occurred.
"""

import os
import json
import oci
from typing import Optional, Tuple
import urllib.request


def get_config() -> dict:
    """Build OCI config from environment variables."""
    private_key = os.environ.get("OCI_PRIVATE_KEY", "")

    return {
        "user": os.environ["OCI_USER_OCID"],
        "key_content": private_key,
        "fingerprint": os.environ["OCI_FINGERPRINT"],
        "tenancy": os.environ["OCI_TENANCY_OCID"],
        "region": os.environ["OCI_REGION"],
    }


def check_existing_nodepool(ce_client, compartment_id: str, cluster_id: str, name: str) -> Tuple[Optional[str], Optional[str]]:
    """
    Check for any existing node pool matching the name.

    Returns (nodepool_id, lifecycle_state) or (None, None) if no pool found.
    Searches across all non-terminal states.
    """
    NON_TERMINAL_STATES = {"ACTIVE", "CREATING", "UPDATING", "NEEDS_ATTENTION", "FAILED", "DELETING"}
    try:
        response = ce_client.list_node_pools(
            compartment_id=compartment_id,
            cluster_id=cluster_id,
            name=name,
        )
        for pool in (response.data or []):
            if pool.lifecycle_state in NON_TERMINAL_STATES:
                return pool.id, pool.lifecycle_state
    except Exception as e:
        print(f"Error checking existing node pool: {e}")
    return None, None


def is_nodepool_stuck(ce_client, nodepool_id: str) -> bool:
    """
    Check if a CREATING/UPDATING node pool is stuck due to capacity.

    A pool is stuck when all nodes have lifecycle_details containing
    'cannot create compute instance'.
    """
    try:
        response = ce_client.get_node_pool(node_pool_id=nodepool_id)
        nodes = response.data.nodes or []

        if not nodes:
            # No nodes yet — pool just started creating, not stuck
            print("  No nodes in pool yet, still initializing")
            return False

        stuck_count = 0
        for node in nodes:
            details = (node.lifecycle_details or "").lower()
            state = node.lifecycle_state or ""
            print(f"  Node {node.name}: state={state}, details={details}")
            if "cannot create compute instance" in details:
                stuck_count += 1

        if stuck_count == len(nodes):
            print(f"  All {len(nodes)} nodes stuck with capacity errors")
            return True

        print(f"  {stuck_count}/{len(nodes)} nodes stuck, not all — still progressing")
        return False

    except Exception as e:
        print(f"Error inspecting node pool nodes: {e}")
        return False


def delete_nodepool(ce_client, nodepool_id: str) -> bool:
    """Delete a stuck/failed node pool. Returns True if delete was initiated."""
    try:
        print(f"Deleting stuck node pool: {nodepool_id}")
        ce_client.delete_node_pool(node_pool_id=nodepool_id)
        return True
    except Exception as e:
        print(f"Error deleting node pool: {e}")
        return False


def check_capacity(compute_client, compartment_id: str, ad_name: str, shape: str, ocpus: int, memory_gb: int) -> bool:
    """Check if capacity is available for the requested shape."""
    try:
        response = compute_client.create_compute_capacity_report(
            create_compute_capacity_report_details=oci.core.models.CreateComputeCapacityReportDetails(
                compartment_id=compartment_id,
                availability_domain=ad_name,
                shape_availabilities=[
                    oci.core.models.CreateCapacityReportShapeAvailabilityDetails(
                        instance_shape=shape,
                        instance_shape_config=oci.core.models.CapacityReportInstanceShapeConfig(
                            ocpus=float(ocpus),
                            memory_in_gbs=float(memory_gb)
                        )
                    )
                ]
            )
        )

        status = response.data.shape_availabilities[0].availability_status
        print(f"Capacity status for {shape}: {status}")
        return status == "AVAILABLE"

    except Exception as e:
        print(f"Error checking capacity: {e}")
        return False


def get_node_image_id(ce_client, compartment_id: str, k8s_version: str, is_arm: bool) -> Optional[str]:
    """Get the appropriate OKE node image ID."""
    try:
        response = ce_client.get_node_pool_options(
            node_pool_option_id="all",
            compartment_id=compartment_id
        )

        version_prefix = k8s_version.lstrip("v")

        for source in response.data.sources:
            source_name = source.source_name or ""
            if version_prefix in source_name:
                if is_arm and "aarch64" in source_name:
                    return source.image_id
                elif not is_arm and "aarch64" not in source_name and "GPU" not in source_name:
                    return source.image_id

        # Fallback: any image with matching version
        for source in response.data.sources:
            if version_prefix in (source.source_name or ""):
                return source.image_id

    except Exception as e:
        print(f"Error getting node image: {e}")
    return None


def create_nodepool(ce_client, config: dict) -> dict:
    """Create the node pool."""
    create_details = oci.container_engine.models.CreateNodePoolDetails(
        compartment_id=config["compartment_id"],
        cluster_id=config["cluster_id"],
        name=config["node_pool_name"],
        kubernetes_version=config["k8s_version"],
        node_shape=config["node_shape"],
        node_shape_config=oci.container_engine.models.CreateNodeShapeConfigDetails(
            ocpus=float(config["ocpus"]),
            memory_in_gbs=float(config["memory_gb"])
        ),
        node_source_details=oci.container_engine.models.NodeSourceViaImageDetails(
            image_id=config["image_id"]
        ),
        node_config_details=oci.container_engine.models.CreateNodePoolNodeConfigDetails(
            size=config["node_count"],
            placement_configs=[
                oci.container_engine.models.NodePoolPlacementConfigDetails(
                    availability_domain=config["ad_name"],
                    subnet_id=config["subnet_id"]
                )
            ]
        )
    )

    response = ce_client.create_node_pool(create_node_pool_details=create_details)
    return {
        "work_request_id": response.headers.get("opc-work-request-id"),
        "status": "creating"
    }


def send_notification(url: str, message: str):
    """Send a webhook notification."""
    if not url:
        return
    try:
        data = json.dumps({"text": message}).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=10)
        print(f"Notification sent: {message}")
    except Exception as e:
        print(f"Failed to send notification: {e}")


def main(request=None):
    """
    Main entry point for Cloud Function.

    State machine:
      1. Check for existing node pool in any non-terminal state
      2. If ACTIVE         -> return "active" (stop polling)
      3. If CREATING       -> check if stuck (all nodes have capacity errors)
                              If stuck -> delete pool, return "stuck_deleted"
                              If progressing -> return "creating" (wait)
      4. If NEEDS_ATTENTION/FAILED -> delete pool, return "stuck_deleted"
      5. If DELETING       -> return "deleting" (wait for cleanup)
      6. If no pool exists -> check capacity -> create if available
    """
    try:
        # Load configuration
        oci_config = get_config()

        compartment_id = os.environ["OCI_TENANCY_OCID"]
        cluster_id = os.environ["OCI_CLUSTER_OCID"]
        subnet_id = os.environ["OCI_NODE_SUBNET_OCID"]

        node_shape = os.environ.get("NODE_SHAPE", "VM.Standard.A1.Flex")
        node_ocpus = int(os.environ.get("NODE_OCPUS", "2"))
        node_memory_gb = int(os.environ.get("NODE_MEMORY_GB", "12"))
        node_count = int(os.environ.get("NODE_COUNT", "2"))
        k8s_version = os.environ.get("KUBERNETES_VERSION", "v1.32.1")
        node_pool_name = os.environ.get("NODE_POOL_NAME", "my-nodes")
        notification_url = os.environ.get("NOTIFICATION_URL", "")

        is_arm = "A1" in node_shape

        # Initialize clients
        ce_client = oci.container_engine.ContainerEngineClient(oci_config)
        compute_client = oci.core.ComputeClient(oci_config)
        identity_client = oci.identity.IdentityClient(oci_config)

        # --- State machine: check existing node pool ---
        pool_id, pool_state = check_existing_nodepool(ce_client, compartment_id, cluster_id, node_pool_name)

        if pool_id:
            print(f"Found node pool {pool_id} in state: {pool_state}")

            if pool_state == "ACTIVE":
                print("Node pool is ACTIVE — done!")
                send_notification(notification_url,
                    f"✅ OCI Node Pool is ACTIVE: {pool_id}")
                return json.dumps({"status": "active", "nodepool_id": pool_id})

            elif pool_state in ("CREATING", "UPDATING"):
                print("Node pool is CREATING/UPDATING — checking if stuck...")
                if is_nodepool_stuck(ce_client, pool_id):
                    delete_nodepool(ce_client, pool_id)
                    return json.dumps({"status": "stuck_deleted", "deleted_id": pool_id,
                                       "message": "Stuck node pool deleted, will retry on next invocation"})
                else:
                    print("Node pool creation is progressing normally")
                    return json.dumps({"status": "creating", "nodepool_id": pool_id})

            elif pool_state in ("NEEDS_ATTENTION", "FAILED"):
                print(f"Node pool is {pool_state} — deleting to retry")
                delete_nodepool(ce_client, pool_id)
                return json.dumps({"status": "stuck_deleted", "deleted_id": pool_id,
                                   "message": f"Pool in {pool_state} state deleted, will retry on next invocation"})

            elif pool_state == "DELETING":
                print("Node pool is being deleted from a previous cleanup — waiting")
                return json.dumps({"status": "deleting", "nodepool_id": pool_id})

        # --- No existing pool: check capacity and create ---
        # Get availability domain
        ads = identity_client.list_availability_domains(compartment_id=compartment_id).data
        ad_name = ads[0].name
        print(f"Using availability domain: {ad_name}")

        # Check capacity
        if not check_capacity(compute_client, compartment_id, ad_name, node_shape, node_ocpus, node_memory_gb):
            print("Capacity not available, will retry on next invocation")
            return json.dumps({"status": "no_capacity"})

        # Capacity available! Get node image and create pool
        print("Capacity AVAILABLE! Creating node pool...")

        image_id = get_node_image_id(ce_client, compartment_id, k8s_version, is_arm)
        if not image_id:
            return json.dumps({"status": "error", "message": "Could not find node image"})

        result = create_nodepool(ce_client, {
            "compartment_id": compartment_id,
            "cluster_id": cluster_id,
            "node_pool_name": node_pool_name,
            "k8s_version": k8s_version,
            "node_shape": node_shape,
            "ocpus": node_ocpus,
            "memory_gb": node_memory_gb,
            "node_count": node_count,
            "image_id": image_id,
            "ad_name": ad_name,
            "subnet_id": subnet_id,
        })

        send_notification(notification_url,
            f"🎉 OCI Node Pool creation started! Work request: {result['work_request_id']}")

        return json.dumps({"status": "creating", **result})

    except Exception as e:
        error_msg = str(e)
        print(f"Error: {error_msg}")
        return json.dumps({"status": "error", "message": error_msg})


# For local testing
if __name__ == "__main__":
    print(main())
