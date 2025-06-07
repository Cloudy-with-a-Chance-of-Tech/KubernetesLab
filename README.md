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
| **Storage** | Persistent Volumes | NFS + Local Storage Classes |
| **Networking** | CNI & Load Balancing | Cilium + BGP to pfSense |
| **Monitoring** | Observability Stack | Prometheus + Grafana + AlertManager |

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
  - Environment promotion through Git workflows
  - Continuous deployment pipelines

## Getting Started

### Prerequisites

Before diving into these configurations, make sure you have:

- A running Talos Kubernetes cluster (obviously!)
- `kubectl` configured and pointing to your cluster
- `talosctl` configured for cluster management
- Basic understanding of Kubernetes concepts (Pods, Services, Deployments, etc.)
- Optionally: Helm 3.x for chart-based deployments

### Quick Setup

1. **Clone this repository**
   ```bash
   git clone https://github.com/twimprine/KubernetesLab.git
   cd KubernetesLab
   ```

2. **Verify cluster connectivity**
   ```bash
   kubectl cluster-info
   kubectl get nodes
   talosctl version
   ```

3. **Apply base configurations**
   ```bash
   # Start with namespaces and basic RBAC
   kubectl apply -f base/namespaces/
   kubectl apply -f base/rbac/
   ```

4. **Deploy core services**
   ```bash
   # Monitoring stack
   kubectl apply -f monitoring/
   
   # Ingress controller
   kubectl apply -f ingress/
   ```

## Directory Structure

```
├── base/                   # Core cluster configurations
│   ├── namespaces/        # Namespace definitions
│   ├── rbac/              # Role-based access control
│   ├── storage/           # Storage classes and PVs
│   └── talos/             # Talos machine configurations
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

## Quick Setup

### Prerequisites
- Talos Kubernetes cluster with Cilium CNI
- GitHub repository with Actions enabled
- kubectl configured for your cluster

### Initial Setup
1. **Configure GitHub Secrets** (Repository → Settings → Secrets and variables → Actions):
   - `RUNNER_TOKEN` - GitHub Personal Access Token (repo, admin:org, workflow scopes)
   - `ORG_NAME` - Your GitHub organization or username  
   - `GRAFANA_ADMIN_PASSWORD` - Strong password for Grafana admin

2. **Bootstrap Base Infrastructure**:
   ```bash
   kubectl apply -f base/namespaces/
   kubectl apply -f base/rbac/
   ```

3. **Enable GitOps** - Push to main branch triggers automated deployment

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

## Troubleshooting

Most common issues and their solutions:

| Issue | Likely Cause | Solution |
|-------|--------------|----------|
| Pods stuck in Pending | Resource constraints | Check `kubectl describe pod` and node resources |
| Service unreachable | BGP route not advertised | Check Cilium BGP policies and pfSense routing |
| LoadBalancer stuck pending | BGP peering issue | Verify `kubectl get ciliumnodes` and pfSense BGP config |
| Node not ready | Talos system issue | Check `talosctl health` and `talosctl logs` |
| Storage issues | PV/PVC mismatch | Verify storage class and access modes |

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