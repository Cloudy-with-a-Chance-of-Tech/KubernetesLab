#!/bin/bash

# backup-talos-credentials.sh
# Automated backup system for Talos credentials with encryption and versioning

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-kub}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECURE_DIR="${HOME}/.talos-credentials/${CLUSTER_NAME}"
BACKUP_DIR="${HOME}/.talos-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="talos-credentials-${CLUSTER_NAME}-${TIMESTAMP}"

echo -e "${BLUE}🔐 Talos Credential Backup System${NC}"
echo "   Cluster: ${CLUSTER_NAME}"
echo "   Source: ${SECURE_DIR}"
echo "   Backup Dir: ${BACKUP_DIR}"
echo ""

# Check if credentials exist
if [[ ! -d "${SECURE_DIR}" ]]; then
    echo -e "${RED}❌ Error: Credentials directory not found: ${SECURE_DIR}${NC}"
    echo "   Run secure-talos-credentials.sh first"
    exit 1
fi

# Create backup directory
mkdir -p "${BACKUP_DIR}"

echo "📦 Creating credential backup..."

# Create tar archive with proper structure
cd "${HOME}/.talos-credentials"
tar -czf "${BACKUP_DIR}/${BACKUP_FILE}.tar.gz" "${CLUSTER_NAME}/"

echo "   ✅ Archive created: ${BACKUP_FILE}.tar.gz"

# Encrypt the backup
echo "🔒 Encrypting backup..."

# Check if GPG is available
if command -v gpg &> /dev/null; then
    # Prompt for passphrase
    echo "   Enter passphrase for backup encryption:"
    gpg --symmetric --cipher-algo AES256 --output "${BACKUP_DIR}/${BACKUP_FILE}.tar.gz.gpg" "${BACKUP_DIR}/${BACKUP_FILE}.tar.gz"
    
    # Remove unencrypted archive
    rm "${BACKUP_DIR}/${BACKUP_FILE}.tar.gz"
    
    echo "   ✅ Backup encrypted: ${BACKUP_FILE}.tar.gz.gpg"
else
    echo -e "${YELLOW}   ⚠️  GPG not available - backup stored unencrypted${NC}"
    echo "   Consider installing GPG for encryption: sudo apt install gnupg"
fi

# Create backup metadata
echo "🗃️ Creating backup metadata..."

cat > "${BACKUP_DIR}/${BACKUP_FILE}.metadata.json" << EOF
{
  "cluster_name": "${CLUSTER_NAME}",
  "backup_timestamp": "${TIMESTAMP}",
  "backup_date": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "user": "$(whoami)",
  "credentials_included": [
    "ca.crt.b64",
    "client.crt.b64", 
    "client.key.b64",
    "talosconfig"
  ],
  "backup_size": "$(du -h "${BACKUP_DIR}/${BACKUP_FILE}".* | head -1 | cut -f1)",
  "version": "1.0"
}
EOF

echo "   ✅ Metadata created: ${BACKUP_FILE}.metadata.json"

# List current backups
echo ""
echo "📋 Current backups:"
ls -lah "${BACKUP_DIR}/" | grep "${CLUSTER_NAME}" | sort -k6,7

# Cleanup old backups (keep last 10)
echo ""
echo "🧹 Cleaning up old backups (keeping last 10)..."

BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/talos-credentials-${CLUSTER_NAME}-*.tar.gz* 2>/dev/null | wc -l)

if [[ ${BACKUP_COUNT} -gt 10 ]]; then
    OLD_BACKUPS=$(ls -1t "${BACKUP_DIR}"/talos-credentials-${CLUSTER_NAME}-*.tar.gz* | tail -n +11)
    
    for backup in ${OLD_BACKUPS}; do
        # Remove both the backup and its metadata
        base_name=$(basename "${backup}" .tar.gz.gpg)
        base_name=$(basename "${base_name}" .tar.gz)
        
        rm -f "${BACKUP_DIR}/${base_name}".* 
        echo "   🗑️  Removed old backup: $(basename "${backup}")"
    done
else
    echo "   ✅ No cleanup needed (${BACKUP_COUNT} backups)"
fi

echo ""
echo -e "${GREEN}✅ Backup completed successfully!${NC}"
echo ""
echo "📋 Backup details:"
echo "   • Location: ${BACKUP_DIR}/${BACKUP_FILE}.*"
echo "   • Encrypted: $([ -f "${BACKUP_DIR}/${BACKUP_FILE}.tar.gz.gpg" ] && echo "Yes" || echo "No")"
echo "   • Metadata: ${BACKUP_FILE}.metadata.json"
echo ""
echo "🔒 Security reminders:"
echo "   • Store backups in multiple secure locations"
echo "   • Test restoration process regularly"
echo "   • Keep passphrase secure and accessible"
echo "   • Consider offsite backup storage"
echo ""
echo "📖 To restore from backup:"
echo "   ./scripts/restore-from-backup.sh ${BACKUP_FILE}"
