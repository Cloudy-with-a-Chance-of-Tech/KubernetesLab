#!/bin/bash

# Vault Deployment Validation Script
# Comprehensive validation of Vault deployment and security configuration

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_NAMESPACE="vault"
VAULT_SERVICE="vault-external"
VAULT_STATIC_IP="192.168.100.102"

echo -e "${GREEN}🔐 HashiCorp Vault Deployment Validation${NC}"
echo "=========================================="

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
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_header() {
    echo ""
    echo -e "${GREEN}$1${NC}"
    echo "$(echo "$1" | sed 's/./=/g')"
}

# Check prerequisites
print_header "1️⃣  Prerequisites Check"

if ! command -v kubectl &> /dev/null; then
    print_status 1 "kubectl is not installed or not in PATH"
    exit 1
fi
print_status 0 "kubectl is available"

if ! kubectl cluster-info &>/dev/null; then
    print_status 1 "Cannot access Kubernetes cluster"
    exit 1
fi
print_status 0 "Kubernetes cluster is accessible"

# Check namespace
print_header "2️⃣  Vault Namespace Validation"

if kubectl get namespace $VAULT_NAMESPACE &>/dev/null; then
    print_status 0 "Vault namespace exists"
    
    # Check pod security standards
    PSS_ENFORCE=$(kubectl get namespace $VAULT_NAMESPACE -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "none")
    if [ "$PSS_ENFORCE" = "baseline" ]; then
        print_status 0 "Pod security standards set to baseline (required for Vault)"
    else
        print_warning "Pod security standards: $PSS_ENFORCE (should be baseline)"
    fi
else
    print_status 1 "Vault namespace does not exist"
fi

# Check RBAC
print_header "3️⃣  RBAC Validation"

if kubectl get serviceaccount vault -n $VAULT_NAMESPACE &>/dev/null; then
    print_status 0 "Vault service account exists"
else
    print_status 1 "Vault service account missing"
fi

if kubectl get clusterrole vault-auth &>/dev/null; then
    print_status 0 "Vault cluster role exists"
else
    print_status 1 "Vault cluster role missing"
fi

if kubectl get clusterrolebinding vault-auth &>/dev/null; then
    print_status 0 "Vault cluster role binding exists"
else
    print_status 1 "Vault cluster role binding missing"
fi

# Check configuration
print_header "4️⃣  Configuration Validation"

if kubectl get configmap vault-config -n $VAULT_NAMESPACE &>/dev/null; then
    print_status 0 "Vault configuration ConfigMap exists"
    
    # Check for key configuration elements
    CONFIG_CONTENT=$(kubectl get configmap vault-config -n $VAULT_NAMESPACE -o jsonpath='{.data.vault\.hcl}' 2>/dev/null || echo "")
    
    if echo "$CONFIG_CONTENT" | grep -q "disable_mlock = true"; then
        print_status 0 "Vault mlock disabled (required for containers)"
    else
        print_warning "Vault mlock configuration not found"
    fi
    
    if echo "$CONFIG_CONTENT" | grep -q "ui = true"; then
        print_status 0 "Vault UI enabled"
    else
        print_warning "Vault UI not enabled"
    fi
else
    print_status 1 "Vault configuration ConfigMap missing"
fi

# Check storage
print_header "5️⃣  Storage Validation"

if kubectl get pvc vault-data -n $VAULT_NAMESPACE &>/dev/null; then
    print_status 0 "Vault persistent volume claim exists"
    
    PVC_STATUS=$(kubectl get pvc vault-data -n $VAULT_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$PVC_STATUS" = "Bound" ]; then
        print_status 0 "Vault PVC is bound"
    else
        print_warning "Vault PVC status: $PVC_STATUS"
    fi
else
    print_status 1 "Vault persistent volume claim missing"
fi

# Check deployment
print_header "6️⃣  Deployment Validation"

if kubectl get deployment vault -n $VAULT_NAMESPACE &>/dev/null; then
    print_status 0 "Vault deployment exists"
    
    READY_REPLICAS=$(kubectl get deployment vault -n $VAULT_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED_REPLICAS=$(kubectl get deployment vault -n $VAULT_NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$READY_REPLICAS" -eq "$DESIRED_REPLICAS" ] && [ "$READY_REPLICAS" -gt 0 ]; then
        print_status 0 "Vault deployment ready ($READY_REPLICAS/$DESIRED_REPLICAS replicas)"
    else
        print_warning "Vault deployment not ready ($READY_REPLICAS/$DESIRED_REPLICAS replicas)"
    fi
    
    # Check pod security context
    print_info "Checking security context..."
    
    # Check if pods are running as non-root
    PODS=$(kubectl get pods -n $VAULT_NAMESPACE -l app.kubernetes.io/name=vault -o name 2>/dev/null || echo "")
    if [ -n "$PODS" ]; then
        for pod in $PODS; do
            RUN_AS_USER=$(kubectl get $pod -n $VAULT_NAMESPACE -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null || echo "0")
            if [ "$RUN_AS_USER" -ne 0 ]; then
                print_status 0 "Pod running as non-root user ($RUN_AS_USER)"
            else
                print_warning "Pod may be running as root"
            fi
        done
    fi
else
    print_status 1 "Vault deployment does not exist"
fi

# Check services
print_header "7️⃣  Service Validation"

# Internal service
if kubectl get service vault -n $VAULT_NAMESPACE &>/dev/null; then
    print_status 0 "Vault internal service exists"
else
    print_status 1 "Vault internal service missing"
fi

# External service
if kubectl get service $VAULT_SERVICE -n $VAULT_NAMESPACE &>/dev/null; then
    print_status 0 "Vault external service exists"
    
    LOAD_BALANCER_IP=$(kubectl get service $VAULT_SERVICE -n $VAULT_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    CONFIGURED_IP=$(kubectl get service $VAULT_SERVICE -n $VAULT_NAMESPACE -o jsonpath='{.spec.loadBalancerIP}' 2>/dev/null || echo "")
    
    if [ "$CONFIGURED_IP" = "$VAULT_STATIC_IP" ]; then
        print_status 0 "Static IP configured ($VAULT_STATIC_IP)"
    else
        print_warning "Static IP not configured (expected: $VAULT_STATIC_IP, found: $CONFIGURED_IP)"
    fi
    
    if [ -n "$LOAD_BALANCER_IP" ]; then
        print_status 0 "LoadBalancer IP assigned ($LOAD_BALANCER_IP)"
    else
        print_warning "LoadBalancer IP not yet assigned"
    fi
else
    print_status 1 "Vault external service missing"
fi

# Check network policies
print_header "8️⃣  Network Policy Validation"

NETWORK_POLICIES=$(kubectl get cnp -n $VAULT_NAMESPACE 2>/dev/null | wc -l)
if [ "$NETWORK_POLICIES" -gt 1 ]; then
    print_status 0 "Vault network policies configured ($((NETWORK_POLICIES-1)) policies)"
    
    # Check specific policies
    REQUIRED_POLICIES=(
        "vault-default-deny"
        "vault-to-kubernetes-api"
        "vault-dns-access"
        "vault-external-access"
        "vault-external-egress"
        "vault-internal-communication"
    )
    
    for policy in "${REQUIRED_POLICIES[@]}"; do
        if kubectl get cnp $policy -n $VAULT_NAMESPACE &>/dev/null; then
            print_status 0 "Network policy exists: $policy"
        else
            print_warning "Network policy missing: $policy"
        fi
    done
else
    print_warning "No network policies found for Vault"
fi

# Check Vault health
print_header "9️⃣  Vault Health Check"

if [ -n "$LOAD_BALANCER_IP" ]; then
    VAULT_ADDR="http://$LOAD_BALANCER_IP:8200"
    print_info "Testing Vault at: $VAULT_ADDR"
    
    # Test connectivity
    if curl -s --connect-timeout 5 "$VAULT_ADDR/v1/sys/health" &>/dev/null; then
        print_status 0 "Vault is reachable"
        
        # Get health status
        HEALTH_RESPONSE=$(curl -s "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo '{}')
        
        INITIALIZED=$(echo "$HEALTH_RESPONSE" | grep -o '"initialized":[^,}]*' | cut -d':' -f2 | tr -d ' "')
        SEALED=$(echo "$HEALTH_RESPONSE" | grep -o '"sealed":[^,}]*' | cut -d':' -f2 | tr -d ' "')
        VERSION=$(echo "$HEALTH_RESPONSE" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        
        print_info "Vault version: ${VERSION:-unknown}"
        print_info "Initialized: ${INITIALIZED:-unknown}"
        print_info "Sealed: ${SEALED:-unknown}"
        
        if [ "$INITIALIZED" = "true" ]; then
            print_status 0 "Vault is initialized"
        else
            print_warning "Vault is not initialized (run scripts/initialize-vault.sh)"
        fi
        
        if [ "$SEALED" = "false" ]; then
            print_status 0 "Vault is unsealed"
        elif [ "$SEALED" = "true" ]; then
            print_warning "Vault is sealed (run scripts/manage-vault.sh unseal)"
        fi
        
    else
        print_status 1 "Vault is not reachable"
    fi
else
    print_warning "Cannot test Vault health - LoadBalancer IP not assigned"
fi

# Check secrets
print_header "🔟 Secret Management Validation"

if kubectl get secret vault-root-token -n $VAULT_NAMESPACE &>/dev/null; then
    print_status 0 "Vault root token secret exists"
else
    print_warning "Vault root token secret not found (initialization needed)"
fi

if kubectl get secret vault-unseal-keys -n $VAULT_NAMESPACE &>/dev/null; then
    print_status 0 "Vault unseal keys secret exists"
else
    print_warning "Vault unseal keys secret not found (initialization needed)"
fi

# Summary
print_header "📋 Validation Summary"

echo "External Access:"
echo "  🌐 Vault UI:  http://$VAULT_STATIC_IP:8200/ui"
echo "  🔌 Vault API: http://$VAULT_STATIC_IP:8200"
echo ""
echo "Management Commands:"
echo "  📊 Status:      scripts/manage-vault.sh status"
echo "  🔓 Unseal:      scripts/manage-vault.sh unseal"
echo "  ⚙️  Initialize:  scripts/initialize-vault.sh"
echo "  💻 CLI Access:  scripts/manage-vault.sh cli"
echo ""

if [ -n "$LOAD_BALANCER_IP" ] && [ "$LOAD_BALANCER_IP" = "$VAULT_STATIC_IP" ]; then
    if [ "$INITIALIZED" = "true" ] && [ "$SEALED" = "false" ]; then
        print_status 0 "Vault is fully operational!"
    elif [ "$INITIALIZED" = "true" ] && [ "$SEALED" = "true" ]; then
        print_warning "Vault needs to be unsealed"
    elif [ "$INITIALIZED" != "true" ]; then
        print_warning "Vault needs to be initialized"
    fi
else
    print_warning "Vault deployment incomplete - check LoadBalancer configuration"
fi

echo ""
print_info "For detailed troubleshooting, see: docs/vault-deployment.md"
