#!/bin/bash
# Deploy and manage Kubernetes metrics-server
# Usage: ./deploy-metrics-server.sh [deploy|delete|status|logs]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
METRICS_SERVER_MANIFEST="$PROJECT_DIR/monitoring/metrics-server.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
}

check_cluster_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi
}

deploy_metrics_server() {
    log_info "Deploying metrics-server..."
    
    if [[ ! -f "$METRICS_SERVER_MANIFEST" ]]; then
        log_error "Metrics-server manifest not found at $METRICS_SERVER_MANIFEST"
        exit 1
    fi
    
    kubectl apply -f "$METRICS_SERVER_MANIFEST"
    
    log_info "Waiting for metrics-server to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/metrics-server -n kube-system
    
    log_success "Metrics-server deployed successfully!"
    
    # Wait a bit for metrics to populate
    log_info "Waiting for metrics to populate (30 seconds)..."
    sleep 30
    
    # Test metrics
    if kubectl top nodes &> /dev/null; then
        log_success "Metrics-server is working correctly!"
        kubectl top nodes
    else
        log_warning "Metrics not yet available. It may take a few more minutes."
    fi
}

delete_metrics_server() {
    log_info "Deleting metrics-server..."
    
    if [[ -f "$METRICS_SERVER_MANIFEST" ]]; then
        kubectl delete -f "$METRICS_SERVER_MANIFEST" --ignore-not-found=true
        log_success "Metrics-server deleted successfully!"
    else
        log_warning "Metrics-server manifest not found, attempting direct deletion..."
        kubectl delete deployment metrics-server -n kube-system --ignore-not-found=true
        kubectl delete service metrics-server -n kube-system --ignore-not-found=true
        kubectl delete serviceaccount metrics-server -n kube-system --ignore-not-found=true
    fi
}

show_status() {
    log_info "Metrics-server status:"
    
    echo -e "\n${BLUE}Deployment Status:${NC}"
    if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        kubectl get deployment metrics-server -n kube-system
        
        echo -e "\n${BLUE}Pod Status:${NC}"
        kubectl get pods -n kube-system -l k8s-app=metrics-server
        
        echo -e "\n${BLUE}Service Status:${NC}"
        kubectl get service metrics-server -n kube-system
        
        echo -e "\n${BLUE}APIService Status:${NC}"
        kubectl get apiservices v1beta1.metrics.k8s.io
        
        echo -e "\n${BLUE}Testing Metrics:${NC}"
        if kubectl top nodes &> /dev/null; then
            kubectl top nodes
        else
            log_warning "Metrics not available yet"
        fi
    else
        log_warning "Metrics-server is not deployed"
    fi
}

show_logs() {
    log_info "Metrics-server logs:"
    
    if kubectl get pods -n kube-system -l k8s-app=metrics-server &> /dev/null; then
        kubectl logs -n kube-system -l k8s-app=metrics-server --tail=100
    else
        log_error "No metrics-server pods found"
        exit 1
    fi
}

main() {
    check_kubectl
    check_cluster_connection
    
    case "${1:-deploy}" in
        deploy)
            deploy_metrics_server
            ;;
        delete)
            delete_metrics_server
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        help|--help|-h)
            echo "Usage: $0 [deploy|delete|status|logs]"
            echo ""
            echo "Commands:"
            echo "  deploy  - Deploy metrics-server (default)"
            echo "  delete  - Delete metrics-server"
            echo "  status  - Show metrics-server status"
            echo "  logs    - Show metrics-server logs"
            echo "  help    - Show this help message"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
