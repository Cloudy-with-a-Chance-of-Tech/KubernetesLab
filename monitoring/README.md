# Metrics Server

This directory contains the Kubernetes metrics-server deployment configuration for the cluster.

## What is Metrics Server?

The metrics-server provides:
- Resource usage metrics for nodes and pods
- Support for `kubectl top nodes` and `kubectl top pods` commands
- Metrics for Horizontal Pod Autoscaler (HPA)
- CPU and memory utilization data for monitoring

## Configuration

The metrics-server is configured specifically for Talos Linux with:
- `--kubelet-insecure-tls`: Required for Talos nodes without CA certificates
- Resource limits to prevent resource starvation
- Security context following best practices
- System-critical priority class

## Deployment

### Standalone Deployment (Recommended)
The metrics-server must be deployed in the `kube-system` namespace and is deployed separately from the monitoring stack:

```bash
# Deploy metrics-server
kubectl apply -f monitoring/metrics-server.yaml

# Or use the deployment script
./scripts/deploy-metrics-server.sh deploy
```

### With Monitoring Stack
The metrics-server is not included in the monitoring kustomization due to namespace requirements:
```bash
# Deploy monitoring stack (excludes metrics-server)
kubectl apply -k monitoring/

# Deploy metrics-server separately
kubectl apply -f monitoring/metrics-server.yaml
```

## Verification

After deployment, verify metrics-server is working:

```bash
# Check pod status
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Test metrics API
kubectl top nodes
kubectl top pods -A

# Check metrics-server logs
kubectl logs -n kube-system -l k8s-app=metrics-server
```

## Troubleshooting

### Common Issues

1. **Metrics not available**: Wait 1-2 minutes after deployment for metrics to populate
2. **TLS errors**: Ensure `--kubelet-insecure-tls` is set for Talos nodes
3. **Permission errors**: Verify RBAC resources are created

### Useful Commands

```bash
# Check APIService registration
kubectl get apiservices v1beta1.metrics.k8s.io

# View metrics-server configuration
kubectl describe deployment metrics-server -n kube-system

# Test direct API access
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes"
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods"
```

## Integration

The metrics-server integrates with:
- **HPA**: Horizontal Pod Autoscaler for automatic scaling
- **VPA**: Vertical Pod Autoscaler for resource recommendations
- **Monitoring**: Provides data for Prometheus/Grafana dashboards
- **kubectl**: Enables `kubectl top` commands

## Resources

- [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Resource Metrics API](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
