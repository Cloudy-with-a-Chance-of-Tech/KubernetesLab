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

## 🔧 Daily Operations - Updated June 2025

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

### Application Deployment (New Modular Approach)
```bash
# Deploy base infrastructure (excludes storage for selector compatibility)
kubectl apply -k base/

# Deploy storage separately (avoids selector immutability issues)
kubectl apply -k base/storage/

# Deploy applications
kubectl apply -k apps/production/

# Deploy networking configuration (requires new kustomization.yaml)
kubectl apply -k networking/

# Check application status
kubectl get pods -n github-actions
kubectl get pods -n monitoring
kubectl get pods -n local-path-storage

# View logs
kubectl logs -f deployment/github-runner -n github-actions
kubectl logs -f deployment/local-path-provisioner -n local-path-storage
```

### Portable Template System
```bash
# Generate cluster-specific manifests
scripts/detect-cluster-info.sh info
scripts/template-substitution.sh substitute

# Deploy generated manifests
kubectl apply -f manifests/monitoring/
kubectl apply -f manifests/security/

# Verify template variables
grep -r "{{.*}}" templates/
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

### Recent Issue Fixes (June 2025)

**Deployment selector immutability error:**
```bash
# Check if deployment exists with different selector
kubectl get deployment local-path-provisioner -n local-path-storage -o yaml | grep -A 5 selector

# Fix: Deploy storage separately
kubectl apply -k base/storage/
```

**GitOps pipeline sudo errors:**
```bash
# All tools now install to ~/.local/bin
echo $PATH | grep "$HOME/.local/bin"
which kubectl trivy kube-score
```

**Missing kustomization.yaml error:**
```bash
# Check for kustomization files
find . -name "kustomization.yaml"
# Create if missing (example for networking):
cat > networking/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cilium-bgp-config.yaml
EOF
```

**Bash syntax errors in workflow:**
```bash
# Test shell scripts locally
bash -n .github/workflows/gitops-deploy.yml  # Won't work directly, extract scripts first
# Check for missing 'fi' statements in workflow YAML
```

**Security context issues:**
```bash
# Check pod-level vs container-level security context
kubectl get pod <pod-name> -o yaml | grep -A 10 securityContext
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
