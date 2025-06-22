# Security Strategy: Building a Secure Home Lab

Let's talk about security in your home lab. This isn't enterprise-grade paranoia—it's practical security that protects your learning environment while teaching you real-world security practices you'll use professionally.

I've learned that security in home labs needs to balance two things: being secure enough to matter, but not so complex it becomes a barrier to learning. Here's how I approach it.

## The Core Security Principles

### 1. Never Commit Secrets to Git (Ever)
This is non-negotiable. I've seen too many "oops" moments where someone commits a token to a public repo. Here's the rule:

- **NEVER** commit actual secrets, tokens, or passwords to the repository
- All secret files in the `security/` directory are **TEMPLATES ONLY**
- Templates are marked with `config.kubernetes.io/local-config: "true"` annotation

**Why this matters:** Once a secret hits Git history, it's there forever. Even if you delete it in the next commit, it's still in the history. GitHub will even scan for accidentally committed secrets and alert you (or the world).

### 2. Layered Secret Management

I use a layered approach that grows with your needs—start simple, evolve to more sophisticated solutions as you learn.

#### Current Approach: GitHub Actions Secrets (Start Here)
For most home labs, GitHub Actions secrets are perfect. They're simple, secure, and teach you the fundamentals:

**Required GitHub Actions Secrets:**
- `RUNNER_TOKEN` - GitHub Personal Access Token for self-hosted runners
- `ORG_NAME` - Your GitHub organization name  
- `GRAFANA_ADMIN_PASSWORD` - Grafana admin password

**Setting up GitHub Actions secrets (step by step):**
1. Go to your repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each secret with the exact names listed above
4. The CI/CD pipeline will create actual Kubernetes secrets from these values

**Pro tip:** Use a password manager to generate and store these secrets. I use Bitwarden, but any reputable password manager works.

#### Production Approach: Vault + External Secrets Operator (Now Deployed)
HashiCorp's Vault with External Secrets Operator is now production-ready in this cluster:

```bash
# Vault is deployed and accessible
# External URL: http://192.168.100.102:8200
# Check status: scripts/manage-vault.sh status

# Install External Secrets Operator (when ready)
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace

# Configure Vault integration
kubectl apply -f security/external-secrets-vault.yaml
```

This is enterprise-grade secret management that you'll encounter in production environments.

### 3. Secret Template Structure (The Safe Pattern)

Every secret template in this lab follows a consistent, safe pattern. Here's what it looks like:

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

**The key insight:** The `config.kubernetes.io/local-config: "true"` annotation tells tools like Kustomize and kubectl to skip this file. It's a safety net that prevents you from accidentally deploying placeholder values.

### 4. Deployment Security Patterns

#### GitOps CI/CD Pipeline (Recommended)
This is how secrets flow in the automated pipeline:

1. **Source**: Secrets stored in GitHub Actions secrets
2. **Injection**: CI/CD pipeline creates real Kubernetes secrets
3. **Exclusion**: Templates are filtered out using `--selector='!config.kubernetes.io/local-config'`
4. **Validation**: All manifests are validated before applying

Here's the magic command that makes this work:
```bash
# This applies everything EXCEPT templates
kubectl apply -k apps/production/ --selector='!config.kubernetes.io/local-config'
```

#### Manual Deployment (Learning & Debugging)
Sometimes you need to deploy manually for testing or debugging. Here's the safe way:

```bash
# 1. Create secrets manually (NOT from templates)
kubectl create secret generic github-runner-secret \
  --from-literal=github-token="your-actual-token" \
  --from-literal=runner-name="k8s-runner" \
  --from-literal=github-org="your-org" \
  --namespace=github-actions

# 2. Deploy applications excluding templates
kubectl apply -k apps/production/ --selector='!config.kubernetes.io/local-config'
```

**Warning:** Manual deployment is great for learning, but don't rely on it for your main workflow. GitOps is more reliable and auditable.

## Network Security: Defense in Depth

Network security in Kubernetes isn't just about firewalls—it's about creating layers of protection that work together.

### 1. Network Policies: Your First Line of Defense
Think of network policies as firewalls for your pods. They control which pods can talk to which other pods.

**GitHub Actions Runner Isolation:**
```yaml
# This policy allows GitHub runners to talk to the internet and K8s API,
# but blocks lateral movement to other cluster resources
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: github-runner-policy
  namespace: github-actions
spec:
  podSelector:
    matchLabels:
      app: github-runner
  policyTypes:
  - Egress
  egress:
  - to: []  # Allow all egress (HTTPS, DNS, K8s API)
    ports:
    - protocol: TCP
      port: 443
    - protocol: UDP
      port: 53
```

**Monitoring Namespace Isolation:**
```yaml
# Monitoring pods can scrape metrics but can't access application data
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: monitoring-policy
  namespace: monitoring
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 9090  # Prometheus metrics
```

### 2. Cilium BGP Security: Controlled External Access
Your cluster talks to the outside world through Cilium's BGP integration with pfSense. Here's how we secure it:

**BGP Peering Security:**
- Private ASNs only (64512 for Kubernetes, 64511 for pfSense)
- Load balancer IP pools restricted to your homelab network range
- Network segmentation between cluster and external networks

**Load Balancer IP Pool Configuration:**
```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: homelab-pool
spec:
  cidrs:
  - cidr: "192.168.100.0/24"  # Your homelab range only
```

### 3. Container Security: Secure by Default
Every container in this lab runs with security-focused defaults:

**Security Context Standards:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65534  # nobody user
  runAsGroup: 65534
  fsGroup: 65534
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
```

**Why this matters:**
- `runAsNonRoot`: Prevents root privilege escalation
- `readOnlyRootFilesystem`: Limits attack surface
- `drop: ALL`: Removes all Linux capabilities unless explicitly needed
- `seccompProfile`: Restricts system calls

## Access Control: Principle of Least Privilege

Good RBAC (Role-Based Access Control) is about giving just enough permissions to get the job done—nothing more.

### 1. RBAC Philosophy
- **Minimal required permissions** for each service account
- **Namespace-scoped permissions** wherever possible
- **Cluster-wide permissions** only when absolutely necessary (like GitOps runners)

**Example: GitHub Runner RBAC**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-runner
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
# Only the minimum permissions needed for GitOps operations
```

### 2. Service Account Security Best Practices

**Dedicated Service Accounts:**
Every application gets its own service account. No sharing, no shortcuts.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-runner
  namespace: github-actions
automountServiceAccountToken: false  # Disable unless needed
```

**Token Management:**
- Auto-mounting disabled where not needed (`automountServiceAccountToken: false`)
- Manual token mounting only when required
- Regular rotation of service account tokens (automated via cert-manager)

**Why service account isolation matters:**
If one application gets compromised, the blast radius is limited to that application's permissions. No lateral movement through overprivileged shared accounts.

## Monitoring and Auditing: Know What's Happening

You can't secure what you can't see. This lab includes monitoring that teaches you to spot security issues before they become problems.

### 1. Security Monitoring with Prometheus

**Key Security Metrics to Watch:**
```yaml
# Prometheus alerting rules for security events
groups:
- name: security.rules
  rules:
  - alert: FailedAuthentication
    expr: increase(apiserver_audit_failed_authentication_total[5m]) > 5
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High failed authentication rate detected"
      
  - alert: NetworkPolicyViolation
    expr: increase(cilium_policy_denied_total[5m]) > 10
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Network policy violations detected"
```

**Resource Quota Monitoring:**
```yaml
- alert: ResourceQuotaBreach  
  expr: (kube_resourcequota_used / kube_resourcequota_hard) > 0.9
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Resource quota nearly exceeded in {{ $labels.namespace }}"
```

### 2. Audit Logging Strategy

**Kubernetes API Audit Logs:**
Talos Linux provides built-in audit logging. Key events to monitor:
- Failed API calls
- Privileged operations
- Secret access patterns
- Unusual resource access

**Container Runtime Security:**
- Image vulnerability scanning with Trivy
- Runtime behavior monitoring via Cilium
- Network traffic analysis

**Grafana Dashboards for Security:**
The included Grafana setup has dashboards for:
- Authentication failures over time
- Network policy violations
- Resource usage patterns
- Container security events

**Pro tip:** Set up alert channels (Discord, Slack, email) for critical security events. You want to know immediately if something's wrong.

## Advanced: Vault Integration (Graduate-Level Security)

Once you've mastered the basics, HashiCorp Vault provides enterprise-grade secret management. This is what you'll encounter in production environments.

### 1. Vault Architecture in Home Labs

**Vault Deployment Options:**
```bash
# Development mode (learning only - NOT for production)
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --set server.dev.enabled=true \
  --set server.logLevel=debug \
  -n vault-system --create-namespace

# Production mode (HA with persistent storage)
helm install vault hashicorp/vault \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3 \
  --set server.persistentVolumeClaimRetentionPolicy.whenDeleted=Retain \
  -n vault-system --create-namespace
```

**Kubernetes Authentication Setup:**
```bash
# Enable Kubernetes auth method
vault auth enable kubernetes

# Configure the auth method
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443" \
  kubernetes_ca_cert="$(kubectl get secret \
    -o jsonpath="{.items[?(@.type=="kubernetes.io/service-account-token")].data.ca\.crt}" \
    | base64 --decode)"
```

### 2. Vault Secret Organization

**Logical Secret Paths:**
```
secret/
├── github/
│   └── runner/
│       ├── token        # GitHub PAT
│       ├── name         # Runner name
│       └── organization # GitHub org/user
├── monitoring/
│   └── grafana/
│       ├── admin-password    # Grafana admin password
│       └── database-password # Grafana DB password
├── networking/
│   └── bgp/
│       └── peer-secrets     # BGP authentication
└── certificates/
    ├── ca-cert              # Internal CA certificate
    └── tls-keys            # TLS private keys
```

### 3. External Secrets Operator Integration

**SecretStore Configuration:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: github-actions
spec:
  provider:
    vault:
      server: "https://vault.vault-system.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "github-runner"
          serviceAccountRef:
            name: "github-runner"
```

**ExternalSecret Resource:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: github-runner-secret
  namespace: github-actions
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: github-runner-secret
    creationPolicy: Owner
  data:
  - secretKey: github-token
    remoteRef:
      key: github/runner
      property: token
  - secretKey: runner-name
    remoteRef:
      key: github/runner
      property: name
```

**Benefits of this approach:**
- **Centralized secret management** across multiple clusters
- **Automatic secret rotation** with configurable intervals
- **Audit trail** for all secret access
- **Policy-based access control** via Vault policies
- **Secret versioning and rollback** capabilities

## Security Checklist: Your Go-To Reference

Use this checklist to validate your security posture. I recommend going through this monthly.

### Repository Security
- [ ] **No hardcoded secrets** in any files (run `git log --all -S "password" -S "token" -S "key"` to double-check)
- [ ] **All secret templates** marked with `config.kubernetes.io/local-config: "true"` annotation
- [ ] **.gitignore includes** sensitive file patterns (`*.key`, `*secret*`, `.env`, etc.)
- [ ] **Branch protection rules** enabled (require PR reviews, status checks)
- [ ] **Dependency scanning** enabled (GitHub Dependabot or equivalent)
- [ ] **Secret scanning** enabled in repository settings

### GitHub Actions Security
- [ ] **GitHub Actions secrets** configured with proper values
- [ ] **Workflow permissions** set to minimum required (`contents: read`, etc.)
- [ ] **No secrets in workflow logs** (use `::add-mask::` for dynamic secrets)
- [ ] **Artifact retention** set appropriately (7-30 days max)
- [ ] **Security scanning** in CI/CD pipeline (Trivy, GitLeaks, etc.)

### Deployment Security
- [ ] **CI/CD pipeline validates** all manifests before applying
- [ ] **Secret injection** happens at deployment time only
- [ ] **Template exclusion** working (`--selector='!config.kubernetes.io/local-config'`)
- [ ] **Resource limits** set on all workloads
- [ ] **Security contexts** configured on all containers
- [ ] **Network policies** applied to all namespaces

### Runtime Security
- [ ] **RBAC permissions** follow principle of least privilege
- [ ] **Service accounts** are namespace-specific and minimal
- [ ] **Container images** scanned for vulnerabilities
- [ ] **Pod security standards** enforced (restricted profile)
- [ ] **Network segmentation** working (test with `kubectl exec`)
- [ ] **Monitoring and alerting** active and tested

### Advanced Security (Optional)
- [ ] **Vault cluster** deployed and configured
- [ ] **External Secrets Operator** managing secret lifecycle
- [ ] **Certificate management** automated (cert-manager)
- [ ] **Policy-as-Code** implemented (OPA Gatekeeper)
- [ ] **Service mesh** deployed for mTLS (Istio/Linkerd)
- [ ] **Runtime security** monitoring (Falco)

## Incident Response: When Things Go Wrong

Security incidents happen—even in home labs. Having a plan makes the difference between a learning experience and a disaster.

### Secret Compromise Response

**Immediate Actions (First 30 minutes):**
1. **Revoke the compromised secret** in the source system:
   - GitHub: Revoke PAT immediately at https://github.com/settings/tokens
   - Other services: Follow their revocation procedures
2. **Generate new secrets** using a password manager
3. **Update secrets in your secret store** (GitHub Actions secrets or Vault)
4. **Trigger redeployment** to pick up new secrets:
   ```bash
   kubectl rollout restart deployment/github-runner -n github-actions
   kubectl rollout restart deployment/grafana -n monitoring
   ```

**Investigation Phase (Next 2-4 hours):**
1. **Review access logs** to understand the scope:
   ```bash
   # Check GitHub audit logs
   # Review Kubernetes audit logs
   kubectl logs -n kube-system -l component=kube-apiserver | grep "authentication failed"
   ```
2. **Scan Git history** for accidental commits:
   ```bash
   git log --all --full-history -- "*.yaml" | grep -i "token\|secret\|password"
   ```
3. **Check for unauthorized changes** in your infrastructure

**Recovery Actions:**
1. **Update all related secrets** (don't just fix the one that was compromised)
2. **Review and improve** the security practices that led to the compromise
3. **Document the incident** and lessons learned

### Security Breach Response

**Containment (First Hour):**
1. **Isolate affected workloads** with network policies:
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: emergency-isolation
     namespace: affected-namespace
   spec:
     podSelector: {}
     policyTypes:
     - Ingress
     - Egress
   EOF
   ```

2. **Scale down compromised applications**:
   ```bash
   kubectl scale deployment/compromised-app --replicas=0 -n affected-namespace
   ```

**Investigation:**
1. **Collect evidence** before making changes:
   ```bash
   # Export pod logs
   kubectl logs deployment/suspicious-app -n namespace > incident-logs.txt
   
   # Export network policy violations
   kubectl logs -n kube-system -l k8s-app=cilium | grep "denied" > network-violations.txt
   ```

2. **Review security monitoring** for indicators of compromise
3. **Check for persistence mechanisms** (scheduled jobs, modified configs)

**Recovery:**
1. **Apply security patches** or configuration changes
2. **Redeploy from known good state** using GitOps
3. **Implement additional controls** to prevent recurrence

### Communication and Documentation

**During an incident:**
- Keep a timeline of actions taken
- Document what worked and what didn't
- If this is a shared lab, communicate status to other users

**Post-incident:**
- Update security procedures based on lessons learned
- Consider automating detection of similar issues
- Share learnings with the community (without exposing sensitive details)

## Learning Resources and Next Steps

### Beginner Security Learning Path
1. **Start with secret management**: Master GitHub Actions secrets first
2. **Implement basic RBAC**: Create service accounts with minimal permissions
3. **Add network policies**: Start with simple ingress/egress rules
4. **Set up monitoring**: Deploy Prometheus and configure basic alerts

### Intermediate Security Projects  
1. **Deploy cert-manager**: Automate TLS certificate management
2. **Implement Pod Security Standards**: Enforce security contexts across namespaces
3. **Add vulnerability scanning**: Integrate Trivy into your CI/CD pipeline
4. **Create custom security policies**: Use OPA Gatekeeper for policy enforcement

### Advanced Security Challenges
1. **Deploy HashiCorp Vault**: Implement enterprise-grade secret management
2. **Set up service mesh**: Add Istio or Linkerd for mTLS everywhere
3. **Implement runtime security**: Deploy Falco for runtime threat detection
4. **Create zero-trust architecture**: Design network policies for zero-trust security

### Recommended Reading
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)

## Getting Help

**For security questions or concerns:**
- Create a **private issue** in this repository
- Follow **responsible disclosure** practices for vulnerabilities
- Join the **#kubernetes-security** channel in the Kubernetes Slack

**Remember:** Security is a journey, not a destination. Every lab environment teaches you something new about protecting systems in production.

---

*This security strategy evolves with the lab. Contribute improvements via pull requests, and document security lessons learned in the issues.*
