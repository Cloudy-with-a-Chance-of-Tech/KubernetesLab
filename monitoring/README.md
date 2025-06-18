# Metrics Server

Security-hardened Kubernetes metrics-server deployment for the Talos cluster. No fluff, just metrics that work.

## What This Gets You

The metrics-server provides resource usage data that actually matters:
- `kubectl top nodes` and `kubectl top pods` functionality
- CPU and memory metrics for Horizontal Pod Autoscaler (HPA)
- Resource utilization data for capacity planning
- Foundation for proper monitoring and alerting

## Security Posture

This configuration follows security-first principles because security isn't optional:

### Core Security Features
- **Minimal Privileges**: Runs as `nobody` user (UID 65534) with zero capabilities
- **Read-Only Filesystem**: Container filesystem is immutable
- **Resource Limits**: CPU/memory limits prevent resource exhaustion attacks  
- **Seccomp Profile**: Restricts system calls to RuntimeDefault profile
- **Network Policies**: Restricts traffic to only necessary communications
- **Service Account**: Dedicated SA with minimal required RBAC permissions

### Talos-Specific Security Considerations

**The Reality**: Talos Linux kubelets don't use traditional CA certificates, so we're forced to use `--kubelet-insecure-tls`. This isn't ideal, but it's the trade-off for running Talos.

**Mitigation**: 
- Network policies restrict kubelet access to cluster nodes only
- All other communications remain TLS-encrypted
- Service runs in isolated kube-system namespace
- RBAC limits API access to metrics endpoints only

### Security Recommendations

1. **Monitor Metrics-Server Logs**: Watch for unexpected connection attempts
2. **Regular Updates**: Keep the metrics-server image current for security patches
3. **Network Segmentation**: Ensure your CNI (Cilium) enforces the NetworkPolicy
4. **Audit Access**: Monitor who's accessing metrics via kubectl top commands

```bash
# Monitor for security events
kubectl logs -n kube-system -l k8s-app=metrics-server | grep -i "error\|fail\|unauthorized"

# Verify network policy is applied
kubectl describe networkpolicy metrics-server-netpol -n kube-system
```

## Deployment

### Quick Start
Keep it simple - deploy the metrics-server and move on:

```bash
# Deploy metrics-server (recommended)
kubectl apply -f monitoring/metrics-server.yaml

# Or use the management script for additional functionality
./scripts/deploy-metrics-server.sh deploy
```

### With the Full Monitoring Stack
The metrics-server runs independently in kube-system - it doesn't play nice with namespace-specific kustomizations:

```bash
# Deploy monitoring stack (Prometheus, etc.)
kubectl apply -k monitoring/

# Deploy metrics-server separately 
kubectl apply -f monitoring/metrics-server.yaml
```

**Why separate?** The metrics-server needs to live in kube-system to properly integrate with the API server. Trying to force it into the monitoring namespace creates unnecessary complexity.

## Verification

Verify everything's working properly - because trust but verify:

```bash
# Check pod status (should be Running)
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Test metrics API (the money shot)
kubectl top nodes
kubectl top pods -A

# Verify network policy is active
kubectl describe networkpolicy metrics-server-netpol -n kube-system

# Check security context (should run as UID 65534)
kubectl get pod -n kube-system -l k8s-app=metrics-server -o jsonpath='{.items[0].spec.securityContext}'
```

## Troubleshooting

### Common Issues That'll Drive You Nuts

**"Error from server (ServiceUnavailable): the server is currently unable to handle the request (get nodes.metrics.k8s.io)"**
- Wait 2-3 minutes after deployment. Metrics need time to populate.
- Check if the APIService is available: `kubectl get apiservices v1beta1.metrics.k8s.io`

**"x509: certificate signed by unknown authority"**
- You're missing the `--kubelet-insecure-tls` flag. This is expected with Talos.

**"unable to fully collect metrics"**
- One or more nodes might be unreachable. Check node status.
- Verify network policies aren't blocking kubelet communication.

**Pod stuck in Pending/Error state**
- Check resource constraints: `kubectl describe pod -n kube-system -l k8s-app=metrics-server`
- Verify the node selector matches your nodes: `kubectl get nodes --show-labels`

### Debugging Commands That Actually Help

```bash
# Get metrics-server logs (most useful for debugging)
kubectl logs -n kube-system -l k8s-app=metrics-server --tail=50

# Check APIService registration
kubectl get apiservices v1beta1.metrics.k8s.io -o yaml

# Test direct API access (advanced debugging)
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq .
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods" | jq .

# Verify RBAC permissions
kubectl auth can-i get nodes/metrics --as=system:serviceaccount:kube-system:metrics-server
```

## Integration Points

The metrics-server integrates with other systems you're probably already running:

### Horizontal Pod Autoscaler (HPA)
```bash
# Example HPA using metrics-server data
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: webapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Monitoring Stack Integration
- **Prometheus**: Can scrape metrics-server for meta-monitoring
- **Grafana**: Kubernetes dashboards rely on metrics-server data
- **kubectl**: Powers the `top` commands you use daily

### What It Doesn't Do
- **Long-term storage**: Metrics-server only keeps recent data (~1 minute)
- **Custom metrics**: Only provides CPU/memory, not application-specific metrics
- **Historical data**: Use Prometheus for time-series storage

## Security Maintenance

Stay on top of security because attackers don't take breaks:

### Regular Tasks
1. **Update the image** when new versions are released
2. **Monitor logs** for unusual access patterns  
3. **Review RBAC** permissions periodically
4. **Test network policies** after CNI updates

### Security Monitoring Queries
```bash
# Check for failed authentication attempts
kubectl logs -n kube-system -l k8s-app=metrics-server | grep -i "unauthorized\|forbidden"

# Monitor resource usage (prevent resource exhaustion)
kubectl top pod -n kube-system -l k8s-app=metrics-server

# Verify network policy enforcement
kubectl exec -n kube-system deployment/metrics-server -- netstat -tuln
```

## References

Useful docs when you need to go deeper:
- [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Resource Metrics API](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Talos Linux](https://www.talos.dev/v1.10/kubernetes-guides/configuration/pod-security/)

---

**Bottom Line**: This configuration gives you reliable metrics with security baked in. Deploy it, verify it works, and move on to the interesting stuff. The automation handles the rest.
