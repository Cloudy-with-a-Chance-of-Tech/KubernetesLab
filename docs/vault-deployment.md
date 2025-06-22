# HashiCorp Vault Deployment Guide

## 🔐 Overview

This guide covers the production-ready deployment of HashiCorp Vault in the KubernetesLab cluster. The deployment follows Talos Linux security standards with necessary security exceptions for Vault operation, integrating with existing monitoring and CI/CD infrastructure.

**Security Approach**: Vault operates under a "secure by design, relax where necessary" philosophy, with documented security exceptions that enable proper Vault functionality while maintaining defense-in-depth security.

## 🏗️ Architecture

### Deployment Components

| Component | Purpose | Security Features |
|-----------|---------|-------------------|
| **Vault Namespace** | Isolated environment with baseline pod security | Default deny network policies, documented exceptions |
| **Vault Pod** | HashiCorp Vault server | Non-root execution, necessary capabilities (IPC_LOCK, SETFCAP) |
| **Persistent Storage** | Vault data persistence | 10GB local-path storage with proper permissions |
| **LoadBalancer Service** | External access | Static IP `192.168.100.102`, session affinity |
| **Network Policies** | Microsegmentation | Cilium policies for monitoring, CI/CD, and external access |

## 🔒 Security Configuration

### Security Model Summary

HashiCorp Vault deployment follows a **defense-in-depth** security model with carefully controlled exceptions:

**Trust Model**: Vault is trusted to secure itself - minimal security exceptions are granted for operation
**Network Boundaries**: Multi-layered network controls restrict access to authorized sources only
**Access Control**: Role-based access with principle of least privilege throughout

### Network Security

**Network Policies**: Comprehensive Cilium network policies with principle of least privilege:

- **Default Deny**: All traffic denied by default in vault namespace
- **External Access**: Only through LoadBalancer from local network (192.168.1.0/24)
- **Internal Access**: Limited to specific authorized namespaces:
  - `kube-system`: Kubernetes API access
  - `monitoring`: Prometheus metrics collection
  - `github-actions`: CI/CD operations
  - `external-secrets`: External secrets operator (when deployed)
- **DNS Access**: Restricted to cluster DNS for service discovery
- **Vault Clustering**: Inter-pod communication for HA (when scaled)

**Security Boundaries**:
- No direct internet access - all external traffic via pfSense/LoadBalancer
- Pod-to-pod communication restricted to vault namespace
- External secrets integration requires explicit authorization
- Monitoring access limited to metrics endpoints only

## 🚀 Deployment

### Automatic Deployment (CI/CD)

Vault is automatically deployed via the GitOps pipeline when changes are pushed to the `security/` directory:

```bash
# Trigger deployment
git add security/vault-*.yaml
git commit -m "🔐 Deploy HashiCorp Vault"
git push
```

The CI/CD pipeline will:
1. Deploy all Vault components
2. Wait for deployment readiness
3. Initialize Vault (if not already initialized)
4. Store initialization keys in Kubernetes secrets

### Manual Deployment

```bash
# Deploy Vault components
kubectl apply -f security/vault-namespace.yaml
kubectl apply -f security/vault-rbac.yaml
kubectl apply -f security/vault-config.yaml
kubectl apply -f security/vault-storage.yaml
kubectl apply -f security/vault-deployment.yaml
kubectl apply -f security/vault-service.yaml
kubectl apply -f security/vault-network-policy.yaml

# Wait for deployment
kubectl wait --for=condition=available deployment/vault -n vault --timeout=300s

# Initialize Vault
scripts/initialize-vault.sh
```

## 🔧 Configuration

### External Access

| Service | Access URL | Purpose |
|---------|------------|---------|
| **Vault API** | `http://192.168.100.102:8200` | API access and CLI |
| **Vault UI** | `http://192.168.100.102:8200/ui` | Web interface |

### Authentication

**Initial Setup**:
- Single unseal key stored in `vault-unseal-keys` secret
- Root token stored in `vault-root-token` secret
- Kubernetes auth backend enabled and configured

**Access Tokens**:
```bash
# Get root token (use sparingly)
kubectl get secret vault-root-token -n vault -o jsonpath='{.data.root-token}' | base64 -d

# Access Vault CLI
export VAULT_ADDR="http://192.168.100.102:8200"
export VAULT_TOKEN="$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.root-token}' | base64 -d)"
vault status
```

### Storage Backend

**Configuration**: File storage backend
- **Path**: `/vault/data` (persistent volume)
- **Storage Class**: `local-path`
- **Capacity**: 10GB
- **Access Mode**: ReadWriteOnce

## 🛠️ Management Operations

### Using Management Scripts

```bash
# Check Vault status
scripts/manage-vault.sh status

# Unseal Vault (if sealed)
scripts/manage-vault.sh unseal

# View logs
scripts/manage-vault.sh logs

# Access CLI
scripts/manage-vault.sh cli

# Create backup
scripts/manage-vault.sh backup
```

### Common Operations

**Check Vault Health**:
```bash
curl -s http://192.168.100.102:8200/v1/sys/health | jq
```

**Unseal Vault**:
```bash
UNSEAL_KEY=$(kubectl get secret vault-unseal-keys -n vault -o jsonpath='{.data.unseal-key}' | base64 -d)
curl -X PUT http://192.168.100.102:8200/v1/sys/unseal -d "{\"key\":\"$UNSEAL_KEY\"}"
```

**Create KV Secret**:
```bash
vault kv put secret/myapp username=admin password=secret123
```

**Read KV Secret**:
```bash
vault kv get secret/myapp
```

## 🔍 Monitoring Integration

### Prometheus Metrics

Vault exposes metrics at `/v1/sys/metrics` endpoint. The monitoring stack can be configured to scrape these metrics:

```yaml
# Add to Prometheus configuration
- job_name: 'vault'
  static_configs:
    - targets: ['vault.vault.svc.cluster.local:8200']
  metrics_path: '/v1/sys/metrics'
  params:
    format: ['prometheus']
```

### Grafana Dashboard

Key metrics to monitor:
- Vault seal status
- Authentication requests
- Secret operations
- Storage backend performance
- Memory and CPU usage

## 🛡️ Security Best Practices

### Initial Security Setup

1. **Rotate Root Token** (after initial setup):
```bash
vault auth -method=userpass username=admin
vault token-create -policy=admin
vault auth -method=token
vault write auth/token/revoke-self
```

2. **Enable Audit Logging**:
```bash
vault audit enable file file_path=/vault/logs/audit.log
```

3. **Create Policies**:
```bash
# Admin policy
vault policy write admin-policy - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

# Read-only policy
vault policy write readonly-policy - <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
EOF
```

### Network Security

Network policies automatically implemented:
- ✅ Default deny all traffic
- ✅ Allow external access to Vault API
- ✅ Allow monitoring stack access
- ✅ Allow CI/CD pipeline access
- ✅ Allow Kubernetes API access for auth
- ✅ Allow DNS resolution

### Backup Strategy

**Automated Backups**:
```bash
# Create backup using management script
scripts/manage-vault.sh backup

# Manual backup of critical secrets
kubectl get secret vault-root-token -n vault -o yaml > vault-root-token-backup.yaml
kubectl get secret vault-unseal-keys -n vault -o yaml > vault-unseal-keys-backup.yaml
```

## 🚨 Troubleshooting

### Common Issues

**Vault Pod Not Starting**:
```bash
# Check pod logs
kubectl logs -l app.kubernetes.io/name=vault -n vault

# Check storage permissions
kubectl describe pvc vault-data -n vault

# Check security context
kubectl describe pod -l app.kubernetes.io/name=vault -n vault
```

**Vault Sealed After Restart**:
```bash
# Check if unseal key exists
kubectl get secret vault-unseal-keys -n vault

# Unseal manually
scripts/manage-vault.sh unseal
```

**LoadBalancer IP Not Assigned**:
```bash
# Check service status
kubectl get svc vault-external -n vault

# Check BGP announcements
kubectl get ciliumnodes

# Verify IP pool configuration
kubectl get bgppeerings.v2alpha1.cilium.io -A
```

**Network Policy Issues**:
```bash
# Check Cilium network policies
kubectl get cnp -n vault

# Debug network connectivity
kubectl exec -it -n vault deployment/vault -- wget -qO- http://kubernetes.default.svc.cluster.local/api
```

### Recovery Procedures

**Complete Vault Recovery**:
1. Stop Vault deployment: `kubectl scale deployment vault -n vault --replicas=0`
2. Restore backup: Use backup restore script
3. Start Vault: `kubectl scale deployment vault -n vault --replicas=1`
4. Initialize/unseal: `scripts/initialize-vault.sh`

**Lost Unseal Key Recovery**:
If unseal keys are lost and Vault is sealed, data recovery requires:
1. Access to the underlying storage
2. Vault recovery keys (if configured)
3. Vault operator intervention with unsealing process

## 📚 Next Steps

### Integration Opportunities

1. **External Secrets Integration**: Replace manual secret management
2. **Certificate Management**: Use Vault PKI engine for TLS certificates  
3. **Database Secrets**: Dynamic database credentials
4. **Application Authentication**: Service-to-service auth via Vault

### Security Enhancements

1. **Auto-unseal**: Configure cloud KMS for automatic unsealing
2. **HA Deployment**: Scale to multiple replicas with Consul backend
3. **Transit Encryption**: Enable Vault transit engine for encryption-as-a-service
4. **Audit Integration**: Forward audit logs to SIEM system

---

## 🔗 Access Information

| Resource | URL/Command |
|----------|-------------|
| **Vault UI** | `http://192.168.100.102:8200/ui` |
| **Vault API** | `http://192.168.100.102:8200` |
| **Management Script** | `scripts/manage-vault.sh` |
| **Initialization Script** | `scripts/initialize-vault.sh` |
| **Root Token** | `kubectl get secret vault-root-token -n vault -o jsonpath='{.data.root-token}' \| base64 -d` |

**🚨 Security Reminder**: The root token provides unlimited access to Vault. Use it sparingly and consider creating more restrictive tokens for regular operations.

## 🛡️ Security Exceptions and Justifications

Vault requires specific security exceptions to operate properly. These are carefully considered and documented:

### Pod Security Standards: Baseline

**Exception**: Vault namespace uses `baseline` instead of `restricted` pod security standards.

**Justification**: 
- Vault requires capabilities (IPC_LOCK, SETFCAP) that are not permitted under restricted standards
- Vault needs to write temporary files which requires non-readonly root filesystem
- These capabilities are essential for Vault's security model and proper operation

**Mitigation**: Comprehensive network policies and RBAC provide additional security layers.

### Container Security Context Exceptions

**Read-Only Root Filesystem: Disabled**
```yaml
securityContext:
  readOnlyRootFilesystem: false  # Exception for Vault operation
```
- **Reason**: Vault needs to write temporary files and manage internal state
- **Mitigation**: Restricted volume mounts and comprehensive monitoring

**Additional Capabilities**
```yaml
capabilities:
  add:
    - IPC_LOCK           # Memory locking for sensitive data
    - SETFCAP            # Capability management for security
    - NET_BIND_SERVICE   # Binding to privileged ports if needed
```
- **IPC_LOCK**: Required for memory locking even when mlock is disabled in config
- **SETFCAP**: Required for Vault's internal capability and privilege management
- **NET_BIND_SERVICE**: Allows binding to privileged ports for enhanced flexibility
- **Mitigation**: Minimal capability set, all other capabilities dropped

**Init Container Capabilities**
```yaml
capabilities:
  add:
    - CHOWN           # Change ownership of data directory
    - FOWNER          # Set file ownership permissions
    - DAC_OVERRIDE    # Modify files owned by different users
```
- **Purpose**: Ensures proper ownership and permissions on Vault data directory
- **Scope**: Limited to initialization phase only
- **Mitigation**: Runs only during pod startup, separate from main container

**Additional Volume Mounts**
```yaml
volumeMounts:
  - name: dev-shm
    mountPath: /dev/shm  # Shared memory for performance and secure operations
```
- **Purpose**: Provides shared memory access for cryptographic operations
- **Justification**: Improves performance and security of memory-intensive operations
- **Mitigation**: Memory-backed volume with size limits

### Network Access Patterns

**External Access**: Vault is designed to be accessed from outside the cluster
- **Justification**: Vault serves as the secrets management system for external applications
- **Mitigation**: Strong authentication, comprehensive audit logging, network monitoring

**Kubernetes API Access**: Required for Kubernetes auth backend
- **Justification**: Enables secure service account based authentication
- **Mitigation**: Minimal RBAC permissions, specific API endpoint access only

### Security Compensating Controls

To compensate for necessary security exceptions:

1. **Comprehensive Network Policies**: Default deny with explicit allows
2. **RBAC**: Principle of least privilege for Kubernetes API access  
3. **Monitoring**: Full observability via Prometheus and Grafana
4. **Audit Logging**: All Vault access logged and monitored
5. **Secret Management**: All sensitive data stored in Kubernetes secrets
6. **Regular Updates**: Automated deployment pipeline for security patches
