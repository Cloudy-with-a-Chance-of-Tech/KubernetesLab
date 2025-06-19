# Talos Local Storage Configuration

This document outlines how to configure Talos for local storage using the local-path-provisioner.

## Required Talos Configuration

To use local storage with the local-path-provisioner, the Talos machine configuration must include kubelet extraMounts to expose the `/var/mnt` directory to the kubelet container.

### 1. Kubelet Extra Mounts

Add this configuration to your Talos machine configuration (both controlplane and worker nodes):

```yaml
machine:
  kubelet:
    extraMounts:
      - destination: /var/mnt
        type: bind
        source: /var/mnt
        options:
          - bind
          - rshared
          - rw
```

### 2. Optional: User Volume (Recommended)

For production environments, create a dedicated user volume for local storage:

```yaml
apiVersion: v1alpha1
kind: UserVolumeConfig
name: local-path-provisioner
provisioning:
  diskSelector:
    match: disk.transport == 'nvme'  # Adjust based on your disk type
  minSize: 200GB
  maxSize: 200GB
```

## Local Path Provisioner Configuration

Our local-path-provisioner is configured according to Talos best practices:

### Key Configuration Elements:

1. **Correct hostPath**: Uses `/var/mnt/local-path-provisioner` (Talos recommended path)
2. **Privileged namespace**: `local-path-storage` namespace has `pod-security.kubernetes.io/enforce: privileged` label
3. **Security context**: Runs as non-root user (65534) with minimal privileges
4. **Resource limits**: Properly constrained CPU, memory, and ephemeral storage
5. **Network policy**: Restricts network access to only required ports

### Configuration Validation

```bash
# Check namespace labels
kubectl get namespace local-path-storage -o yaml

# Check local-path-provisioner deployment
kubectl get deployment -n local-path-storage local-path-provisioner

# Check storage class
kubectl get storageclass local-path

# Test storage provisioning
kubectl apply -f base/storage/storage-test.yaml
kubectl get pvc -n default
```

### Troubleshooting

1. **Pod fails to start**: Check if kubelet extraMounts are configured
2. **PVC stays pending**: Verify storage class and provisioner logs
3. **Permission issues**: Ensure namespace has privileged label

```bash
# Check provisioner logs
kubectl logs -n local-path-storage deployment/local-path-provisioner

# Verify hostPath exists on nodes
talosctl ls /var/mnt/local-path-provisioner

# Check for created PV directories
talosctl ls /var/mnt/local-path-provisioner
```

## References

- [Talos Local Storage Documentation](https://www.talos.dev/v1.10/kubernetes-guides/configuration/local-storage/)
- [Local Path Provisioner GitHub](https://github.com/rancher/local-path-provisioner)
