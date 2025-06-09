# Cluster Management Scripts

This directory contains automation scripts for managing your Talos Kubernetes cluster lifecycle.

## 🚀 Quick Start

### Complete Cluster Setup
```bash
# Set up everything from scratch (new improved script)
./scripts/setup-complete-cluster.sh

# Legacy complete setup
./scripts/setup-complete.sh
```

### Manual Step-by-Step Setup
```bash
# 1. Generate Talos configurations
./scripts/generate-talos-config.sh

# 2. Deploy configurations to nodes
./scripts/deploy-cluster.sh

# 3. Bootstrap Kubernetes
./scripts/bootstrap-cluster.sh

# 4. Install Cilium CNI
./scripts/install-cilium.sh

# 5. Install storage provisioner
./scripts/install-storage.sh
```

### Cluster Destruction and Rebuild
```bash
# Destroy existing cluster
./scripts/destroy-cluster.sh

# Rebuild from existing configs
./scripts/deploy-cluster.sh
./scripts/bootstrap-cluster.sh
./scripts/install-cilium.sh
```

## 📋 Script Reference

### `generate-talos-config.sh`
- **Purpose**: Generate Talos machine configurations with secrets
- **Output**: Creates `controlplane.yaml`, `worker.yaml`, and `talosconfig` files
- **Security**: Generated files contain secrets and are auto-excluded from git
- **Usage**: Run once per cluster or when rotating secrets

### `deploy-cluster.sh`
- **Purpose**: Apply machine configurations to physical nodes
- **Requirements**: Nodes must be in Talos maintenance mode
- **Process**: Sends configurations to control plane and worker nodes
- **Network**: Requires network access to all node IPs

### `bootstrap-cluster.sh`
- **Purpose**: Initialize Kubernetes cluster on control plane
- **Process**: Bootstraps etcd and starts Kubernetes API server
- **Output**: Generates kubeconfig for cluster access
- **Validation**: Waits for all nodes to join the cluster

### `install-cilium.sh`
- **Purpose**: Install Cilium CNI with BGP support
- **Features**: Installs with BGP control plane, Hubble UI, and monitoring
- **Testing**: Runs connectivity tests to verify installation
- **Requirements**: Cluster must be bootstrapped first

### `destroy-cluster.sh`
- **Purpose**: Safely tear down cluster for rebuilding
- **Process**: Resets all nodes to maintenance mode
- **Raspberry Pi Mode**: Uses `--wipe-mode user-disks` for remote nodes without physical access
- **Preservation**: Keeps Talos configurations for easy rebuild
- **Safety**: Requires confirmation before proceeding

### `setup-complete.sh`
- **Purpose**: Complete end-to-end cluster setup
- **Process**: Orchestrates all setup scripts in sequence
- **Features**: Includes base configurations and monitoring
- **Testing**: Validates load balancer functionality

### `validate-setup.sh`
- **Purpose**: Comprehensive cluster health and configuration validation
- **Checks**: Connectivity, CNI, monitoring, GitHub runners, and more
- **Usage**: Run anytime to check cluster status
- **Output**: Detailed status report with troubleshooting suggestions

## Verification and Monitoring Scripts

### `verify-config.sh`
- **Purpose**: Validate cluster configuration consistency across all files
- **Usage**: Run this script to check:
  - Cluster name consistency across all configuration files
  - Endpoint URLs match your actual cluster
  - Kubernetes version alignment
  - Security configurations (gitignore settings)
  - Script permissions
- **When to use**: Before deploying cluster changes or when troubleshooting configuration issues.

### `cluster-status.sh`
- **Purpose**: Comprehensive cluster health dashboard
- **Usage**: Run this script to get real-time information about:
  - Node health and resource usage
  - System pod status across critical namespaces
  - Storage and network components
  - Recent cluster events and warnings
  - Talos node health (if accessible)
- **When to use**: For daily cluster monitoring, troubleshooting, or health checks.

### `install-storage.sh`
- **Purpose**: Install local-path-provisioner for persistent storage
- **Features**: 
  - Deploys local-path-provisioner to `local-path-storage` namespace
  - Creates `local-path` StorageClass (set as default)
  - Configures storage directory at `/opt/local-path-provisioner`
  - ARM64 optimized for Raspberry Pi nodes
- **Usage**: Run after cluster bootstrap and CNI installation
- **Validation**: Includes automatic PVC testing to verify functionality

### `validate-storage.sh`
- **Purpose**: Comprehensive storage functionality testing
- **Tests**:
  - local-path-provisioner deployment health
  - StorageClass configuration and default status
  - PVC creation and binding
  - Pod storage access and file operations
  - Basic storage performance testing
- **Usage**: Run after storage installation or for troubleshooting storage issues
- **Cleanup**: Automatically cleans up test resources

### `setup-complete-cluster.sh`
- **Purpose**: End-to-end cluster deployment automation
- **Features**:
  - Orchestrates complete cluster setup from clean state
  - Includes optional steps (reset, CNI, storage, base resources)
  - Command-line options for selective deployment
  - Comprehensive validation and status reporting
- **Options**:
  - `--skip-reset`: Skip cluster destruction/reset
  - `--skip-cilium`: Skip Cilium CNI installation
  - `--skip-storage`: Skip storage provisioner installation
  - `--skip-base`: Skip base resource deployment
- **Usage**: For new cluster setup or complete cluster rebuilds

## ⚙️ Configuration

### Node IP Addresses
Update the IP addresses in each script to match your environment:

```bash
# Control plane nodes
CONTROL_PLANE_NODES=(
    "192.168.1.101"  # Update these
    "192.168.1.102"
    "192.168.1.103"
)

# Worker nodes  
WORKER_NODES=(
    "192.168.1.111"  # Update these
    "192.168.1.112"
    "192.168.1.113"
    "192.168.1.114"
    "192.168.1.115"
    "192.168.1.116"
)

# Control plane VIP
CONTROL_PLANE_VIP="192.168.1.100"  # Update this
```

### Cluster Configuration
Key settings in `base/talos/talosconfig.yaml`:
- Cluster name: `kub`
- Pod subnet: `10.244.0.0/16`
- Service subnet: `10.96.0.0/12`
- DNS domain: `cluster.local`

## 🔐 Security Considerations

### Secret Management
- Talos configurations contain cryptographic secrets
- Files are automatically excluded from git via `.gitignore`
- Backup these files securely for disaster recovery
- Rotate secrets periodically using `generate-talos-config.sh`

### Access Control
- Scripts require direct network access to nodes
- Use VPN or secure network for remote management
- Talos API uses mutual TLS authentication
- Kubeconfig provides cluster administrator access

### Network Security
- BGP peering requires trusted network environment
- Load balancer IPs should be within controlled subnets
- Consider firewall rules for cluster traffic

## 🛠️ Troubleshooting

### Common Issues

**Nodes not accessible:**
```bash
# Check network connectivity
ping 192.168.1.101

# Verify Talos is running
talosctl --nodes 192.168.1.101 version --insecure
```

**Bootstrap fails:**
```bash
# Check node status
talosctl --nodes 192.168.1.101 health --server=false

# View system logs
talosctl --nodes 192.168.1.101 logs
```

**Cilium not ready:**
```bash
# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# View Cilium logs
kubectl logs -n kube-system -l k8s-app=cilium
```

**BGP not working:**
```bash
# Check BGP peering policy
kubectl get ciliumbgppeeringpolicy

# Verify load balancer pools
kubectl get ciliumloadbalancerippool
```

### Recovery Procedures

**Lost kubeconfig:**
```bash
talosctl kubeconfig --nodes 192.168.1.100 ~/.kube/config
```

**Cluster partially failed:**
```bash
# Reset specific node
talosctl reset --nodes 192.168.1.101 --graceful=false

# Reapply configuration
talosctl apply-config --nodes 192.168.1.101 --file base/talos/controlplane.yaml
```

**Complete cluster rebuild:**
```bash
./scripts/destroy-cluster.sh
./scripts/setup-complete.sh
```

## 🔧 Dependencies

### Required Tools
- `talosctl` - Talos management CLI
- `kubectl` - Kubernetes CLI
- `helm` - Kubernetes package manager
- `curl` - For downloading components
- `bash` - Shell environment

### Installation
```bash
# Install talosctl
curl -sL https://talos.dev/install | sh

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## 📚 Additional Resources

- [Talos Documentation](https://www.talos.dev/docs/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Repository README](../README.md)
