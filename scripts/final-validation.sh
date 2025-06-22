#!/bin/bash

# KubernetesLab Final Validation Script
# Validates all recent changes and integrations

set -e

echo "🔍 KubernetesLab Final Validation"
echo "=================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
        return 1
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "ℹ️  $1"
}

echo ""
echo "1️⃣  Validating Cluster Access"
echo "----------------------------"

# Check kubectl access
if kubectl cluster-info &>/dev/null; then
    print_status 0 "Kubernetes cluster accessible"
    CLUSTER_VERSION=$(kubectl version --output=yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}')
    print_info "Cluster version: $CLUSTER_VERSION"
else
    print_status 1 "Cannot access Kubernetes cluster"
    exit 1
fi

echo ""
echo "2️⃣  Validating Static IP Services"
echo "--------------------------------"

# Check Hubble UI service
if kubectl get svc hubble-ui -n cilium -o jsonpath='{.spec.loadBalancerIP}' 2>/dev/null | grep -q "192.168.100.99"; then
    print_status 0 "Hubble UI static IP configured (192.168.100.99)"
else
    print_status 1 "Hubble UI static IP not configured"
fi

# Check Prometheus service
if kubectl get svc prometheus -n monitoring -o jsonpath='{.spec.loadBalancerIP}' 2>/dev/null | grep -q "192.168.100.100"; then
    print_status 0 "Prometheus static IP configured (192.168.100.100)"
else
    print_status 1 "Prometheus static IP not configured"
fi

# Check Grafana service
if kubectl get svc grafana -n monitoring -o jsonpath='{.spec.loadBalancerIP}' 2>/dev/null | grep -q "192.168.100.101"; then
    print_status 0 "Grafana static IP configured (192.168.100.101)"
else
    print_status 1 "Grafana static IP not configured"
fi

# Check Vault service
if kubectl get svc vault-external -n vault -o jsonpath='{.spec.loadBalancerIP}' 2>/dev/null | grep -q "192.168.100.102"; then
    print_status 0 "Vault static IP configured (192.168.100.102)"
else
    print_status 1 "Vault static IP not configured"
fi

echo ""
echo "3️⃣  Validating Monitoring Stack"
echo "------------------------------"

# Check Prometheus deployment
if kubectl get deployment prometheus -n monitoring &>/dev/null; then
    PROMETHEUS_READY=$(kubectl get deployment prometheus -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$PROMETHEUS_READY" -gt 0 ]; then
        print_status 0 "Prometheus deployment ready ($PROMETHEUS_READY replicas)"
    else
        print_status 1 "Prometheus deployment not ready"
    fi
else
    print_status 1 "Prometheus deployment not found"
fi

# Check Grafana deployment
if kubectl get deployment grafana -n monitoring &>/dev/null; then
    GRAFANA_READY=$(kubectl get deployment grafana -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$GRAFANA_READY" -gt 0 ]; then
        print_status 0 "Grafana deployment ready ($GRAFANA_READY replicas)"
    else
        print_status 1 "Grafana deployment not ready"
    fi
else
    print_status 1 "Grafana deployment not found"
fi

# Check Node Exporter
NODE_EXPORTER_READY=$(kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
NODE_EXPORTER_DESIRED=$(kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
if [ "$NODE_EXPORTER_READY" -eq "$NODE_EXPORTER_DESIRED" ] && [ "$NODE_EXPORTER_READY" -gt 0 ]; then
    print_status 0 "Node Exporter ready ($NODE_EXPORTER_READY/$NODE_EXPORTER_DESIRED nodes)"
else
    print_status 1 "Node Exporter not ready ($NODE_EXPORTER_READY/$NODE_EXPORTER_DESIRED nodes)"
fi

echo ""
echo "4️⃣  Validating Home Assistant Integration"
echo "---------------------------------------"

# Check Home Assistant secret
if kubectl get secret homeassistant-token -n monitoring &>/dev/null; then
    print_status 0 "Home Assistant token secret exists"
else
    print_warning "Home Assistant token secret not found (may need CI/CD deployment)"
fi

# Check Prometheus config for Home Assistant
if kubectl get configmap prometheus-config -n monitoring -o yaml 2>/dev/null | grep -q "homeassistant"; then
    print_status 0 "Home Assistant scrape config found in Prometheus"
else
    print_status 1 "Home Assistant scrape config not found in Prometheus"
fi

# Check Grafana dashboard ConfigMap
if kubectl get configmap grafana-dashboards -n monitoring -o yaml 2>/dev/null | grep -q "homeassistant"; then
    print_status 0 "Home Assistant dashboard ConfigMap exists"
else
    print_status 1 "Home Assistant dashboard ConfigMap not found"
fi

echo ""
echo "5️⃣  Validating Network Configuration"
echo "----------------------------------"

# Check Hubble UI in cilium namespace
if kubectl get pod -n cilium -l app.kubernetes.io/name=hubble-ui --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
    print_status 0 "Hubble UI pod running"
else
    print_status 1 "Hubble UI pod not running"
fi

# Check Cilium pods
CILIUM_READY=$(kubectl get daemonset cilium -n cilium -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
CILIUM_DESIRED=$(kubectl get daemonset cilium -n cilium -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
if [ "$CILIUM_READY" -eq "$CILIUM_DESIRED" ] && [ "$CILIUM_READY" -gt 0 ]; then
    print_status 0 "Cilium ready ($CILIUM_READY/$CILIUM_DESIRED nodes)"
else
    print_status 1 "Cilium not ready ($CILIUM_READY/$CILIUM_DESIRED nodes)"
fi

echo ""
echo "6️⃣  Validating Kustomizations"
echo "----------------------------"

# Test key kustomizations
KUSTOMIZATIONS=(
    "base/"
    "base/storage/"
    "monitoring/"
    "networking/"
)

for kustomization in "${KUSTOMIZATIONS[@]}"; do
    if [ -f "$kustomization/kustomization.yaml" ]; then
        if kubectl apply --dry-run=client -k "$kustomization" &>/dev/null; then
            print_status 0 "Kustomization $kustomization builds successfully"
        else
            print_status 1 "Kustomization $kustomization has errors"
        fi
    else
        print_warning "Kustomization file not found: $kustomization"
    fi
done

echo ""
echo "8️⃣  Validating HashiCorp Vault"
echo "-----------------------------"

# Check Vault deployment
if kubectl get deployment vault -n vault &>/dev/null; then
    VAULT_READY=$(kubectl get deployment vault -n vault -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$VAULT_READY" -gt 0 ]; then
        print_status 0 "Vault deployment ready ($VAULT_READY replicas)"
    else
        print_status 1 "Vault deployment not ready"
    fi
else
    print_warning "Vault deployment not found (may not be deployed yet)"
fi

# Check Vault secrets
if kubectl get secret vault-root-token -n vault &>/dev/null; then
    print_status 0 "Vault root token secret exists"
else
    print_warning "Vault root token secret not found (initialization may be needed)"
fi

if kubectl get secret vault-unseal-keys -n vault &>/dev/null; then
    print_status 0 "Vault unseal keys secret exists"
else
    print_warning "Vault unseal keys secret not found (initialization may be needed)"
fi

# Check Vault network policies
VAULT_POLICIES=$(kubectl get cnp -n vault 2>/dev/null | wc -l)
if [ "$VAULT_POLICIES" -gt 1 ]; then
    print_status 0 "Vault network policies configured ($((VAULT_POLICIES-1)) policies)"
else
    print_warning "Vault network policies not found"
fi

echo ""
echo "9️⃣  Documentation and Security Check"
echo "-----------------------------------"

# Check for sensitive files that shouldn't exist
SENSITIVE_PATTERNS=(
    "*.key"
    "*.pem"
    "*.crt"
    "*secret*"
    "talosconfig.yaml"
)

FOUND_SENSITIVE=false
for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    if find . -name "$pattern" -not -path "./.git/*" -not -path "./templates/*" -not -path "./docs/*" 2>/dev/null | grep -q .; then
        FOUND_SENSITIVE=true
        break
    fi
done

if [ "$FOUND_SENSITIVE" = false ]; then
    print_status 0 "No sensitive files found in repository"
else
    print_status 1 "Potential sensitive files found - review needed"
fi

# Check .gitignore exists and has key patterns
if [ -f ".gitignore" ] && grep -q "\.env" .gitignore && grep -q "talosconfig\.yaml" .gitignore; then
    print_status 0 ".gitignore properly configured"
else
    print_status 1 ".gitignore missing or incomplete"
fi

# Check key documentation exists
KEY_DOCS=(
    "docs/static-ip-configuration.md"
    "docs/homeassistant-integration.md"
    "docs/monitoring-external-access.md"
    "AUDIT_COMPLETE.md"
)

for doc in "${KEY_DOCS[@]}"; do
    if [ -f "$doc" ]; then
        print_status 0 "Documentation exists: $doc"
    else
        print_status 1 "Missing documentation: $doc"
    fi
done

echo ""
echo "🎯 External Access URLs"
echo "======================"
echo "📊 Grafana:    http://192.168.100.101:3000"
echo "📈 Prometheus: http://192.168.100.100:9090"
echo "🌐 Hubble UI:  http://192.168.100.99"
echo "🔐 Vault:      http://192.168.100.102:8200"

echo ""
echo "🎉 Validation Complete!"
echo "======================"
print_info "If all checks passed, your KubernetesLab is fully operational!"
print_info "Next: Verify external access to the URLs above"
print_info "For troubleshooting, check docs/operations-guide-2025.md"
