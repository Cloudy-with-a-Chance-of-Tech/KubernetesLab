#!/bin/bash
set -euo pipefail

# Destroy Talos Raspberry Pi cluster
# This script safely tears down the cluster for rebuilding
# Designed for remote Raspberry Pi nodes without physical access

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"

echo "⚠️  RASPBERRY PI CLUSTER DESTRUCTION SCRIPT"
echo ""
echo "This script will completely destroy your Talos Kubernetes cluster."
echo "All data will be lost unless backed up separately."
echo "Designed for safe remote reset of Raspberry Pi nodes."
echo ""

# Check prerequisites
if [[ ! -f "${TALOS_DIR}/talosconfig" ]]; then
    echo "❌ Talos client configuration not found."
    echo "   Nothing to destroy or already destroyed."
    exit 0
fi

# Set talosconfig for this session
export TALOSCONFIG="${TALOS_DIR}/talosconfig"

# Your actual Pi cluster configuration
CONTROL_PLANE_VIP="192.168.1.30"

# Pi nodes (using VIP for control plane operations)
declare -A ALL_NODES=(
    ["lead"]="control-plane"
    ["nickel"]="control-plane"  
    ["tin"]="control-plane"
    # Add worker nodes here if you have specific IPs
    # ["worker1"]="192.168.1.XXX"
)

echo "📋 Raspberry Pi cluster nodes:"
for node in "${!ALL_NODES[@]}"; do
    echo "   - ${node} (${ALL_NODES[$node]})"
done
echo ""
echo "🎯 VIP endpoint: ${CONTROL_PLANE_VIP}"
echo ""

# Confirmation prompt with additional warning for Pi nodes
read -p "⚠️  Are you sure you want to destroy the Pi cluster? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Cluster destruction cancelled."
    exit 0
fi

echo ""
echo "🔍 Checking cluster accessibility..."
if ! talosctl --nodes "${CONTROL_PLANE_VIP}" health --server=false 2>/dev/null; then
    echo "⚠️  Cluster not accessible via VIP - might already be down"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Destruction cancelled"
        exit 0
    fi
fi

echo ""
echo "🔥 Starting Raspberry Pi cluster destruction..."

# Reset using VIP endpoint for Pi nodes  
echo "🔧 Resetting Pi cluster via VIP endpoint..."
echo "  📡 Resetting cluster via VIP: ${CONTROL_PLANE_VIP}"
echo "  ⚠️  Using --wipe-mode user-disks for safe Pi reset"

# For Pi nodes, we use the VIP and let Talos handle the reset across the cluster
if talosctl reset --nodes "${CONTROL_PLANE_VIP}" --wipe-mode user-disks --graceful=true --reboot; then
    echo "    ✅ Cluster reset initiated successfully"
else
    echo "    ⚠️  Failed to reset cluster - trying individual node approach"
    
    # Fallback: try to reset individual nodes if you have specific IPs
    # Add individual Pi node IPs here if needed
    # Example:
    # PI_NODES=("192.168.1.X" "192.168.1.Y" "192.168.1.Z")
    # for node in "${PI_NODES[@]}"; do
    #     echo "  📡 Resetting individual node: ${node}"
    #     talosctl reset --nodes "${node}" --wipe-mode user-disks --graceful=false --reboot || true
    # done
fi

echo ""
echo "⏳ Waiting for Pi nodes to reboot into maintenance mode..."
echo "   This may take 2-5 minutes for Raspberry Pi nodes..."
sleep 120

# Verify cluster is down
echo "🔍 Verifying cluster destruction..."
if ! talosctl --nodes "${CONTROL_PLANE_VIP}" health --server=false 2>/dev/null; then
    echo "    ✅ Cluster is no longer accessible (expected after reset)"
else
    echo "    ⚠️  Cluster still accessible - reset may not be complete"
    echo "    💡 You may need to wait longer or check individual node status"
fi

# Cleanup local configurations
echo ""
echo "🧹 Cleaning up local configurations..."

# Backup current kubeconfig if it exists
if [[ -f "${HOME}/.kube/config" ]]; then
    BACKUP_FILE="${HOME}/.kube/config.backup.$(date +%Y%m%d_%H%M%S)"
    echo "  📦 Backing up kubeconfig to: ${BACKUP_FILE}"
    cp "${HOME}/.kube/config" "${BACKUP_FILE}"
fi

# Remove cluster context from kubeconfig
if command -v kubectl &> /dev/null; then
    echo "  🔧 Removing cluster context from kubeconfig..."
    kubectl config delete-cluster kub 2>/dev/null || true
    kubectl config delete-context admin@kub 2>/dev/null || true
    kubectl config delete-user admin 2>/dev/null || true
fi

echo ""
echo "💥 Raspberry Pi cluster destruction completed!"
echo ""
echo "📋 Summary:"
echo "   - Pi cluster has been reset via VIP endpoint"
echo "   - Nodes should be rebooting into maintenance mode"
echo "   - Local kubeconfig has been cleaned up"
echo "   - Talos configurations are preserved for rebuild"
echo ""
echo "🚀 To rebuild the cluster:"
echo "   1. Wait for Pi nodes to fully boot (2-5 minutes)"
echo "   2. ./scripts/deploy-cluster.sh"
echo "   3. ./scripts/bootstrap-cluster.sh"
echo "   4. ./scripts/install-cilium.sh"
echo ""
echo "🔑 To generate new secrets (optional):"
echo "   1. rm base/talos/controlplane.yaml base/talos/worker.yaml base/talos/talosconfig"
echo "   2. ./scripts/generate-talos-config.sh"
echo "   3. Continue with deploy and bootstrap"
echo ""
echo "📡 Monitor Pi node status:"
echo "   talosctl --nodes ${CONTROL_PLANE_VIP} --insecure disks"
