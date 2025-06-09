#!/bin/bash
set -euo pipefail

# Complete cluster setup automation for Talos Raspberry Pi cluster
# This script orchestrates the entire cluster deployment from clean state to production ready

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "🚀 Complete Talos Raspberry Pi Cluster Setup"
echo "============================================="
echo ""

# Configuration
CLUSTER_NAME="kub"
VIP="192.168.1.30"

# Parse command line arguments
SKIP_RESET=false
SKIP_CILIUM=false
SKIP_STORAGE=false
SKIP_BASE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-reset)
            SKIP_RESET=true
            shift
            ;;
        --skip-cilium)
            SKIP_CILIUM=true
            shift
            ;;
        --skip-storage)
            SKIP_STORAGE=true
            shift
            ;;
        --skip-base)
            SKIP_BASE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-reset    Skip cluster reset/destroy step"
            echo "  --skip-cilium   Skip Cilium CNI installation"
            echo "  --skip-storage  Skip local-path-provisioner installation"
            echo "  --skip-base     Skip base resource deployment"
            echo "  --help          Show this help message"
            echo ""
            echo "This script performs a complete cluster setup:"
            echo "  1. Generate fresh Talos configurations"
            echo "  2. Reset cluster (unless --skip-reset)"
            echo "  3. Deploy new configurations"
            echo "  4. Bootstrap cluster"
            echo "  5. Install Cilium CNI (unless --skip-cilium)"
            echo "  6. Install storage (unless --skip-storage)"
            echo "  7. Deploy base resources (unless --skip-base)"
            echo "  8. Validate setup"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "📋 Setup Configuration:"
echo "   Cluster: $CLUSTER_NAME"
echo "   VIP: $VIP"
echo "   Skip reset: $SKIP_RESET"
echo "   Skip Cilium: $SKIP_CILIUM"
echo "   Skip storage: $SKIP_STORAGE"
echo "   Skip base: $SKIP_BASE"
echo ""

# Confirmation prompt
if [[ "$SKIP_RESET" == "false" ]]; then
    echo "⚠️  WARNING: This will completely reset your cluster!"
    echo "   All data and configurations will be lost."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "❌ Aborted by user"
        exit 1
    fi
    echo ""
fi

# Step 1: Generate fresh configurations
echo "🔧 Step 1: Generating fresh Talos configurations..."
if ./scripts/generate-talos-config.sh; then
    echo "✅ Fresh configurations generated"
else
    echo "❌ Failed to generate configurations"
    exit 1
fi

# Step 2: Reset cluster (if not skipped)
if [[ "$SKIP_RESET" == "false" ]]; then
    echo ""
    echo "💥 Step 2: Resetting cluster nodes..."
    if ./scripts/destroy-cluster.sh; then
        echo "✅ Cluster reset completed"
    else
        echo "❌ Cluster reset failed"
        exit 1
    fi
    
    # Wait a bit for nodes to fully reset
    echo "⏳ Waiting for nodes to fully reset..."
    sleep 30
fi

# Step 3: Deploy configurations
echo ""
echo "🚀 Step 3: Deploying fresh configurations..."
if ./scripts/deploy-cluster.sh; then
    echo "✅ Configurations deployed"
else
    echo "❌ Configuration deployment failed"
    exit 1
fi

# Step 4: Bootstrap cluster
echo ""
echo "🏗️ Step 4: Bootstrapping cluster..."
if ./scripts/bootstrap-cluster.sh; then
    echo "✅ Cluster bootstrapped"
else
    echo "❌ Cluster bootstrap failed"
    exit 1
fi

# Wait for cluster to stabilize
echo ""
echo "⏳ Waiting for cluster to stabilize..."
sleep 30

# Step 5: Install Cilium CNI (if not skipped)
if [[ "$SKIP_CILIUM" == "false" ]]; then
    echo ""
    echo "🌐 Step 5: Installing Cilium CNI..."
    if ./scripts/install-cilium.sh; then
        echo "✅ Cilium CNI installed"
    else
        echo "❌ Cilium CNI installation failed"
        exit 1
    fi
    
    # Wait for networking to stabilize
    echo "⏳ Waiting for networking to stabilize..."
    sleep 60
else
    echo ""
    echo "⏭️ Step 5: Skipping Cilium installation"
fi

# Step 6: Install storage (if not skipped)
if [[ "$SKIP_STORAGE" == "false" ]]; then
    echo ""
    echo "💾 Step 6: Installing local-path-provisioner..."
    if ./scripts/install-storage.sh; then
        echo "✅ Storage provisioner installed"
    else
        echo "❌ Storage installation failed"
        exit 1
    fi
    
    # Wait for storage to be ready
    echo "⏳ Waiting for storage to be ready..."
    sleep 30
else
    echo ""
    echo "⏭️ Step 6: Skipping storage installation"
fi

# Step 7: Deploy base resources (if not skipped)
if [[ "$SKIP_BASE" == "false" ]]; then
    echo ""
    echo "📦 Step 7: Deploying base resources..."
    
    # Wait for all system components to be ready
    echo "⏳ Ensuring all system components are ready..."
    kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s
    
    if kubectl apply -k base/; then
        echo "✅ Base resources deployed"
    else
        echo "❌ Base resource deployment failed"
        exit 1
    fi
else
    echo ""
    echo "⏭️ Step 7: Skipping base resource deployment"
fi

# Step 8: Validate setup
echo ""
echo "🔍 Step 8: Validating cluster setup..."
sleep 10  # Allow things to settle

echo ""
echo "📊 Final Cluster Status:"
./scripts/cluster-status.sh

echo ""
echo "🎉 Cluster setup completed successfully!"
echo ""
echo "📋 Summary:"
echo "   ✅ Cluster: $CLUSTER_NAME"
echo "   ✅ API Endpoint: https://$VIP:6443"
echo "   ✅ Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "unknown")"
if [[ "$SKIP_CILIUM" == "false" ]]; then
    echo "   ✅ CNI: Cilium"
fi
if [[ "$SKIP_STORAGE" == "false" ]]; then
    echo "   ✅ Storage: local-path-provisioner"
fi

echo ""
echo "🎯 Next steps:"
echo "   • Deploy monitoring: kubectl apply -k monitoring/"
echo "   • Set up BGP: kubectl apply -f networking/cilium-bgp-config.yaml"
echo "   • Deploy applications: kubectl apply -k apps/production/"
echo "   • Monitor cluster: ./scripts/cluster-status.sh"
echo ""
echo "🔧 Useful commands:"
echo "   • Cluster health: kubectl get nodes"
echo "   • System pods: kubectl get pods -n kube-system"
echo "   • Storage: kubectl get pv,pvc --all-namespaces"
echo "   • Talos health: talosctl health"
