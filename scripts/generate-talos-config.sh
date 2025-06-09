#!/bin/bash
set -euo pipefail

# Generate fresh Talos configuration for Raspberry Pi cluster reset
# This script creates new certificates and configurations for a clean cluster build

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/base/talos"
CONTROL_NODES_FILE="${REPO_ROOT}/control_nodes.yaml"

echo "🔧 Generating fresh Talos cluster configuration..."

# Check if talosctl is installed
if ! command -v talosctl &> /dev/null; then
    echo "❌ talosctl is not installed. Please install it first:"
    echo "   curl -sL https://talos.dev/install | sh"
    exit 1
fi

# Extract cluster configuration from control_nodes.yaml
if [[ ! -f "${CONTROL_NODES_FILE}" ]]; then
    echo "❌ control_nodes.yaml not found at ${CONTROL_NODES_FILE}"
    exit 1
fi

# Parse cluster configuration
CLUSTER_NAME=$(yq eval '.cluster.name' "${CONTROL_NODES_FILE}")
VIP=$(yq eval '.cluster.endpoint' "${CONTROL_NODES_FILE}" | sed 's|https://||' | sed 's|:6443||')
DNS_DOMAIN=$(yq eval '.cluster.clusterNetwork.dnsDomain' "${CONTROL_NODES_FILE}")
KUBERNETES_VERSION=$(yq eval '.cluster.kubernetesVersion' "${CONTROL_NODES_FILE}")

echo "📝 Cluster Configuration:"
echo "   Name: ${CLUSTER_NAME}"
echo "   VIP: ${VIP}"
echo "   DNS Domain: ${DNS_DOMAIN}"
echo "   Kubernetes: ${KUBERNETES_VERSION}"

# Create talos directory
mkdir -p "${TALOS_DIR}"

# Remove old configurations to ensure clean start
echo "🧹 Cleaning up old configurations..."
rm -f "${TALOS_DIR}/talosconfig" "${TALOS_DIR}"/controlplane*.yaml "${TALOS_DIR}"/worker*.yaml

# Generate fresh Talos configuration with new certificates
echo "🔐 Generating new cluster certificates and configuration..."

talosctl gen config "${CLUSTER_NAME}" "https://${VIP}:6443" \
    --output-dir "${TALOS_DIR}" \
    --with-docs=false \
    --with-examples=false \
    --kubernetes-version="${KUBERNETES_VERSION}" \
    --additional-sans="${VIP}"

echo "✅ Generated base Talos configuration files"

# Create Pi-optimized control plane configuration patch
echo "🥧 Creating Raspberry Pi optimized configurations..."

cat > "${TALOS_DIR}/controlplane-pi.yaml.patch" << 'EOF'
machine:
  install:
    disk: /dev/mmcblk0
    image: ghcr.io/siderolabs/installer:v1.9.5
    wipe: false
  features:
    rbac: true
    stableHostname: true
    apidCheckExtKeyUsage: true
    diskQuotaSupport: true
    kubePrism:
      enabled: true
      port: 7445
  sysctls:
    net.core.somaxconn: 65535
    net.core.netdev_max_backlog: 4096
  kubelet:
    image: ghcr.io/siderolabs/kubelet:v1.32.3
    extraArgs:
      feature-gates: GracefulNodeShutdown=true
      rotate-server-certificates: true
    nodeIP:
      validSubnets:
        - 192.168.1.0/24
  network:
    hostname: ""  # Will be set per-node
    interfaces:
      - interface: eth0
        dhcp: false
        addresses:
          - ""  # Will be set per-node
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
        mtu: 1500
        vip:
          ip: 192.168.1.30
  files:
    - content: |
        [plugins."io.containerd.grpc.v1.cri"]
          enable_unprivileged_ports = true
          enable_unprivileged_icmp = true
      path: /etc/cri/conf.d/20-customization.part
      op: create
  systemDiskEncryption:
    ephemeral:
      provider: luks2
      keys:
        - nodeID: {}
          slot: 0
    state:
      provider: luks2
      keys:
        - nodeID: {}
          slot: 0
  dirs:
    - path: /opt/local-path-provisioner
      mode: 0755
cluster:
  allowSchedulingOnControlPlanes: false
  network:
    dnsDomain: kub-cluster.local
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.96.0.0/12
    cni:
      name: none  # We'll install Cilium manually
  proxy:
    disabled: true  # Cilium will handle kube-proxy functionality
  discovery:
    enabled: true
    registries:
      kubernetes:
        disabled: false
      service:
        disabled: false
  scheduler:
    image: ghcr.io/siderolabs/kube-scheduler:v1.32.3
  controllerManager:
    image: ghcr.io/siderolabs/kube-controller-manager:v1.32.3
  apiServer:
    image: ghcr.io/siderolabs/kube-apiserver:v1.32.3
    extraArgs:
      feature-gates: GracefulNodeShutdown=true
    admissionControl:
      - name: PodSecurity
        configuration:
          apiVersion: pod-security.admission.config.k8s.io/v1alpha1
          kind: PodSecurityConfiguration
          defaults:
            enforce: "restricted"
            enforce-version: "latest"
            audit: "restricted"
            audit-version: "latest"
            warn: "restricted" 
            warn-version: "latest"
          exemptions:
            usernames: []
            runtimeClasses: []
            namespaces: [kube-system, cilium]
EOF

# Create worker configuration patch
cat > "${TALOS_DIR}/worker-pi.yaml.patch" << 'EOF'
machine:
  install:
    disk: /dev/mmcblk0
    image: ghcr.io/siderolabs/installer:v1.9.5
    wipe: false
  features:
    rbac: true
    stableHostname: true
    diskQuotaSupport: true
    kubePrism:
      enabled: true
      port: 7445
  sysctls:
    net.core.somaxconn: 65535
    net.core.netdev_max_backlog: 4096
  kubelet:
    image: ghcr.io/siderolabs/kubelet:v1.32.3
    extraArgs:
      feature-gates: GracefulNodeShutdown=true
      rotate-server-certificates: true
    nodeIP:
      validSubnets:
        - 192.168.1.0/24
  network:
    hostname: ""  # Will be set per-node
    interfaces:
      - interface: eth0
        dhcp: false
        addresses:
          - ""  # Will be set per-node
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
        mtu: 1500
  files:
    - content: |
        [plugins."io.containerd.grpc.v1.cri"]
          enable_unprivileged_ports = true
          enable_unprivileged_icmp = true
      path: /etc/cri/conf.d/20-customization.part
      op: create
  dirs:
    - path: /opt/local-path-provisioner
      mode: 0755
EOF

echo "✅ Created Pi-specific configuration patches"

# Create secure configuration management
echo "🔐 Setting up secure credential management..."

# Create secure credentials directory outside git repo
SECURE_DIR="${HOME}/.talos-credentials/${CLUSTER_NAME}"
mkdir -p "${SECURE_DIR}"

# Extract sensitive credentials from talosconfig
echo "🔑 Extracting sensitive credentials..."
yq eval '.contexts.*.ca' "${TALOS_DIR}/talosconfig" > "${SECURE_DIR}/ca.crt.b64"
yq eval '.contexts.*.crt' "${TALOS_DIR}/talosconfig" > "${SECURE_DIR}/client.crt.b64"
yq eval '.contexts.*.key' "${TALOS_DIR}/talosconfig" > "${SECURE_DIR}/client.key.b64"

# Create sanitized talosconfig template (without sensitive keys)
echo "📝 Creating sanitized configuration template..."
cat > "${TALOS_DIR}/talosconfig.template" << EOF
context: ${CLUSTER_NAME}
contexts:
    ${CLUSTER_NAME}:
        endpoints:
            - $(echo ${VIP})
        nodes:
            - $(echo ${VIP})
        ca: "{{ CA_CERTIFICATE }}"
        crt: "{{ CLIENT_CERTIFICATE }}"  
        key: "{{ CLIENT_KEY }}"
EOF

# Move original talosconfig to secure location
mv "${TALOS_DIR}/talosconfig" "${SECURE_DIR}/talosconfig"

# Create symlink for convenience (but add to .gitignore)
ln -sf "${SECURE_DIR}/talosconfig" "${TALOS_DIR}/talosconfig"

# Update .gitignore to exclude sensitive files
GITIGNORE_FILE="${REPO_ROOT}/.gitignore"
echo "🚫 Updating .gitignore to exclude sensitive files..."

if [[ ! -f "${GITIGNORE_FILE}" ]]; then
    touch "${GITIGNORE_FILE}"
fi

# Add entries if they don't already exist
grep -qxF "# Talos sensitive credentials" "${GITIGNORE_FILE}" || {
    echo "" >> "${GITIGNORE_FILE}"
    echo "# Talos sensitive credentials" >> "${GITIGNORE_FILE}"
    echo "base/talos/talosconfig" >> "${GITIGNORE_FILE}"
    echo "*.key" >> "${GITIGNORE_FILE}"
    echo "*.crt" >> "${GITIGNORE_FILE}"
    echo "**/secrets/" >> "${GITIGNORE_FILE}"
}

# Set proper permissions
chmod 700 "${SECURE_DIR}"
chmod 600 "${SECURE_DIR}"/*
chmod 644 "${TALOS_DIR}"/*.yaml*
chmod 644 "${TALOS_DIR}/talosconfig.template"

echo ""
echo "🔐 Configuration files generated securely:"
echo "   ✅ ${TALOS_DIR}/talosconfig.template (safe for git)"
echo "   ✅ ${SECURE_DIR}/talosconfig (contains real credentials)"
echo "   ✅ ${TALOS_DIR}/controlplane.yaml (base control plane)"
echo "   ✅ ${TALOS_DIR}/worker.yaml (base worker)"
echo "   ✅ ${TALOS_DIR}/controlplane-pi.yaml.patch (Pi optimizations)"
echo "   ✅ ${TALOS_DIR}/worker-pi.yaml.patch (Pi optimizations)"

echo ""
echo "🔒 Security Setup Complete:"
echo "   ✅ Sensitive credentials stored in: ${SECURE_DIR}/"
echo "   ✅ Template without secrets: ${TALOS_DIR}/talosconfig.template"
echo "   ✅ Updated .gitignore to exclude sensitive files"
echo "   ✅ Symlink created for tool compatibility"

echo ""
echo "🚀 Next steps for clean cluster rebuild:"
echo "   1. Reset all nodes: ./scripts/destroy-cluster.sh"
echo "   2. Deploy fresh configs: ./scripts/deploy-cluster.sh"
echo "   3. Bootstrap cluster: ./scripts/bootstrap-cluster.sh"
echo "   4. Install Cilium: ./scripts/install-cilium.sh"
echo ""
echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "   • Real credentials are in ~/.talos-credentials/${CLUSTER_NAME}/"
echo "   • Only the template (without keys) is tracked in git"
echo "   • Backup your credentials securely outside this repository"
echo "   • Share credentials securely with team members (not via git)"
