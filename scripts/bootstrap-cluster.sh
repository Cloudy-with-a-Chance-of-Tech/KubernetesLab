#!/bin/bash
set -euo pipefail

# Bootstrap Talos Kubernetes cluster
# This script initializes the cluster and sets up essential components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"

echo "🚀 Bootstrapping Talos Kubernetes cluster..."

# Check prerequisites
if [[ ! -f "${TALOS_DIR}/talosconfig" ]]; then
    echo "❌ Talos client configuration not found."
    echo "   You need a working talosconfig in ${TALOS_DIR}/talosconfig"
    echo "   Copy from your existing setup or run: ./scripts/generate-talos-config.sh"
    exit 1
fi

# Set talosconfig for this session
export TALOSCONFIG="${TALOS_DIR}/talosconfig"

# Your cluster configuration
CONTROL_PLANE_VIP="192.168.1.30"
BOOTSTRAP_NODE="192.168.1.30"  # Use VIP for bootstrap
CLUSTER_NAME="kub"

echo "📋 Cluster: ${CLUSTER_NAME}"
echo "📋 Control plane VIP: ${CONTROL_PLANE_VIP}"  
echo "📋 Bootstrap endpoint: ${BOOTSTRAP_NODE}"
echo ""

# Check if cluster is already bootstrapped
echo "🔍 Checking cluster status..."
if talosctl --nodes "${BOOTSTRAP_NODE}" health --server=false 2>/dev/null; then
    echo "✅ Cluster appears to be accessible"
    
    # Check if etcd is already running
    if talosctl --nodes "${BOOTSTRAP_NODE}" service etcd status 2>/dev/null | grep -q "Running"; then
        echo "✅ etcd service is already running"
        echo "🔄 Cluster appears to be already bootstrapped"
        
        read -p "⚠️  Cluster seems bootstrapped. Continue anyway? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Bootstrap cancelled by user"
            echo "💡 Use ./scripts/cluster-status.sh to check cluster health"
            exit 0
        fi
    else
        echo "⚠️  Cluster accessible but etcd not running - proceeding with bootstrap"
    fi
else
    echo "⚠️  Cluster not accessible - this might be initial bootstrap"
fi

echo ""

# Wait for nodes to be ready
echo "⏳ Waiting for bootstrap node to be ready..."
timeout=300
elapsed=0
while ! talosctl --nodes "${BOOTSTRAP_NODE}" health --server=false 2>/dev/null; do
    if [[ $elapsed -ge $timeout ]]; then
        echo "❌ Timeout waiting for bootstrap node to be ready"
        echo "   Check node status with:"
        echo "   talosctl --nodes ${BOOTSTRAP_NODE} dmesg"
        echo "   talosctl --nodes ${BOOTSTRAP_NODE} logs"
        exit 1
    fi
    echo "   Still waiting... (${elapsed}s/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

echo "✅ Bootstrap node is ready!"

# Bootstrap the cluster
echo "🔧 Bootstrapping Kubernetes cluster..."
if talosctl bootstrap --nodes "${BOOTSTRAP_NODE}"; then
    echo "✅ Cluster bootstrap successful!"
else
    echo "❌ Cluster bootstrap failed"
    exit 1
fi

# Wait for kubernetes API to be available
echo "⏳ Waiting for Kubernetes API server..."
timeout=300
elapsed=0
while ! talosctl --nodes "${BOOTSTRAP_NODE}" health --server=true 2>/dev/null; do
    if [[ $elapsed -ge $timeout ]]; then
        echo "❌ Timeout waiting for Kubernetes API server"
        exit 1
    fi
    echo "   API server not ready yet... (${elapsed}s/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

echo "✅ Kubernetes API server is ready!"

# Generate kubeconfig
echo "🔑 Generating kubeconfig..."
KUBECONFIG_PATH="${HOME}/.kube/config"
mkdir -p "$(dirname "${KUBECONFIG_PATH}")"

if talosctl kubeconfig --nodes "${CONTROL_PLANE_VIP}" "${KUBECONFIG_PATH}"; then
    echo "✅ Kubeconfig saved to: ${KUBECONFIG_PATH}"
else
    echo "❌ Failed to generate kubeconfig"
    exit 1
fi

# Test kubectl access
echo "🧪 Testing kubectl access..."
export KUBECONFIG="${KUBECONFIG_PATH}"
if kubectl cluster-info; then
    echo "✅ kubectl access confirmed!"
else
    echo "❌ kubectl access failed"
    exit 1
fi

# Wait for all nodes to join
echo "⏳ Waiting for all nodes to join the cluster..."
expected_nodes=9  # 3 control plane + 6 workers (adjust as needed)
timeout=600
elapsed=0

while true; do
    ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    
    echo "   Nodes: ${ready_nodes}/${total_nodes} ready (expecting ${expected_nodes})"
    
    if [[ $ready_nodes -eq $expected_nodes ]]; then
        echo "✅ All nodes are ready!"
        break
    fi
    
    if [[ $elapsed -ge $timeout ]]; then
        echo "⚠️  Timeout reached, but continuing with available nodes"
        echo "   You may need to troubleshoot missing nodes manually"
        break
    fi
    
    sleep 15
    elapsed=$((elapsed + 15))
done

# Show cluster status
echo ""
echo "🎯 Cluster bootstrap completed!"
echo ""
echo "📊 Cluster Status:"
kubectl get nodes -o wide
echo ""
echo "🚀 Next steps:"
echo "   1. Install Cilium CNI: ./scripts/install-cilium.sh"
echo "   2. Install storage: ./scripts/install-storage.sh"
echo "   3. Apply base configurations: kubectl apply -k base/"
echo "   4. Deploy monitoring: kubectl apply -k monitoring/"
echo "   5. Set up BGP: kubectl apply -f networking/cilium-bgp-config.yaml"
echo ""
echo "🔧 Useful commands:"
echo "   - Cluster health: talosctl --talosconfig ${TALOS_DIR}/talosconfig health"
echo "   - Node status: kubectl get nodes"
echo "   - System pods: kubectl get pods -n kube-system"
