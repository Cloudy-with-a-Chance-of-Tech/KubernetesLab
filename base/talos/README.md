# Talos Configuration Files

This directory contains Talos Linux machine configurations for the cluster.

## ⚠️ Security Notice

**IMPORTANT**: Actual machine configuration files contain sensitive cryptographic keys and tokens. These files are automatically excluded from git via `.gitignore` for security.

## Files in this directory:

### Template Files (committed to git):
- `talosconfig.yaml` - Cluster configuration template
- `controlplane.yaml.template` - Control plane configuration template  
- `worker.yaml.template` - Worker node configuration template
- `README.md` - This file

### Generated Files (NOT committed to git):
- `controlplane.yaml` - Actual control plane configuration (contains secrets)
- `worker.yaml` - Actual worker configuration (contains secrets)
- `talosconfig` - Talos client configuration (contains secrets)

## Usage

### Initial Setup
```bash
# Generate configurations (run from repository root)
./scripts/generate-talos-config.sh

# Apply configurations to nodes
./scripts/deploy-cluster.sh

# Bootstrap the cluster
./scripts/bootstrap-cluster.sh
```

## Important Notes

### Raspberry Pi Considerations
This setup is optimized for Raspberry Pi nodes with remote management:

- **Wipe Mode**: Uses `--wipe-mode user-disks` in destroy script
- **Remote Safe**: Preserves system partition, only wipes user data
- **No Physical Access Required**: Safe for headless Pi clusters
- **Recovery**: Nodes will reboot to maintenance mode automatically

### Cluster Management
```bash
# Get cluster status
talosctl --talosconfig base/talos/talosconfig health

# Update a node
talosctl --talosconfig base/talos/talosconfig upgrade --nodes 192.168.1.101

# Destroy and rebuild (Pi-safe)
./scripts/destroy-cluster.sh    # Uses user-disks wipe mode
./scripts/deploy-cluster.sh
```

## Backup and Recovery

The sensitive configuration files should be backed up securely:

1. **Backup**: Store `talosconfig`, `controlplane.yaml`, and `worker.yaml` in a secure location
2. **Recovery**: Restore these files to rebuild the exact same cluster
3. **Rotation**: Use `talosctl gen secrets` to generate new secrets when needed

## Network Configuration

Update the IP addresses in `talosconfig.yaml` to match your environment:

- Control plane VIP: `kub.home.thomaswimprine.com` (your actual endpoint)
- Control plane nodes: `192.168.1.101-103` (update these)
- Worker nodes: `192.168.1.111-116` (update these)

## Integration with Repository

The cluster configurations integrate with:
- **Cilium BGP**: Networking configurations in `../networking/`
- **Monitoring**: Prometheus configurations in `../monitoring/`
- **Security**: RBAC and policies in `../rbac/`
- **Applications**: Workloads in `../apps/`
