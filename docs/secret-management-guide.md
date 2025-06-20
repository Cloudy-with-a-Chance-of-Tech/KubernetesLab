# Secret Management Guide for KubernetesLab

## Overview

This guide outlines the proper procedures for handling secrets within the KubernetesLab repository and infrastructure. Following these practices is crucial to maintain security and prevent accidental exposure of sensitive information.

## ⚠️ Critical Rules

1. **ABSOLUTELY NO SECRETS IN CODE**: UNDER NO CIRCUMSTANCES should there be a key, password, token, certificate, or ANY security-related credential in documentation or committed to Git
2. **Zero Tolerance for Hardcoded Secrets**: Not in comments, examples, documentation, README files, or anywhere in the codebase
3. **Environment Files Only**: All secrets must be stored in `.env` files which are never committed (included in `.gitignore`)
4. **Use Placeholders**: When showing examples, use placeholders like `<REDACTED>` or `<SECRET_FROM_VAULT>`

## Secret Management Architecture

The KubernetesLab uses a multi-layered approach to secret management:

1. **Local Development**:
   - Environment variables in `.env` files (never committed)
   - Local vault CLI for development secrets

2. **Cluster Secrets**:
   - External Secrets Operator with Vault integration
   - Kubernetes secret objects created by pipeline or scripts
   - Secret rotation handled by automation

3. **CI/CD Pipeline**:
   - GitHub Actions secrets for workflow execution
   - Short-lived credentials generated at runtime

## Handling Secrets in Documentation

When writing documentation that requires referencing secrets:

```bash
# ✅ DO THIS: Use environment variables
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"

# ✅ OR THIS: Use explicit placeholders
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-password="<REDACTED_PASSWORD>"

# ❌ NEVER DO THIS: Include actual secrets
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-password="actual-password-here"
```

## What To Do If You Find a Secret In the Repo

If you discover a committed secret:

1. **DO NOT** simply delete it in a new commit, as it remains in Git history
2. **DO NOT** share or mention the secret in issues, PRs, or chat
3. **DO** follow this procedure:
   - Immediately rotate the secret if it's a production credential
   - Use the `remove_secrets.sh` script to purge it from Git history
   - Force push the changes to remove the secret from the remote repository
   - Notify the team to update their local repositories

## Using the Secret Removal Tool

```bash
# Execute the removal script
./remove_secrets.sh

# Force push the changes (only if you're authorized)
git push origin main --force
```

## Tools and Resources

- [External Secrets Operator](https://external-secrets.io/)
- [HashiCorp Vault](https://www.vaultproject.io/)
- [git-filter-repo](https://github.com/newren/git-filter-repo)

## Regular Auditing

The repository is regularly scanned for secrets using:

1. Pre-commit hooks to prevent accidental commits
2. GitHub secret scanning at the platform level
3. Periodic security audits and reviews

Remember: The most secure secret is one that never enters your repository in the first place!
