#!/bin/bash
set -euo pipefail

# Bootstrap control plane. k8s-cp-02 is provisioned as a future control-plane
# candidate, but this script intentionally joins workers only.
MASTER_NODE="192.168.17.11"
SSH_USER="kubereats"
SSH_OPTIONS="-o StrictHostKeyChecking=no -i tf-cloud-init"
LOCAL_KUBE_DIR="$HOME/.kube"
LOCAL_KUBE_CONFIG="$LOCAL_KUBE_DIR/config"

# Format: KubernetesNodeName=NodeIPAddress
WORKER_NODES=(
  "k8s-worker-a1=192.168.17.21"
  "k8s-worker-a2=192.168.17.22"
  "k8s-worker-b1=192.168.17.31"
  "k8s-worker-b2=192.168.17.32"
)

HYBRID_NEG_ENDPOINTS=(
  "192.168.17.21:30443"
  "192.168.17.22:30443"
  "192.168.17.31:30443"
  "192.168.17.32:30443"
)

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

for cmd in ssh scp; do
  if ! command_exists "$cmd"; then
    echo "Error: required command '$cmd' not found. Please install it and try again."
    exit 1
  fi
done

echo "=== Kubernetes Worker Join Script ==="
echo "Bootstrap control plane: $MASTER_NODE"
echo ""

check_node_exists() {
  local node_name=$1
  local node_check
  node_check=$(ssh $SSH_OPTIONS "$SSH_USER@$MASTER_NODE" "sudo kubectl get nodes -o wide | grep -w '$node_name' || true")

  if [[ -n "$node_check" ]]; then
    echo "Node $node_name is already part of the cluster with status:"
    echo "$node_check"
    return 0
  fi

  return 1
}

check_kubelet_active() {
  local node_ip=$1
  local kubelet_status
  kubelet_status=$(ssh $SSH_OPTIONS "$SSH_USER@$node_ip" "sudo systemctl is-active kubelet || echo inactive")

  if [[ "$kubelet_status" == "active" ]]; then
    echo "Kubelet is already active on $node_ip. Node may be part of a cluster."
    return 0
  fi

  echo "Kubelet is not active on $node_ip."
  return 1
}

echo "Retrieving join command from bootstrap control plane..."
JOIN_COMMAND=$(ssh $SSH_OPTIONS "$SSH_USER@$MASTER_NODE" "sudo kubeadm token create --print-join-command")

if [[ -z "$JOIN_COMMAND" ]]; then
  echo "Error: failed to retrieve join command from bootstrap control plane."
  exit 1
fi

echo "Retrieved join command successfully."
echo ""

for node_entry in "${WORKER_NODES[@]}"; do
  node_name="${node_entry%%=*}"
  node_ip="${node_entry#*=}"

  echo "Processing $node_name ($node_ip)..."

  if ! ssh $SSH_OPTIONS "$SSH_USER@$node_ip" "exit" >/dev/null 2>&1; then
    echo "Warning: cannot connect to $node_ip. Skipping $node_name."
    continue
  fi

  if check_node_exists "$node_name"; then
    echo "Skipping join process for $node_name."
    echo ""
    continue
  fi

  if check_kubelet_active "$node_ip"; then
    echo "Kubelet is active but $node_name is not registered. Resetting Kubernetes on $node_name..."
    ssh $SSH_OPTIONS "$SSH_USER@$node_ip" "sudo kubeadm reset -f"
    echo "Reset completed on $node_name."
  fi

  echo "Joining $node_name ($node_ip) to the cluster..."
  ssh $SSH_OPTIONS "$SSH_USER@$node_ip" "sudo $JOIN_COMMAND"

  echo "Join command completed for $node_name. Verifying registration..."
  sleep 10
  if check_node_exists "$node_name"; then
    echo "Verified $node_name is now part of the cluster."
  else
    echo "Warning: $node_name was not found in the cluster after join command."
  fi

  echo ""
done

echo "Final cluster status:"
ssh $SSH_OPTIONS "$SSH_USER@$MASTER_NODE" "sudo kubectl get nodes -o wide"

echo ""
echo "Planned GCP Hybrid NEG ingress endpoints:"
printf '  %s
' "${HYBRID_NEG_ENDPOINTS[@]}"

echo ""
echo "=== Copying Kubernetes admin config to local machine ==="

if [[ ! -d "$LOCAL_KUBE_DIR" ]]; then
  echo "Creating local directory $LOCAL_KUBE_DIR..."
  mkdir -p "$LOCAL_KUBE_DIR"
fi

if [[ -f "$LOCAL_KUBE_CONFIG" ]]; then
  echo "Backing up existing kubectl config to ${LOCAL_KUBE_CONFIG}.bak..."
  cp "$LOCAL_KUBE_CONFIG" "${LOCAL_KUBE_CONFIG}.bak"
fi

echo "Creating a temporary copy of admin.conf with correct permissions..."
ssh $SSH_OPTIONS "$SSH_USER@$MASTER_NODE" "sudo cp /etc/kubernetes/admin.conf /tmp/k8s-admin.conf && sudo chmod 644 /tmp/k8s-admin.conf && sudo chown $SSH_USER:$SSH_USER /tmp/k8s-admin.conf"

echo "Copying Kubernetes admin config from $MASTER_NODE to local machine..."
scp $SSH_OPTIONS "$SSH_USER@$MASTER_NODE:/tmp/k8s-admin.conf" "$LOCAL_KUBE_CONFIG"

ssh $SSH_OPTIONS "$SSH_USER@$MASTER_NODE" "rm /tmp/k8s-admin.conf"

if [[ -f "$LOCAL_KUBE_CONFIG" ]]; then
  echo "Successfully copied admin.conf to $LOCAL_KUBE_CONFIG"
  chmod 600 "$LOCAL_KUBE_CONFIG"

  if command_exists kubectl; then
    echo "Testing connection to cluster..."
    kubectl --kubeconfig="$LOCAL_KUBE_CONFIG" get nodes
  else
    echo "kubectl not found. Install it to manage your cluster from this machine."
  fi
else
  echo "Failed to copy admin.conf from bootstrap control plane."
fi

echo ""
echo "=== Worker join process completed ==="
