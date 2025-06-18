#!/bin/bash
# Template substitution script for portable Kubernetes deployments
# This script replaces template variables with actual cluster-detected values

set -uo pipefail

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

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="${WORKSPACE_ROOT}/templates"
OUTPUT_DIR="${WORKSPACE_ROOT}/manifests"
DRY_RUN=${DRY_RUN:-false}

show_usage() {
    cat << EOF
Template Substitution Script for Portable Kubernetes Deployments

Usage: $0 [OPTIONS] [COMMAND]

OPTIONS:
  -h, --help              Show this help message
  -d, --dry-run          Show what would be substituted without making changes
  -t, --template-dir DIR  Template directory (default: $TEMPLATE_DIR)
  -o, --output-dir DIR    Output directory (default: $OUTPUT_DIR)
  --cluster-vars FILE     Use specific cluster variables file

COMMANDS:
  substitute              Substitute templates with cluster values (default)
  validate                Validate templates and cluster detection
  clean                   Clean generated manifests
  list-templates          List available templates
  list-variables          List available template variables

EXAMPLES:
  $0                              # Substitute all templates
  $0 --dry-run                    # Show what would be substituted
  $0 validate                     # Validate templates and cluster detection
  $0 --template-dir ./my-templates # Use custom template directory

TEMPLATE VARIABLES:
  {{CLUSTER_DOMAIN}}              - Cluster DNS domain (e.g., cluster.local)
  {{CLUSTER_NAME}}                - Cluster name (e.g., kubernetes)
  {{CLUSTER_REGION}}              - Cluster region (e.g., us-west-2)
  {{CLUSTER_ENVIRONMENT}}         - Environment (e.g., production)
  {{CLUSTER_FQDN}}                - Full cluster FQDN
  {{KUBERNETES_SERVICE_FQDN}}     - Kubernetes service FQDN
  {{GRAFANA_EXTERNAL_URL}}        - Grafana external URL
  {{PROMETHEUS_EXTERNAL_URL}}     - Prometheus external URL
  {{VAULT_EXTERNAL_URL}}          - Vault external URL
  {{TIMESTAMP}}                   - Current timestamp
EOF
}

load_cluster_variables() {
    local cluster_vars_file="${1:-}"
    
    if [[ -n "$cluster_vars_file" && -f "$cluster_vars_file" ]]; then
        log_info "Loading cluster variables from: $cluster_vars_file"
        source "$cluster_vars_file"
    else
        log_info "Detecting cluster variables..."
        
        # Use the cluster detection script
        if [[ -f "$SCRIPT_DIR/detect-cluster-info.sh" ]]; then        # Source the environment variables
        eval "$("$SCRIPT_DIR/detect-cluster-info.sh" env)" 2>/dev/null || {
            log_error "Failed to detect cluster configuration"
            exit 1
        }
        else
            log_error "Cluster detection script not found: $SCRIPT_DIR/detect-cluster-info.sh"
            exit 1
        fi
    fi
    
    # Validate required variables
    local required_vars=(
        "CLUSTER_DOMAIN"
        "CLUSTER_NAME"
        "CLUSTER_REGION"
        "CLUSTER_ENVIRONMENT"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var is not set"
            exit 1
        fi
    done
    
    # Set additional computed variables if not already set
    CLUSTER_FQDN="${CLUSTER_FQDN:-${CLUSTER_NAME}.${CLUSTER_DOMAIN}}"
    KUBERNETES_SERVICE_FQDN="${KUBERNETES_SERVICE_FQDN:-kubernetes.default.svc.${CLUSTER_DOMAIN}}"
    TIMESTAMP="${TIMESTAMP:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
    
    # Set service URLs with better domain detection
    local external_domain="${CLUSTER_DOMAIN}"
    if [[ "$external_domain" == "cluster.local" ]]; then
        external_domain="homelab.local"  # Default for local clusters
    fi
    
    GRAFANA_EXTERNAL_URL="${GRAFANA_EXTERNAL_URL:-http://grafana.${external_domain}}"
    PROMETHEUS_EXTERNAL_URL="${PROMETHEUS_EXTERNAL_URL:-http://prometheus.${external_domain}}"
    VAULT_EXTERNAL_URL="${VAULT_EXTERNAL_URL:-https://vault.${external_domain}:8200}"
    
    log_success "Cluster variables loaded:"
    log_info "  Domain: $CLUSTER_DOMAIN"
    log_info "  Name: $CLUSTER_NAME"
    log_info "  Region: $CLUSTER_REGION"
    log_info "  Environment: $CLUSTER_ENVIRONMENT"
    log_info "  FQDN: $CLUSTER_FQDN"
}

find_template_files() {
    local template_dir="$1"
    
    if [[ ! -d "$template_dir" ]]; then
        log_warning "Template directory not found: $template_dir"
        return 0
    fi
    
    find "$template_dir" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) -print0 | sort -z
}

substitute_template() {
    local template_file="$1"
    local output_file="$2"
    
    log_info "Processing template: $(basename "$template_file")"
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output_file")"
    
    # Perform substitutions
    local content
    if ! content=$(cat "$template_file"); then
        log_error "Failed to read template file: $template_file"
        return 1
    fi
    
    # Replace template variables
    content="${content//\{\{CLUSTER_DOMAIN\}\}/$CLUSTER_DOMAIN}"
    content="${content//\{\{CLUSTER_NAME\}\}/$CLUSTER_NAME}"
    content="${content//\{\{CLUSTER_REGION\}\}/$CLUSTER_REGION}"
    content="${content//\{\{CLUSTER_ENVIRONMENT\}\}/$CLUSTER_ENVIRONMENT}"
    content="${content//\{\{CLUSTER_FQDN\}\}/$CLUSTER_FQDN}"
    content="${content//\{\{KUBERNETES_SERVICE_FQDN\}\}/$KUBERNETES_SERVICE_FQDN}"
    content="${content//\{\{GRAFANA_EXTERNAL_URL\}\}/$GRAFANA_EXTERNAL_URL}"
    content="${content//\{\{PROMETHEUS_EXTERNAL_URL\}\}/$PROMETHEUS_EXTERNAL_URL}"
    content="${content//\{\{VAULT_EXTERNAL_URL\}\}/$VAULT_EXTERNAL_URL}"
    content="${content//\{\{TIMESTAMP\}\}/$TIMESTAMP}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - Would write to: $output_file"
        echo "--- Template content preview ---"
        echo "$content" | head -20
        echo "--- End preview ---"
    else
        if ! echo "$content" > "$output_file"; then
            log_error "Failed to write output file: $output_file"
            return 1
        fi
        log_success "Generated: $output_file"
    fi
    
    return 0
}

substitute_all_templates() {
    local template_dir="$1"
    local output_dir="$2"
    
    log_info "Substituting templates from $template_dir to $output_dir"
    
    local count=0
    local template_files
    mapfile -t template_files < <(find "$template_dir" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) | sort)
    
    log_info "Found ${#template_files[@]} template files"
    
    for template_file in "${template_files[@]}"; do
        # Calculate relative path and output file
        local rel_path="${template_file#$template_dir/}"
        local output_file="$output_dir/$rel_path"
        
        log_info "Processing: $template_file -> $output_file"
        if substitute_template "$template_file" "$output_file"; then
            ((count++))
        else
            log_error "Failed to process template: $template_file"
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        log_warning "No template files found in $template_dir"
    else
        log_success "Processed $count template files"
    fi
}

validate_templates() {
    local template_dir="$1"
    
    log_info "Validating templates in $template_dir"
    
    local count=0
    local errors=0
    
    while IFS= read -r -d '' template_file; do
        log_info "Validating template: $(basename "$template_file")"
        
        # Check for valid YAML/JSON syntax
        if [[ "$template_file" =~ \.(yaml|yml)$ ]]; then
            if ! python3 -c "import yaml; yaml.safe_load(open('$template_file'))" 2>/dev/null; then
                log_error "Invalid YAML syntax in $template_file"
                ((errors++))
            fi
        elif [[ "$template_file" =~ \.json$ ]]; then
            if ! python3 -c "import json; json.load(open('$template_file'))" 2>/dev/null; then
                log_error "Invalid JSON syntax in $template_file"
                ((errors++))
            fi
        fi
        
        # Check for template variables
        local vars_found
        vars_found=$(grep -o '{{[^}]*}}' "$template_file" | sort -u || true)
        if [[ -n "$vars_found" ]]; then
            log_info "  Template variables found:"
            echo "$vars_found" | while read -r var; do
                log_info "    $var"
            done
        fi
        
        ((count++))
    done < <(find_template_files "$template_dir")
    
    if [[ $errors -gt 0 ]]; then
        log_error "Validation failed with $errors errors"
        exit 1
    else
        log_success "Validated $count template files successfully"
    fi
}

list_templates() {
    local template_dir="$1"
    
    log_info "Available templates in $template_dir:"
    
    local count=0
    local template_files
    mapfile -t template_files < <(find "$template_dir" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) | sort)
    
    for template_file in "${template_files[@]}"; do
        local rel_path="${template_file#$template_dir/}"
        echo "  $rel_path"
        ((count++))
    done
    
    echo ""
    log_info "Total: $count templates"
}

list_variables() {
    cat << EOF
Available template variables:
  {{CLUSTER_DOMAIN}}              - Cluster DNS domain (e.g., cluster.local)
  {{CLUSTER_NAME}}                - Cluster name (e.g., kubernetes)
  {{CLUSTER_REGION}}              - Cluster region (e.g., us-west-2)
  {{CLUSTER_ENVIRONMENT}}         - Environment (e.g., production)
  {{CLUSTER_FQDN}}                - Full cluster FQDN
  {{KUBERNETES_SERVICE_FQDN}}     - Kubernetes service FQDN
  {{GRAFANA_EXTERNAL_URL}}        - Grafana external URL
  {{PROMETHEUS_EXTERNAL_URL}}     - Prometheus external URL
  {{VAULT_EXTERNAL_URL}}          - Vault external URL
  {{TIMESTAMP}}                   - Current timestamp

Example usage in templates:
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: cluster-config
  data:
    domain: "{{CLUSTER_DOMAIN}}"
    name: "{{CLUSTER_NAME}}"
    grafana_url: "{{GRAFANA_EXTERNAL_URL}}"
EOF
}

clean_manifests() {
    local output_dir="$1"
    
    if [[ -d "$output_dir" ]]; then
        log_info "Cleaning generated manifests in $output_dir"
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN - Would remove: $output_dir"
            find "$output_dir" -type f -name "*.yaml" -o -name "*.yml" -o -name "*.json" | head -10
        else
            rm -rf "$output_dir"
            log_success "Cleaned: $output_dir"
        fi
    else
        log_info "Output directory does not exist: $output_dir"
    fi
}

main() {
    local command="substitute"
    local cluster_vars_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -t|--template-dir)
                TEMPLATE_DIR="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --cluster-vars)
                cluster_vars_file="$2"
                shift 2
                ;;
            substitute|validate|clean|list-templates|list-variables)
                command="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    case "$command" in
        substitute)
            load_cluster_variables "$cluster_vars_file"
            substitute_all_templates "$TEMPLATE_DIR" "$OUTPUT_DIR"
            ;;
        validate)
            validate_templates "$TEMPLATE_DIR"
            ;;
        clean)
            clean_manifests "$OUTPUT_DIR"
            ;;
        list-templates)
            list_templates "$TEMPLATE_DIR"
            ;;
        list-variables)
            list_variables
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
