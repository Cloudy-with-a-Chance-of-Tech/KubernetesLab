# GitHub Actions Self-Hosted Runner Setup

This guide walks through setting up self-hosted GitHub Actions runners in your Talos Kubernetes cluster.

## Overview

The GitHub runner setup consists of:
- **Namespace**: `github-actions` with resource quotas
- **RBAC**: ServiceAccount with cluster-wide permissions for GitOps
- **Secret**: Stores GitHub token and configuration
- **Deployment**: Runs the GitHub Actions runner containers
- **HPA**: Auto-scales runners based on CPU/memory usage
- **PDB**: Ensures high availability during updates

## Prerequisites

1. **GitHub Personal Access Token** with the following scopes:
   - `repo` (for private repositories)
   - `admin:org` (for organization-level runners)
   - `workflow` (to manage workflow runs)

2. **Talos Kubernetes Cluster** running with:
   - Cilium CNI configured
   - Container runtime accessible (`/var/run/docker.sock`)

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
- The `RUNNER_TOKEN` should have minimal required permissions

### Step 3: Update the Secret Templates

The secret templates in the `security/` directory are for reference only and contain placeholders:

```bash
# Navigate to the repository
cd /home/thomas/Repositories/personal/KubernetesLab

# Generate base64 encoded token
echo -n "your-github-token-here" | base64

# Update the secret file
vim security/github-runner-secret.yaml
```

Replace `REPLACE_WITH_BASE64_ENCODED_TOKEN` with your actual base64-encoded token.

### Step 4: Deploy the Runner Infrastructure

Apply the base infrastructure manually first, then use GitOps for application deployment:

```bash
# 1. Create namespaces and RBAC (one-time setup)
kubectl apply -f base/namespaces/
kubectl apply -f base/rbac/

# 2. Push to main branch to trigger GitOps deployment
git add .
git commit -m "Configure GitHub Actions secrets"
git push origin main
```

The GitHub Actions workflow will automatically:
- Create secrets from repository secrets
- Deploy the runner applications
- Set up monitoring and networking

### Step 5: Verify Deployment

Check that everything is running correctly:

```bash
# Check namespace and pods
kubectl get pods -n github-actions

# Check runner logs
kubectl logs -n github-actions deployment/github-runner

# Check HPA status
kubectl get hpa -n github-actions

# Check PDB status
kubectl get pdb -n github-actions
```

## Configuration Details

### Security Features

- **Non-root execution**: Runs as user/group 1000
- **Read-only root filesystem**: Where possible (runner needs some write access)
- **Dropped capabilities**: All unnecessary Linux capabilities removed
- **Seccomp profile**: Runtime default security profile
- **Network policies**: Restrict network access (configure in networking/)

### Resource Management

- **Requests**: 250m CPU, 512Mi memory per runner
- **Limits**: 1000m CPU, 2Gi memory per runner
- **Auto-scaling**: 1-5 replicas based on CPU/memory usage
- **Ephemeral runners**: Automatically destroyed after job completion

### Talos Compatibility

- **Security contexts**: Compatible with Talos security model
- **Host path access**: Limited to Docker socket only
- **Node selectors**: Targets ARM64 nodes (Raspberry Pi CM4)
- **Tolerations**: Can run on control plane nodes if needed

### Labels and Targeting

Runners are configured with the following labels:
- `kubernetes`
- `talos`
- `cilium`
- `homelab`
- `arm64`

Use these in your workflow files:

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