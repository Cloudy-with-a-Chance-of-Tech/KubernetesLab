#!/bin/bash
set -euo pipefail

# Deploy Talos cluster configuration to nodes
# This script applies the machine configurations to your Raspberry Pi cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"
EXISTING_CONFIG="${REPO_ROOT}/control_nodes.yaml"

echo "🚀 Deploying Talos cluster configuration to Raspberry Pi nodes..."

# Check prerequisites
if [[ ! -f "${TALOS_DIR}/talosconfig" ]]; then
    echo "❌ Talos client configuration not found."
    echo "   You may need to copy your working talosconfig to ${TALOS_DIR}/talosconfig"
    echo "   Or run: ./scripts/generate-talos-config.sh first"
    exit 1
fi

# Check if we're working with existing config or templates
if [[ -f "${EXISTING_CONFIG}" ]]; then
    echo "✅ Found existing cluster configuration"
    echo "🔄 Using existing cluster setup"
    CONFIG_SOURCE="${EXISTING_CONFIG}"
else
    echo "📝 Using template configurations"
    if [[ ! -f "${TALOS_DIR}/controlplane.yaml.template" ]]; then
        echo "❌ Control plane template not found."
        echo "   Run: ./scripts/generate-talos-config.sh first"
        exit 1
    fi
    
    if [[ ! -f "${TALOS_DIR}/worker.yaml.template" ]]; then
        echo "❌ Worker template not found."
        echo "   Run: ./scripts/generate-talos-config.sh first"
        exit 1
    fi
    CONFIG_SOURCE="templates"
fi

# Set talosconfig for this session
export TALOSCONFIG="${TALOS_DIR}/talosconfig"

# Your actual Pi cluster configuration - extracted from control_nodes.yaml
# Control plane nodes (based on your hardware addresses)
declare -A CONTROL_PLANE_NODES=(
    ["lead"]="78:45:c4:38:df:3d"      # Lead node
    ["nickel"]="00:23:24:62:32:b7"    # Nickel node  
    ["tin"]="00:23:24:66:01:38"       # Tin node
)

# VIP endpoint
CLUSTER_VIP="192.168.1.30"

echo "📋 Control plane nodes: ${!CONTROL_PLANE_NODES[@]}"
echo "📋 VIP endpoint: ${CLUSTER_VIP}"
echo ""

# Function to get node IP by hostname (you may need to adjust this)
get_node_ip() {
    local hostname=$1
    # You can implement this based on your network setup
    # For now, we'll use the VIP for control plane operations
    case $hostname in
        "lead"|"nickel"|"tin")
            echo "${CLUSTER_VIP}"  # Use VIP for control plane
            ;;
        *)
            echo "192.168.1.XXX"  # You'll need to specify worker IPs
            ;;
    esac
}

# Check if cluster is already running
echo "🔍 Checking cluster status..."
if talosctl --nodes "${CLUSTER_VIP}" version >/dev/null 2>&1; then
    echo "✅ Cluster is accessible via VIP ${CLUSTER_VIP}"
    echo "🔄 This will update existing cluster configuration"
    
    read -p "⚠️  Do you want to continue with configuration update? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled by user"
        exit 1
    fi
else
    echo "⚠️  Cluster not accessible via VIP - this might be initial deployment"
fi

echo ""

# Deploy to control plane nodes
if [[ -f "${EXISTING_CONFIG}" ]]; then
    echo "🔧 Working with existing cluster configuration..."
    echo "⚠️  Using existing control_nodes.yaml configuration"
    echo "💡 For configuration updates, you may need to extract specific node configs"
    echo "   and apply them individually using talosctl apply-config"
    
    # For existing clusters, we typically don't redeploy the entire config
    # Instead, we might apply specific updates
    echo ""
    echo "📝 Available operations for existing cluster:"
    echo "   - Use 'talosctl edit machineconfig' to modify running config"
    echo "   - Use 'talosctl apply-config' for specific node updates"
    echo "   - Use 'talosctl upgrade' for Talos version updates"
    
else
    echo "🔧 Deploying from templates..."
    
    # Deploy control plane configurations (when using templates)
    echo "📡 Deploying control plane configurations..."
    for hostname in "${!CONTROL_PLANE_NODES[@]}"; do
        node_ip=$(get_node_ip "$hostname")
        echo "  🔧 Applying configuration to control plane node: ${hostname} (${node_ip})"
        
        # Note: You'll need actual control plane config files per node
        # This is a template - adjust based on your specific setup
        if [[ -f "${TALOS_DIR}/controlplane-${hostname}.yaml" ]]; then
            if talosctl apply-config --insecure --nodes "${node_ip}" --file "${TALOS_DIR}/controlplane-${hostname}.yaml"; then
                echo "    ✅ Configuration applied successfully to ${hostname}"
            else
                echo "    ❌ Failed to apply configuration to ${hostname}"
                echo "    💡 Make sure the node is accessible and in maintenance mode"
            fi
        else
            echo "    ⚠️  No specific config found for ${hostname}, using template"
            # Use template with hostname substitution
            if talosctl apply-config --insecure --nodes "${node_ip}" --file "${TALOS_DIR}/controlplane.yaml.template"; then
                echo "    ✅ Template applied successfully to ${hostname}"
            else
                echo "    ❌ Failed to apply template to ${hostname}"
            fi
        fi
    done
fi

echo ""
echo "🎯 Deployment guidance completed!"
echo ""
echo "💡 For existing clusters:"
echo "   - Configuration is already applied via control_nodes.yaml"
echo "   - Use cluster management scripts for updates"
echo "   - Monitor cluster health with: ./scripts/cluster-status.sh"
echo ""
echo "🚀 Next steps:"
echo "   1. Verify cluster health: ./scripts/cluster-status.sh"
echo "   2. Check cluster access: talosctl --talosconfig ${TALOS_DIR}/talosconfig health"
echo "   3. If needed, bootstrap: ./scripts/bootstrap-cluster.sh"
