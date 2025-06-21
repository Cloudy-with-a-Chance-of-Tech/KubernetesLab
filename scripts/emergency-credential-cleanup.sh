#!/bin/bash

# CRITICAL SECURITY REMEDIATION SCRIPT
# This script removes leaked credentials from Git history

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}🚨 CRITICAL SECURITY ISSUE - CREDENTIAL LEAK DETECTED 🚨${NC}"
echo -e "${YELLOW}This script will permanently remove sensitive data from Git history${NC}"
echo -e "${YELLOW}⚠️  This is a destructive operation that rewrites Git history${NC}"
echo
read -p "Are you sure you want to proceed? (type 'YES' to continue): " confirm

if [ "$confirm" != "YES" ]; then
    echo "Operation cancelled."
    exit 1
fi

echo -e "${GREEN}Starting credential cleanup...${NC}"

# Backup current state
echo "Creating backup of current repository state..."
git bundle create ../KubernetesLab-backup-$(date +%Y%m%d-%H%M%S).bundle --all

# Files containing credentials that need to be purged
CREDENTIAL_FILES=(
    "networking/cilium/no-tls/hubble-relay-deployment-no-tls.yaml"
    ".hubble-backup/hubble-relay-20250620221215.yaml"
    ".hubble-backup/hubble-relay-config-20250620221215.yaml"
    ".hubble-backup/hubble-ui-20250620221215.yaml"
)

echo "Installing git-filter-repo if not present..."
if ! command -v git-filter-repo &> /dev/null; then
    echo "git-filter-repo not found. Installing..."
    pip3 install git-filter-repo || {
        echo "Failed to install git-filter-repo. Please install it manually:"
        echo "pip install git-filter-repo"
        exit 1
    }
fi

echo "Removing credential files from Git history..."

# Remove specific files from entire Git history
for file in "${CREDENTIAL_FILES[@]}"; do
    echo "Purging: $file"
    git filter-repo --path "$file" --invert-paths --force || {
        echo "Warning: Failed to remove $file from history (may not exist)"
    }
done

# Also search for and remove any content containing private keys
echo "Removing any remaining private key content..."
git filter-repo --replace-text <(cat <<'EOF'
-----BEGIN RSA PRIVATE KEY-----***REMOVED***
-----BEGIN PRIVATE KEY-----***REMOVED***
-----BEGIN OPENSSH PRIVATE KEY-----***REMOVED***
-----BEGIN EC PRIVATE KEY-----***REMOVED***
-----BEGIN DSA PRIVATE KEY-----***REMOVED***
MIIEogIBAAKCAQEArBTJpR***REMOVED***
EOF
) --force

echo -e "${GREEN}✓ Git history cleaned${NC}"

# Clean up current working directory
echo "Cleaning up current working directory..."
for file in "${CREDENTIAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Removing: $file"
        rm -f "$file"
    fi
done

# Remove entire .hubble-backup directory as it contains sensitive data
if [ -d ".hubble-backup" ]; then
    echo "Removing .hubble-backup directory containing sensitive data..."
    rm -rf .hubble-backup
fi

echo -e "${GREEN}✓ Working directory cleaned${NC}"

# Update .gitignore to prevent future leaks
echo "Updating .gitignore..."
cat >> .gitignore <<'EOF'

# Security - Prevent credential leaks
*.key
*.pem
*.crt
*.p12
*.pfx
*.jks
*.keystore
**/secrets/
**/*secret*
**/*credential*
**/*password*
*backup*/*.yaml
.hubble-backup/
.talos-backup/
EOF

echo -e "${GREEN}✓ .gitignore updated${NC}"

# Force garbage collection to remove old objects
echo "Running aggressive garbage collection..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo -e "${GREEN}✓ Repository cleaned${NC}"

# Display next steps
echo
echo -e "${YELLOW}NEXT STEPS REQUIRED:${NC}"
echo "1. Force push to remote to update Git history:"
echo "   git push --force-with-lease origin main"
echo
echo "2. Regenerate ALL compromised credentials immediately"
echo "3. Rotate any API keys, tokens, or certificates that were exposed"
echo "4. Review access logs for unauthorized usage"
echo "5. Notify team members to re-clone the repository"
echo
echo -e "${RED}⚠️  ALL TEAM MEMBERS MUST RE-CLONE THE REPOSITORY${NC}"
echo -e "${RED}   Old clones still contain the leaked credentials!${NC}"

echo
echo -e "${GREEN}Credential cleanup completed successfully!${NC}"
