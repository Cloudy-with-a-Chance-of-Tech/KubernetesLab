# Monitoring Services External Access Configuration

## 📊 External Access Setup for Prometheus and Grafana

Both Prometheus and Grafana are configured with LoadBalancer services to enable external access from outside the Kubernetes cluster.

### 🔧 Service Configurations

#### Prometheus Service
- **Service Type**: `LoadBalancer`
- **Port**: `9090`
- **Namespace**: `monitoring`
- **Service Name**: `prometheus`

#### Grafana Service  
- **Service Type**: `LoadBalancer`
- **Port**: `3000`
- **Namespace**: `monitoring`
- **Service Name**: `grafana`

### 📁 Configuration Files

The LoadBalancer configuration is maintained in:

1. **Primary Configurations** (deployed by CI/CD):
   - `monitoring/prometheus/prometheus-deployment.yaml`
   - `monitoring/grafana/grafana-deployment.yaml`

2. **Template Configurations** (for multi-cluster deployments):
   - `templates/monitoring/prometheus/prometheus-deployment.yaml`
   - `templates/monitoring/grafana/grafana-deployment.yaml`

### 🌐 External Access

Once deployed via the CI/CD pipeline, the services will be accessible at:

- **Prometheus**: `http://<external-lb-ip>:9090`
- **Grafana**: `http://<external-lb-ip>:3000`

The external IP addresses will be assigned by your cluster's LoadBalancer implementation (e.g., MetalLB, cloud provider LB, etc.).

### 🔍 Verification Commands

After deployment, verify external access with:

```bash
# Check service status and external IPs
kubectl get services -n monitoring

# Get specific external IPs
kubectl get service prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
kubectl get service grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 🛡️ Security Considerations

**Important**: LoadBalancer services expose the monitoring stack to external networks. Consider implementing:

1. **Network Policies**: Restrict traffic to monitoring services
2. **Authentication**: Ensure Grafana authentication is enabled (configured)
3. **Firewall Rules**: Limit access to trusted networks only
4. **TLS**: Consider adding TLS termination for production use

### 🚀 Deployment

These configurations will be automatically deployed when the CI/CD pipeline runs. The pipeline will:

1. Apply monitoring configurations from `monitoring/` directory
2. Create LoadBalancer services for external access
3. Verify service health and accessibility

**Note**: Do not apply these configurations manually - they are designed for automated deployment via the GitOps CI/CD pipeline.
