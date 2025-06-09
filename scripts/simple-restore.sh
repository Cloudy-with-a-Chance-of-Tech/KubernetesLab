#!/bin/bash

# simple-restore.sh
# Simple restore of Talos credentials from backup

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kub}"
BACKUP_DIR="${HOME}/.talos-backups"
RESTORE_DIR="${HOME}/.talos-credentials"

echo "🔄 Simple Talos Restore"
echo "   Cluster: ${CLUSTER_NAME}"

# Check if backup directory exists
if [[ ! -d "${BACKUP_DIR}" ]]; then
    echo "❌ No backup directory found: ${BACKUP_DIR}"
    exit 1
fi

# List available backups
echo "📦 Available backups:"
BACKUPS=($(ls -t "${BACKUP_DIR}"/talos-${CLUSTER_NAME}-*.tar.gz 2>/dev/null || true))

if [[ ${#BACKUPS[@]} -eq 0 ]]; then
    echo "❌ No backups found for cluster: ${CLUSTER_NAME}"
    exit 1
fi

# Show numbered list
for i in "${!BACKUPS[@]}"; do
    backup_file="${BACKUPS[i]}"
    backup_name=$(basename "${backup_file}")
    backup_date=$(echo "${backup_name}" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
    backup_size=$(du -h "${backup_file}" | cut -f1)
    echo "   $((i+1)). ${backup_date} (${backup_size})"
done

# Get user selection
echo ""
read -p "Select backup to restore (1-${#BACKUPS[@]}, or Enter for latest): " selection

if [[ -z "${selection}" ]]; then
    selection=1
elif [[ ! "${selection}" =~ ^[0-9]+$ ]] || [[ ${selection} -lt 1 ]] || [[ ${selection} -gt ${#BACKUPS[@]} ]]; then
    echo "❌ Invalid selection"
    exit 1
fi

SELECTED_BACKUP="${BACKUPS[$((selection-1))]}"
echo "📁 Selected: $(basename "${SELECTED_BACKUP}")"

# Confirm if credentials already exist
if [[ -d "${RESTORE_DIR}/${CLUSTER_NAME}" ]]; then
    echo ""
    echo "⚠️  Existing credentials found for cluster: ${CLUSTER_NAME}"
    read -p "This will overwrite existing credentials. Continue? (y/N): " confirm
    if [[ ! "${confirm}" =~ ^[Yy] ]]; then
        echo "❌ Restore cancelled"
        exit 1
    fi
    rm -rf "${RESTORE_DIR}/${CLUSTER_NAME}"
fi

# Create restore directory
mkdir -p "${RESTORE_DIR}"

# Extract backup
echo ""
echo "🔄 Restoring credentials..."
tar -xzf "${SELECTED_BACKUP}" -C "${RESTORE_DIR}/"

# Set proper permissions
chmod 700 "${RESTORE_DIR}/${CLUSTER_NAME}"
chmod 600 "${RESTORE_DIR}/${CLUSTER_NAME}"/*

echo "✅ Credentials restored to: ${RESTORE_DIR}/${CLUSTER_NAME}/"

# Verify restoration
echo ""
echo "🔍 Verifying restored credentials..."
EXPECTED_FILES=("talosconfig" "ca.crt.b64" "client.crt.b64" "client.key.b64")
for file in "${EXPECTED_FILES[@]}"; do
    if [[ -f "${RESTORE_DIR}/${CLUSTER_NAME}/${file}" ]]; then
        echo "   ✅ ${file}"
    else
        echo "   ❌ Missing: ${file}"
    fi
done

echo ""
echo "✅ Restore complete!"
echo ""
echo "🚀 Next steps:"
echo "   1. cd to your KubernetesLab repository"
echo "   2. Run: ./scripts/restore-talos-credentials.sh"
echo "   3. Test: talosctl --talosconfig base/talos/talosconfig version"
