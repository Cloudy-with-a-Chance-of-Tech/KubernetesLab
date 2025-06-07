# Quick Setup: GitHub Actions Secrets

## Required Secrets

Before deploying this lab environment, configure these secrets in your GitHub repository:

### 1. Navigate to Repository Settings
- Go to your repository → Settings → Secrets and variables → Actions
- Click "New repository secret"

### 2. Add Required Secrets

| Secret Name | Description | How to Get |
|-------------|-------------|-------------|
| `RUNNER_TOKEN` | GitHub Personal Access Token | [Create PAT](https://github.com/settings/tokens) with `repo`, `admin:org`, `workflow` scopes |
| `ORG_NAME` | GitHub username/organization | Your GitHub username or organization name |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password | Generate strong password (min 12 chars) |

### 3. Verification Checklist

- [ ] `RUNNER_TOKEN` - Valid GitHub PAT with correct scopes
- [ ] `ORG_NAME` - Matches your GitHub username/org exactly
- [ ] `GRAFANA_ADMIN_PASSWORD` - Strong password (no special chars that might break shell)

### 4. Deploy Base Infrastructure

```bash
# Apply base resources manually (one-time setup)
kubectl apply -f base/namespaces/
kubectl apply -f base/rbac/

# Push to main branch to trigger GitOps
git push origin main
```

## Security Notes

- Never commit actual secrets to the repository
- All files in `security/` directory are templates only
- Actual secrets are created by GitHub Actions workflow
- Rotate secrets regularly (especially GitHub tokens)

## Troubleshooting

**Runner not appearing in GitHub:**
- Check `RUNNER_TOKEN` has correct scopes
- Verify `ORG_NAME` matches exactly (case-sensitive)
- Check GitHub Actions workflow logs

**Secret creation failures:**
- Ensure no special characters that break shell commands
- Verify secret names match exactly (case-sensitive)
- Check kubectl access from GitHub runner

---

📖 **Full documentation**: [github-actions-setup.md](github-actions-setup.md)
