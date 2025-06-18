#!/bin/bash
# Deploy and manage Kubernetes metrics-server with security validation
# Usage: ./deploy-metrics-server.sh [deploy|delete|status|logs|security-check]

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

security_check() {
    log_info "Running security validation checks..."
    
    local issues=0
    
    echo -e "\n${BLUE}Security Context Validation:${NC}"
    local security_context
    security_context=$(kubectl get pod -n kube-system -l k8s-app=metrics-server -o jsonpath='{.items[0].spec.securityContext}' 2>/dev/null || echo "")
    
    if [[ -n "$security_context" ]]; then
        echo "✅ Pod security context configured"
        echo "$security_context" | jq .
    else
        echo "❌ No pod security context found"
        ((issues++))
    fi
    
    echo -e "\n${BLUE}Container Security Context:${NC}"
    local container_security
    container_security=$(kubectl get pod -n kube-system -l k8s-app=metrics-server -o jsonpath='{.items[0].spec.containers[0].securityContext}' 2>/dev/null || echo "")
    
    if echo "$container_security" | grep -q "runAsUser.*65534"; then
        echo "✅ Running as nobody user (65534)"
    else
        echo "❌ Not running as nobody user"
        ((issues++))
    fi
    
    if echo "$container_security" | grep -q "readOnlyRootFilesystem.*true"; then
        echo "✅ Read-only root filesystem enabled"
    else
        echo "❌ Read-only root filesystem not enabled"
        ((issues++))
    fi
    
    echo -e "\n${BLUE}Network Policy Validation:${NC}"
    if kubectl get networkpolicy metrics-server-netpol -n kube-system &> /dev/null; then
        echo "✅ Network policy exists"
        kubectl describe networkpolicy metrics-server-netpol -n kube-system | grep -A 10 "Spec:"
    else
        echo "❌ Network policy not found"
        ((issues++))
    fi
    
    echo -e "\n${BLUE}Resource Limits Check:${NC}"
    local limits
    limits=$(kubectl get pod -n kube-system -l k8s-app=metrics-server -o jsonpath='{.items[0].spec.containers[0].resources.limits}' 2>/dev/null || echo "")
    
    if [[ -n "$limits" ]] && echo "$limits" | grep -q "cpu\|memory"; then
        echo "✅ Resource limits configured"
        echo "$limits" | jq .
    else
        echo "❌ Resource limits not configured"
        ((issues++))
    fi
    
    echo -e "\n${BLUE}TLS Configuration Check:${NC}"
    local args
    args=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || echo "")
    
    if echo "$args" | grep -q "kubelet-insecure-tls"; then
        echo "⚠️  kubelet-insecure-tls enabled (required for Talos)"
    fi
    
    if echo "$args" | grep -q "requestheader-client-ca-file"; then
        echo "✅ Request header authentication configured"
    else
        echo "❌ Request header authentication not configured"
        ((issues++))
    fi
    
    echo -e "\n${BLUE}RBAC Validation:${NC}"
    if kubectl auth can-i get nodes/metrics --as=system:serviceaccount:kube-system:metrics-server &> /dev/null; then
        echo "✅ Service account has required permissions"
    else
        echo "❌ Service account missing required permissions"
        ((issues++))
    fi
    
    echo -e "\n${BLUE}Security Summary:${NC}"
    if [[ $issues -eq 0 ]]; then
        log_success "All security checks passed! 🔒"
    else
        log_warning "$issues security issues found. Review configuration."
    fi
    
    return $issues
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
        security-check)
            security_check
            ;;
        help|--help|-h)
            echo "Usage: $0 [deploy|delete|status|logs|security-check]"
            echo ""
            echo "Commands:"
            echo "  deploy         - Deploy metrics-server (default)"
            echo "  delete         - Delete metrics-server"
            echo "  status         - Show metrics-server status"
            echo "  logs           - Show metrics-server logs"
            echo "  security-check - Run security validation checks"
            echo "  help           - Show this help message"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
