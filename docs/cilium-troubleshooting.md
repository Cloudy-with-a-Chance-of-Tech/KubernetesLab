# Cilium Troubleshooting Guide

## Common Issues and Solutions

### Issue: Hubble UI Not Displaying Network Flows

**Symptoms:**
- Hubble UI loads successfully but shows no network flows
- Flow buffer appears to be at 100% capacity
- Backend connection errors in logs

**Root Causes:**
1. **Cluster Name Mismatch**: Cilium configuration using incorrect cluster name
2. **Flow Buffer Exhaustion**: Monitor buffer pages insufficient for cluster traffic
3. **DNS Resolution Issues**: Hubble components unable to resolve service names

**Diagnostic Commands:**
```bash
# Check flow buffer status
kubectl exec -n cilium ds/cilium -- cilium status --verbose | grep -i hubble

# Check cluster name configuration
kubectl get configmap cilium-config -n cilium -o yaml | grep cluster-name

# Check Hubble UI backend logs
kubectl logs -n cilium deployment/hubble-ui -c backend --tail=20

# Verify service accessibility
kubectl get svc -n cilium | grep hubble
```

**Solution Steps:**

1. **Detect Correct Cluster Name:**
   ```bash
   ./scripts/detect-cluster-info.sh name
   ```

2. **Update Cilium Configuration:**
   ```bash
   # Replace "kub" with your actual cluster name
   kubectl patch configmap cilium-config -n cilium --type merge -p '{"data":{"cluster-name":"kub"}}'
   
   # Increase flow buffer capacity
   kubectl patch configmap cilium-config -n cilium --type merge -p '{"data":{"monitor-num-pages":"256","hubble-metrics":""}}'
   ```

3. **Restart Cilium Components:**
   ```bash
   kubectl rollout restart daemonset/cilium -n cilium
   kubectl rollout restart deployment/hubble-relay -n cilium
   kubectl rollout restart deployment/hubble-ui -n cilium
   ```

4. **Wait for Rollout Completion:**
   ```bash
   kubectl wait --for=condition=ready pod -l k8s-app=cilium -n cilium --timeout=300s
   kubectl wait --for=condition=ready pod -l k8s-app=hubble-relay -n cilium --timeout=300s
   kubectl wait --for=condition=ready pod -l k8s-app=hubble-ui -n cilium --timeout=300s
   ```

5. **Verify Resolution:**
   ```bash
   # Should show flows at reasonable percentage (< 50%)
   kubectl exec -n cilium ds/cilium -- cilium status --verbose | grep -i hubble
   
   # Should show successful connections
   kubectl logs -n cilium deployment/hubble-ui -c backend --tail=10
   ```

**Expected Results After Fix:**
- Flow buffer at manageable capacity (< 50%)
- Active flow processing (flows/second > 0)
- No DNS resolution errors in backend logs
- Network flows visible in Hubble UI

### Configuration Parameters Reference

| Parameter | Purpose | Recommended Value |
|-----------|---------|-------------------|
| `cluster-name` | Cluster identifier for service discovery | Use output from `detect-cluster-info.sh name` |
| `monitor-num-pages` | Flow buffer size (pages) | `256` (up from default `64`) |
| `hubble-metrics` | Enable flow metrics export | `""` (empty to enable default metrics) |
| `enable-hubble` | Enable Hubble observability | `"true"` |

### Integration with Portable Deployment System

When using the portable deployment system, ensure Cilium configuration aligns with detected cluster parameters:

```bash
# Get cluster configuration
source <(./scripts/detect-cluster-info.sh config env)

# Apply to Cilium
kubectl patch configmap cilium-config -n cilium --type merge -p "{\"data\":{\"cluster-name\":\"$CLUSTER_NAME\"}}"
```

### Monitoring and Maintenance

**Regular Health Checks:**
```bash
# Weekly flow buffer check
kubectl exec -n cilium ds/cilium -- cilium status --verbose | grep "Current/Max Flows"

# Monthly configuration validation
kubectl get configmap cilium-config -n cilium -o yaml | grep -E "(cluster-name|monitor-num-pages)"
```

**Performance Tuning:**
- Monitor flow buffer utilization
- Adjust `monitor-num-pages` based on cluster traffic patterns
- Enable metrics for detailed observability

This guide resolves the most common Hubble UI flow capture issues by ensuring proper cluster name alignment and adequate buffer sizing.
