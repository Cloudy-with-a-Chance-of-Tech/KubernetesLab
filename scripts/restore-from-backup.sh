#!/bin/bash

# restore-from-backup.sh
# Restore Talos credentials from encrypted backup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_FILE="${1:-}"
CLUSTER_NAME="${CLUSTER_NAME:-kub}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="${HOME}/.talos-backups"
RESTORE_DIR="${HOME}/.talos-credentials"

echo -e "${BLUE}🔐 Talos Credential Restoration from Backup${NC}"
echo ""

# Check if backup file specified
if [[ -z "${BACKUP_FILE}" ]]; then
    echo -e "${RED}❌ Error: No backup file specified${NC}"
    echo ""
    echo "Usage: $0 <backup-file-name>"
    echo ""
    echo "Available backups:"
    if [[ -d "${BACKUP_DIR}" ]]; then
        ls -1 "${BACKUP_DIR}"/talos-credentials-*.tar.gz* 2>/dev/null | \
        sed 's|.*/talos-credentials-||' | sed 's|\.tar\.gz.*||' | sort -r || echo "   No backups found"
    else
        echo "   No backup directory found"
    fi
    exit 1
fi

# Locate backup files
ENCRYPTED_BACKUP="${BACKUP_DIR}/talos-credentials-${BACKUP_FILE}.tar.gz.gpg"
UNENCRYPTED_BACKUP="${BACKUP_DIR}/talos-credentials-${BACKUP_FILE}.tar.gz"
METADATA_FILE="${BACKUP_DIR}/talos-credentials-${BACKUP_FILE}.metadata.json"

echo "🔍 Locating backup files..."

# Check which backup format exists
if [[ -f "${ENCRYPTED_BACKUP}" ]]; then
    BACKUP_PATH="${ENCRYPTED_BACKUP}"
    ENCRYPTED=true
    echo "   ✅ Found encrypted backup: $(basename "${ENCRYPTED_BACKUP}")"
elif [[ -f "${UNENCRYPTED_BACKUP}" ]]; then
    BACKUP_PATH="${UNENCRYPTED_BACKUP}"
    ENCRYPTED=false
    echo "   ✅ Found unencrypted backup: $(basename "${UNENCRYPTED_BACKUP}")"
else
    echo -e "${RED}❌ Error: Backup file not found${NC}"
    echo "   Expected: talos-credentials-${BACKUP_FILE}.tar.gz[.gpg]"
    echo "   In: ${BACKUP_DIR}/"
    exit 1
fi

# Show metadata if available
if [[ -f "${METADATA_FILE}" ]]; then
    echo ""
    echo "📋 Backup metadata:"
    if command -v jq &> /dev/null; then
        jq -r '
            "   • Date: " + .backup_date +
            "\n   • Cluster: " + .cluster_name +
            "\n   • Hostname: " + .hostname +
            "\n   • Size: " + .backup_size
        ' "${METADATA_FILE}"
    else
        echo "   • File: ${METADATA_FILE}"
        echo "   • Install jq for detailed metadata display"
    fi
fi

# Confirm restoration
echo ""
echo -e "${YELLOW}⚠️  This will overwrite existing credentials for cluster '${CLUSTER_NAME}'${NC}"
read -p "Continue with restoration? (y/N): " -r REPLY
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restoration cancelled"
    exit 0
fi

# Create temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo "🔄 Extracting backup..."

if [[ "${ENCRYPTED}" == "true" ]]; then
    echo "   Decrypting backup (enter passphrase)..."
    if ! gpg --decrypt "${BACKUP_PATH}" > "${TEMP_DIR}/backup.tar.gz" 2>/dev/null; then
        echo -e "${RED}❌ Error: Failed to decrypt backup${NC}"
        echo "   Check passphrase and try again"
        exit 1
    fi
    EXTRACT_FILE="${TEMP_DIR}/backup.tar.gz"
else
    EXTRACT_FILE="${BACKUP_PATH}"
fi

# Extract to temporary location
echo "   Extracting archive..."
cd "${TEMP_DIR}"
if ! tar -xzf "${EXTRACT_FILE}"; then
    echo -e "${RED}❌ Error: Failed to extract backup archive${NC}"
    exit 1
fi

# Verify extracted contents
if [[ ! -d "${TEMP_DIR}/${CLUSTER_NAME}" ]]; then
    echo -e "${RED}❌ Error: Expected cluster directory '${CLUSTER_NAME}' not found in backup${NC}"
    exit 1
fi

REQUIRED_FILES=(
    "ca.crt.b64"
    "client.crt.b64"
    "client.key.b64"
    "talosconfig"
)

echo "   Verifying backup contents..."
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "${TEMP_DIR}/${CLUSTER_NAME}/${file}" ]]; then
        echo -e "${RED}❌ Error: Required file '${file}' not found in backup${NC}"
        exit 1
    fi
    echo "     ✅ ${file}"
done

# Backup existing credentials if they exist
EXISTING_DIR="${RESTORE_DIR}/${CLUSTER_NAME}"
if [[ -d "${EXISTING_DIR}" ]]; then
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_EXISTING="${EXISTING_DIR}.backup.${BACKUP_TIMESTAMP}"
    
    echo "   💾 Backing up existing credentials to: $(basename "${BACKUP_EXISTING}")"
    mv "${EXISTING_DIR}" "${BACKUP_EXISTING}"
fi

# Restore credentials
echo ""
echo "🔧 Restoring credentials..."

# Create restore directory
mkdir -p "${RESTORE_DIR}"

# Move extracted credentials to final location
mv "${TEMP_DIR}/${CLUSTER_NAME}" "${RESTORE_DIR}/"

# Set proper permissions
chmod 700 "${RESTORE_DIR}/${CLUSTER_NAME}"
chmod 600 "${RESTORE_DIR}/${CLUSTER_NAME}"/*

echo "   ✅ Credentials restored to: ${RESTORE_DIR}/${CLUSTER_NAME}"

# Restore working configuration
echo ""
echo "🔨 Restoring working configuration..."

TALOS_DIR="${REPO_ROOT}/base/talos"
if [[ -f "${TALOS_DIR}/talosconfig.template" ]]; then
    # Use restore script if available
    if [[ -f "${SCRIPT_DIR}/restore-talos-credentials.sh" ]]; then
        echo "   Using existing restore script..."
        CLUSTER_NAME="${CLUSTER_NAME}" "${SCRIPT_DIR}/restore-talos-credentials.sh"
    else
        echo "   Creating working config manually..."
        
        # Read credentials
        CA_CERT=$(cat "${RESTORE_DIR}/${CLUSTER_NAME}/ca.crt.b64")
        CLIENT_CERT=$(cat "${RESTORE_DIR}/${CLUSTER_NAME}/client.crt.b64")
        CLIENT_KEY=$(cat "${RESTORE_DIR}/${CLUSTER_NAME}/client.key.b64")
        
        # Create working config
        sed \
            -e "s|{{ CA_CERTIFICATE }}|${CA_CERT}|g" \
            -e "s|{{ CLIENT_CERTIFICATE }}|${CLIENT_CERT}|g" \
            -e "s|{{ CLIENT_KEY }}|${CLIENT_KEY}|g" \
            "${TALOS_DIR}/talosconfig.template" > "${TALOS_DIR}/talosconfig"
        
        chmod 600 "${TALOS_DIR}/talosconfig"
        echo "   ✅ Working config created: ${TALOS_DIR}/talosconfig"
    fi
else
    echo -e "${YELLOW}   ⚠️  No template found - only credentials restored${NC}"
fi

echo ""
echo -e "${GREEN}✅ Restoration completed successfully!${NC}"
echo ""
echo "📋 Restored:"
echo "   • Credentials: ${RESTORE_DIR}/${CLUSTER_NAME}/"
echo "   • Working config: ${TALOS_DIR}/talosconfig"
echo ""
echo "🧪 Next steps:"
echo "   • Test connectivity: talosctl --talosconfig ${TALOS_DIR}/talosconfig version"
echo "   • Verify cluster access: kubectl get nodes"
echo ""
echo "🔒 Security reminder:"
echo "   • Verify restored credentials work correctly"
echo "   • Update team members if this is a shared cluster"
echo "   • Consider rotating credentials if compromise suspected"
