#!/bin/bash

# HashiCorp Vault Initialization Script
# Initializes Vault with single unseal key and sets up basic configuration

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VAULT_NAMESPACE="vault"
VAULT_SERVICE="vault-external"
VAULT_PORT="8200"
INIT_OUTPUT_FILE="/tmp/vault-init.json"
UNSEAL_KEY_FILE="/tmp/vault-unseal-key"

echo -e "${GREEN}🔐 HashiCorp Vault Initialization${NC}"
echo "=================================="

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

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_status 1 "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if Vault is deployed
print_info "Checking Vault deployment status..."
if ! kubectl get deployment vault -n $VAULT_NAMESPACE &>/dev/null; then
    print_status 1 "Vault deployment not found in namespace $VAULT_NAMESPACE"
    print_info "Please deploy Vault first using: kubectl apply -k security/"
    exit 1
fi

# Wait for Vault to be ready
print_info "Waiting for Vault pod to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n $VAULT_NAMESPACE --timeout=300s
print_status $? "Vault pod is ready"

# Get Vault external IP
print_info "Getting Vault external access information..."
VAULT_EXTERNAL_IP=$(kubectl get svc $VAULT_SERVICE -n $VAULT_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$VAULT_EXTERNAL_IP" ]; then
    print_warning "LoadBalancer IP not yet assigned, using port-forward"
    # Start port-forward in background
    kubectl port-forward svc/vault -n $VAULT_NAMESPACE 8200:8200 &
    PORT_FORWARD_PID=$!
    sleep 5
    VAULT_ADDR="http://localhost:8200"
else
    VAULT_ADDR="http://$VAULT_EXTERNAL_IP:$VAULT_PORT"
    print_status 0 "Vault accessible at $VAULT_ADDR"
fi

export VAULT_ADDR

# Check if Vault is already initialized
print_info "Checking Vault initialization status..."
if curl -s "$VAULT_ADDR/v1/sys/init" | grep -q '"initialized":true'; then
    print_warning "Vault is already initialized"
    
    # Check if unseal key secret exists
    if kubectl get secret vault-unseal-keys -n $VAULT_NAMESPACE &>/dev/null; then
        print_status 0 "Vault unseal key secret already exists"
        
        # Get the unseal key and try to unseal
        UNSEAL_KEY=$(kubectl get secret vault-unseal-keys -n $VAULT_NAMESPACE -o jsonpath='{.data.unseal-key}' | base64 -d)
        
        print_info "Attempting to unseal Vault..."
        if curl -s -X PUT "$VAULT_ADDR/v1/sys/unseal" -d "{\"key\":\"$UNSEAL_KEY\"}" | grep -q '"sealed":false'; then
            print_status 0 "Vault successfully unsealed"
        else
            print_warning "Failed to unseal Vault or already unsealed"
        fi
    else
        print_warning "Vault is initialized but unseal key secret not found"
        print_info "Manual intervention may be required"
    fi
    
    cleanup_and_exit 0
fi

# Initialize Vault with single key threshold
print_info "Initializing Vault with single unseal key..."
INIT_RESPONSE=$(curl -s -X PUT "$VAULT_ADDR/v1/sys/init" \
    -d '{
        "secret_shares": 1,
        "secret_threshold": 1
    }')

if [ $? -eq 0 ] && echo "$INIT_RESPONSE" | grep -q "keys"; then
    print_status 0 "Vault initialized successfully"
    echo "$INIT_RESPONSE" > "$INIT_OUTPUT_FILE"
else
    print_status 1 "Failed to initialize Vault"
    echo "Response: $INIT_RESPONSE"
    cleanup_and_exit 1
fi

# Extract keys from response
UNSEAL_KEY=$(echo "$INIT_RESPONSE" | jq -r '.keys[0]')
ROOT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r '.root_token')

if [ "$UNSEAL_KEY" = "null" ] || [ "$ROOT_TOKEN" = "null" ]; then
    print_status 1 "Failed to extract keys from initialization response"
    cleanup_and_exit 1
fi

# Store unseal key in Kubernetes secret
print_info "Storing unseal key in Kubernetes secret..."
kubectl create secret generic vault-unseal-keys \
    --from-literal=unseal-key="$UNSEAL_KEY" \
    --namespace=$VAULT_NAMESPACE \
    --dry-run=client -o yaml | kubectl apply -f -

print_status $? "Unseal key stored in Kubernetes secret"

# Store root token in Kubernetes secret (for CI/CD access)
print_info "Storing root token in Kubernetes secret..."
kubectl create secret generic vault-root-token \
    --from-literal=root-token="$ROOT_TOKEN" \
    --namespace=$VAULT_NAMESPACE \
    --dry-run=client -o yaml | kubectl apply -f -

print_status $? "Root token stored in Kubernetes secret"

# Unseal Vault
print_info "Unsealing Vault..."
UNSEAL_RESPONSE=$(curl -s -X PUT "$VAULT_ADDR/v1/sys/unseal" -d "{\"key\":\"$UNSEAL_KEY\"}")

if echo "$UNSEAL_RESPONSE" | grep -q '"sealed":false'; then
    print_status 0 "Vault successfully unsealed"
else
    print_status 1 "Failed to unseal Vault"
    echo "Response: $UNSEAL_RESPONSE"
    cleanup_and_exit 1
fi

# Configure basic Vault settings
print_info "Configuring basic Vault settings..."
export VAULT_TOKEN="$ROOT_TOKEN"

# Enable Kubernetes auth backend
print_info "Enabling Kubernetes auth backend..."
curl -s -X POST "$VAULT_ADDR/v1/sys/auth/kubernetes" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -d '{"type": "kubernetes"}'

# Configure Kubernetes auth
print_info "Configuring Kubernetes auth backend..."
KUBERNETES_HOST="https://kubernetes.default.svc.kub-cluster.local"
KUBERNETES_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].kub-clustercertificate-authority-data}' | base64 -d)

curl -s -X POST "$VAULT_ADDR/v1/auth/kubernetes/config" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -d "{
        \"kubernetes_host\": \"$KUBERNETES_HOST\",
        \"kubernetes_ca_cert\": \"$KUBERNETES_CA_CERT\"
    }"

print_status $? "Kubernetes auth backend configured"

# Enable KV v2 secrets engine
print_info "Enabling KV v2 secrets engine..."
curl -s -X POST "$VAULT_ADDR/v1/sys/mounts/secret" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -d '{
        "type": "kv",
        "options": {
            "version": "2"
        }
    }'

print_status $? "KV v2 secrets engine enabled"

# Cleanup function
cleanup_and_exit() {
    if [ -n "$PORT_FORWARD_PID" ]; then
        print_info "Cleaning up port-forward..."
        kill $PORT_FORWARD_PID 2>/dev/null || true
    fi
    
    # Clean up temporary files
    rm -f "$INIT_OUTPUT_FILE" "$UNSEAL_KEY_FILE"
    
    exit $1
}

# Final status
echo ""
echo -e "${GREEN}🎉 Vault Initialization Complete!${NC}"
echo "=================================="
print_info "Vault Address: $VAULT_ADDR"
print_info "Vault UI: $VAULT_ADDR/ui"
print_info "Root token stored in: vault-root-token secret"
print_info "Unseal key stored in: vault-unseal-keys secret"
echo ""
print_warning "SECURITY REMINDER:"
print_info "- The root token has unlimited access - use it sparingly"
print_info "- Create additional auth methods and policies for regular use"
print_info "- Consider rotating the root token after setup"
print_info "- Monitor Vault access logs and audit trails"

cleanup_and_exit 0
