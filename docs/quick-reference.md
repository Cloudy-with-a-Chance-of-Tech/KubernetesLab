# Quick Reference - Talos Kubernetes Lab

## 🚀 Getting Started

### First Time Setup
```bash
# 1. Update IP addresses in scripts to match your environment
nano scripts/deploy-cluster.sh     # Update CONTROLPLANE_IPS and WORKER_IPS
nano scripts/validate-setup.sh     # Update CONTROL_PLANE_NODE IP

# 2. Run complete setup
./scripts/setup-complete.sh
```

### Validation
```bash
# Check everything is working
./scripts/validate-setup.sh
```

## 🔧 Daily Operations

### Cluster Management
```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A
talosctl health

# Restart a problematic node
talosctl reboot --nodes 192.168.1.101

# Update node configuration
talosctl apply-config --nodes 192.168.1.101 --file base/talos/controlplane.yaml
```

### Application Deployment
```bash
# Deploy applications
kubectl apply -k apps/production/

# Check application status
kubectl get pods -n github-actions
kubectl get pods -n monitoring

# View logs
kubectl logs -f deployment/github-runner -n github-actions
```

### Networking & Load Balancing
```bash
# Check BGP status
kubectl get ciliumbgppeeringpolicy
kubectl get ciliumloadbalancerippool

# Test load balancer
kubectl create deployment test --image=nginx
kubectl expose deployment test --port=80 --type=LoadBalancer
kubectl get svc test  # Check for external IP
kubectl delete deployment test && kubectl delete svc test
```

## 🔄 Maintenance

### Complete Rebuild
```bash
# Destroy and rebuild everything (Raspberry Pi safe)
./scripts/destroy-cluster.sh    # Uses --wipe-mode user-disks for Pi nodes
./scripts/setup-complete.sh
```

### Partial Updates
```bash
# Just update CNI
./scripts/install-cilium.sh

# Just update configurations
./scripts/generate-talos-config.sh
./scripts/deploy-cluster.sh

# Just bootstrap (if cluster lost)
./scripts/bootstrap-cluster.sh
```

### Secret Rotation
```bash
# Generate new secrets
rm base/talos/controlplane.yaml base/talos/worker.yaml base/talos/talosconfig
./scripts/generate-talos-config.sh
./scripts/deploy-cluster.sh
```

## 🌐 Access UIs

```bash
# Hubble (Network monitoring)
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Access: http://localhost:12000

# Prometheus (Metrics)
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Access: http://localhost:9090

# Grafana (Dashboards)
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Access: http://localhost:3000
```

## 🔐 Security

### Important Files (Keep Secure)
- `base/talos/talosconfig` - Talos admin access
- `base/talos/controlplane.yaml` - Control plane secrets
- `base/talos/worker.yaml` - Worker secrets
- `~/.kube/config` - Kubernetes admin access

### Backup Strategy
```bash
# Backup critical configurations
tar -czf talos-backup-$(date +%Y%m%d).tar.gz base/talos/talosconfig base/talos/controlplane.yaml base/talos/worker.yaml ~/.kube/config

# Store securely offsite
```

## 🐛 Troubleshooting

### Common Issues

**Nodes not ready:**
```bash
kubectl describe node <node-name>
talosctl logs --nodes <node-ip>
```

**CNI issues:**
```bash
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl logs -n kube-system -l k8s-app=cilium
```

**BGP not working:**
```bash
kubectl get ciliumbgppeeringpolicy -o yaml
kubectl get ciliumloadbalancerippool -o yaml
```

**GitHub runners not connecting:**
```bash
kubectl logs -n github-actions deployment/github-runner
kubectl describe secret github-runner-secret -n github-actions
```

### Recovery Commands

**Lost kubeconfig:**
```bash
talosctl kubeconfig --nodes 192.168.1.100 ~/.kube/config
```

**Cluster API down:**
```bash
talosctl bootstrap --nodes 192.168.1.101
```

**Complete disaster:**
```bash
./scripts/destroy-cluster.sh
./scripts/setup-complete.sh
```

## 📞 Support

- **Repository Issues**: Check [GitHub Issues](https://github.com/twimprine/KubernetesLab/issues)
- **Talos Documentation**: https://www.talos.dev/docs/
- **Cilium Documentation**: https://docs.cilium.io/
- **Validation Script**: `./scripts/validate-setup.sh`

---

*Quick Reference for the Talos Kubernetes Lab*
*Last updated: $(date)*
