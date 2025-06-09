#!/bin/bash

# personal-workflow.sh
# Summary of your personal Talos credential management workflow

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔐 Personal Talos Credential Management${NC}"
echo ""

echo -e "${GREEN}✅ Your Current Setup:${NC}"
echo "   • Credentials secured in ~/.talos-credentials/kub/"
echo "   • Template in git at base/talos/talosconfig.template"  
echo "   • Working config excluded from git (.gitignore)"
echo "   • Simple backup/restore scripts available"
echo ""

echo -e "${GREEN}📋 Key Scripts for Personal Use:${NC}"
echo ""

echo -e "${YELLOW}Credential Management:${NC}"
echo "   ./scripts/restore-talos-credentials.sh    # Restore working config from template"
echo "   ./scripts/simple-backup.sh               # Backup your credentials"
echo "   ./scripts/simple-restore.sh              # Restore from backup"
echo ""

echo -e "${YELLOW}Cluster Management:${NC}"
echo "   ./scripts/cluster-status.sh              # Check cluster health"
echo "   ./scripts/install-cilium.sh              # Install/upgrade Cilium"
echo "   ./scripts/validate-setup.sh              # Full cluster validation"
echo ""

echo -e "${GREEN}🔄 Typical Workflows:${NC}"
echo ""

echo -e "${YELLOW}After git pull (restore working config):${NC}"
echo "   ./scripts/restore-talos-credentials.sh"
echo ""

echo -e "${YELLOW}Daily health check:${NC}"
echo "   ./scripts/cluster-status.sh"
echo ""

echo -e "${YELLOW}Weekly backup:${NC}"
echo "   ./scripts/simple-backup.sh"
echo ""

echo -e "${GREEN}📁 File Locations:${NC}"
echo "   ~/.talos-credentials/kub/        # Your secure credentials (NEVER commit)"
echo "   base/talos/talosconfig          # Working config (gitignored)"
echo "   base/talos/talosconfig.template # Safe template (committed)"
echo ""

echo -e "${GREEN}🔒 Security Notes:${NC}"
echo "   • Real credentials are outside git repository"
echo "   • Only configuration templates are versioned"
echo "   • .gitignore protects sensitive files automatically"
echo "   • Regular backups protect against data loss"
echo ""

echo "💡 Run specific scripts for more detailed help and options."
