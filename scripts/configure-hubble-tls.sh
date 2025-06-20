#!/bin/bash
set -e

# Ensure we're in the repo root
cd "$(git rev-parse --show-toplevel)"

# Define color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

usage() {
  echo -e "${YELLOW}Usage: $0 [--tls|--no-tls]${NC}"
  echo ""
  echo "Options:"
  echo "  --tls      Enable TLS for Hubble communications (default)"
  echo "  --no-tls   Disable TLS for Hubble communications (use when no CA/certificates available)"
  echo ""
  exit 1
}

# Process command line arguments
mode=""
if [[ $# -eq 0 ]]; then
  usage
elif [[ $# -eq 1 ]]; then
  case "$1" in
    --tls)
      mode="tls"
      ;;
    --no-tls)
      mode="no-tls"
      ;;
    *)
      usage
      ;;
  esac
else
  usage
fi

# Display startup banner
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   Hubble TLS Configuration Manager - June 2025            ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

backup_existing_deployments() {
  echo -e "${YELLOW}→ Backing up current Hubble deployments...${NC}"
  
  # Create a backup directory if it doesn't exist
  mkdir -p .hubble-backup
  
  # Backup current deployments
  kubectl get deployment -n cilium hubble-relay -o yaml > .hubble-backup/hubble-relay-$(date +%Y%m%d%H%M%S).yaml 2>/dev/null || true
  kubectl get deployment -n cilium hubble-ui -o yaml > .hubble-backup/hubble-ui-$(date +%Y%m%d%H%M%S).yaml 2>/dev/null || true
  kubectl get configmap -n cilium hubble-relay-config -o yaml > .hubble-backup/hubble-relay-config-$(date +%Y%m%d%H%M%S).yaml 2>/dev/null || true
  
  echo -e "${GREEN}✓ Backups created in .hubble-backup directory${NC}"
}

configure_hubble_with_tls() {
  echo -e "${YELLOW}→ Configuring Hubble with TLS enabled...${NC}"
  
  # Apply standard TLS-enabled configurations
  kubectl apply -f networking/cilium/hubble-relay-config.yaml
  kubectl apply -k networking/
  
  echo -e "${GREEN}✓ Hubble configured with TLS enabled${NC}"
  echo ""
  echo -e "${YELLOW}NOTE: This requires valid TLS certificates in the 'hubble-relay-client-certs' secret${NC}"
  echo -e "${YELLOW}If certificates are not yet configured, communication will fail${NC}"
}

configure_hubble_without_tls() {
  echo -e "${YELLOW}→ Configuring Hubble with TLS disabled...${NC}"
  
  # Apply the no-TLS configurations
  kubectl apply -f networking/cilium/no-tls/hubble-relay-config-no-tls.yaml
  kubectl apply -f networking/cilium/no-tls/hubble-relay-deployment-no-tls.yaml
  kubectl apply -f networking/cilium/no-tls/hubble-ui-deployment-no-tls.yaml
  
  echo -e "${GREEN}✓ Hubble configured with TLS disabled${NC}"
  echo ""
  echo -e "${YELLOW}NOTE: This is less secure but works without certificates${NC}"
  echo -e "${YELLOW}Consider enabling TLS when a proper CA is available${NC}"
}

# Backup existing deployments first
backup_existing_deployments

# Configure according to the requested mode
if [[ "$mode" == "tls" ]]; then
  configure_hubble_with_tls
elif [[ "$mode" == "no-tls" ]]; then
  configure_hubble_without_tls
fi

# Wait for deployments to be ready
echo ""
echo -e "${YELLOW}→ Waiting for deployments to be ready...${NC}"

echo -ne "${YELLOW}→ Checking hubble-relay status...${NC}"
kubectl rollout status deployment/hubble-relay -n cilium --timeout=60s && echo -e "${GREEN} ✓ Ready${NC}" || echo -e "${RED} ✗ Failed${NC}"

echo -ne "${YELLOW}→ Checking hubble-ui status...${NC}"
kubectl rollout status deployment/hubble-ui -n cilium --timeout=60s && echo -e "${GREEN} ✓ Ready${NC}" || echo -e "${RED} ✗ Failed${NC}"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   Hubble ${mode} configuration completed                   ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "Hubble UI should be accessible via NodePort: http://<node-ip>:31235"
echo -e "To verify connectivity, run: kubectl logs -n cilium deployment/hubble-relay"
echo ""
