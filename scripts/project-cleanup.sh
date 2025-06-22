#!/bin/bash
set -e

# KubernetesLab Project Structure Cleanup Script
# This script removes obsolete files and ensures proper CI/CD pipeline organization

echo "🧹 KubernetesLab Project Structure Cleanup"
echo "==========================================="

# Ensure we're in the repo root
cd "$(git rev-parse --show-toplevel)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to safely remove files
safe_remove() {
    local file="$1"
    if [ -f "$file" ]; then
        echo -e "  ${RED}Removing:${NC} $file"
        rm "$file"
        return 0
    else
        echo -e "  ${YELLOW}Not found:${NC} $file (already removed)"
        return 1
    fi
}

# Function to safely remove empty files
remove_empty_file() {
    local file="$1"
    if [ -f "$file" ] && [ ! -s "$file" ]; then
        echo -e "  ${RED}Removing empty file:${NC} $file"
        rm "$file"
        return 0
    elif [ -f "$file" ]; then
        echo -e "  ${YELLOW}File not empty, keeping:${NC} $file"
        return 1
    else
        echo -e "  ${YELLOW}Not found:${NC} $file"
        return 1
    fi
}

echo ""
echo -e "${BLUE}📋 Phase 1: Remove Obsolete Hubble Files${NC}"
echo "============================================="

# Remove old Hubble deployment variants (these are all superseded by networking/cilium/)
HUBBLE_FILES=(
    "hubble-relay-deployment-basic.yaml"
    "hubble-relay-deployment-fixed-final.yaml"
    "hubble-relay-deployment-fixed-v2.yaml"
    "hubble-relay-deployment-fixed.yaml"
    "hubble-relay-deployment-minimal.yaml"
    "hubble-relay-deployment-working.yaml"
    "hubble-relay-minimal.yaml"
)

for file in "${HUBBLE_FILES[@]}"; do
    safe_remove "$file"
done

echo ""
echo -e "${BLUE}📋 Phase 2: Remove Development/Test Files${NC}"
echo "============================================="

# Remove empty test files and development scripts
safe_remove "test-traffic-pod.yaml"
safe_remove "install_hubble.sh"
safe_remove "remove_secrets.sh"

echo ""
echo -e "${BLUE}📋 Phase 3: Handle Environment Files (SECURITY CRITICAL)${NC}"
echo "========================================================="

# Keep .env file for local development (it's in .gitignore)
if [ -f ".env" ]; then
    echo -e "  ${GREEN}✓ Keeping .env for local development (protected by .gitignore)${NC}"
fi

# Keep .env.example as a template, but ensure it has no real secrets
if [ -f ".env.example" ]; then
    echo -e "  ${GREEN}✓ Keeping .env.example as template${NC}"
fi

# Remove .env.template (redundant with .env.example)
safe_remove ".env.template"

echo ""
echo -e "${BLUE}📋 Phase 4: Verify CI/CD Pipeline Structure${NC}"
echo "=============================================="

# Check that essential CI/CD directories exist and are properly organized
REQUIRED_DIRS=(
    ".github/workflows"
    "apps/production"
    "base"
    "monitoring"
    "networking"
    "security"
    "scripts"
    "docs"
)

echo "Verifying CI/CD pipeline structure:"
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "  ${GREEN}✓${NC} $dir"
    else
        echo -e "  ${RED}✗${NC} $dir (missing)"
    fi
done

echo ""
echo -e "${BLUE}📋 Phase 5: Check for Additional Cleanup Opportunities${NC}"
echo "========================================================"

# Look for additional patterns that might need cleanup
echo "Scanning for additional cleanup opportunities..."

# Check for any .tmp files
if find . -name "*.tmp" -type f | grep -q .; then
    echo -e "  ${YELLOW}Found .tmp files:${NC}"
    find . -name "*.tmp" -type f -exec echo "    {}" \;
    read -p "Remove all .tmp files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        find . -name "*.tmp" -type f -delete
        echo -e "  ${RED}Removed all .tmp files${NC}"
    fi
fi

# Check for any .bak files
if find . -name "*.bak" -type f | grep -q .; then
    echo -e "  ${YELLOW}Found .bak files:${NC}"
    find . -name "*.bak" -type f -exec echo "    {}" \;
    read -p "Remove all .bak files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        find . -name "*.bak" -type f -delete
        echo -e "  ${RED}Removed all .bak files${NC}"
    fi
fi

# Check for any empty directories
echo "Checking for empty directories..."
if find . -type d -empty | grep -v ".git" | grep -q .; then
    echo -e "  ${YELLOW}Found empty directories:${NC}"
    find . -type d -empty | grep -v ".git" | while read dir; do
        echo "    $dir"
    done
    echo -e "  ${BLUE}Note: Empty directories are kept as they may be needed for CI/CD${NC}"
fi

echo ""
echo -e "${BLUE}📋 Phase 6: Generate Project Structure Summary${NC}"
echo "==============================================="

echo "Current project structure after cleanup:"
echo "├── .github/              # CI/CD workflows and configurations"
echo "├── apps/                 # Application deployments"
echo "│   └── production/       # Production application manifests"
echo "├── base/                 # Base Kubernetes resources"
echo "│   ├── namespaces/       # Namespace definitions"
echo "│   ├── rbac/            # RBAC configurations"
echo "│   └── storage/         # Storage configurations"
echo "├── docs/                 # Documentation"
echo "├── manifests/           # Generated manifests (from templates/)"
echo "├── monitoring/          # Monitoring stack"
echo "├── networking/          # Network policies and configurations"
echo "├── scripts/             # Automation scripts"
echo "├── security/            # Security configurations"
echo "└── templates/           # Manifest templates for multi-cluster"

echo ""
echo -e "${GREEN}✅ Project cleanup completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo "1. Review the changes: git status"
echo "2. Commit the cleanup: git add . && git commit -m 'Clean up obsolete files and organize project structure'"
echo "3. Push changes: git push origin main"
echo ""
echo -e "${GREEN}✅ Note:${NC} The .env file is preserved for local development (protected by .gitignore)."
echo "Use .env.example as a template for setting up new environments."
