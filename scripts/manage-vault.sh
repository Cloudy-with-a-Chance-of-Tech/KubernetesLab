#!/bin/bash

# HashiCorp Vault Management Script
# Common operations for Vault administration

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
VAULT_PORT="8200"

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
    echo -e "${GREEN}$1${NC}"
    echo "$(echo "$1" | sed 's/./=/g')"
}

# Function to get Vault address
get_vault_address() {
    VAULT_EXTERNAL_IP=$(kubectl get svc $VAULT_SERVICE -n $VAULT_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -z "$VAULT_EXTERNAL_IP" ]; then
        echo "http://localhost:8200"
    else
        echo "http://$VAULT_EXTERNAL_IP:$VAULT_PORT"
    fi
}

# Function to get root token
get_root_token() {
    kubectl get secret vault-root-token -n $VAULT_NAMESPACE -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d
}

# Function to get unseal key
get_unseal_key() {
    kubectl get secret vault-unseal-keys -n $VAULT_NAMESPACE -o jsonpath='{.data.unseal-key}' 2>/dev/null | base64 -d
}

# Function to check vault status
vault_status() {
    print_header "🔐 Vault Status"
    
    local vault_addr=$(get_vault_address)
    export VAULT_ADDR=$vault_addr
    
    print_info "Vault Address: $vault_addr"
    
    # Check if Vault is reachable
    if curl -s "$vault_addr/v1/sys/health" &>/dev/null; then
        print_status 0 "Vault is reachable"
    else
        print_status 1 "Vault is not reachable"
        return 1
    fi
    
    # Get health status
    local health_response=$(curl -s "$vault_addr/v1/sys/health" || echo '{}')
    local sealed=$(echo "$health_response" | jq -r '.sealed // "unknown"')
    local initialized=$(echo "$health_response" | jq -r '.initialized // "unknown"')
    local version=$(echo "$health_response" | jq -r '.version // "unknown"')
    
    print_info "Initialized: $initialized"
    print_info "Sealed: $sealed"
    print_info "Version: $version"
    
    # Check Kubernetes deployment
    if kubectl get deployment vault -n $VAULT_NAMESPACE &>/dev/null; then
        local ready_replicas=$(kubectl get deployment vault -n $VAULT_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_replicas=$(kubectl get deployment vault -n $VAULT_NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        print_info "Deployment: $ready_replicas/$desired_replicas replicas ready"
    else
        print_status 1 "Vault deployment not found"
    fi
}

# Function to unseal vault
vault_unseal() {
    print_header "🔓 Unsealing Vault"
    
    local vault_addr=$(get_vault_address)
    local unseal_key=$(get_unseal_key)
    
    if [ -z "$unseal_key" ]; then
        print_status 1 "Unseal key not found in Kubernetes secret"
        return 1
    fi
    
    print_info "Attempting to unseal Vault..."
    local unseal_response=$(curl -s -X PUT "$vault_addr/v1/sys/unseal" -d "{\"key\":\"$unseal_key\"}")
    
    if echo "$unseal_response" | grep -q '"sealed":false'; then
        print_status 0 "Vault successfully unsealed"
    else
        print_status 1 "Failed to unseal Vault"
        echo "Response: $unseal_response"
        return 1
    fi
}

# Function to backup vault data
vault_backup() {
    print_header "💾 Backing up Vault Data"
    
    local backup_dir="./vault-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    print_info "Creating backup in: $backup_dir"
    
    # Backup Kubernetes secrets
    print_info "Backing up Vault secrets..."
    kubectl get secret vault-root-token -n $VAULT_NAMESPACE -o yaml > "$backup_dir/vault-root-token.yaml" 2>/dev/null || true
    kubectl get secret vault-unseal-keys -n $VAULT_NAMESPACE -o yaml > "$backup_dir/vault-unseal-keys.yaml" 2>/dev/null || true
    
    # Backup configuration
    print_info "Backing up Vault configuration..."
    kubectl get configmap vault-config -n $VAULT_NAMESPACE -o yaml > "$backup_dir/vault-config.yaml" 2>/dev/null || true
    
    # Backup deployment manifests
    print_info "Backing up deployment manifests..."
    kubectl get deployment vault -n $VAULT_NAMESPACE -o yaml > "$backup_dir/vault-deployment.yaml" 2>/dev/null || true
    kubectl get service vault -n $VAULT_NAMESPACE -o yaml > "$backup_dir/vault-service.yaml" 2>/dev/null || true
    kubectl get service vault-external -n $VAULT_NAMESPACE -o yaml > "$backup_dir/vault-external-service.yaml" 2>/dev/null || true
    
    # Create backup script
    cat > "$backup_dir/restore.sh" << 'EOF'
#!/bin/bash
# Vault backup restore script
echo "Restoring Vault backup..."
kubectl apply -f vault-root-token.yaml
kubectl apply -f vault-unseal-keys.yaml
kubectl apply -f vault-config.yaml
echo "Backup restored. Redeploy Vault if needed."
EOF
    chmod +x "$backup_dir/restore.sh"
    
    print_status 0 "Backup completed in: $backup_dir"
}

# Function to show vault logs
vault_logs() {
    print_header "📝 Vault Logs"
    
    if kubectl get pods -l app.kubernetes.io/name=vault -n $VAULT_NAMESPACE &>/dev/null; then
        kubectl logs -l app.kubernetes.io/name=vault -n $VAULT_NAMESPACE --tail=50 -f
    else
        print_status 1 "No Vault pods found"
    fi
}

# Function to access vault CLI
vault_cli() {
    print_header "💻 Vault CLI Access"
    
    local vault_addr=$(get_vault_address)
    local root_token=$(get_root_token)
    
    if [ -z "$root_token" ]; then
        print_status 1 "Root token not found in Kubernetes secret"
        return 1
    fi
    
    print_info "Starting Vault CLI session..."
    print_info "Vault Address: $vault_addr"
    print_warning "Using root token - use with caution!"
    
    export VAULT_ADDR=$vault_addr
    export VAULT_TOKEN=$root_token
    
    # Check if vault CLI is available
    if command -v vault &> /dev/null; then
        echo "Type 'exit' to return to management script"
        vault status
        bash
    else
        print_warning "Vault CLI not installed locally"
        print_info "You can access Vault via:"
        print_info "  Address: $vault_addr"
        print_info "  Token: $root_token"
        print_info "  UI: $vault_addr/ui"
    fi
}

# Function to show help
show_help() {
    print_header "🔐 HashiCorp Vault Management"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  status    - Show Vault status and health"
    echo "  unseal    - Unseal Vault using stored key"
    echo "  backup    - Create backup of Vault data and config"
    echo "  logs      - Show Vault logs (follow mode)"
    echo "  cli       - Access Vault CLI with root token"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 status          # Check Vault health"
    echo "  $0 unseal          # Unseal Vault"
    echo "  $0 backup          # Create backup"
    echo "  $0 logs            # View logs"
    echo ""
}

# Main script logic
case "${1:-help}" in
    "status")
        vault_status
        ;;
    "unseal")
        vault_unseal
        ;;
    "backup")
        vault_backup
        ;;
    "logs")
        vault_logs
        ;;
    "cli")
        vault_cli
        ;;
    "help"|*)
        show_help
        ;;
esac
