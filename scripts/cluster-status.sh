#!/bin/bash
set -euo pipefail

# Cluster status monitoring script for Raspberry Pi Talos cluster
# Provides a quick overview of cluster health and resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"

echo "🏥 Raspberry Pi Talos Cluster Health Dashboard"
echo "=============================================="
echo ""

# Check Talos configuration
if [[ -f "${TALOS_DIR}/talosconfig" ]]; then
    export TALOSCONFIG="${TALOS_DIR}/talosconfig"
    echo "✅ Using talosconfig: ${TALOS_DIR}/talosconfig"
else
    echo "⚠️  No talosconfig found at ${TALOS_DIR}/talosconfig"
    echo "   Some Talos-specific commands may not work"
fi

# Your cluster configuration
CONTROL_PLANE_VIP="192.168.1.30"
CLUSTER_NAME="kub"

echo "📋 Cluster: ${CLUSTER_NAME}"
echo "📋 VIP Endpoint: https://${CONTROL_PLANE_VIP}:6443"
echo ""

# Check Talos cluster health
echo "🔧 Talos Cluster Health:"
echo "   🔍 Testing Talos API connectivity to VIP..."
if timeout 10 talosctl --nodes "${CONTROL_PLANE_VIP}" health --server=false 2>/dev/null; then
    echo "   ✅ Talos API accessible via VIP"
    
    # Get individual node status from Talos
    echo "   🖥️  Talos Node Status:"
    if timeout 10 talosctl --nodes "${CONTROL_PLANE_VIP}" get members 2>/dev/null; then
        echo "   ✅ etcd cluster healthy"
    else
        echo "   ⚠️  Could not retrieve etcd member status"
    fi
else
    echo "   ❌ Talos API not accessible via VIP (${CONTROL_PLANE_VIP})"
    echo "   💡 VIP may not be active or nodes may be down"
    
    # Try individual nodes if we can determine their IPs
    echo "   🔍 Attempting to check individual Pi nodes..."
    individual_nodes=("192.168.1.31" "192.168.1.32" "192.168.1.33")  # Based on your control_nodes.yaml
    node_names=("lead" "nickel" "tin")
    
    for i in "${!individual_nodes[@]}"; do
        node_ip="${individual_nodes[i]}"
        node_name="${node_names[i]}"
        echo "   🖥️  Testing ${node_name} (${node_ip})..."
        
        # Quick ping test first
        if timeout 3 ping -c 1 "${node_ip}" &>/dev/null; then
            echo "      ✅ Network connectivity to ${node_name}"
            
            # Test Talos API
            if timeout 10 talosctl --nodes "${node_ip}" version --short 2>/dev/null; then
                echo "      ✅ Talos API responding on ${node_name}"
            else
                echo "      ❌ Talos API not responding on ${node_name}"
            fi
        else
            echo "      ❌ No network connectivity to ${node_name}"
        fi
    done
fi

echo ""

# Check if Kubernetes cluster is accessible
echo "☸️  Kubernetes Cluster Health:"
echo "   🔍 Testing kubectl connectivity..."
if timeout 10 kubectl cluster-info &>/dev/null; then
    echo "   ✅ Kubernetes API accessible"
    
    # Cluster info
    cluster_context=$(timeout 5 kubectl config current-context 2>/dev/null || echo "unknown")
    server_url=$(timeout 5 kubectl cluster-info 2>/dev/null | grep -o 'https://[^[:space:]]*' | head -1)
    echo "   📋 Context: ${cluster_context}"
    echo "   📋 Server: ${server_url}"
    echo ""

    # Node status
    echo "🖥️  Kubernetes Node Status:"
    timeout 10 kubectl get nodes -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[?(@.type=='Ready')].status,ROLES:.metadata.labels.node-role\.kubernetes\.io/control-plane,VERSION:.status.nodeInfo.kubeletVersion,ARCH:.metadata.labels.kubernetes\.io/arch" --no-headers 2>/dev/null | while read -r line; do
        if [[ "$line" == *"True"* ]]; then
            echo "   ✅ $line"
        else
            echo "   ❌ $line"
        fi
    done || echo "   ❌ Could not retrieve node status"
    echo ""

    # Resource usage
    echo "📊 Resource Usage:"
    if timeout 10 kubectl top nodes 2>/dev/null; then
        echo ""
    else
        echo "   ⚠️  Metrics server not available"
        echo "   💡 Install metrics server: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
        echo ""
    fi
    

    # Critical system pods
    echo "🔧 System Pods Status:"
    critical_namespaces=("kube-system" "cilium" "monitoring")
    for ns in "${critical_namespaces[@]}"; do
        if timeout 5 kubectl get namespace "$ns" &>/dev/null; then
            echo "   📦 Namespace: $ns"
            failed_pods=$(timeout 10 kubectl get pods -n "$ns" --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
            total_pods=$(timeout 10 kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
            ready_pods=$((total_pods - failed_pods))
            
            if [[ $failed_pods -eq 0 ]]; then
                echo "      ✅ All pods running ($ready_pods/$total_pods)"
            else
                echo "      ⚠️  $failed_pods pods not ready ($ready_pods/$total_pods)"
                timeout 10 kubectl get pods -n "$ns" --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | while read -r pod_line; do
                    echo "         ❌ $pod_line"
                done
            fi
        else
            echo "   📦 Namespace: $ns (not found)"
        fi
    done
echo ""

# Storage status
echo "💾 Storage Status:"
# Check for local-path-provisioner
if timeout 10 kubectl get deployment -n local-path-storage local-path-provisioner &>/dev/null; then
    lpp_pods=$(timeout 10 kubectl get pods -n local-path-storage -l app=local-path-provisioner --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    echo "   ✅ local-path-provisioner: $lpp_pods pods running"
else
    echo "   ❌ local-path-provisioner: Not installed"
    echo "   💡 Install with: ./scripts/install-storage.sh"
fi

# Check default StorageClass
default_sc=$(timeout 10 kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "none")
echo "   🏠 Default StorageClass: $default_sc"

# PV/PVC counts
pv_count=$(timeout 10 kubectl get pv --no-headers 2>/dev/null | wc -l)
pvc_count=$(timeout 10 kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)
echo "   📁 Persistent Volumes: $pv_count"
echo "   📄 Persistent Volume Claims: $pvc_count"

# Storage capacity (if PVs exist)
if [[ $pv_count -gt 0 ]]; then
    echo "   📊 Storage Capacity:"
    timeout 10 kubectl get pv --no-headers 2>/dev/null | awk '{print "      " $1 ": " $2 " (" $5 ")"}' | head -5
    if [[ $pv_count -gt 5 ]]; then
        echo "      ... and $((pv_count - 5)) more"
    fi
fi
echo ""

# Network status
echo "🌐 Network Status:"
if timeout 10 kubectl get pods -n cilium -l k8s-app=cilium --no-headers 2>/dev/null | grep -q Running; then
    cilium_pods=$(timeout 10 kubectl get pods -n cilium -l k8s-app=cilium --no-headers 2>/dev/null | grep Running | wc -l)
    echo "   ✅ Cilium CNI: $cilium_pods pods running"
else
    echo "   ❌ Cilium CNI: Not running or not found"
fi

# Check for LoadBalancer services
lb_services=$(timeout 10 kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer --no-headers 2>/dev/null | wc -l)
echo "   🔀 LoadBalancer services: $lb_services"
echo ""

# Recent events (warnings/errors)
echo "⚠️  Recent Cluster Events:"
timeout 10 kubectl get events --all-namespaces --sort-by='.lastTimestamp' --field-selector type!=Normal 2>/dev/null | tail -10 || echo "   ✅ No recent warnings or errors"
echo ""

fi

# Talos health (if available)
if [[ -f "${TALOS_DIR}/talosconfig" ]]; then
    echo "🔧 Talos System Health:"
    export TALOSCONFIG="${TALOS_DIR}/talosconfig"
    if timeout 10 talosctl health --server=false 2>/dev/null; then
        echo "   ✅ Talos nodes are healthy"
    else
        echo "   ⚠️  Cannot reach Talos nodes or health check failed"
    fi
else
    echo "🔧 Talos System Health:"
    echo "   ⚠️  Talos config not found (run ./scripts/generate-talos-config.sh)"
fi

echo ""
echo "🎯 Quick Actions:"
echo "   Monitor logs: kubectl logs -f -n kube-system <pod-name>"
echo "   Check node details: kubectl describe node <node-name>"
echo "   Validate setup: ./scripts/validate-setup.sh"
echo "   Update cluster: ./scripts/verify-config.sh"
