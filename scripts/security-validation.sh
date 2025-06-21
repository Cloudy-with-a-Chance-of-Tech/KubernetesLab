#!/bin/bash
set -euo pipefail

# Security Validation Script - Post-Cleanup
# Validates that the repository is clean of sensitive data

echo "🔐 SECURITY VALIDATION: Post-Cleanup Repository Scan"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

FAILED_CHECKS=0

# Function to check for patterns
check_pattern() {
    local pattern="$1"
    local description="$2"
    
    echo -n "Checking for $description... "
    
    if grep -r "$pattern" . --exclude-dir=.git --exclude-dir=.venv --exclude-dir=venv --exclude-dir=node_modules --exclude="*.sh" --exclude="SECURITY_INCIDENT_REPORT.md" >/dev/null 2>&1; then
        echo -e "${RED}FOUND${NC}"
        echo "  Files containing $description:"
        grep -r "$pattern" . --exclude-dir=.git --exclude-dir=.venv --exclude-dir=venv --exclude-dir=node_modules --exclude="*.sh" --exclude="SECURITY_INCIDENT_REPORT.md" -l
        ((FAILED_CHECKS++))
    else
        echo -e "${GREEN}CLEAN${NC}"
    fi
}

# Function to check Git history
check_git_history() {
    local pattern="$1"
    local description="$2"
    
    echo -n "Checking Git history for $description... "
    
    if git log --all -S "$pattern" --oneline | grep -q .; then
        echo -e "${RED}FOUND IN HISTORY${NC}"
        echo "  Commits containing $description:"
        git log --all -S "$pattern" --oneline
        ((FAILED_CHECKS++))
    else
        echo -e "${GREEN}CLEAN${NC}"
    fi
}

echo "1. Scanning working directory for sensitive patterns..."
echo "------------------------------------------------------"

# Check for private keys
check_pattern "BEGIN.*PRIVATE.*KEY" "private keys"
check_pattern "BEGIN RSA PRIVATE KEY" "RSA private keys"
check_pattern "BEGIN OPENSSH PRIVATE KEY" "OpenSSH private keys"
check_pattern "BEGIN EC PRIVATE KEY" "EC private keys"
check_pattern "BEGIN DSA PRIVATE KEY" "DSA private keys"

# Check for certificates (but exclude placeholders)
check_pattern "BEGIN CERTIFICATE.*[A-Za-z0-9+/]{20}" "real certificates"

# Check for common secret patterns
check_pattern "password.*=" "passwords"
check_pattern "token.*=" "tokens"
check_pattern "secret.*=" "secrets"
check_pattern "api.key.*=" "API keys"

# Check for specific backup directories
echo -n "Checking for .hubble-backup directory... "
if [ -d ".hubble-backup" ]; then
    echo -e "${RED}EXISTS${NC}"
    echo "  Directory still present - should be removed"
    ((FAILED_CHECKS++))
else
    echo -e "${GREEN}REMOVED${NC}"
fi

echo ""
echo "2. Scanning Git history for sensitive data..."
echo "---------------------------------------------"

# Check Git history
check_git_history "BEGIN PRIVATE KEY" "private keys"
check_git_history "BEGIN RSA PRIVATE KEY" "RSA private keys"
check_git_history "hubble-backup" ".hubble-backup references"

echo ""
echo "3. Validating .gitignore coverage..."
echo "-----------------------------------"

# Check if .gitignore has security patterns
echo -n "Checking .gitignore for security patterns... "
if grep -q "*.key" .gitignore && grep -q "*backup*" .gitignore; then
    echo -e "${GREEN}CONFIGURED${NC}"
else
    echo -e "${YELLOW}INCOMPLETE${NC}"
    echo "  Consider adding more security patterns to .gitignore"
fi

echo ""
echo "4. Final Security Assessment"
echo "============================"

if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}✅ SECURITY VALIDATION PASSED${NC}"
    echo "Repository is clean of sensitive data"
    echo ""
    echo "Next steps:"
    echo "- Regenerate all certificates and keys"
    echo "- Update all affected credentials"
    echo "- Notify team members if this was a shared repository"
    echo "- Consider implementing pre-commit hooks"
else
    echo -e "${RED}❌ SECURITY VALIDATION FAILED${NC}"
    echo "Found $FAILED_CHECKS security issues that need attention"
    echo ""
    echo "Immediate actions required:"
    echo "1. Review and fix all flagged items above"
    echo "2. Re-run this validation script"
    echo "3. Do not push to remote until all issues are resolved"
    exit 1
fi

echo ""
echo "Security validation completed at $(date)"
