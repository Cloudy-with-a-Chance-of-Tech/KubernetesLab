#!/bin/bash
# deploy-phoenix-runner.sh - Secure deployment script for Phoenix runner
# Usage: ./deploy-phoenix-runner.sh [local|github]

set -euo pipefail

DEPLOYMENT_MODE=${1:-local}
NAMESPACE="github-actions"
RUNNER_NAME="phoenix-runner"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check if required tools are available
check_prerequisites() {
    log "Checking prerequisites..."
    
    command -v kubectl >/dev/null 2>&1 || error "kubectl is required but not installed"
    command -v base64 >/dev/null 2>&1 || error "base64 is required but not installed"
    
    # Check if cluster is accessible
    kubectl cluster-info >/dev/null 2>&1 || error "Cannot connect to Kubernetes cluster"
    
    log "Prerequisites check passed"
}

# Function to load environment variables securely
load_env_vars() {
    if [ "$DEPLOYMENT_MODE" = "local" ]; then
        # Load from .env file for local development
        if [ -f ".env" ]; then
            log "Loading environment variables from .env file"
            source .env
        else
            warn ".env file not found, using environment variables"
        fi
        
        # Check required variables
        if [ -z "${PHOENIX_RUNNER_TOKEN:-}" ]; then
            error "PHOENIX_RUNNER_TOKEN environment variable is required"
        fi
        
        if [ -z "${PHOENIX_REPO_URL:-}" ]; then
            error "PHOENIX_REPO_URL environment variable is required"
        fi
        
    elif [ "$DEPLOYMENT_MODE" = "github" ]; then
        # In GitHub Actions, secrets are passed as environment variables
        log "Using GitHub Actions environment variables"
        
        # Check required variables
        if [ -z "${PHOENIX_RUNNER_TOKEN:-}" ]; then
            error "PHOENIX_RUNNER_TOKEN secret is required in GitHub Actions"
        fi
        
        if [ -z "${PHOENIX_REPO_URL:-}" ]; then
            error "PHOENIX_REPO_URL secret is required in GitHub Actions"
        fi
    else
        error "Invalid deployment mode. Use 'local' or 'github'"
    fi
}

# Function to create namespace if it doesn't exist
ensure_namespace() {
    log "Ensuring namespace $NAMESPACE exists..."
    
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        kubectl create namespace "$NAMESPACE"
        log "Created namespace $NAMESPACE"
    else
        log "Namespace $NAMESPACE already exists"
    fi
}

# Function to apply RBAC
apply_rbac() {
    log "Applying RBAC configuration..."
    kubectl apply -f base/rbac/phoenix-runner-rbac.yaml
    log "RBAC configuration applied"
}

# Function to create secret securely
create_secret() {
    log "Creating runner secret..."
    
    # Delete existing secret if it exists
    kubectl delete secret "${RUNNER_NAME}-secret" -n "$NAMESPACE" 2>/dev/null || true
    
    # Create new secret
    kubectl create secret generic "${RUNNER_NAME}-secret" \
        --namespace="$NAMESPACE" \
        --from-literal=github-token="$PHOENIX_RUNNER_TOKEN" \
        --from-literal=runner-name="phoenix-k8s-runner" \
        --from-literal=repo-url="$PHOENIX_REPO_URL"
    
    # Add labels for better management
    kubectl label secret "${RUNNER_NAME}-secret" \
        -n "$NAMESPACE" \
        app.kubernetes.io/name="$RUNNER_NAME" \
        app.kubernetes.io/component="secret" \
        app.kubernetes.io/part-of="cicd"
    
    log "Secret created successfully"
}

# Function to deploy the runner
deploy_runner() {
    log "Deploying Phoenix runner..."
    
    # Apply the deployment
    kubectl apply -f apps/production/phoenix-runner.yaml
    
    # Wait for deployment to be ready
    log "Waiting for deployment to be ready..."
    kubectl rollout status deployment/"$RUNNER_NAME" -n "$NAMESPACE" --timeout=300s
    
    log "Phoenix runner deployed successfully"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check if pods are running
    PODS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$RUNNER_NAME" --no-headers)
    if [ -z "$PODS" ]; then
        error "No pods found for $RUNNER_NAME"
    fi
    
    # Check pod status
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$RUNNER_NAME"
    
    # Show logs
    log "Recent logs from runner:"
    kubectl logs -n "$NAMESPACE" deployment/"$RUNNER_NAME" --tail=20 || warn "Could not retrieve logs"
    
    log "Deployment verification completed"
}

# Function to show usage instructions
show_usage() {
    cat << EOF

✅ Phoenix GitHub Runner Deployed Successfully!

📋 Next Steps:
1. Check your GitHub repository settings for the self-hosted runner
2. You should see a self-hosted runner with labels:
   - kubernetes, talos, cilium, homelab, arm64, phoenix

3. Use the runner in your workflows:
   runs-on: [self-hosted, kubernetes, phoenix]

📊 Monitoring Commands:
- Check pods: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$RUNNER_NAME
- View logs: kubectl logs -n $NAMESPACE deployment/$RUNNER_NAME -f
- Check HPA: kubectl get hpa -n $NAMESPACE ${RUNNER_NAME}-hpa

🔐 Security Notes:
- Secret is stored in Kubernetes (base64 encoded)
- For production, consider External Secrets Operator
- Token is only accessible to the runner ServiceAccount

EOF
}

# Main execution
main() {
    log "Starting Phoenix runner deployment in $DEPLOYMENT_MODE mode"
    
    check_prerequisites
    load_env_vars
    ensure_namespace
    apply_rbac
    create_secret
    deploy_runner
    verify_deployment
    show_usage
    
    log "Deployment completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    "local"|"github"|"")
        main
        ;;
    "-h"|"--help")
        cat << EOF
Usage: $0 [MODE]

Deploy Phoenix GitHub Actions runner securely

Modes:
  local     - Local development (uses .env file)
  github    - GitHub Actions (uses environment variables)

Environment Variables Required:
  PHOENIX_RUNNER_TOKEN - GitHub Personal Access Token with repo scope
  PHOENIX_REPO_URL - Full repository URL (https://github.com/username/repo)

Examples:
  $0 local          # Deploy locally using .env file
  $0 github         # Deploy in GitHub Actions
  
EOF
        ;;
    *)
        error "Invalid argument. Use '$0 --help' for usage information"
        ;;
esac
