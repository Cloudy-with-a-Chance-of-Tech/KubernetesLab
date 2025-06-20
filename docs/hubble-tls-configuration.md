# Hubble TLS Configuration Guide

## Overview

Hubble, the observability layer for Cilium, uses TLS for secure communications between its components by default. However, in environments where a proper Certificate Authority (CA) is not available or during initial setup, you may need to operate Hubble without TLS temporarily.

This guide explains both configurations and how to switch between them.

## Configuration Options

### 1. With TLS (Default)

The default configuration uses TLS certificates for secure communication between:
- Hubble UI backend and Hubble Relay
- Hubble Relay and Hubble Peer (Cilium agents)

**Requirements:**
- A valid TLS certificate in the `hubble-relay-client-certs` Kubernetes secret
- Certificate files mounted properly in the pods

**Files:**
- `networking/cilium/hubble-relay-config.yaml`
- `networking/cilium/hubble-ui.yaml`

### 2. Without TLS (Temporary Solution)

This configuration disables TLS checks, allowing Hubble components to communicate without certificates.

**Use when:**
- No CA infrastructure is available
- During initial cluster setup
- For testing/development environments

**Files:**
- `networking/cilium/no-tls/hubble-relay-config-no-tls.yaml`
- `networking/cilium/no-tls/hubble-relay-deployment-no-tls.yaml`
- `networking/cilium/no-tls/hubble-ui-deployment-no-tls.yaml`

⚠️ **Security Note**: The no-TLS configuration is less secure and should only be used temporarily until proper certificates can be provisioned.

## Switching Between Configurations

Use the provided script to easily switch between configurations:

```bash
# Enable TLS (default)
./scripts/configure-hubble-tls.sh --tls

# Disable TLS (temporary solution)
./scripts/configure-hubble-tls.sh --no-tls
```

The script will:
1. Back up current configurations
2. Apply the selected configuration
3. Wait for deployments to be ready
4. Display the status of the deployments

## Troubleshooting

### TLS Errors

If you see errors like:

```
Error: certificate file path is required
```

It means Hubble is trying to use TLS but can't find the certificates. Solutions:

1. Switch to no-TLS mode temporarily: `./scripts/configure-hubble-tls.sh --no-tls`
2. Set up proper certificates and secrets (recommended for production)

### Verifying Connectivity

To verify that Hubble components are communicating properly:

```bash
# Check Hubble Relay logs
kubectl logs -n cilium deployment/hubble-relay

# Check Hubble UI backend logs
kubectl logs -n cilium deployment/hubble-ui -c backend
```

## Next Steps

1. **Setting up proper TLS**: Once you have a CA infrastructure (like Vault), set up proper TLS certificates
2. **Switch back to TLS mode**: After certificates are provisioned, switch back to TLS mode for enhanced security

## Additional Resources

- [Cilium Documentation](https://docs.cilium.io/)
- [Hubble Documentation](https://docs.cilium.io/en/stable/gettingstarted/hubble/)
- [Security Best Practices](docs/security-strategy.md)
