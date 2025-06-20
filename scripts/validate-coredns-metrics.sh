#!/bin/bash
set -euo pipefail

# This script validates that Prometheus can successfully scrape CoreDNS metrics
# It checks the connection between Prometheus and CoreDNS in the kube-system namespace

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "🔍 Validating Prometheus to CoreDNS metrics connectivity..."

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check Prometheus pod status
echo "Checking Prometheus pod status..."
PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o name 2>/dev/null || echo "")

if [[ -z "$PROMETHEUS_POD" ]]; then
    echo "❌ Prometheus pod not found in monitoring namespace"
    exit 1
fi

echo "✅ Found Prometheus pod: $PROMETHEUS_POD"

# Check CoreDNS pod status
echo "Checking CoreDNS pod status..."
COREDNS_POD=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o name 2>/dev/null | head -1 || echo "")

if [[ -z "$COREDNS_POD" ]]; then
    echo "❌ CoreDNS pod not found in kube-system namespace"
    exit 1
fi

echo "✅ Found CoreDNS pod: $COREDNS_POD"

# Check if CoreDNS metrics port is accessible
echo "Checking if CoreDNS metrics port 9153 is open..."
COREDNS_POD_NAME=$(echo $COREDNS_POD | sed 's|pod/||')
if ! kubectl exec -n kube-system $COREDNS_POD_NAME -- nc -z localhost 9153 2>/dev/null; then
    echo "❌ CoreDNS metrics port 9153 is not listening"
    echo "   This could indicate CoreDNS is not configured to expose metrics."
    exit 1
fi

echo "✅ CoreDNS metrics port 9153 is open"

# Check if Prometheus can access CoreDNS metrics
echo "Checking if Prometheus is scraping CoreDNS metrics..."
PROM_POD_NAME=$(echo $PROMETHEUS_POD | sed 's|pod/||')
COREDNS_TARGETS=$(kubectl exec -n monitoring $PROM_POD_NAME -- curl -s localhost:9090/api/v1/targets | grep "kube-dns\|coredns")

if [[ -z "$COREDNS_TARGETS" ]]; then
    echo "❌ Prometheus is not scraping CoreDNS metrics"
    echo "   This could indicate a network policy issue or misconfiguration"
    
    # Check NetworkPolicies
    echo "Checking for network policies that might block access..."
    NETPOL_MONITORING=$(kubectl get networkpolicy -n monitoring -o name 2>/dev/null || echo "No NetworkPolicies in monitoring namespace")
    NETPOL_KUBESYSTEM=$(kubectl get networkpolicy -n kube-system -o name 2>/dev/null || echo "No NetworkPolicies in kube-system namespace")
    
    echo "NetworkPolicies in monitoring namespace:"
    echo "$NETPOL_MONITORING"
    echo "NetworkPolicies in kube-system namespace:"
    echo "$NETPOL_KUBESYSTEM"
    
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Ensure port 9153 is allowed in Prometheus NetworkPolicy egress rules"
    echo "2. Check CoreDNS configuration for metrics exposure"
    echo "3. Verify no CiliumNetworkPolicies are blocking the traffic"
    exit 1
fi

echo "✅ Prometheus is successfully scraping CoreDNS metrics"

# Check CoreDNS metrics in Prometheus
echo "Checking for CoreDNS metrics in Prometheus..."
COREDNS_METRICS=$(kubectl exec -n monitoring $PROM_POD_NAME -- curl -s 'localhost:9090/api/v1/query?query=coredns_dns_requests_total' | grep "result")

if [[ -z "$COREDNS_METRICS" ]]; then
    echo "⚠️  CoreDNS metrics not found in Prometheus"
    echo "   This could be normal if there haven't been any DNS requests yet"
    echo "   Try: kubectl exec -n monitoring $PROM_POD_NAME -- curl -s 'localhost:9090/api/v1/query?query=up{job=\"coredns\"}'"
else
    echo "✅ CoreDNS metrics found in Prometheus"
fi

echo ""
echo "🎯 CoreDNS metrics validation completed!"
echo ""
echo "📊 To check CoreDNS metrics in Prometheus UI:"
echo "   1. Run: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo "   2. Open: http://localhost:9090 in your browser"
echo "   3. Query: coredns_dns_requests_total or up{job=\"coredns\"} or up{job=\"kube-dns\"}"
