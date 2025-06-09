#!/bin/bash
set -euo pipefail

# Install Cilium CNI with BGP support
# This script installs Cilium as the CNI for the cluster with BGP capabilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"

echo "🌐 Installing Cilium CNI with BGP support..."

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ helm is not installed. Installing helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Test cluster access
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cannot access Kubernetes cluster"
    echo "   Make sure kubeconfig is properly configured"
    echo "   Run: ./scripts/bootstrap-cluster.sh first"
    exit 1
fi

echo "✅ Cluster access confirmed"

# Add Cilium Helm repository
echo "📦 Adding Cilium Helm repository..."
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium with BGP configuration
echo "🔧 Installing Cilium CNI..."
helm upgrade --install cilium cilium/cilium \
    --version 1.15.6 \
    --namespace cilium \
    --create-namespace \
    --set bgpControlPlane.enabled=true \
    --set kubeProxyReplacement=strict \
    --set operator.replicas=1 \
    --set ipam.mode=kubernetes \
    --set routingMode=tunnel \
    --set tunnelProtocol=vxlan \
    --set enableIPv4Masquerade=true \
    --set enableIPv6Masquerade=false \
    --set monitor.enabled=true \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set prometheus.enabled=true \
    --set operator.prometheus.enabled=true \
    --set cluster.name=cluster.local \
    --set cluster.id=1

if [[ $? -eq 0 ]]; then
    echo "✅ Cilium installation initiated"
else
    echo "❌ Cilium installation failed"
    exit 1
fi

# Wait for Cilium to be ready
echo "⏳ Waiting for Cilium to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s

if [[ $? -eq 0 ]]; then
    echo "✅ Cilium is ready!"
else
    echo "❌ Cilium failed to become ready"
    echo "   Check status: kubectl get pods -n cilium -l k8s-app=cilium"
    exit 1
fi

# Wait for nodes to be ready with CNI
echo "⏳ Waiting for all nodes to be ready with CNI..."
timeout=300
elapsed=0

while true; do
    not_ready=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l || echo "0")
    
    if [[ $not_ready -eq 0 ]]; then
        echo "✅ All nodes are ready with CNI!"
        break
    fi
    
    if [[ $elapsed -ge $timeout ]]; then
        echo "⚠️  Some nodes may still be initializing"
        break
    fi
    
    echo "   ${not_ready} nodes still initializing... (${elapsed}s/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

# Test Cilium connectivity
echo "🧪 Testing Cilium connectivity..."
kubectl create namespace cilium-test --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n cilium-test -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/kubernetes/connectivity-check/connectivity-check.yaml

echo "⏳ Waiting for connectivity test to complete..."
sleep 30

# Check connectivity test results
echo "📊 Connectivity test results:"
kubectl get pods -n cilium-test

# Cleanup connectivity test
echo "🧹 Cleaning up connectivity test..."
kubectl delete namespace cilium-test

echo ""
echo "🎯 Cilium installation completed!"
echo ""
echo "📊 Cilium Status:"
kubectl get pods -n cilium -l k8s-app=cilium
echo ""
echo "🚀 Next steps:"
echo "   1. Apply BGP configuration: kubectl apply -f networking/cilium-bgp-config.yaml"
echo "   2. Test load balancer: kubectl apply -f networking/example-services.yaml"
echo "   3. Check Hubble UI: kubectl port-forward -n cilium svc/hubble-ui 12000:80"
echo ""
echo "🔧 Useful commands:"
echo "   - Cilium status: cilium status"
echo "   - BGP peers: kubectl get ciliumbgppeeringpolicy"
echo "   - Load balancer pools: kubectl get ciliumloadbalancerippool"
