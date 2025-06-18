#!/bin/bash
# Detect cluster information for dynamic deployment configuration
# This script extracts cluster domain, name, and other environment details

set -euo pipefail

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

detect_cluster_domain() {
    # Method 1: Try to get domain from CoreDNS configmap
    local domain=""
    if kubectl get configmap coredns -n kube-system >/dev/null 2>&1; then
        # Look for custom domains first (non-default), then fallback to cluster.local
        local corefile=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null)
        # Extract domains from kubernetes directive, prefer custom domains over cluster.local
        domain=$(echo "$corefile" | grep -oP 'kubernetes\s+\K[^{]+' | tr ' ' '\n' | grep -v '^cluster\.local$\|^svc\.cluster\.local$\|in-addr\.arpa\|ip6\.arpa' | head -1 || echo "")
        
        # If no custom domain found, use cluster.local
        if [[ -z "$domain" ]]; then
            domain=$(echo "$corefile" | grep -oP 'kubernetes\s+\K[^{]+' | tr ' ' '\n' | grep 'cluster\.local' | head -1 || echo "")
        fi
    fi
    
    # Method 2: Try to get from kubelet config
    if [[ -z "$domain" ]]; then
        domain=$(kubectl get nodes -o jsonpath='{.items[0].status.config.kubelet.clusterDNS}' 2>/dev/null | \
                 grep -oP '(?<=\.)[^.]+\.local$' || echo "")
    fi
    
    # Method 3: Try to resolve kubernetes service and extract domain
    if [[ -z "$domain" ]]; then
        if kubectl run cluster-domain-test --image=busybox:1.35 --rm -it --restart=Never --quiet -- \
           nslookup kubernetes.default.svc 2>/dev/null | grep -q "kubernetes.default.svc."; then
            domain=$(kubectl run cluster-domain-test --image=busybox:1.35 --rm -it --restart=Never --quiet -- \
                    nslookup kubernetes.default.svc 2>/dev/null | \
                    grep "kubernetes.default.svc." | \
                    sed 's/.*kubernetes\.default\.svc\.\([^[:space:]]*\).*/\1/' | head -1 || echo "")
        fi
    fi
    
    # Method 4: Default fallback
    if [[ -z "$domain" ]]; then
        domain="cluster.local"
    fi
    
    echo "$domain"
}

detect_cluster_name() {
    # Method 1: Try to get from kubeconfig context
    local cluster_name=""
    local context=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ -n "$context" ]]; then
        # Extract cluster name from context (format: user@cluster or cluster)
        if [[ "$context" =~ @ ]]; then
            cluster_name="${context##*@}"  # Get part after @
        else
            cluster_name="$context"
        fi
    fi
    
    # Method 2: Try to get from cluster-info
    if [[ -z "$cluster_name" ]]; then
        cluster_name=$(kubectl cluster-info 2>/dev/null | grep "Kubernetes control plane" | \
                      grep -oP '(?<=https://)[^:]+' | sed 's/\..*$//' || echo "")
    fi
    
    # Method 3: Try to get from node labels
    if [[ -z "$cluster_name" ]]; then
        cluster_name=$(kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null | \
                      grep -oP '(?<="cluster-name":")[^"]+' || echo "")
    fi
    
    # Method 4: Default fallback
    if [[ -z "$cluster_name" ]]; then
        cluster_name="kubernetes"
    fi
    
    echo "$cluster_name"
}

detect_cluster_region() {
    # Try to get region from node labels (common in cloud environments)
    local region=""
    region=$(kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null | \
             grep -oP '(?<="topology\.kubernetes\.io/region":")[^"]+' || \
             kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null | \
             grep -oP '(?<="failure-domain\.beta\.kubernetes\.io/region":")[^"]+' || \
             echo "unknown")
    
    echo "$region"
}

detect_cluster_environment() {
    # Try to infer environment from context, namespace patterns, or labels
    local environment=""
    local context=$(kubectl config current-context 2>/dev/null || echo "")
    
    if [[ "$context" =~ prod|production ]]; then
        environment="production"
    elif [[ "$context" =~ dev|development ]]; then
        environment="development"
    elif [[ "$context" =~ stag|staging ]]; then
        environment="staging"
    elif [[ "$context" =~ test ]]; then
        environment="testing"
    else
        # Check for common environment indicators
        if kubectl get namespace production >/dev/null 2>&1; then
            environment="production"
        elif kubectl get namespace development >/dev/null 2>&1; then
            environment="development"
        elif kubectl get namespace staging >/dev/null 2>&1; then
            environment="staging"
        else
            environment="development"  # Default to development
        fi
    fi
    
    echo "$environment"
}

generate_cluster_config() {
    local output_format="${1:-env}"  # env, json, yaml
    
    log_info "Generating cluster configuration..."
    
    local domain=$(detect_cluster_domain)
    local cluster_name=$(detect_cluster_name)
    local region=$(detect_cluster_region)
    local environment=$(detect_cluster_environment)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    case "$output_format" in
        "env")
            cat << EOF
# Cluster Configuration - Generated $(date)
CLUSTER_DOMAIN="$domain"
CLUSTER_NAME="$cluster_name"
CLUSTER_REGION="$region"
CLUSTER_ENVIRONMENT="$environment"
CLUSTER_FQDN="$cluster_name.$domain"
CLUSTER_CONFIG_TIMESTAMP="$timestamp"

# Service FQDNs
KUBERNETES_SERVICE_FQDN="kubernetes.default.svc.$domain"
GRAFANA_EXTERNAL_URL="http://grafana.${cluster_name/kubernetes/homelab}.local"
PROMETHEUS_EXTERNAL_URL="http://prometheus.${cluster_name/kubernetes/homelab}.local"
VAULT_EXTERNAL_URL="https://vault.${cluster_name/kubernetes/homelab}.local:8200"
EOF
            ;;
        "json")
            cat << EOF
{
  "cluster": {
    "domain": "$domain",
    "name": "$cluster_name",
    "region": "$region",
    "environment": "$environment",
    "fqdn": "$cluster_name.$domain",
    "timestamp": "$timestamp"
  },
  "services": {
    "kubernetes": "kubernetes.default.svc.$domain",
    "grafana_external_url": "http://grafana.${cluster_name/kubernetes/homelab}.local",
    "prometheus_external_url": "http://prometheus.${cluster_name/kubernetes/homelab}.local",
    "vault_external_url": "https://vault.${cluster_name/kubernetes/homelab}.local:8200"
  }
}
EOF
            ;;
        "yaml")
            cat << EOF
cluster:
  domain: "$domain"
  name: "$cluster_name"
  region: "$region"
  environment: "$environment"
  fqdn: "$cluster_name.$domain"
  timestamp: "$timestamp"
services:
  kubernetes: "kubernetes.default.svc.$domain"
  grafana_external_url: "http://grafana.${cluster_name/kubernetes/homelab}.local"
  prometheus_external_url: "http://prometheus.${cluster_name/kubernetes/homelab}.local"
  vault_external_url: "https://vault.${cluster_name/kubernetes/homelab}.local:8200"
EOF
            ;;
        *)
            log_error "Unknown output format: $output_format"
            exit 1
            ;;
    esac
    
    log_success "Cluster configuration generated:"
    log_info "Domain: $domain"
    log_info "Name: $cluster_name"
    log_info "Region: $region"
    log_info "Environment: $environment"
}

main() {
    case "${1:-info}" in
        "domain")
            detect_cluster_domain
            ;;
        "name")
            detect_cluster_name
            ;;
        "region")
            detect_cluster_region
            ;;
        "environment")
            detect_cluster_environment
            ;;
        "config")
            generate_cluster_config "${2:-env}"
            ;;
        "env")
            generate_cluster_config "env" | grep -E '^[A-Z_]+=.*' # Only output variable assignments
            ;;
        "json")
            generate_cluster_config "json"
            ;;
        "yaml")
            generate_cluster_config "yaml"
            ;;
        "info"|*)
            echo "Cluster Information Detection Tool"
            echo ""
            echo "Usage: $0 [command] [format]"
            echo ""
            echo "Commands:"
            echo "  domain      - Detect cluster DNS domain"
            echo "  name        - Detect cluster name"
            echo "  region      - Detect cluster region/zone"
            echo "  environment - Detect cluster environment"
            echo "  config      - Generate full cluster config"
            echo "  env         - Generate environment variables (default)"
            echo "  json        - Generate JSON config"
            echo "  yaml        - Generate YAML config"
            echo "  info        - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 domain                    # Get cluster domain"
            echo "  $0 config env               # Generate .env format"
            echo "  $0 config json              # Generate JSON config"
            echo "  source <($0 env)            # Load env vars in shell"
            ;;
    esac
}

main "$@"
