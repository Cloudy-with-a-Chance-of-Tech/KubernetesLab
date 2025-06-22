#!/bin/bash
set -e

# Kustomization Validation Script
# Validates that all kustomization files reference existing resources

echo "🔍 Validating Kustomization Files"
echo "================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

ERRORS=0

# Find all kustomization files
echo "📋 Found kustomization files:"
find . -name "kustomization.yaml" -type f | while read kustomization_file; do
    echo "  • $kustomization_file"
done

echo ""
echo "🔍 Validating resource references..."

# Check each kustomization file
find . -name "kustomization.yaml" -type f | while read kustomization_file; do
    dir=$(dirname "$kustomization_file")
    echo -e "${YELLOW}Checking: $kustomization_file${NC}"
    
    # Extract resources from kustomization file, ignoring comments
    resources=$(grep -A 100 "^resources:" "$kustomization_file" | grep "^  - " | grep -v "^  #" | sed 's/^  - //' || true)
    
    if [ -z "$resources" ]; then
        echo -e "  ${GREEN}✓ No resources defined${NC}"
        continue
    fi
    
    # Check each resource
    while IFS= read -r resource; do
        if [ -n "$resource" ]; then
            resource_path="$dir/$resource"
            if [ -f "$resource_path" ] || [ -d "$resource_path" ]; then
                echo -e "  ${GREEN}✓ $resource${NC}"
            else
                echo -e "  ${RED}✗ $resource (missing file/directory)${NC}"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    done <<< "$resources"
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All kustomization files validated successfully!${NC}"
    echo "All referenced resources exist and are accessible."
else
    echo -e "${RED}❌ Found $ERRORS missing resource references${NC}"
    echo "Fix the missing files or update kustomization.yaml files."
    exit 1
fi

echo ""
echo "🧪 Testing kustomization builds..."

# Test build each kustomization
find . -name "kustomization.yaml" -type f | while read kustomization_file; do
    dir=$(dirname "$kustomization_file")
    echo -e "${YELLOW}Testing build: $dir${NC}"
    
    if kubectl kustomize "$dir" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Builds successfully${NC}"
    else
        echo -e "  ${RED}✗ Build failed${NC}"
        echo "    Error details:"
        kubectl kustomize "$dir" 2>&1 | sed 's/^/    /' || true
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}🎉 All kustomizations are valid and ready for deployment!${NC}"
    exit 0
else
    echo -e "${RED}💥 Found $ERRORS kustomization issues${NC}"
    echo "Fix the issues above before deploying."
    exit 1
fi
