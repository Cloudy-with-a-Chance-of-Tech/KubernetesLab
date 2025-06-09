#!/bin/bash

# secure-talos-credentials.sh
# Extracts sensitive credentials from existing talosconfig and creates secure management system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-kub}"
TALOS_DIR="${REPO_ROOT}/base/talos"
SECURE_DIR="${HOME}/.talos-credentials/${CLUSTER_NAME}"
SOURCE_CONFIG="${HOME}/.talos/config"

echo -e "${BLUE}🔐 Talos Credential Security Setup${NC}"
echo "   Cluster: ${CLUSTER_NAME}"
echo "   Source: ${SOURCE_CONFIG}"
echo "   Target: ${TALOS_DIR}/"
echo "   Secure: ${SECURE_DIR}/"
echo ""

# Check if source talosconfig exists
if [[ ! -f "${SOURCE_CONFIG}" ]]; then
    echo -e "${RED}❌ Error: Source talosconfig not found: ${SOURCE_CONFIG}${NC}"
    echo "   Please ensure you have a working talosconfig file"
    exit 1
fi

echo "✅ Found source talosconfig: ${SOURCE_CONFIG}"

# Create secure credentials directory
echo ""
echo "🔒 Creating secure credentials directory..."
mkdir -p "${SECURE_DIR}"

# Extract configuration details
echo "🔍 Extracting configuration details..."
CONTEXT=$(yq eval '.context' "${SOURCE_CONFIG}")
ENDPOINTS=$(yq eval '.contexts.*.endpoints[]' "${SOURCE_CONFIG}" | tr '\n' ',' | sed 's/,$//')
NODES=$(yq eval '.contexts.*.nodes[]' "${SOURCE_CONFIG}" | tr '\n' ',' | sed 's/,$//')

echo "   ✅ Context: ${CONTEXT}"
echo "   ✅ Endpoints: ${ENDPOINTS}"
echo "   ✅ Nodes: ${NODES}"

# Extract sensitive credentials
echo ""
echo "🔑 Extracting sensitive credentials..."
yq eval '.contexts.*.ca' "${SOURCE_CONFIG}" > "${SECURE_DIR}/ca.crt.b64"
yq eval '.contexts.*.crt' "${SOURCE_CONFIG}" > "${SECURE_DIR}/client.crt.b64"
yq eval '.contexts.*.key' "${SOURCE_CONFIG}" > "${SECURE_DIR}/client.key.b64"

echo "   ✅ CA Certificate extracted"
echo "   ✅ Client Certificate extracted"
echo "   ✅ Client Key extracted"

# Create sanitized talosconfig template
echo ""
echo "📝 Creating sanitized configuration template..."
cat > "${TALOS_DIR}/talosconfig.template" << EOF
context: ${CONTEXT}
contexts:
    ${CONTEXT}:
        endpoints:
$(echo "${ENDPOINTS}" | tr ',' '\n' | sed 's/^/            - /')
        nodes:
$(echo "${NODES}" | tr ',' '\n' | sed 's/^/            - /')
        ca: "{{ CA_CERTIFICATE }}"
        crt: "{{ CLIENT_CERTIFICATE }}"
        key: "{{ CLIENT_KEY }}"
EOF

echo "   ✅ Template created: ${TALOS_DIR}/talosconfig.template"

# Copy complete config to secure location
cp "${SOURCE_CONFIG}" "${SECURE_DIR}/talosconfig"
echo "   ✅ Full config copied to secure location"

# Create working talosconfig in project (will be gitignored)
cp "${SOURCE_CONFIG}" "${TALOS_DIR}/talosconfig"
echo "   ✅ Working config created in project"

# Update .gitignore to exclude sensitive files
GITIGNORE_FILE="${REPO_ROOT}/.gitignore"
echo ""
echo "🚫 Updating .gitignore to exclude sensitive files..."

if [[ ! -f "${GITIGNORE_FILE}" ]]; then
    touch "${GITIGNORE_FILE}"
fi

# Add entries if they don't already exist
if ! grep -q "# Talos sensitive credentials" "${GITIGNORE_FILE}"; then
    echo "" >> "${GITIGNORE_FILE}"
    echo "# Talos sensitive credentials" >> "${GITIGNORE_FILE}"
    echo "base/talos/talosconfig" >> "${GITIGNORE_FILE}"
    echo "*.key" >> "${GITIGNORE_FILE}"
    echo "*.crt" >> "${GITIGNORE_FILE}"
    echo "**/secrets/" >> "${GITIGNORE_FILE}"
    echo "   ✅ Added gitignore entries"
else
    echo "   ✅ Gitignore entries already exist"
fi

# Set proper permissions
echo ""
echo "🔐 Setting secure permissions..."
chmod 700 "${SECURE_DIR}"
chmod 600 "${SECURE_DIR}"/*
chmod 644 "${TALOS_DIR}/talosconfig.template"
chmod 600 "${TALOS_DIR}/talosconfig"

echo "   ✅ Secure directory: 700"
echo "   ✅ Credential files: 600"
echo "   ✅ Template file: 644"

echo ""
echo -e "${GREEN}✅ Credential security setup complete!${NC}"
echo ""
echo "📋 Files created:"
echo "   • ${TALOS_DIR}/talosconfig.template (safe for git)"
echo "   • ${TALOS_DIR}/talosconfig (working config, gitignored)"
echo "   • ${SECURE_DIR}/talosconfig (backup)"
echo "   • ${SECURE_DIR}/*.b64 (extracted credentials)"
echo ""
echo "🔒 Security setup:"
echo "   • Sensitive credentials stored in: ${SECURE_DIR}/"
echo "   • Template without secrets: ${TALOS_DIR}/talosconfig.template"
echo "   • .gitignore updated to exclude sensitive files"
echo "   • Proper file permissions set"
echo ""
echo "🚀 Usage:"
echo "   • Use talosctl normally - working config is in ${TALOS_DIR}/talosconfig"
echo "   • To restore config: ./scripts/restore-talos-credentials.sh"
echo "   • Template is safe to commit to git"
echo ""
echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "   • Real credentials are in ~/.talos-credentials/${CLUSTER_NAME}/"
echo "   • Only the template (without keys) should be committed to git"
echo "   • Backup your credentials securely outside this repository"
echo "   • Share credentials securely with team members (not via git)"
