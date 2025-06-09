# Talos Credential Security Guide

This guide explains how to securely manage Talos cluster credentials while maintaining configuration structure in source control.

## Security Overview

The Talos credential management system separates sensitive cryptographic material from configuration structure:

- **Sensitive**: CA certificates, client certificates, and private keys
- **Safe for Git**: Configuration templates with placeholders for credentials
- **Working Copies**: Local files with real credentials (gitignored)

## Quick Setup

### 1. Secure Existing Credentials

If you already have a working `~/.talos/config`:

```bash
./scripts/secure-talos-credentials.sh
```

This will:
- Extract credentials to `~/.talos-credentials/kub/`
- Create template at `base/talos/talosconfig.template`
- Set up working config in `base/talos/talosconfig`
- Update `.gitignore` to exclude sensitive files

### 2. Restore Credentials (for team members)

If you have the template and secure credentials:

```bash
CLUSTER_NAME=kub ./scripts/restore-talos-credentials.sh
```

## File Structure

```
~/.talos-credentials/kub/          # Secure credentials (NEVER commit)
├── talosconfig                    # Full working config
├── ca.crt.b64                    # CA certificate (base64)
├── client.crt.b64                # Client certificate (base64)
└── client.key.b64                # Client private key (base64)

base/talos/
├── talosconfig.template          # Safe template (commit this)
├── talosconfig                   # Working config (gitignored)
├── controlplane.yaml.template    # Machine configs
└── worker.yaml.template
```

## Security Features

### ✅ What's Safe for Git
- `talosconfig.template` - Configuration structure with placeholders
- Machine configuration templates
- Documentation and scripts

### ❌ What's Protected from Git
- `talosconfig` - Working configuration with real keys
- `*.key` - Private key files
- `*.crt` - Certificate files
- `**/secrets/` - Any secrets directories

### 🔒 Secure Storage
- Credentials stored in `~/.talos-credentials/` outside repository
- Directory permissions: `700` (owner only)
- File permissions: `600` (owner read/write only)
- Automatic `.gitignore` protection

## Team Collaboration

### For Team Lead (Initial Setup)
1. Run `./scripts/secure-talos-credentials.sh`
2. Commit the template file to git
3. Share credentials securely (see sharing methods below)

### For Team Members
1. Pull latest changes to get template
2. Receive credentials securely from team lead
3. Place credentials in `~/.talos-credentials/kub/`
4. Run `CLUSTER_NAME=kub ./scripts/restore-talos-credentials.sh`

### Sharing Credentials Securely

#### Option 1: Encrypted File Sharing
```bash
# Team lead creates encrypted archive
tar -czf talos-credentials.tar.gz -C ~/.talos-credentials kub/
gpg --symmetric --cipher-algo AES256 talos-credentials.tar.gz
# Share talos-credentials.tar.gz.gpg via secure channel

# Team member decrypts
gpg --decrypt talos-credentials.tar.gz.gpg | tar -xzf - -C ~/.talos-credentials/
```

#### Option 2: Secure Vault (Recommended)
- Use HashiCorp Vault, Azure Key Vault, or AWS Secrets Manager
- Store base64-encoded certificates and keys
- Team members fetch with appropriate vault CLI

#### Option 3: Password Manager
- Use 1Password, Bitwarden, or similar enterprise solution
- Store credentials as secure notes
- Share via secure vault sharing features

## Using Talosctl

### Standard Usage
```bash
# Uses working config automatically
cd /path/to/KubernetesLab
talosctl --talosconfig base/talos/talosconfig version

# Or set TALOSCONFIG environment variable
export TALOSCONFIG=/path/to/KubernetesLab/base/talos/talosconfig
talosctl version
```

### Alternative: Use Default Location
```bash
# Copy working config to default location
cp base/talos/talosconfig ~/.talos/config
talosctl version  # Uses ~/.talos/config automatically
```

## Credential Rotation

When rotating certificates:

1. Generate new Talos configuration
2. Run `./scripts/secure-talos-credentials.sh` again
3. Commit updated template
4. Share new credentials with team

## Troubleshooting

### "No such file or directory: talosconfig"
```bash
# Restore from template
CLUSTER_NAME=kub ./scripts/restore-talos-credentials.sh
```

### "Permission denied" errors
```bash
# Fix permissions
chmod 700 ~/.talos-credentials/kub/
chmod 600 ~/.talos-credentials/kub/*
```

### "Invalid certificate" errors
- Verify credentials match the cluster
- Check if certificates have expired
- Ensure CA certificate is correct

### Wrong cluster name
```bash
# Use correct cluster name
CLUSTER_NAME=your-cluster-name ./scripts/restore-talos-credentials.sh
```

## Security Best Practices

1. **Never commit real credentials to git**
2. **Use encrypted channels for credential sharing**
3. **Regularly rotate certificates**
4. **Audit access to credential storage**
5. **Use vault solutions for production environments**
6. **Keep backups of credentials in secure locations**

## Emergency Recovery

If you lose credentials but have cluster access:

```bash
# Re-extract from existing cluster
talosctl config export > ~/.talos/config
./scripts/secure-talos-credentials.sh
```

If you lose both credentials and cluster access:
- Restore from secure backup
- Or rebuild cluster with new certificates
- Update all team members with new credentials
