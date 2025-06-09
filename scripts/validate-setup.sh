#!/bin/bash
set -euo pipefail

# Validate cluster setup and configuration
# This script checks the health and configuration of your Talos Kubernetes cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"

echo "🔍 Validating Kubernetes Lab Setup"
echo "=================================="
echo ""

# Check if configurations exist
echo "📋 Configuration Check:"
echo "======================"

if [[ -f "${TALOS_DIR}/talosconfig" ]]; then
    echo "✅ Talos client configuration found"
    export TALOSCONFIG="${TALOS_DIR}/talosconfig"
else
    echo "❌ Talos client configuration missing"
    echo "   Run: ./scripts/generate-talos-config.sh"
    exit 1
fi

if [[ -f "${TALOS_DIR}/controlplane.yaml" ]]; then
    echo "✅ Control plane configuration found"
else
    echo "❌ Control plane configuration missing"
    echo "   Run: ./scripts/generate-talos-config.sh"
    exit 1
fi

if [[ -f "${TALOS_DIR}/worker.yaml" ]]; then
    echo "✅ Worker configuration found"
else
    echo "❌ Worker configuration missing"
    echo "   Run: ./scripts/generate-talos-config.sh"
    exit 1
fi

echo ""

# Check cluster connectivity
echo "🌐 Cluster Connectivity:"
echo "========================"

if command -v kubectl &> /dev/null; then
    if kubectl cluster-info &>/dev/null; then
        echo "✅ Kubernetes API server is accessible"
        
        # Get cluster info
        CLUSTER_VERSION=$(kubectl version --short --client=false -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' 2>/dev/null || echo "unknown")
        echo "   Kubernetes version: ${CLUSTER_VERSION}"
        
        # Node status
        TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
        READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
        echo "   Nodes: ${READY_NODES}/${TOTAL_NODES} ready"
        
        if [[ $READY_NODES -eq $TOTAL_NODES ]] && [[ $TOTAL_NODES -gt 0 ]]; then
            echo "✅ All nodes are ready"
        else
            echo "⚠️  Some nodes may not be ready"
        fi
    else
        echo "❌ Cannot access Kubernetes API server"
        echo "   Run: ./scripts/bootstrap-cluster.sh"
    fi
else
    echo "❌ kubectl not found or not configured"
fi

echo ""

# Check Talos connectivity
echo "🔧 Talos Connectivity:"
echo "======================"

if command -v talosctl &> /dev/null; then
    # Test connection to first control plane node
    CONTROL_PLANE_NODE="192.168.1.101"  # Update this to match your environment
    
    if talosctl --nodes "${CONTROL_PLANE_NODE}" health --server=false &>/dev/null; then
        echo "✅ Talos API is accessible"
        
        # Get Talos version
        TALOS_VERSION=$(talosctl --nodes "${CONTROL_PLANE_NODE}" version 2>/dev/null | grep -E "Tag:" | head -1 | awk '{print $2}' || echo "unknown")
        echo "   Talos version: ${TALOS_VERSION}"
    else
        echo "❌ Cannot access Talos API"
        echo "   Check network connectivity to ${CONTROL_PLANE_NODE}"
        echo "   Or update IP address in this script"
    fi
else
    echo "❌ talosctl not found"
    echo "   Install: curl -sL https://talos.dev/install | sh"
fi

echo ""

# Check CNI
echo "🌐 CNI (Cilium) Status:"
echo "======================="

if kubectl get pods -n cilium -l k8s-app=cilium &>/dev/null; then
    CILIUM_PODS=$(kubectl get pods -n cilium -l k8s-app=cilium --no-headers 2>/dev/null | wc -l || echo "0")
    CILIUM_READY=$(kubectl get pods -n cilium -l k8s-app=cilium --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    echo "   Cilium pods: ${CILIUM_READY}/${CILIUM_PODS} running"
    
    if [[ $CILIUM_READY -eq $CILIUM_PODS ]] && [[ $CILIUM_PODS -gt 0 ]]; then
        echo "✅ Cilium is running"
        
        # Check BGP status
        if kubectl get ciliumbgppeeringpolicy &>/dev/null; then
            BGP_POLICIES=$(kubectl get ciliumbgppeeringpolicy --no-headers 2>/dev/null | wc -l || echo "0")
            echo "   BGP policies: ${BGP_POLICIES} configured"
            
            if [[ $BGP_POLICIES -gt 0 ]]; then
                echo "✅ BGP is configured"
            else
                echo "⚠️  No BGP policies found"
                echo "   Apply: kubectl apply -f networking/cilium-bgp-config.yaml"
            fi
        else
            echo "⚠️  BGP CRDs not found"
        fi
    else
        echo "❌ Cilium is not ready"
        echo "   Run: ./scripts/install-cilium.sh"
    fi
else
    echo "❌ Cilium not found"
    echo "   Run: ./scripts/install-cilium.sh"
fi

echo ""

# Check monitoring
echo "📊 Monitoring Stack:"
echo "==================="

if kubectl get namespace monitoring &>/dev/null; then
    echo "✅ Monitoring namespace exists"
    
    # Check Prometheus
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus &>/dev/null; then
        PROM_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l || echo "0")
        PROM_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        
        echo "   Prometheus pods: ${PROM_READY}/${PROM_PODS} running"
        
        if [[ $PROM_READY -eq $PROM_PODS ]] && [[ $PROM_PODS -gt 0 ]]; then
            echo "✅ Prometheus is running"
        else
            echo "⚠️  Prometheus is not ready"
        fi
    else
        echo "⚠️  Prometheus not found"
        echo "   Apply: kubectl apply -k monitoring/"
    fi
    
    # Check Grafana
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana &>/dev/null; then
        GRAFANA_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | wc -l || echo "0")
        GRAFANA_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        
        echo "   Grafana pods: ${GRAFANA_READY}/${GRAFANA_PODS} running"
        
        if [[ $GRAFANA_READY -eq $GRAFANA_PODS ]] && [[ $GRAFANA_PODS -gt 0 ]]; then
            echo "✅ Grafana is running"
        else
            echo "⚠️  Grafana is not ready"
        fi
    else
        echo "⚠️  Grafana not found"
    fi
else
    echo "❌ Monitoring namespace not found"
    echo "   Apply: kubectl apply -k base/ && kubectl apply -k monitoring/"
fi

echo ""

# Check GitHub Actions runners
echo "🤖 GitHub Actions Runners:"
echo "=========================="

if kubectl get namespace github-actions &>/dev/null; then
    echo "✅ GitHub Actions namespace exists"
    
    if kubectl get pods -n github-actions -l app=github-runner &>/dev/null; then
        RUNNER_PODS=$(kubectl get pods -n github-actions -l app=github-runner --no-headers 2>/dev/null | wc -l || echo "0")
        RUNNER_READY=$(kubectl get pods -n github-actions -l app=github-runner --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        
        echo "   Runner pods: ${RUNNER_READY}/${RUNNER_PODS} running"
        
        if [[ $RUNNER_READY -eq $RUNNER_PODS ]] && [[ $RUNNER_PODS -gt 0 ]]; then
            echo "✅ GitHub runners are running"
        else
            echo "⚠️  GitHub runners are not ready"
        fi
    else
        echo "⚠️  GitHub runners not found"
        echo "   Apply: kubectl apply -f apps/production/github-runner.yaml"
    fi
else
    echo "⚠️  GitHub Actions namespace not found"
    echo "   Apply: kubectl apply -k base/"
fi

echo ""

# Summary
echo "📋 Validation Summary:"
echo "======================"

if kubectl cluster-info &>/dev/null && \
   kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready" && \
   kubectl get pods -n cilium -l k8s-app=cilium --no-headers 2>/dev/null | grep -q "Running"; then
    echo "✅ Core cluster functionality is working"
    echo ""
    echo "🚀 Cluster is ready for workloads!"
    echo ""
    echo "🔧 Access commands:"
    echo "   - Cluster info: kubectl cluster-info"
    echo "   - Node status: kubectl get nodes -o wide"
    echo "   - Pod status: kubectl get pods -A"
    echo "   - Talos health: talosctl health"
    echo ""
    echo "🌐 Access UIs:"
    echo "   - Hubble: kubectl port-forward -n kube-system svc/hubble-ui 12000:80"
    echo "   - Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    echo "   - Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
else
    echo "❌ Cluster has issues that need attention"
    echo ""
    echo "🔧 Troubleshooting steps:"
    echo "   1. Check individual components above"
    echo "   2. Run: kubectl get pods -A"
    echo "   3. Check logs: kubectl logs -n cilium -l k8s-app=cilium"
    echo "   4. Verify Talos: talosctl health"
    echo ""
    echo "🔄 Recovery options:"
    echo "   - Restart cluster: ./scripts/destroy-cluster.sh && ./scripts/setup-complete.sh"
    echo "   - Reinstall CNI: ./scripts/install-cilium.sh"
fi
