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
  echo "  --no-tls   Disable TLS for Hubble communications but use certificate paths"
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

# We no longer need to generate certificates for no-TLS mode
ensure_tls_configuration() {
  if [[ "$mode" == "tls" ]]; then
    echo -e "${YELLOW}→ Ensuring Hubble certificates exist for TLS mode...${NC}"
    # Check if certificate secrets already exist
    if ! kubectl get secret -n cilium hubble-relay-client-certs &>/dev/null; then
      echo -e "${YELLOW}Certificates not found. Generating certificates...${NC}"
      ./scripts/generate-hubble-certs.sh
    else
      echo -e "${GREEN}✓ Certificate secrets already exist${NC}"
    fi
  else
    echo -e "${YELLOW}→ Using no-TLS mode, no certificates needed${NC}"
  fi
}

configure_hubble_with_tls() {
  echo -e "${YELLOW}→ Configuring Hubble with TLS enabled...${NC}"
  
  # Apply standard TLS-enabled configurations
  kubectl apply -f networking/cilium/hubble-relay-config.yaml
  kubectl apply -k networking/
  
  echo -e "${GREEN}✓ Hubble configured with TLS enabled${NC}"
}

configure_hubble_without_tls() {
  echo -e "${YELLOW}→ Configuring Hubble with TLS disabled (but certificate paths)...${NC}"
  
  # Apply the no-TLS configurations with certificate paths
  kubectl apply -f networking/cilium/no-tls/hubble-relay-config-no-tls-with-certs.yaml
  kubectl apply -f networking/cilium/no-tls/hubble-relay-deployment-no-tls-with-certs.yaml
  kubectl apply -f networking/cilium/no-tls/hubble-ui-deployment-no-tls.yaml
  
  echo -e "${GREEN}✓ Hubble configured with TLS disabled (but certificate paths)${NC}"
  echo ""
  echo -e "${YELLOW}NOTE: This keeps certificates available but disables TLS encryption${NC}"
  echo -e "${YELLOW}Consider enabling TLS when a proper CA is available${NC}"
}

# Backup existing deployments first
backup_existing_deployments

# Ensure certificates exist (for both TLS and no-TLS modes)
ensure_certificates_exist

# Configure according to the requested mode
if [[ "$mode" == "tls" ]]; then
  configure_hubble_with_tls
elif [[ "$mode" == "no-tls" ]]; then
  configure_hubble_without_tls
fi

# Restart pods to apply changes
echo -e "${YELLOW}→ Restarting Hubble pods to apply changes...${NC}"
kubectl delete pod -n cilium -l k8s-app=hubble-relay --grace-period=1
kubectl delete pod -n cilium -l k8s-app=hubble-ui --grace-period=1

echo -e "${YELLOW}→ Waiting for Hubble pods to restart...${NC}"
sleep 5
kubectl get pods -n cilium | grep hubble

echo -e "${GREEN}✓ Configuration completed${NC}"
