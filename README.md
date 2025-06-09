# KubernetesLab

A comprehensive collection of Kubernetes configurations and manifests for my home lab environment. This repository serves as both a learning playground and a production-ready setup for containerized workloads.

## Overview

This lab focuses on building a robust Kubernetes environment that can handle everything from development testing to production workloads. The configurations here are battle-tested in my home lab setup, which includes a mix of Raspberry Pi CM4 clusters and Lenovo Tiny desktops running Talos Linux for an immutable, security-focused infrastructure.

## Lab Architecture

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| **Operating System** | Immutable OS | Talos Linux |
| **Control Plane** | Kubernetes Masters | Lenovo Tiny Desktops (3x nodes) |
| **Worker Nodes** | Workload Execution | Raspberry Pi CM4 Cluster (6x nodes, 8GB RAM, NVMe) |
| **Storage** | Persistent Volumes | local-path-provisioner + NFS |
| **Networking** | CNI & Load Balancing | Cilium + BGP to pfSense |
| **Monitoring** | Observability Stack | Prometheus + Grafana + AlertManager |
| **CI/CD** | GitHub Actions Runners | Self-hosted runners on ARM64 nodes |

## What's Inside

This repository contains configurations for:

- **Core Infrastructure**
  - Talos cluster configuration and machine configs
  - Network policies and security contexts
  - Storage classes and persistent volume definitions
  
- **Application Deployments**
  - Namespace organization and resource quotas
  - Common application stacks (monitoring, logging, etc.)
  - Development and testing environments
  
- **GitOps Workflows**
  - GitHub-based GitOps with automated deployments
  - Self-hosted GitHub Actions runners on Kubernetes
  - Environment promotion through Git workflows
  - Continuous deployment pipelines

## Getting Started

### Prerequisites

Before diving into these configurations, make sure you have:

- Physical nodes or VMs ready for Talos installation
- `talosctl` CLI tool installed
- `kubectl` CLI tool installed  
- Basic understanding of Kubernetes concepts (Pods, Services, Deployments, etc.)
- Network configuration planned (node IPs, BGP setup if applicable)
- Optionally: Helm 3.x for chart-based deployments

### Cluster Lifecycle Management

This repository includes comprehensive automation scripts for managing your Talos Kubernetes cluster from initial deployment to teardown. All scripts are located in the `scripts/` directory.

#### 🚀 **Complete Setup (New Cluster)**

1. **Clone this repository**
   ```bash
   git clone https://github.com/twimprine/KubernetesLab.git
   cd KubernetesLab
   ```

2. **Configure node IP addresses**
   ```bash
   # Edit scripts to match your environment
   nano scripts/deploy-cluster.sh      # Update CONTROLPLANE_IPS and WORKER_IPS
   nano scripts/install-cilium.sh     # Update BGP configuration if needed
   ```

3. **Run complete setup**
   ```bash
   # This orchestrates the entire cluster deployment
   ./scripts/setup-complete-cluster.sh
   ```

   Or for a quick setup without prompts:
   ```bash
   # Skip confirmation prompts and reset
   ./scripts/setup-complete-cluster.sh --skip-reset
   ```

#### 🔧 **Manual Step-by-Step Deployment**

For more control or troubleshooting, you can run each step individually:

1. **Generate Talos configurations**
   ```bash
   ./scripts/generate-talos-config.sh
   ```

2. **Deploy configurations to nodes**
   ```bash
   ./scripts/deploy-cluster.sh
   ```

3. **Bootstrap Kubernetes cluster**
   ```bash
   ./scripts/bootstrap-cluster.sh
   ```

4. **Install Cilium CNI**
   ```bash
   ./scripts/install-cilium.sh
   ```

#### 🗑️ **Cluster Teardown**

When you need to rebuild or decommission:

```bash
# Safely destroy the entire cluster
./scripts/destroy-cluster.sh
```

#### 🔄 **Working with Existing Pi Cluster**

If you already have a running Talos Kubernetes cluster on Raspberry Pi hardware, these scripts can help you manage it safely:

1. **Setup talosconfig for existing cluster**
   ```bash
   # Configure talosctl to work with your existing cluster
   ./scripts/setup-talosconfig.sh
   ```

2. **Check cluster status and health**
   ```bash
   # Comprehensive health check for Pi cluster
   ./scripts/cluster-status.sh
   ```

3. **Regenerate configurations (if needed)**
   ```bash
   # Updates Talos configs based on existing control_nodes.yaml
   ./scripts/generate-talos-config.sh
   ```

4. **Safe cluster reset for Pi nodes**
   ```bash
   # Safely destroys cluster using VIP endpoint
   # Uses --wipe-mode user-disks for remote Pi nodes
   ./scripts/destroy-cluster.sh
   ```

**Pi-Specific Considerations:**
- All operations use VIP endpoint (192.168.1.30) for remote management
- Scripts include extended timeouts for Pi boot sequences
- Destroy operations use `--wipe-mode user-disks` for safe remote reset
- Hardware address to hostname mapping handles Pi-specific networking

#### 📖 **Script Documentation**

Each script includes detailed documentation and error handling. For comprehensive usage information:

```bash
# See all available scripts and their purposes
ls -la scripts/
cat scripts/README.md
```

## Directory Structure

```
├── base/                   # Core cluster configurations
│   ├── namespaces/        # Namespace definitions
│   ├── rbac/              # Role-based access control
│   ├── storage/           # Storage classes and PVs
│   └── talos/             # Talos machine configuration templates
├── scripts/               # Cluster lifecycle automation
│   ├── generate-talos-config.sh    # Generate machine configs
│   ├── deploy-cluster.sh           # Deploy configs to nodes
│   ├── bootstrap-cluster.sh        # Initialize Kubernetes
│   ├── install-cilium.sh          # Install CNI with BGP
│   ├── destroy-cluster.sh         # Safely teardown cluster
│   ├── setup-complete.sh          # End-to-end automation
│   ├── validate-setup.sh          # Health & status validation
│   └── README.md                   # Script documentation
├── apps/                   # Application deployments
│   ├── development/       # Dev environment apps
│   ├── staging/           # Staging environment apps
│   └── production/        # Production workloads
├── monitoring/            # Observability stack
│   ├── prometheus/        # Metrics collection
│   ├── grafana/          # Visualization
│   └── alertmanager/     # Alert routing
├── networking/            # Cilium configs and BGP policies
├── security/              # Security policies and tools
└── docs/                  # Additional documentation
```

## Storage Configuration

The cluster uses **local-path-provisioner** for dynamic persistent volume provisioning on the Raspberry Pi nodes. This provides fast local storage for applications while maintaining the ability to schedule pods with persistent storage on any node.

### 🏠 **Storage Setup**

#### **Automatic Installation**
Storage is automatically configured when using the complete setup script:
```bash
./scripts/setup-complete-cluster.sh
```

#### **Manual Installation**
To install storage separately:
```bash
# Install local-path-provisioner
./scripts/install-storage.sh

# Validate storage functionality
./scripts/validate-storage.sh
```

### 📊 **Storage Features**

- **Dynamic Provisioning**: Automatically creates persistent volumes on demand
- **Default StorageClass**: `local-path` is set as the default storage class
- **Node Storage Path**: `/opt/local-path-provisioner` on each node
- **Volume Binding Mode**: `WaitForFirstConsumer` for optimal pod scheduling
- **Reclaim Policy**: `Delete` to clean up storage when PVCs are removed
- **ARM64 Optimized**: Specifically configured for Raspberry Pi CM4 architecture

### 🧪 **Testing Storage**

The repository includes comprehensive storage testing:

```bash
# Run storage validation tests
./scripts/validate-storage.sh

# Deploy test workloads
kubectl apply -f base/storage/storage-test.yaml

# Monitor storage usage
kubectl get pv,pvc --all-namespaces
```

### 💡 **Usage Examples**

**Simple PVC:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-storage
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path  # Can be omitted (default)
  resources:
    requests:
      storage: 10Gi
```

**StatefulSet with Storage:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
spec:
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: local-path
      resources:
        requests:
          storage: 5Gi
```

## GitHub Actions Self-Hosted Runners

This lab includes a production-ready setup for GitHub Actions self-hosted runners that execute directly on your Kubernetes cluster. This provides several advantages over GitHub's hosted runners:

### 🚀 **Benefits**
- **Native Kubernetes Access**: Runners can directly interact with your cluster
- **ARM64 Support**: Optimized for Raspberry Pi CM4 worker nodes
- **Cost Effective**: No GitHub Actions minutes consumed for self-hosted runner jobs
- **Custom Environment**: Full control over runner environment and tools
- **Network Access**: Direct access to internal services and resources

### 📋 **Current Configuration**
- **Location**: `apps/production/github-runner.yaml`
- **Namespace**: `github-actions`
- **Architecture**: ARM64 (Raspberry Pi CM4 optimized)
- **Mode**: Ephemeral (fresh environment per job)
- **Labels**: `kubernetes`, `talos`, `cilium`, `homelab`, `arm64`, `self-hosted`
- **Security**: Privileged containers with proper RBAC

### 🔧 **Required Secrets**
Before deploying runners, create these Kubernetes secrets:

```bash
# GitHub token with repo, admin:org, workflow scopes
kubectl create secret generic github-runner-secret \
  --from-literal=github-token="your_github_token" \
  --from-literal=runner-name="k8s-runner" \
  -n github-actions
```

### 🎯 **Using in Workflows**
Target your self-hosted runners in GitHub Actions workflows:

```yaml
jobs:
  deploy:
    runs-on: [self-hosted, kubernetes, arm64]
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to cluster
        run: kubectl apply -f manifests/
```

### 📊 **Monitoring & Scaling**
- **HPA**: Auto-scales from 1-5 runners based on CPU/memory usage
- **Resource Limits**: 2Gi RAM, 1 CPU per runner
- **Health Checks**: Liveness and readiness probes monitor runner status
- **Logs**: Centralized logging with pod log aggregation

**Verify runner status:**
```bash
kubectl get pods -n github-actions
kubectl logs -f deployment/github-runner -n github-actions
```

**Check in GitHub**: Organization Settings → Actions → Runners

📖 **Detailed setup guide**: [docs/github-actions-setup.md](docs/github-actions-setup.md)

## Automation & Management

This lab leverages automation wherever possible:

- **Infrastructure as Code**: All configurations are version-controlled and declarative
- **Immutable Infrastructure**: Talos provides immutable OS with API-driven management
- **GitHub GitOps**: Changes flow through GitHub workflows with automated deployments
- **BGP Load Balancing**: Cilium provides native load balancing via BGP peering with pfSense
- **Declarative Management**: Talos machine configs define the entire system state
- **Monitoring First**: Every service includes appropriate monitoring and alerting

## Lab Philosophy

This setup follows several key principles:

1. **Everything as Code** - No manual kubectl gymnastics in production
2. **Immutable Infrastructure** - Talos ensures consistent, secure, and reproducible deployments
3. **Security by Default** - Network policies, RBAC, and security contexts on everything
4. **Observable Always** - If it's running, it's monitored
5. **Failure is Expected** - Chaos engineering and resilience testing built-in
6. **Documentation Matters** - Every configuration should be self-explanatory

## Application Deployment

Once your cluster is running, you can deploy applications using the pre-configured manifests:

### Prerequisites for Applications
- Running Talos Kubernetes cluster with Cilium CNI
- GitHub repository with Actions enabled (for GitHub runners)
- kubectl configured for your cluster

### Initial Application Setup
1. **Configure GitHub Secrets** (Repository → Settings → Secrets and variables → Actions):
   - `RUNNER_TOKEN` - GitHub Personal Access Token (repo, admin:org, workflow scopes)
   - `ORG_NAME` - Your GitHub organization or username  
   - `GRAFANA_ADMIN_PASSWORD` - Strong password for Grafana admin

2. **Create Kubernetes Secrets**:
   ```bash
   # GitHub runner authentication
   kubectl create secret generic github-runner-secret \
     --from-literal=github-token="$RUNNER_TOKEN" \
     --from-literal=runner-name="k8s-runner" \
     -n github-actions
   ```

3. **Bootstrap Base Infrastructure**:
   ```bash
   kubectl apply -f base/namespaces/
   kubectl apply -f base/rbac/
   ```

4. **Deploy Core Services**:
   ```bash
   # Monitoring stack
   kubectl apply -f monitoring/
   
   # GitHub Actions runners
   kubectl apply -f apps/production/github-runner.yaml
   ```

5. **Enable GitOps** - Push to main branch triggers automated deployment

📖 **Detailed setup guide**: [docs/github-actions-setup.md](docs/github-actions-setup.md)

## Usage Notes

### Development Workflow

1. Make changes in feature branches
2. Test configurations in the development namespace first
3. Create pull request for review
4. Merge triggers GitHub Actions for automated deployment
5. Promote through staging before production deployment
6. Monitor everything - seriously, everything

### Common Operations

**Cluster Lifecycle:**
```bash
# Rebuild entire cluster
./scripts/destroy-cluster.sh && ./scripts/setup-complete.sh

# Update cluster configurations
./scripts/generate-talos-config.sh
./scripts/deploy-cluster.sh

# Validate cluster health
./scripts/validate-setup.sh

# Recreate just the CNI
kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/1.14.3/install/kubernetes/quick-install.yaml
./scripts/install-cilium.sh
```

**Scale a deployment:**
```bash
kubectl scale deployment/my-app --replicas=3 -n production
```

**Check resource usage:**
```bash
kubectl top nodes
kubectl top pods -n production
```

**Debug networking issues:**
```bash
kubectl get ciliumnodes
kubectl get bgppolicies -A
kubectl describe svc my-service -n production
```

**Check Talos system status:**
```bash
talosctl health
talosctl logs --tail
talosctl get members
```

**Manage GitHub Actions runners:**
```bash
# Check runner status
kubectl get pods -n github-actions
kubectl logs -f deployment/github-runner -n github-actions

# Scale runners manually
kubectl scale deployment/github-runner --replicas=3 -n github-actions

# Restart runners (useful for updates)
kubectl rollout restart deployment/github-runner -n github-actions
```

## Troubleshooting

Most common issues and their solutions:

| Issue | Likely Cause | Solution |
|-------|--------------|----------|
| Script fails during cluster setup | Network/connectivity issue | Check node IPs in scripts, verify network connectivity |
| Talos config generation fails | Missing talosctl or permissions | Install talosctl, check file permissions in base/talos/ |
| Cluster bootstrap timeout | Nodes not responding | Verify Talos installation, check `talosctl health` |
| Cilium installation fails | CNI conflict or network policy | Clean install with `./scripts/destroy-cluster.sh` then retry |
| Pods stuck in Pending | Resource constraints | Check `kubectl describe pod` and node resources |
| Service unreachable | BGP route not advertised | Check Cilium BGP policies and pfSense routing |
| LoadBalancer stuck pending | BGP peering issue | Verify `kubectl get ciliumnodes` and pfSense BGP config |
| Node not ready | Talos system issue | Check `talosctl health` and `talosctl logs` |
| Storage issues | PV/PVC mismatch | Verify storage class and access modes |
| GitHub runner not appearing | Authentication or permission issue | Check `kubectl logs deployment/github-runner -n github-actions` and verify secrets |
| Runner jobs failing | Missing tools or permissions | Check runner logs and ensure required tools are installed in container |

**Cluster Recovery:**
- For persistent issues, use `./scripts/destroy-cluster.sh` followed by `./scripts/setup-complete.sh`
- Scripts are configured for Raspberry Pi with `--wipe-mode user-disks` (safe for remote nodes)
- Check all scripts have executable permissions: `chmod +x scripts/*.sh`
- Verify node IP addresses in scripts match your actual hardware

For more complex issues, check the monitoring dashboards first - they usually tell the story.

## Contributing

This is primarily a personal lab environment, but if you find something useful or spot an improvement opportunity:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/awesome-improvement`)
3. Test your changes thoroughly
4. Submit a pull request with a clear description

## Learning Resources

If you're new to Kubernetes or want to dive deeper:

- [Official Kubernetes Documentation](https://kubernetes.io/docs/)
- [Talos Linux Documentation](https://www.talos.dev/docs/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [CNCF Landscape](https://landscape.cncf.io/) - Great for discovering tools

## Disclaimer

This lab configuration works great for my environment, but your mileage may vary. Always test configurations in a safe environment before applying to anything important. That said, these configs are battle-tested and should provide a solid foundation for your own Kubernetes journey.

## Contact

Questions, suggestions, or just want to chat about Kubernetes?

- **Blog**: [https://blog.thomaswimprine.com](https://blog.thomaswimprine.com)
- **GitHub Projects**: [@Cloudy-with-a-Chance-of-Tech](https://github.com/Cloudy-with-a-Chance-of-Tech)
- **GitHub Personal**: [@twimprine](https://github.com/twimprine)
- **LinkedIn**: [thomaswimprine](https://www.linkedin.com/in/thomaswimprine)

Until the next deployment,

• Cheers

---

*Part of the "Cloudy with a Chance of Tech" series - Exploring the intersection of home labs and cloud-native technologies.*