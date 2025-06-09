#!/bin/bash
set -euo pipefail

# Extract sensitive keys from talosconfig and create a template for source control
# This script separates secrets from configuration structure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"
SECRETS_DIR="${HOME}/.talos/secrets"

echo "🔐 Extracting Talos secrets from configuration..."

# Check if talosconfig exists
if [[ ! -f "${TALOS_DIR}/talosconfig" ]]; then
    echo "❌ talosconfig not found at ${TALOS_DIR}/talosconfig"
    echo "   Run generate-talos-config.sh first"
    exit 1
fi

# Create secrets directory (outside of source control)
mkdir -p "${SECRETS_DIR}"

# Extract secrets from talosconfig using yq
echo "📤 Extracting client certificate and key..."

# Extract the client certificate
yq eval '.contexts[0].crt' "${TALOS_DIR}/talosconfig" > "${SECRETS_DIR}/client.crt"

# Extract the client key  
yq eval '.contexts[0].key' "${TALOS_DIR}/talosconfig" > "${SECRETS_DIR}/client.key"

# Extract the CA certificate
yq eval '.contexts[0].ca' "${TALOS_DIR}/talosconfig" > "${SECRETS_DIR}/ca.crt"

# Create a template version with placeholders
echo "📝 Creating talosconfig template for source control..."

cat > "${TALOS_DIR}/talosconfig.template" << EOF
# Talos configuration template
# Secrets are stored separately in ~/.talos/secrets/
context: default
contexts:
  default:
    endpoints:
      - $(yq eval '.contexts[0].endpoints[0]' "${TALOS_DIR}/talosconfig")
    nodes:
      - $(yq eval '.contexts[0].nodes[0]' "${TALOS_DIR}/talosconfig")
    ca: "{{CA_CERTIFICATE}}"
    crt: "{{CLIENT_CERTIFICATE}}"
    key: "{{CLIENT_KEY}}"
EOF

# Create a reconstruction script
cat > "${SCRIPT_DIR}/restore-talos-secrets.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# Restore talosconfig from template and secrets
# This script reconstructs the working talosconfig from the template and stored secrets

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"
SECRETS_DIR="${HOME}/.talos/secrets"

echo "🔧 Restoring talosconfig from template and secrets..."

# Check if template exists
if [[ ! -f "${TALOS_DIR}/talosconfig.template" ]]; then
    echo "❌ talosconfig.template not found"
    exit 1
fi

# Check if secrets exist
for file in ca.crt client.crt client.key; do
    if [[ ! -f "${SECRETS_DIR}/${file}" ]]; then
        echo "❌ Secret file ${SECRETS_DIR}/${file} not found"
        echo "   Extract secrets first or regenerate configuration"
        exit 1
    fi
done

# Read secrets
CA_CERT=$(cat "${SECRETS_DIR}/ca.crt")
CLIENT_CERT=$(cat "${SECRETS_DIR}/client.crt")
CLIENT_KEY=$(cat "${SECRETS_DIR}/client.key")

# Create working talosconfig
sed -e "s|{{CA_CERTIFICATE}}|${CA_CERT}|g" \
    -e "s|{{CLIENT_CERTIFICATE}}|${CLIENT_CERT}|g" \
    -e "s|{{CLIENT_KEY}}|${CLIENT_KEY}|g" \
    "${TALOS_DIR}/talosconfig.template" > "${TALOS_DIR}/talosconfig"

# Set proper permissions
chmod 600 "${TALOS_DIR}/talosconfig"

echo "✅ talosconfig restored successfully"
echo "   File: ${TALOS_DIR}/talosconfig"
EOF

chmod +x "${SCRIPT_DIR}/restore-talos-secrets.sh"

# Set proper permissions on secrets
chmod 600 "${SECRETS_DIR}"/*

echo ""
echo "✅ Secrets extracted successfully:"
echo "   📁 Secrets stored in: ${SECRETS_DIR}/"
echo "   🗂️  Template created: ${TALOS_DIR}/talosconfig.template"
echo "   🔧 Restore script: ${SCRIPT_DIR}/restore-talos-secrets.sh"
echo ""
echo "🔒 Security recommendations:"
echo "   1. Add talosconfig to .gitignore (done below)"
echo "   2. Only commit talosconfig.template to source control"
echo "   3. Backup secrets directory securely (encrypted)"
echo ""
echo "📋 To restore talosconfig later:"
echo "   ./scripts/restore-talos-secrets.sh"

# Update .gitignore to exclude the actual talosconfig
GITIGNORE_FILE="${REPO_ROOT}/.gitignore"

if ! grep -q "base/talos/talosconfig$" "${GITIGNORE_FILE}" 2>/dev/null; then
    echo "" >> "${GITIGNORE_FILE}"
    echo "# Talos secrets (keep template only)" >> "${GITIGNORE_FILE}"
    echo "base/talos/talosconfig" >> "${GITIGNORE_FILE}"
    echo "✅ Added talosconfig to .gitignore"
fi
