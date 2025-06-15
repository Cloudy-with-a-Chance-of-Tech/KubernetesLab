# GitHub Actions Self-Hosted Runners Setup Guide

*Because why pay for GitHub Actions minutes when you have perfectly good compute sitting in your home lab?*

## The Story

Like most infrastructure enthusiasts, I quickly discovered that GitHub's hosted runners have some limitations:
- They're expensive for heavy workloads
- No direct access to your internal infrastructure  
- Limited customization options
- ARM64 support is... let's call it "emerging"

Self-hosted runners solve all these problems, but they come with their own challenges. This guide walks you through setting up production-ready, secure, self-hosted GitHub Actions runners on your Kubernetes cluster.

## Architecture Overview

Here's what we're building:

```
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Actions                              │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐ │
│  │   Workflow      │    │   Workflow      │    │   Workflow   │ │
│  │   (Org Repo)    │    │   (Personal)    │    │   (Other)    │ │
│  └─────────────────┘    └─────────────────┘    └──────────────┘ │
│           │                       │                     │       │
│           └───────────────────────┼─────────────────────┘       │
│                                   │                             │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS/REST API
                                    │
┌─────────────────────────────────────────────────────────────────┐
│                 Kubernetes Cluster                               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                github-actions namespace                     ││
│  │                                                             ││
│  │  ┌─────────────────┐    ┌─────────────────┐                ││
│  │  │ Organization    │    │ Phoenix         │                ││
│  │  │ Runner          │    │ Runner          │                ││
│  │  │ (Full RBAC)     │    │ (App RBAC)      │                ││
│  │  │                 │    │                 │                ││
│  │  │ - Infra Mgmt    │    │ - App Deploy    │                ││
│  │  │ - Storage       │    │ - Testing       │                ││
│  │  │ - Networking    │    │ - Monitoring    │                ││
│  │  │ - RBAC Admin    │    │                 │                ││
│  │  └─────────────────┘    └─────────────────┘                ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                  Security Layer                             ││
│  │  - Network Policies (Egress Control)                       ││
│  │  - RBAC (Principle of Least Privilege)                     ││
│  │  - Security Contexts (Non-root, Capabilities Dropped)      ││
│  │  - Resource Limits (CPU/Memory)                            ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Why Two Runners?

After years of running self-hosted runners, I've learned that one size doesn't fit all:

### Organization Runner (Full Infrastructure Access)
- **Purpose**: Infrastructure-as-Code deployments
- **RBAC**: Cluster-admin level permissions
- **Use Cases**: 
  - Deploying storage configurations
  - Managing network policies
  - Updating RBAC configurations
  - Installing cluster-wide resources

### Phoenix Runner (Application-Focused)
- **Purpose**: Application deployments and testing
- **RBAC**: Namespace-scoped permissions
- **Use Cases**:
  - Deploying applications
  - Running tests
  - Managing application secrets
  - Monitoring application health

This separation follows the principle of least privilege and reduces the blast radius if something goes wrong.

## Prerequisites

Before setting up the runners, you'll need:

### GitHub Setup
1. **Personal Access Token** with scopes:
   - `repo` (full repository access)
   - `admin:org` (organization administration)
   - `workflow` (workflow management)

2. **Organization Settings** (if using org runner):
   - Navigate to Organization → Settings → Actions → Runners
   - Note the registration URL and token (we'll automate this)

### Kubernetes Prerequisites
```bash
# Verify cluster is ready
kubectl get nodes
kubectl get ns github-actions || kubectl create ns github-actions

# Verify RBAC is configured
kubectl auth can-i create clusterroles --as=system:serviceaccount:github-actions:github-runner
```

### Required Secrets

Let's create the secrets both runners need:

```bash
# GitHub token for runner registration
kubectl create secret generic github-runner-secret \
  --from-literal=github-token="<REDACTED_GITHUB_TOKEN>" \
  --from-literal=runner-name="org-runner" \
  -n github-actions

kubectl create secret generic phoenix-runner-secret \
  --from-literal=github-token="<REDACTED_GITHUB_TOKEN>" \
  --from-literal=runner-name="phoenix-runner" \
  -n github-actions
```

## Setup Instructions

### Step 1: Create GitHub Personal Access Token

1. Go to GitHub Settings → Developer settings → Personal access tokens
2. Click "Generate new token (classic)"
3. Select the required scopes mentioned above
4. Copy the token securely

### Step 2: Configure GitHub Actions Secrets

Before deploying, you must configure the required secrets in your GitHub repository:

1. Go to your repository → Settings → Secrets and variables → Actions
2. Click "New repository secret" and add each of the following:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `RUNNER_TOKEN` | GitHub Personal Access Token with repo, admin:org, workflow scopes | `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `ORG_NAME` | Your GitHub organization or username | `your-github-username` |
| `GRAFANA_ADMIN_PASSWORD` | Strong password for Grafana admin user | `your-secure-grafana-password` |

**Important:** 
- Never use secret names that start with `GITHUB_` as GitHub Actions restricts these
- Store these values securely and rotate them regularly
### Step 3: Deploy RBAC Configurations

First, let's set up the permission boundaries:

```bash
# Deploy minimal RBAC for Phoenix runner
kubectl apply -f base/rbac/phoenix-runner-minimal-rbac.yaml

# Deploy full RBAC for organization runner  
kubectl apply -f base/rbac/github-runner-minimal-rbac.yaml
```

Let's examine what these RBAC configs actually allow:

**Phoenix Runner (Application-Scoped):**
```yaml
# Can manage applications but not infrastructure
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["services", "configmaps", "secrets", "persistentvolumeclaims"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
# No cluster-level resources
```

**Organization Runner (Infrastructure-Scoped):**
```yaml
# Can manage cluster infrastructure
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
# This is cluster-admin level - use with caution
```

### Step 4: Deploy Network Policies

Security first - let's lock down network access:

```bash
kubectl apply -f security/github-actions-network-policy.yaml
```

This policy:
- Allows outbound HTTPS to GitHub APIs
- Allows DNS resolution
- Allows access to Kubernetes API server
- Denies everything else

### Step 5: Deploy the Runners

Now for the main event:

```bash
# Deploy organization runner
kubectl apply -f apps/production/github-runner.yaml

# Deploy Phoenix runner  
kubectl apply -f apps/production/phoenix-runner.yaml
```

### Step 6: Verify Deployment

Let's make sure everything is working:

```bash
# Check pod status
kubectl get pods -n github-actions -w

# Check logs for successful registration
kubectl logs -f deployment/github-runner -n github-actions
kubectl logs -f deployment/phoenix-runner -n github-actions

# Verify runners appear in GitHub
# Organization Settings → Actions → Runners
# Should show both runners with "Idle" status
```

## Configuration Deep Dive

### Runner Environment

Each runner comes pre-configured with essential tools:

```dockerfile
# Base tools included in runner image
- Docker (for container builds)
- kubectl (for Kubernetes management)  
- helm (for chart deployments)
- git (for repository operations)
- curl, jq, wget (for API interactions)
- Custom tools via init containers
```

### Environment Variables

Key environment variables that control runner behavior:

```yaml
env:
- name: RUNNER_NAME_PREFIX
  value: "k8s-runner"
- name: RUNNER_WORKDIR
  value: "/tmp/github-runner"
- name: LABELS
  value: "kubernetes,talos,cilium,homelab,arm64,self-hosted"
- name: EPHEMERAL
  value: "true"  # Fresh environment per job
```

### Resource Allocation

Carefully tuned based on workload patterns:

```yaml
# Organization runner (infrastructure workloads)
resources:
  requests:
    memory: "2Gi"    # Terraform/Ansible needs memory
    cpu: "1000m"     # Infrastructure deployments are CPU-intensive
  limits:
    memory: "4Gi"    # Allow bursts for large deployments
    cpu: "2000m"

# Phoenix runner (application workloads)  
resources:
  requests:
    memory: "1Gi"    # Application builds are lighter
    cpu: "500m"
  limits:
    memory: "2Gi"    # Sufficient for most app workloads
    cpu: "1500m"
```

### Security Features

- **Non-root execution**: Runs as user/group 10001
- **Dropped capabilities**: All unnecessary Linux capabilities removed
- **Read-only root filesystem**: Where possible (runner needs some write access)
- **Network policies**: Restrict network access to essential services only
- **RBAC boundaries**: Principle of least privilege enforced

```yaml
jobs:
  deploy:
    runs-on: [self-hosted, kubernetes, talos]
    steps:
      # Your deployment steps
```

## Troubleshooting

### Common Issues

| Issue | Symptoms | Solution |
|-------|----------|----------|
| Runner not registering | Pods running but no runners in GitHub | Check GitHub Actions secret values and token permissions |
| Permission denied | Containers crashing with permission errors | Verify Talos security contexts and RBAC |
| Docker socket access | Build failures with Docker commands | Ensure `/var/run/docker.sock` is available on nodes |
| High resource usage | Frequent restarts or slow performance | Adjust resource limits or increase node capacity |

### Debugging Commands

```bash
# Check runner registration status
kubectl logs -n github-actions deployment/github-runner

# Describe pod for events and configuration
kubectl describe pod -n github-actions -l app.kubernetes.io/name=github-runner

# Check secret content (be careful with tokens!)
kubectl get secret -n github-actions github-runner-secret -o yaml

# Monitor resource usage
kubectl top pods -n github-actions

# Check HPA scaling decisions
kubectl describe hpa -n github-actions github-runner-hpa
```

### GitHub Organization Settings

Ensure your organization allows self-hosted runners:
1. Go to Organization Settings → Actions → Runners
2. Enable "Allow select actions and reusable workflows"
3. Add your repository patterns to the allowed list
4. Verify runner appears in the organization runners list

## Security Considerations

### Network Isolation

Consider implementing network policies to restrict runner traffic:

```yaml
# Example: Limit outbound connections
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: github-runner-netpol
  namespace: github-actions
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: github-runner
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 443  # HTTPS to GitHub
    - protocol: TCP
      port: 80   # HTTP for package downloads
```

### Secret Rotation

Regularly rotate your GitHub tokens:
1. Generate new token in GitHub
2. Update the `RUNNER_TOKEN` secret in GitHub Actions repository secrets
3. Re-run the GitOps deployment workflow to update cluster secrets
4. Or manually update: `kubectl create secret generic github-runner-secret --from-literal=github-token=NEW_TOKEN --namespace=github-actions --dry-run=client -o yaml | kubectl apply -f -`

### Monitoring

Consider adding monitoring for:
- Runner registration success/failure
- Job execution times
- Resource utilization
- Security events

## Integration with GitOps

This runner setup integrates with your GitOps workflows by providing:
- Cluster access for deployment operations
- Proper RBAC for namespace and resource management
- Auto-scaling based on workflow demand
- High availability during cluster maintenance

The runners can deploy applications to any namespace they have permissions for, making them ideal for GitOps automation in your homelab environment.