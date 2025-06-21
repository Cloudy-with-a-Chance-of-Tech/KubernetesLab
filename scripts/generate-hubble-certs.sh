#!/bin/bash
set -e

# Generate self-signed certificates for Hubble relay but don't enable TLS
# This script creates temporary certificates required by Hubble relay while keeping TLS disabled

# Define color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   Hubble Certificate Generator - TLS Disabled Mode         ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf ${TEMP_DIR}' EXIT

echo -e "${YELLOW}→ Generating self-signed certificates for Hubble relay...${NC}"

# Generate a private key for the CA
openssl genrsa -out "${TEMP_DIR}/ca.key" 2048

# Generate CA certificate
openssl req -x509 -new -nodes -key "${TEMP_DIR}/ca.key" -sha256 -days 365 -out "${TEMP_DIR}/ca.crt" \
    -subj "/CN=Hubble Relay CA"

# Generate a private key for the server
openssl genrsa -out "${TEMP_DIR}/server.key" 2048

# Create a certificate signing request (CSR) for the server
openssl req -new -key "${TEMP_DIR}/server.key" -out "${TEMP_DIR}/server.csr" \
    -subj "/CN=hubble-relay.cilium.svc"

# Sign the server CSR with the CA
openssl x509 -req -in "${TEMP_DIR}/server.csr" -CA "${TEMP_DIR}/ca.crt" \
    -CAkey "${TEMP_DIR}/ca.key" -CAcreateserial -out "${TEMP_DIR}/server.crt" \
    -days 365 -sha256

# Generate a private key for the client
openssl genrsa -out "${TEMP_DIR}/client.key" 2048

# Create a CSR for the client
openssl req -new -key "${TEMP_DIR}/client.key" -out "${TEMP_DIR}/client.csr" \
    -subj "/CN=hubble-client"

# Sign the client CSR with the CA
openssl x509 -req -in "${TEMP_DIR}/client.csr" -CA "${TEMP_DIR}/ca.crt" \
    -CAkey "${TEMP_DIR}/ca.key" -CAcreateserial -out "${TEMP_DIR}/client.crt" \
    -days 365 -sha256

echo -e "${YELLOW}→ Creating Kubernetes secrets for certificates...${NC}"

# Create or update the server certificate secret
kubectl create secret generic -n cilium hubble-relay-server-certs \
    --from-file=tls.crt="${TEMP_DIR}/server.crt" \
    --from-file=tls.key="${TEMP_DIR}/server.key" \
    --from-file=ca.crt="${TEMP_DIR}/ca.crt" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create or update the client certificate secret
kubectl create secret generic -n cilium hubble-relay-client-certs \
    --from-file=tls.crt="${TEMP_DIR}/client.crt" \
    --from-file=tls.key="${TEMP_DIR}/client.key" \
    --from-file=ca.crt="${TEMP_DIR}/ca.crt" \
    --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✅ Generated and deployed Hubble relay certificates successfully!${NC}"
echo -e "${YELLOW}NOTE: Certificates are created but TLS remains disabled in the configuration.${NC}"
echo -e "${YELLOW}      These certificates provide required paths without enforcing encryption.${NC}"
