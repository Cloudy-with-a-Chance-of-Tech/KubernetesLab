#!/bin/bash

# restore-talos-credentials.sh
# Restores working talosconfig from template + secure credentials

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
CLUSTER_NAME="${CLUSTER_NAME:-picluster}"
TALOS_DIR="${REPO_ROOT}/base/talos"
SECURE_DIR="${HOME}/.talos-credentials/${CLUSTER_NAME}"

echo -e "${BLUE}🔐 Talos Credential Restoration${NC}"
echo "   Cluster: ${CLUSTER_NAME}"
echo "   Template: ${TALOS_DIR}/talosconfig.template"
echo "   Credentials: ${SECURE_DIR}/"
echo ""

# Check if template exists
if [[ ! -f "${TALOS_DIR}/talosconfig.template" ]]; then
    echo -e "${RED}❌ Error: Template file not found: ${TALOS_DIR}/talosconfig.template${NC}"
    echo "   This script requires a sanitized template created by generate-talos-config.sh"
    exit 1
fi

# Check if secure credentials exist
if [[ ! -d "${SECURE_DIR}" ]]; then
    echo -e "${RED}❌ Error: Secure credentials directory not found: ${SECURE_DIR}${NC}"
    echo "   Run generate-talos-config.sh first to create secure credentials"
    exit 1
fi

echo "🔍 Checking for secure credential files..."
REQUIRED_FILES=(
    "ca.crt.b64"
    "client.crt.b64" 
    "client.key.b64"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "${SECURE_DIR}/${file}" ]]; then
        echo -e "${RED}❌ Missing credential file: ${SECURE_DIR}/${file}${NC}"
        exit 1
    fi
    echo "   ✅ Found ${file}"
done

# Read credentials from secure location
echo ""
echo "🔑 Reading secure credentials..."
CA_CERT=$(cat "${SECURE_DIR}/ca.crt.b64")
CLIENT_CERT=$(cat "${SECURE_DIR}/client.crt.b64")
CLIENT_KEY=$(cat "${SECURE_DIR}/client.key.b64")

echo "   ✅ CA Certificate (${#CA_CERT} chars)"
echo "   ✅ Client Certificate (${#CLIENT_CERT} chars)"
echo "   ✅ Client Key (${#CLIENT_KEY} chars)"

# Create working talosconfig by substituting credentials into template
echo ""
echo "📝 Reconstructing working talosconfig..."

# Use sed to replace placeholders with actual credentials
sed \
    -e "s|{{ CA_CERTIFICATE }}|${CA_CERT}|g" \
    -e "s|{{ CLIENT_CERTIFICATE }}|${CLIENT_CERT}|g" \
    -e "s|{{ CLIENT_KEY }}|${CLIENT_KEY}|g" \
    "${TALOS_DIR}/talosconfig.template" > "${TALOS_DIR}/talosconfig"

# Set proper permissions
chmod 600 "${TALOS_DIR}/talosconfig"

echo "   ✅ Working talosconfig created: ${TALOS_DIR}/talosconfig"

# Verify the restored config works
echo ""
echo "🧪 Testing restored configuration..."

# Test talosctl connectivity
if command -v talosctl &> /dev/null; then
    if talosctl --talosconfig "${TALOS_DIR}/talosconfig" version --client > /dev/null 2>&1; then
        echo "   ✅ talosctl client test passed"
        
        # Try to contact the cluster (this may fail if cluster is down, but config is valid)
        echo "   🔗 Testing cluster connectivity..."
        if talosctl --talosconfig "${TALOS_DIR}/talosconfig" version --short 2>/dev/null; then
            echo "   ✅ Successfully connected to Talos cluster!"
        else
            echo -e "${YELLOW}   ⚠️  Cannot reach cluster (cluster may be down, but config is valid)${NC}"
        fi
    else
        echo -e "${RED}   ❌ talosctl client test failed - config may be corrupted${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}   ⚠️  talosctl not found - cannot test config${NC}"
fi

echo ""
echo -e "${GREEN}✅ Credential restoration complete!${NC}"
echo ""
echo "📋 Summary:"
echo "   • Template used: ${TALOS_DIR}/talosconfig.template"
echo "   • Credentials from: ${SECURE_DIR}/"
echo "   • Working config: ${TALOS_DIR}/talosconfig"
echo ""
echo "🔒 Security reminder:"
echo "   • Working talosconfig contains sensitive keys"
echo "   • File is excluded from git via .gitignore"
echo "   • Back up credentials securely outside repository"
echo ""
echo "🚀 Ready to use talosctl with restored configuration!"
