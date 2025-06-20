# Talos Kubernetes Cluster - Network Observability & Monitoring Troubleshooting Guide

## Table of Contents
- [Overview](#overview)
- [Hubble Network Observability](#hubble-network-observability)
- [Grafana Monitoring](#grafana-monitoring)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Security Context Requirements](#security-context-requirements)
- [Validation Steps](#validation-steps)

## Overview

This guide documents the configuration fixes and troubleshooting steps for network observability (Cilium/Hubble) and monitoring (Grafana/Prometheus) on a Talos-based Kubernetes cluster. All components are configured to comply with Talos security requirements.

## Hubble Network Observability

### Issue: Hubble UI Not Displaying Flows

**Root Cause**: DNS domain mismatch between cluster configuration and Hubble component configurations.

**Cluster Configuration**:
- Cluster domain: `kub-cluster.local` (configured in Talos/CoreDNS)
- Standard Kubernetes domain: `cluster.local`

#### Fix 1: Hubble Relay Configuration

Update the Hubble relay ConfigMap to use standard domain for peer-service communication:

```bash
# Check current configuration
kubectl get configmap -n cilium hubble-relay-config -o yaml

# Apply fix - update peer-service to use standard domain
kubectl patch configmap -n cilium hubble-relay-config --type='json' \
  -p='[{"op": "replace", "path": "/data/config.yaml", "value": "peer-service: \"hubble-peer.cilium.svc.cluster.local:4244\"\nlisten-address: \":4245\"\nmetrics-listen-address: \":9966\"\npprof: true\npprof-address: \"localhost\"\npprof-port: 6061\nserver-name: \"relay.cilium.io\"\nretry-timeout: 30s\nsort-buffer-len-max: 100\nsort-buffer-drain-timeout: 1s\nredact-enabled: false\nredact-http-headers-allow: \"\"\nredact-http-headers-deny: \"\"\nredact-http-url-query: false\nredact-kafka-api-key: false\n"}]'

# Restart Hubble relay to apply changes
kubectl rollout restart deployment/hubble-relay -n cilium
```

#### Fix 2: Hubble UI Backend Configuration

Update the Hubble UI deployment to use FQDN for hubble-relay connection:

```bash
# Apply fix - update FLOWS_API_ADDR to use FQDN
kubectl patch deployment -n cilium hubble-ui --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/1/env/1/value", "value": "hubble-relay.cilium.svc.cluster.local:80"}]'

# Wait for rollout to complete
kubectl rollout status deployment/hubble-ui -n cilium
```

#### Fix 3: Cilium Cluster Name Configuration

Ensure Cilium cluster name matches your DNS configuration:

```bash
# Update Cilium ConfigMap
kubectl patch configmap -n cilium cilium-config --type='merge' \
  -p='{"data":{"cluster-name":"kub-cluster"}}'

# Restart Cilium DaemonSet
kubectl rollout restart daemonset/cilium -n cilium
```

### Verification Steps

```bash
# 1. Check Hubble relay connectivity
kubectl logs -n cilium deployment/hubble-relay --tail=10
# Should show successful connections to all cluster nodes

# 2. Verify Hubble UI is accessible
kubectl get svc -n cilium hubble-ui
# Access via NodePort: http://<node-ip>:31235

# 3. Check Cilium agent status
kubectl get pods -n cilium -l k8s-app=cilium
```

## Grafana Monitoring

### Issue: "Unknown Error Occurred at Login"

**Root Cause**: Empty admin password secret and missing explicit admin username configuration.

#### Fix 1: Recreate Admin Password Secret

```bash
# Source environment variables
source .env

# Delete existing empty secret
kubectl delete secret -n monitoring grafana-admin-secret

# Create secret with correct password
kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"

# Verify secret contains password
kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d
```

#### Fix 2: Add Explicit Admin Username

The Grafana deployment has been updated to include explicit admin username configuration:

```yaml
env:
- name: GF_SECURITY_ADMIN_USER
  value: "admin"
- name: GF_SECURITY_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: grafana-admin-secret
      key: admin-password
```

#### Fix 3: Restart Grafana Deployment

```bash
# Apply updated deployment
kubectl apply -f monitoring/grafana/grafana-deployment.yaml

# Wait for rollout
kubectl rollout status deployment/grafana -n monitoring

# Verify environment variables
kubectl exec -n monitoring deployment/grafana -- env | grep GF_SECURITY_ADMIN
```

### Access Information

- **URL**: `http://192.168.100.96:3000` (LoadBalancer IP)
- **Username**: `admin`
- **Password**: From `GRAFANA_ADMIN_PASSWORD` in `.env` file

## Common Issues and Solutions

### 1. Pod Security Context Violations

**Issue**: Pods fail to start with security context violations on Talos nodes.

**Solution**: All deployments include Talos-compatible security contexts:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: <specific-user-id>
  runAsGroup: <specific-group-id>
  fsGroup: <group-id>
  seccompProfile:
    type: RuntimeDefault

containers:
- securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop: [ALL]
    readOnlyRootFilesystem: true  # where possible
    runAsNonRoot: true
```

### 2. DNS Resolution Issues

**Issue**: Services can't resolve each other using short names.

**Solution**: Use FQDNs with the correct cluster domain:
- For standard services: `service.namespace.svc.cluster.local`
- For cluster-specific services: `service.namespace.svc.kub-cluster.local`

### 3. Secret Management Issues

**Issue**: Secrets not properly populated from environment variables.

**Solution**: Ensure secrets are created from CI/CD pipeline or manually:

```bash
# From CI/CD (GitHub Actions)
kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"

# Manual creation
source .env
kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"
```

## Security Context Requirements

### Talos Security Standards

All pods must comply with these security requirements:

1. **Non-root execution**: `runAsNonRoot: true`
2. **Specific user/group IDs**: No root (0) user/group
3. **Capability dropping**: `capabilities.drop: [ALL]`
4. **No privilege escalation**: `allowPrivilegeEscalation: false`
5. **Seccomp profiles**: `seccompProfile.type: RuntimeDefault`
6. **Read-only root filesystem**: Where application permits

### Component-Specific User IDs

- **Grafana**: User/Group 472
- **Prometheus**: User/Group 65534
- **Cilium/Hubble**: Uses Talos-compatible base images

## Validation Steps

### Complete System Health Check

```bash
# 1. Check all pods are running
kubectl get pods -A | grep -E "(cilium|hubble|grafana|prometheus)"

# 2. Verify Hubble connectivity
kubectl logs -n cilium deployment/hubble-relay --tail=5

# 3. Test Grafana login
# Access http://<grafana-ip>:3000 with admin/password

# 4. Check network flows in Hubble UI
# Access http://<node-ip>:31235

# 5. Verify Prometheus targets
# Port-forward and check http://localhost:9090/targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

### Generate Test Traffic

```bash
# Create test deployment
kubectl create deployment test-nginx --image=nginx:alpine
kubectl expose deployment test-nginx --port=80

# Generate traffic
kubectl run test-client --image=curlimages/curl --rm -it --restart=Never \
  -- sh -c "while true; do curl test-nginx; sleep 2; done"
```

This should generate visible flows in the Hubble UI.

## Configuration Files Updated

- `monitoring/grafana/grafana-deployment.yaml`: Added explicit admin username
- Cilium ConfigMaps: Updated for DNS domain consistency
- Documentation: Comprehensive troubleshooting guide

## References

- [Talos Security Context Requirements](https://www.talos.dev/)
- [Cilium Network Observability](https://docs.cilium.io/en/stable/observability/)
- [Grafana Configuration](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/)
