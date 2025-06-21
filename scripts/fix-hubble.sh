#!/bin/bash
set -e

# Fix and verify Hubble configurations
# This script checks and resolves common issues with Hubble UI and Relay

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Define color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   Hubble Configuration Verification and Fix Tool           ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we can access the cluster
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Cannot access Kubernetes cluster${NC}"
    echo -e "   Make sure kubeconfig is properly configured"
    exit 1
fi

# Check if Cilium namespace exists
if ! kubectl get namespace cilium &>/dev/null; then
    echo -e "${RED}❌ Cilium namespace does not exist${NC}"
    echo -e "   Make sure Cilium is installed"
    exit 1
fi

# We no longer need certificates since we're using TLS disabled mode
echo -e "${YELLOW}→ Using no-TLS mode for Hubble relay...${NC}"

# Apply the fixed configurations
echo -e "${YELLOW}→ Applying fixed Hubble configurations...${NC}"
echo -e "  • Updating network policies"
kubectl apply -f "${REPO_ROOT}/networking/cilium/hubble-relay-netpol.yaml"
kubectl apply -f "${REPO_ROOT}/networking/cilium/hubble-ui-netpol.yaml"

# Check if we're in no-tls mode or tls mode
if kubectl get configmap -n cilium hubble-relay-config -o yaml | grep -q "tls-disabled: true"; then
    echo -e "  • TLS is disabled, applying no-TLS configuration with certificates"
    kubectl apply -f "${REPO_ROOT}/networking/cilium/no-tls/hubble-relay-config-no-tls-with-certs.yaml"
    kubectl apply -f "${REPO_ROOT}/networking/cilium/no-tls/hubble-relay-deployment-no-tls-with-certs.yaml"
    kubectl apply -f "${REPO_ROOT}/networking/cilium/no-tls/hubble-ui-deployment-no-tls.yaml"
else
    echo -e "  • TLS is enabled, fixing standard TLS configuration"
    kubectl apply -f "${REPO_ROOT}/networking/cilium/hubble-relay-config.yaml"
    kubectl apply -k "${REPO_ROOT}/networking/"
fi

# Check and fix services if needed
echo -e "${YELLOW}→ Checking Hubble services...${NC}"

# Restart the pods to apply the changes
echo -e "${YELLOW}→ Restarting Hubble pods to apply changes...${NC}"
kubectl delete pod -n cilium -l k8s-app=hubble-relay --grace-period=0 --force
kubectl delete pod -n cilium -l k8s-app=hubble-ui --grace-period=0 --force

# Wait for the pods to be ready
echo -e "${YELLOW}→ Waiting for Hubble pods to be ready...${NC}"
echo -e "  • Waiting for Hubble Relay"
kubectl rollout status deployment/hubble-relay -n cilium --timeout=120s
echo -e "  • Waiting for Hubble UI"
kubectl rollout status deployment/hubble-ui -n cilium --timeout=120s

# Verify that everything is working
echo -e "${YELLOW}→ Verifying Hubble components...${NC}"
RELAY_READY=$(kubectl get pods -n cilium -l k8s-app=hubble-relay -o jsonpath='{.items[0].status.containerStatuses[0].ready}')
UI_READY=$(kubectl get pods -n cilium -l k8s-app=hubble-ui -o jsonpath='{.items[0].status.containerStatuses[*].ready}' | grep -c "true")

if [[ "$RELAY_READY" == "true" ]]; then
    echo -e "${GREEN}✅ Hubble Relay is running properly${NC}"
else
    echo -e "${RED}❌ Hubble Relay is still having issues${NC}"
    echo -e "   Checking logs:"
    kubectl logs -n cilium -l k8s-app=hubble-relay --tail=20
fi

if [[ "$UI_READY" -eq 2 ]]; then
    echo -e "${GREEN}✅ Hubble UI is running properly${NC}"
else
    echo -e "${RED}❌ Hubble UI is still having issues${NC}"
    echo -e "   Checking logs for UI container:"
    kubectl logs -n cilium -l k8s-app=hubble-ui -c ui --tail=10 2>/dev/null || echo "UI container not found"
    echo -e "   Checking logs for backend container:"
    kubectl logs -n cilium -l k8s-app=hubble-ui -c backend --tail=10
fi

echo ""
echo -e "${GREEN}→ Setup complete!${NC}"
echo -e "   To use Hubble UI locally:"
echo -e "   ${YELLOW}kubectl port-forward -n cilium svc/hubble-ui 12000:80${NC}"
