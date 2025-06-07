# Security and Secret Management Strategy

This document outlines the security approach for the Kubernetes Lab repository and the management of sensitive data.

## Security Principles

### 1. No Secrets in Git
- **NEVER** commit actual secrets, tokens, or passwords to the repository
- All secret files in the `security/` directory are **TEMPLATES ONLY**
- Templates are marked with `config.kubernetes.io/local-config: "true"` annotation

### 2. Secret Management Layers

#### Current Approach (GitHub Actions)
During CI/CD deployment, secrets are injected from GitHub Actions secrets:

**Required GitHub Actions Secrets:**
- `RUNNER_TOKEN` - GitHub Personal Access Token for self-hosted runners
- `ORG_NAME` - Your GitHub organization name
- `GRAFANA_ADMIN_PASSWORD` - Grafana admin password

**How to set up GitHub Actions secrets:**
1. Go to your repository → Settings → Secrets and variables → Actions
2. Add each secret with the exact names listed above
3. The CI/CD pipeline will create actual Kubernetes secrets from these values

#### Future Approach (Vault + External Secrets Operator)
For production environments, implement HashiCorp Vault with External Secrets Operator:

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace

# Configure Vault integration
kubectl apply -f security/external-secrets-vault.yaml
```

### 3. Secret Template Structure

All secret templates follow this pattern:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: example-secret
  annotations:
    # This prevents accidental application of templates
    config.kubernetes.io/local-config: "true"
type: Opaque
stringData:
  secret-key: "VAULT_SECRET_OR_PIPELINE_INJECTED"
```

### 4. Deployment Security

#### CI/CD Pipeline Security
- Secrets are injected at deployment time, never stored in the repository
- Use `kubectl apply --selector='!config.kubernetes.io/local-config'` to exclude templates
- Validate all manifests before applying

#### Manual Deployment Security
If deploying manually (not recommended for production):

```bash
# Create secrets manually (NOT from templates)
kubectl create secret generic github-runner-secret \
  --from-literal=github-token="your-actual-token" \
  --from-literal=runner-name="k8s-runner" \
  --from-literal=github-org="your-org" \
  --namespace=github-actions

# Deploy applications excluding templates
kubectl apply -k apps/production/ --selector='!config.kubernetes.io/local-config'
```

## Network Security

### 1. Network Policies
- GitHub Actions runners have restricted egress (HTTPS, DNS, Kubernetes API only)
- Monitoring namespace isolation
- Pod-to-pod communication controls

### 2. Cilium BGP Security
- BGP peering with pfSense using private ASNs
- Load balancer IP pools restricted to homelab network range
- Network segmentation between cluster and external networks

### 3. Container Security
- Non-root containers with dropped capabilities
- Read-only root filesystems where possible
- Seccomp profiles enabled
- Security contexts aligned with Talos Linux security model

## Access Control

### 1. RBAC (Role-Based Access Control)
- Minimal required permissions for each service account
- Namespace-scoped permissions where possible
- Cluster-wide permissions only when necessary (like GitOps runners)

### 2. Service Account Security
- Dedicated service accounts for each application
- Token auto-mounting disabled where not needed
- Regular rotation of service account tokens

## Monitoring and Auditing

### 1. Security Monitoring
- Prometheus alerts for security events
- Failed authentication monitoring
- Network policy violations
- Resource quota breaches

### 2. Audit Logging
- Kubernetes API audit logs
- Container runtime security events
- Network traffic monitoring via Cilium

## Vault Integration (Future)

### 1. Vault Setup
```bash
# Install Vault (example for development)
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault -n vault-system --create-namespace

# Configure Kubernetes auth
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"
```

### 2. Secret Paths in Vault
```
secret/
├── github/
│   └── runner/
│       ├── token
│       ├── name
│       └── organization
├── monitoring/
│   └── grafana/
│       └── admin-password
└── networking/
    └── bgp/
        └── peer-secrets
```

### 3. External Secrets Operator
- Automatic secret synchronization from Vault
- Regular secret rotation
- Centralized secret management
- Audit trail for secret access

## Security Checklist

### Repository Security
- [ ] No hardcoded secrets in any files
- [ ] All secret templates marked with local-config annotation
- [ ] .gitignore includes sensitive file patterns
- [ ] Branch protection rules enabled
- [ ] Required status checks for security scans

### Deployment Security
- [ ] GitHub Actions secrets configured
- [ ] CI/CD pipeline validates manifests
- [ ] Security scanning in pipeline (trivy, gitleaks)
- [ ] Secrets injected at deployment time only

### Runtime Security
- [ ] Network policies applied
- [ ] RBAC permissions minimal
- [ ] Container security contexts configured
- [ ] Monitoring and alerting active

### Future Enhancements
- [ ] Vault cluster deployed
- [ ] External Secrets Operator configured
- [ ] Certificate management automated
- [ ] Policy-as-Code implemented (OPA Gatekeeper)

## Incident Response

### Secret Compromise
1. **Immediate**: Revoke compromised secrets in source system (GitHub, etc.)
2. **Update**: Generate new secrets and update in secret management system
3. **Rotate**: Restart affected applications to pick up new secrets
4. **Audit**: Review access logs to understand scope of compromise

### Security Breach
1. **Isolate**: Apply network policies to contain affected workloads
2. **Investigate**: Review audit logs and security monitoring
3. **Remediate**: Apply security patches or configuration changes
4. **Document**: Update security procedures based on lessons learned

## Contact and Support

For security issues or questions:
- Create a private issue in the repository
- Follow responsible disclosure practices
- Document all security-related decisions in this file
