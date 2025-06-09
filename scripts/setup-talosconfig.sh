#!/bin/bash
set -euo pipefail

# Setup talosconfig for existing cluster
# This script helps configure talosctl to work with your existing Raspberry Pi cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"

echo "🔧 Setting up talosconfig for existing cluster..."

# Your cluster configuration
CONTROL_PLANE_VIP="192.168.1.30"
CLUSTER_NAME="kub"

echo "📋 Cluster: ${CLUSTER_NAME}"
echo "📋 VIP Endpoint: https://${CONTROL_PLANE_VIP}:6443"
echo ""

# Create talos directory if it doesn't exist
mkdir -p "${TALOS_DIR}"

# Check if talosconfig already exists
if [[ -f "${TALOS_DIR}/talosconfig" ]]; then
    echo "✅ Found existing talosconfig"
    echo "📍 Location: ${TALOS_DIR}/talosconfig"
    
    # Test existing config
    echo "🔍 Testing existing configuration..."
    export TALOSCONFIG="${TALOS_DIR}/talosconfig"
    if talosctl --nodes "${CONTROL_PLANE_VIP}" health --server=false 2>/dev/null; then
        echo "✅ Existing talosconfig works!"
        echo ""
        echo "🚀 You can now use the cluster management scripts:"
        echo "   ./scripts/cluster-status.sh"
        echo "   ./scripts/bootstrap-cluster.sh (if needed)"
        echo "   ./scripts/install-cilium.sh"
        exit 0
    else
        echo "❌ Existing talosconfig doesn't work"
        echo "   Continuing with setup..."
    fi
fi

echo ""
echo "📝 Setting up talosconfig..."
echo ""
echo "💡 Options to get a working talosconfig:"
echo ""
echo "1. 📁 Copy from existing working setup:"
echo "   If you have a working talosconfig elsewhere, copy it to:"
echo "   ${TALOS_DIR}/talosconfig"
echo ""
echo "2. 🔑 Generate from existing cluster secrets:"
echo "   If you have access to the cluster's machine secrets:"
echo "   talosctl gen config ${CLUSTER_NAME} https://${CONTROL_PLANE_VIP}:6443"
echo "   Then copy the generated talosconfig to ${TALOS_DIR}/"
echo ""
echo "3. 🆕 Generate new client config (if you have admin access):"
echo "   talosctl config new --roles=os:admin ${TALOS_DIR}/talosconfig"
echo "   (This requires existing cluster access)"
echo ""

# Interactive setup
read -p "Do you want to try generating a new client config now? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔑 Attempting to generate new client config..."
    
    # Try to generate new config
    if talosctl config new --roles=os:admin "${TALOS_DIR}/talosconfig" 2>/dev/null; then
        echo "✅ New client config generated!"
        
        # Set proper permissions
        chmod 600 "${TALOS_DIR}/talosconfig"
        
        # Test the new config
        export TALOSCONFIG="${TALOS_DIR}/talosconfig"
        if talosctl --nodes "${CONTROL_PLANE_VIP}" health --server=false 2>/dev/null; then
            echo "✅ New talosconfig works!"
        else
            echo "❌ New talosconfig doesn't work with your cluster"
            echo "   You may need to copy from your working setup"
        fi
    else
        echo "❌ Failed to generate new client config"
        echo "   You'll need to copy from your existing working setup"
    fi
else
    echo "💡 Manual setup required:"
    echo "   1. Copy your working talosconfig to: ${TALOS_DIR}/talosconfig"
    echo "   2. Run: chmod 600 ${TALOS_DIR}/talosconfig"
    echo "   3. Test: ./scripts/cluster-status.sh"
fi

echo ""
echo "📚 For more information:"
echo "   https://www.talos.dev/latest/reference/cli/#talosctl-config"
