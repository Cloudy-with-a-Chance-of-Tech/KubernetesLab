#!/bin/bash
set -euo pipefail

# Complete cluster setup with all components
# This script orchestrates the full cluster deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "🚀 Complete Kubernetes Lab Setup"
echo "=================================="
echo ""

# Configuration check
echo "📋 Pre-flight checks..."

# Check if we're in the right directory
if [[ ! -f "${REPO_ROOT}/README.md" ]] || [[ ! -d "${REPO_ROOT}/base/talos" ]]; then
    echo "❌ This script must be run from the KubernetesLab repository root"
    exit 1
fi

# Check required tools
REQUIRED_TOOLS=("talosctl" "kubectl" "helm")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Required tool '$tool' is not installed"
        echo "   Please install it and try again"
        exit 1
    fi
done

echo "✅ All required tools are available"

# Check if cluster already exists
if [[ -f "${REPO_ROOT}/base/talos/talosconfig" ]]; then
    echo ""
    echo "⚠️  Existing cluster configuration detected"
    echo ""
    read -p "Do you want to destroy and rebuild the cluster? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "🔥 Destroying existing cluster..."
        "${SCRIPT_DIR}/destroy-cluster.sh"
        echo ""
    else
        echo "❌ Setup cancelled. Use individual scripts for specific operations."
        exit 0
    fi
fi

echo ""
echo "🔧 Starting complete cluster setup..."
echo ""

# Step 1: Generate configurations
echo "Step 1/6: Generating Talos configurations..."
echo "============================================="
"${SCRIPT_DIR}/generate-talos-config.sh"
echo ""

# Step 2: Deploy cluster
echo "Step 2/6: Deploying cluster configurations..."
echo "=============================================="
"${SCRIPT_DIR}/deploy-cluster.sh"
echo ""

# Step 3: Bootstrap cluster
echo "Step 3/6: Bootstrapping Kubernetes cluster..."
echo "=============================================="
"${SCRIPT_DIR}/bootstrap-cluster.sh"
echo ""

# Step 4: Install Cilium
echo "Step 4/6: Installing Cilium CNI..."
echo "=================================="
"${SCRIPT_DIR}/install-cilium.sh"
echo ""

# Step 5: Apply base configurations
echo "Step 5/6: Applying base configurations..."
echo "========================================"
echo "📦 Applying namespaces..."
kubectl apply -k "${REPO_ROOT}/base/"

echo "📦 Applying networking configurations..."
kubectl apply -f "${REPO_ROOT}/networking/cilium-bgp-config.yaml"

echo "📦 Waiting for BGP peering to establish..."
sleep 30

echo ""

# Step 6: Deploy monitoring
echo "Step 6/6: Deploying monitoring stack..."
echo "======================================"
echo "📊 Applying monitoring configurations..."
kubectl apply -k "${REPO_ROOT}/monitoring/"

echo "⏳ Waiting for monitoring pods to start..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s

echo ""
echo "🎯 Complete cluster setup finished!"
echo ""
echo "📊 Cluster Summary:"
echo "=================="
kubectl get nodes -o wide
echo ""
kubectl get pods -n kube-system
echo ""
kubectl get pods -n monitoring
echo ""

# Test load balancer
echo "🧪 Testing load balancer functionality..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: test-lb
  namespace: default
  labels:
    environment: development
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF

echo "⏳ Waiting for LoadBalancer IP assignment..."
timeout=120
elapsed=0
while true; do
    LB_IP=$(kubectl get svc test-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$LB_IP" && "$LB_IP" != "null" ]]; then
        echo "✅ LoadBalancer IP assigned: $LB_IP"
        break
    fi
    
    if [[ $elapsed -ge $timeout ]]; then
        echo "⚠️  LoadBalancer IP not assigned within timeout"
        echo "   Check BGP peering: kubectl get ciliumbgppeeringpolicy"
        break
    fi
    
    echo "   Still waiting for IP assignment... (${elapsed}s/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

# Cleanup test resources
kubectl delete deployment nginx-test
kubectl delete service test-lb

echo ""
echo "🎉 Kubernetes Lab Setup Complete!"
echo "================================="
echo ""
echo "🔗 Access Points:"
echo "   - Cluster: kubectl cluster-info"
echo "   - Hubble UI: kubectl port-forward -n kube-system svc/hubble-ui 12000:80"
echo "   - Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo ""
echo "📚 Next Steps:"
echo "   1. Deploy applications: kubectl apply -k apps/production/"
echo "   2. Set up GitHub Actions secrets (see docs/quick-setup-secrets.md)"
echo "   3. Configure external access through your pfSense/router"
echo ""
echo "🔧 Management Commands:"
echo "   - Cluster health: talosctl health"
echo "   - Node status: kubectl get nodes"
echo "   - Destroy/rebuild: ./scripts/destroy-cluster.sh && ./scripts/setup-complete.sh"
