#!/bin/bash

# simple-backup.sh  
# Simple backup of Talos credentials for personal use

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kub}"
SECURE_DIR="${HOME}/.talos-credentials/${CLUSTER_NAME}"
BACKUP_DIR="${HOME}/.talos-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "🔐 Simple Talos Backup"
echo "   Cluster: ${CLUSTER_NAME}"

# Check if credentials exist
if [[ ! -d "${SECURE_DIR}" ]]; then
    echo "❌ No credentials found in ${SECURE_DIR}"
    exit 1
fi

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Simple tar backup
BACKUP_FILE="${BACKUP_DIR}/talos-${CLUSTER_NAME}-${TIMESTAMP}.tar.gz"
tar -czf "${BACKUP_FILE}" -C "${HOME}/.talos-credentials" "${CLUSTER_NAME}/"

echo "✅ Backup created: ${BACKUP_FILE}"
echo "📁 Size: $(du -h "${BACKUP_FILE}" | cut -f1)"

# Keep only last 10 backups
cd "${BACKUP_DIR}"
ls -t talos-${CLUSTER_NAME}-*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm
echo "🧹 Cleaned old backups (keeping 10 most recent)"

echo ""
echo "💡 To restore: tar -xzf '${BACKUP_FILE}' -C ~/.talos-credentials/"
