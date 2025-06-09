#!/bin/bash
set -euo pipefail

# Verify cluster configuration consistency
# This script checks that all configurations use the correct cluster name and endpoints

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "🔍 Verifying cluster configuration consistency..."
echo ""

# Expected values
EXPECTED_CLUSTER_NAME="kub"
EXPECTED_ENDPOINT="https://kub.home.thomaswimprine.com:6443"
EXPECTED_K8S_VERSION="v1.32.3"

errors=0

# Function to check file content
check_file() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    
    if [[ -f "$file" ]]; then
        if grep -q "$pattern" "$file"; then
            echo "✅ $description: $file"
        else
            echo "❌ $description: $file"
            ((errors++))
        fi
    else
        echo "⚠️  File not found: $file"
        ((errors++))
    fi
}

echo "📋 Checking cluster name consistency..."
check_file "${REPO_ROOT}/base/kustomization.yaml" "cluster: ${EXPECTED_CLUSTER_NAME}" "Base kustomization"
check_file "${REPO_ROOT}/monitoring/kustomization.yaml" "cluster: ${EXPECTED_CLUSTER_NAME}" "Monitoring kustomization"
check_file "${REPO_ROOT}/apps/production/kustomization.yaml" "cluster: ${EXPECTED_CLUSTER_NAME}" "Production kustomization"
check_file "${REPO_ROOT}/base/talos/talosconfig.yaml" "name: ${EXPECTED_CLUSTER_NAME}" "Talos config"
check_file "${REPO_ROOT}/scripts/generate-talos-config.sh" "CLUSTER_NAME=\"${EXPECTED_CLUSTER_NAME}\"" "Generate script"

echo ""
echo "🌐 Checking endpoint consistency..."
check_file "${REPO_ROOT}/base/talos/controlplane.yaml.template" "${EXPECTED_ENDPOINT}" "Control plane template"
check_file "${REPO_ROOT}/scripts/generate-talos-config.sh" "${EXPECTED_ENDPOINT}" "Generate script"
check_file "${REPO_ROOT}/scripts/bootstrap-cluster.sh" "kub.home.thomaswimprine.com" "Bootstrap script"

echo ""
echo "🔧 Checking Kubernetes version..."
check_file "${REPO_ROOT}/base/talos/worker.yaml.template" "${EXPECTED_K8S_VERSION}" "Worker template"

echo ""
echo "🛡️ Checking security configurations..."
check_file "${REPO_ROOT}/.gitignore" "base/talos/controlplane.yaml" "Gitignore control plane"
check_file "${REPO_ROOT}/.gitignore" "base/talos/worker.yaml" "Gitignore worker"
check_file "${REPO_ROOT}/.gitignore" "base/talos/talosconfig" "Gitignore talos client config"

echo ""
echo "📂 Checking script permissions..."
for script in "${REPO_ROOT}/scripts"/*.sh; do
    if [[ -x "$script" ]]; then
        echo "✅ Executable: $(basename "$script")"
    else
        echo "❌ Not executable: $(basename "$script")"
        ((errors++))
    fi
done

echo ""
echo "🔍 Summary:"
if [[ $errors -eq 0 ]]; then
    echo "✅ All configurations are consistent!"
    echo ""
    echo "🚀 Ready for cluster deployment:"
    echo "   1. ./scripts/generate-talos-config.sh"
    echo "   2. ./scripts/deploy-cluster.sh"
    echo "   3. ./scripts/bootstrap-cluster.sh"
    echo "   4. ./scripts/install-cilium.sh"
    echo "   5. ./scripts/setup-complete.sh"
else
    echo "❌ Found $errors configuration issues"
    echo "   Please review and fix the issues above"
    exit 1
fi
