# KubernetesLab Operations Guide - June 2025 Update

## Quick Reference - Recent Improvements

### Deployment Architecture Overview

The KubernetesLab now uses a modular deployment approach with the following improvements:

```bash
# Current deployment workflow (automated via GitOps)
kubectl apply -k base/                    # Base infrastructure (namespaces, RBAC)
kubectl apply -k base/storage/            # Storage (separate to avoid selector conflicts)
kubectl apply -k apps/production/         # Production applications
kubectl apply -k networking/              # BGP and load balancer configuration
kubectl apply -f manifests/monitoring/    # Generated monitoring stack
kubectl apply -f manifests/security/      # Generated security configuration
```

### Key Configuration Files

| File | Purpose | Recent Changes |
|------|---------|----------------|
| `base/kustomization.yaml` | Base infrastructure labels | Uses new `labels` syntax, excludes storage |
| `base/storage/kustomization.yaml` | Storage provisioner config | Separate to avoid selector immutability |
| `networking/kustomization.yaml` | BGP and load balancer setup | **NEW**: Created to support kustomize deployment |
| `.github/workflows/gitops-deploy.yml` | CI/CD pipeline | Major reliability improvements |
| `templates/` | Portable deployment templates | Cluster-agnostic configurations |

## Troubleshooting Common Issues

### 1. Pipeline Failures

#### Selector Immutability Error
```bash
# Problem: "spec.selector: field is immutable"
# Solution: Storage deployed separately from base
kubectl get daemonset local-path-provisioner -n local-path-storage -o yaml | grep selector
```

#### Sudo Permission Denied
```bash
# Problem: Tools fail to install with sudo
# Solution: All tools now install to ~/.local/bin
echo $PATH | grep -o "$HOME/.local/bin"
```

#### Missing Kustomization Files
```bash
# Problem: "unable to find kustomization.yaml"
# Solution: Check for proper kustomization.yaml in each directory
find . -name "kustomization.yaml" | head -5
```

### 2. Storage Issues

#### Local Path Provisioner Problems
```bash
# Check storage DaemonSet (worker nodes only)
kubectl get daemonset local-path-provisioner -n local-path-storage
kubectl get pods -n local-path-storage -o wide
kubectl logs -n local-path-storage daemonset/local-path-provisioner

# Verify worker node isolation
kubectl get pods -n local-path-storage -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort

# Verify storage class
kubectl get storageclass
kubectl describe storageclass local-path
```

#### Storage Security Context Issues
```bash
# Verify proper security context
kubectl get daemonset local-path-provisioner -n local-path-storage -o yaml | grep -A 10 securityContext
```

### 3. Networking Configuration

#### BGP Peering Status
```bash
# Check Cilium BGP configuration
kubectl get ciliumbgppeeringpolicy -A
kubectl get ciliumloadbalancerippool -A

# Verify network policies
kubectl get networkpolicy -A
```

#### Load Balancer IP Pool Management
```bash
# Check available IP pools
kubectl get ciliumloadbalancerippool -o yaml

# Test load balancer service
kubectl apply -f networking/test-loadbalancer.yaml
kubectl get svc test-loadbalancer -o wide
```

### 4. GitHub Actions Runners

#### Runner Health Check
```bash
# Check runner pods
kubectl get pods -n github-actions
kubectl describe pod -n github-actions -l app=github-runner

# Check runner logs
kubectl logs -n github-actions -l app=github-runner --tail=100
```

#### Runner Configuration Issues
```bash
# Verify secrets
kubectl get secret github-runner-secret -n github-actions
kubectl describe secret github-runner-secret -n github-actions

# Check RBAC
kubectl get clusterrolebinding | grep github-runner
kubectl get rolebinding -n github-actions
```

## Monitoring and Observability

### Grafana Access
```bash
# Get Grafana admin password
kubectl get secret grafana-admin-secret -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d

# Port forward to access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Access: http://localhost:3000 (admin / <password>)
```

### Prometheus Monitoring
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Access: http://localhost:9090/targets

# View Prometheus configuration
kubectl get configmap prometheus-config -n monitoring -o yaml
```

### Cilium/Hubble Flow Monitoring
```bash
# Enable Hubble UI
cilium hubble ui
# Access: http://localhost:12000

# Check flow visibility
cilium hubble observe --follow
```

## Network Observability and Monitoring Access

### Hubble UI - Network Flow Visualization

The Hubble UI provides real-time network flow visualization for the Cilium-powered cluster:

```bash
# Access Hubble UI via NodePort
# Available at: http://<any-node-ip>:31235
kubectl get svc -n cilium hubble-ui
# Example: http://192.168.1.40:31235

# Check Hubble relay connectivity
kubectl logs -n cilium deployment/hubble-relay --tail=10
# Should show successful connections to all cluster nodes

# Verify Hubble is capturing flows
kubectl get pods -n cilium -l k8s-app=hubble-ui
kubectl get pods -n cilium -l k8s-app=hubble-relay
```

**Recent Fix Applied**: Resolved DNS domain mismatch between cluster configuration (`kub-cluster.local`) and Hubble relay peer-service configuration. Updated Hubble relay ConfigMap to use standard `svc.cluster.local` domain for peer communication.

### Grafana Dashboard Access

```bash
# Access Grafana via LoadBalancer (if available)
kubectl get svc -n monitoring grafana
# Grafana admin credentials stored in secret
kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d
```

### Prometheus Metrics Access

```bash
# Internal cluster access
kubectl get svc -n monitoring prometheus
# Available at: http://prometheus.monitoring.svc.kub-cluster.local:9090

# Port-forward for external access
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

### Security Context Compliance - Talos Requirements

All monitoring and observability components are configured with Talos-compatible security contexts:

```yaml
# Example security context for Talos nodes
securityContext:
  runAsNonRoot: true
  runAsUser: 65534  # or specific service user (e.g., 472 for Grafana)
  runAsGroup: 65534
  fsGroup: 65534
  seccompProfile:
    type: RuntimeDefault
containers:
- securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop: [ALL]
    readOnlyRootFilesystem: true  # where possible
    runAsNonRoot: true
```

## Security Validation

### Security Context Verification
```bash
# Check all deployments have proper security contexts
kubectl get deployments -A -o json | jq -r '.items[] | select(.spec.template.spec.securityContext.runAsNonRoot != true) | .metadata.name'

# Verify no privileged containers
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[]?.securityContext.privileged == true) | .metadata.name'
```

### RBAC Audit
```bash
# List all cluster roles
kubectl get clusterroles | grep -E "github-runner|phoenix-runner"

# Check role bindings
kubectl get clusterrolebindings | grep -E "github-runner|phoenix-runner"
```

### Network Policy Enforcement
```bash
# Verify network policies are applied
kubectl get networkpolicy -A
kubectl describe networkpolicy -n github-actions github-actions-netpol
```

## Maintenance Procedures

### Updating Base Configuration
```bash
# Test changes with dry-run
kubectl apply -k base/ --dry-run=server
kubectl apply -k base/storage/ --dry-run=server

# Apply updates
kubectl apply -k base/
kubectl apply -k base/storage/
```

### Template System Updates
```bash
# Regenerate portable manifests
scripts/template-substitution.sh substitute

# Verify generated manifests
find manifests/ -name "*.yaml" | head -5
kubectl apply --dry-run=client -f manifests/monitoring/
```

### CI/CD Pipeline Maintenance
```bash
# Test workflow locally (if using act)
act -j validate

# Check workflow syntax
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/gitops-deploy.yml'))"
```

## Performance Tuning

### Resource Optimization
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -A

# Review resource requests/limits
kubectl get pods -A -o json | jq -r '.items[] | [.metadata.name, .spec.containers[].resources] | @csv'
```

### Storage Performance
```bash
# Test storage performance
kubectl apply -f base/storage/storage-test.yaml
kubectl logs -f storage-test-pod
```

## Backup and Recovery

### Cluster Configuration Backup
```bash
# Backup critical configurations
kubectl get all,configmap,secret -A -o yaml > cluster-backup-$(date +%Y%m%d).yaml

# Backup Talos configuration
cp base/talos/talosconfig.yaml ~/.talos/config.backup
```

### Application Data Backup
```bash
# Export persistent volume data
kubectl get pv,pvc -A -o yaml > storage-backup-$(date +%Y%m%d).yaml
```

## Recent Architecture Changes Summary

### June 2025 Improvements

1. **Modular Kustomization**: Separated storage from base to resolve selector immutability
2. **Sudo-Free Pipeline**: All tools install to user directories without system privileges
3. **Enhanced Validation**: Comprehensive security checks and deployment verification
4. **Networking Formalization**: Proper kustomization for BGP and load balancer configuration
5. **Error Recovery**: Improved error handling and fallback mechanisms throughout

### Breaking Changes
- Storage must now be deployed separately: `kubectl apply -k base/storage/`
- Networking requires kustomization.yaml (automatically created)
- Tool installation changed from system-wide to user-local paths

### Migration Notes
Existing clusters should continue working without changes. New deployments automatically use the improved architecture.

---

*This operations guide reflects the current state as of June 2025. For the latest updates, see the git commit history and PORTABLE_DEPLOYMENT_SUMMARY.md.*

## Component Status Summary - June 2025

#### ✅ Fully Operational Components

1. **Cilium CNI & Network Policies**
   - All DaemonSet pods running across cluster nodes
   - BGP configuration applied and functional
   - Cluster domain: `kub-cluster.local`

2. **Hubble Network Observability**
   - ✅ Hubble relay successfully connecting to all cluster nodes
   - ✅ Hubble UI accessible via NodePort 31235
   - ✅ DNS domain mismatch resolved (relay peer-service configuration fixed)
   - ✅ Network flows now visible after configuration fixes

3. **Monitoring Stack**
   - ✅ Grafana: Running with Talos-compatible security context (user 472)
   - ✅ Prometheus: Running with Talos-compatible security context (user 65534)
   - ✅ LoadBalancer access configured for Grafana
   - ✅ All pods have proper seccomp profiles and capabilities dropped

4. **Security Compliance**
   - ✅ All pods run as non-root users
   - ✅ Privilege escalation disabled
   - ✅ Capabilities dropped to minimum required
   - ✅ RuntimeDefault seccomp profiles applied
   - ✅ Read-only root filesystems where feasible

#### Recent Fixes Applied

1. **DNS Domain Consistency**
   - Fixed Hubble relay peer-service configuration
   - Updated from custom domain to standard `svc.cluster.local`
   - Result: Hubble UI now displays network flows

2. **Security Context Hardening**
   - All monitoring components comply with Talos security requirements
   - Container and pod-level security contexts properly configured
   - Resource limits and requests applied to prevent resource exhaustion
