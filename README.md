# KubernetesLab - Production-Ready Home Infrastructure

Welcome to my Kubernetes home lab—a place where enterprise-grade infrastructure meets hobbyist curiosity. This isn't just another "hello world" Kubernetes setup; it's a battle-tested, security-focused cluster that runs real workloads and handles production traffic in my home environment.

## Why This Lab Exists

Like most infrastructure enthusiasts, I needed a playground where I could break things safely, test new concepts, and run actual services without the corporate constraints. What started as a simple learning exercise has evolved into a robust platform that hosts everything from development environments to critical home automation systems.

This repository represents years of iteration, countless late-night debugging sessions, and the accumulated wisdom of running Kubernetes in production (even if that production happens to be my living room).

## The Lab Philosophy

Every decision in this lab follows three core principles:

1. **Security First**: If it can be hardened, it should be hardened
2. **Infrastructure as Code**: Everything must be reproducible and version-controlled  
3. **Real-World Ready**: Configurations should translate to enterprise environments

## Lab Architecture - The Hardware Story

Let me walk you through what's actually running this show:

### The Foundation

| Component | Specs | Why This Choice |
|-----------|-------|-----------------|
| **Control Plane** | 3x Lenovo Tiny M720q (Intel i5, 16GB RAM) | Dedicated masters free from Pi limitations |
| **Worker Nodes** | 6x Raspberry Pi CM4 (8GB RAM, NVMe storage) | ARM64 goodness for cost-effective compute |
| **Operating System** | Talos Linux | Immutable OS designed for Kubernetes |
| **Networking** | Cilium CNI + BGP to pfSense | Enterprise-grade networking stack |
| **Storage** | local-path-provisioner + Synology NAS | Fast local + reliable network storage |

### The Software Stack

This isn't your typical "throw some YAML at the wall and see what sticks" setup. Every component has been chosen for a reason:

- **Talos Linux**: Because who wants to SSH into nodes and manually configure things in 2025?
- **Cilium**: eBPF-powered networking that makes traditional firewalls look quaint
- **GitHub Actions Runners**: Self-hosted on ARM64 because why pay for compute you already own?
- **Prometheus + Grafana**: Because if it's not monitored, it doesn't exist

## What Makes This Different

### Security-First Architecture

Every service runs with:
- Non-root security contexts
- Dropped Linux capabilities  
- Network policies for micro-segmentation
- RBAC following principle of least privilege
- Encrypted communication everywhere

### Real Production Workloads

This cluster doesn't just run demos—it handles:
- Home automation backend services
- Development environments for multiple projects
- CI/CD pipelines for both personal and work projects
- Network services (DNS, VPN, monitoring)
- Data processing and analytics workloads

### Enterprise Patterns at Home Scale

You'll find patterns here that scale from 6 nodes to 600:
- GitOps workflows with environment promotion
- Comprehensive monitoring and alerting
- Disaster recovery and backup strategies
- Infrastructure as Code for everything
- Proper secret management and rotation

## Getting Started - The Practical Approach

## Getting Started - The Practical Approach

### Prerequisites

Let's be honest about what you need to make this work:

**Hardware Requirements:**
- At least 3 nodes (masters can run workloads in smaller setups)
- ARM64 or x86_64 architecture (configs support both)
- Minimum 8GB RAM per node (16GB recommended for masters)
- Fast storage (NVMe preferred, SD cards will make you sad)

**Knowledge Prerequisites:**
- Comfort with Linux command line
- Basic Kubernetes concepts (if you don't know what a Pod is, start elsewhere)
- Git workflow familiarity
- Networking fundamentals (VLANs, routing, DNS)

**Tools You'll Need:**
```bash
# Essential tools
curl -sL https://github.com/siderolabs/talos/releases/latest/download/talosctl-linux-amd64 -o talosctl
curl -sL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o kubectl
sudo install -o root -g root -m 0755 {talosctl,kubectl} /usr/local/bin/

# For the ambitious
brew install helm
brew install cilium-cli
```

## Documentation Structure

This repository includes comprehensive documentation for both entry-level and advanced users:

### 📚 **Entry-Level Guides**
- **[Main README](README.md)** - You are here! Overview and quick start
- **[Quick Setup Guide](docs/quick-setup-secrets.md)** - Get running in 30 minutes
- **[GitHub Actions Setup](docs/github-actions-setup.md)** - Self-hosted runners configuration
- **[GitHub Actions Troubleshooting](docs/github-actions-troubleshooting.md)** - CI/CD pipeline issue resolution
- **[Quick Reference](docs/quick-reference.md)** - Common commands and operations
- **[Operations Guide 2025](docs/operations-guide-2025.md)** - Current procedures and maintenance

### 🔬 **Deep-Dive Technical Documentation**
- **[Architecture Deep Dive](docs/architecture/README.md)** - PhD-level system design analysis
- **[Networking Deep Dive](docs/networking-deep-dive.md)** - BGP, Cilium, and load balancing internals
- **[Storage Deep Dive](docs/storage-deep-dive.md)** - Performance, persistence, and pragmatism
- **[Operations Guide](docs/operations-guide.md)** - Day-to-day cluster management

### 🛡️ **Security and Operations**
- **[Security Strategy](docs/security-strategy.md)** - Defense-in-depth approach
- **[Network Segmentation](docs/network-segmentation.md)** - Microsegmentation with Cilium
- **[Talos Credential Security](docs/talos-credential-security.md)** - Securing cluster access
- **[Cilium Troubleshooting](docs/cilium-troubleshooting.md)** - Network monitoring and flow capture fixes
- **[GitHub Actions Troubleshooting](docs/github-actions-troubleshooting.md)** - Runner and workflow issue resolution

### 🔧 **Recent Major Updates (June 2025)**
- **Portable Deployment System**: Cluster-agnostic templates with automatic configuration detection
- **GitOps Pipeline Hardening**: Security-focused validation, deployment error recovery, and modular kustomization
- **Networking Configuration**: BGP peering with pfSense, load balancer IP pools, and proper kustomization
- **Storage Architecture**: Fixed selector immutability issues and separated storage from base kustomization
- **CI/CD Robustness**: Sudo-free tool installation, improved error handling, and comprehensive validation steps

*Each deep-dive document contains both conceptual explanations and practical implementation details.*

### Quick Start Guide

**Step 1: Clone and Explore**
```bash
git clone https://github.com/twimprine/KubernetesLab.git
cd KubernetesLab
find . -name "README.md" | head -5  # Start with the docs
```

**Step 2: Review the Architecture**
- Read `docs/architecture/` for the deep dive
- Check `base/talos/` for cluster configuration templates
- Review `docs/quick-reference.md` for common operations

**Step 3: Adapt to Your Environment**
- Update Talos configs in `base/talos/` for your hardware
- Modify network settings in `networking/`
- Adjust storage configs in `base/storage/`

**Step 4: Deploy and Iterate**
```bash
# Generate your Talos configs
./scripts/generate-talos-config.sh

# Bootstrap the cluster  
./scripts/bootstrap-cluster.sh

# Deploy core services
kubectl apply -k base/
```
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

The cluster uses **local-path-provisioner** for dynamic persistent volume provisioning on the worker nodes only. This provides fast local storage for applications while maintaining proper separation between control-plane and worker node responsibilities.

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
- **Worker Node Only**: DaemonSet runs exclusively on worker nodes (excludes control-plane)
- **Default StorageClass**: `local-path` is set as the default storage class
- **Node Storage Path**: `/var/mnt/local-path-provisioner` on each worker node
- **Volume Binding Mode**: `WaitForFirstConsumer` for optimal pod scheduling
- **Reclaim Policy**: `Delete` to clean up storage when PVCs are removed
- **Security Hardened**: Non-root security contexts with dropped capabilities
- **ARM64 + x86_64**: Supports both Raspberry Pi CM4 and x86_64 architectures

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

### Start Here (Entry Level)
If you're new to Kubernetes or want to understand this lab setup:

1. **[Architecture Overview](docs/architecture/README.md)** - Start with the big picture
2. **[Quick Setup Guide](docs/quick-setup-secrets.md)** - Get hands-on experience
3. **[Operations Guide](docs/operations-guide.md)** - Learn day-to-day management
4. **[GitHub Actions Setup](docs/github-actions-setup.md)** - Implement CI/CD

### Go Deeper (Advanced Technical)
Ready for the PhD-level analysis?

1. **[Networking Deep Dive](docs/networking-deep-dive.md)** - BGP, eBPF, and load balancing internals
2. **[Storage Deep Dive](docs/storage-deep-dive.md)** - Performance analysis and design decisions
3. **[Security Strategy](docs/security-strategy.md)** - Defense-in-depth implementation
4. **[Talos Credential Security](docs/talos-credential-security.md)** - Immutable OS security model

### External Resources
Foundational knowledge for cloud-native infrastructure:

- **[Official Kubernetes Documentation](https://kubernetes.io/docs/)** - The authoritative source
- **[Talos Linux Documentation](https://www.talos.dev/docs/)** - Immutable Kubernetes OS
- **[Cilium Documentation](https://docs.cilium.io/)** - eBPF-powered networking
- **[Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)** - Build from scratch
- **[CNCF Landscape](https://landscape.cncf.io/)** - Discover cloud-native tools

### Learning Path Recommendations

**For Systems Administrators:**
1. Start with the main README and architecture overview
2. Follow the quick setup guide with your own hardware
3. Implement the operations guide procedures
4. Dive into specific areas (networking, storage, security) as needed

**For Developers:**
1. Review the GitHub Actions setup for CI/CD patterns
2. Explore the storage deep dive for persistent application patterns
3. Study the networking guide for service communication
4. Implement your own applications using the established patterns

**For Security Engineers:**
1. Start with the security strategy document
2. Review network segmentation and policies
3. Study the Talos credential security model
4. Implement additional security controls based on your requirements

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