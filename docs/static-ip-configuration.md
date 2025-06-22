# Static IP Configuration for Monitoring and Networking Services

## 📋 Static IP Address Assignments

The following services are configured with static LoadBalancer IP addresses for consistent external access:

| Service | Namespace | Static IP | Port | URL |
|---------|-----------|-----------|------|-----|
| Hubble UI | `cilium` | `192.168.100.99` | `80` | `http://192.168.100.99` |
| Prometheus | `monitoring` | `192.168.100.100` | `9090` | `http://192.168.100.100:9090` |
| Grafana | `monitoring` | `192.168.100.101` | `3000` | `http://192.168.100.101:3000` |

## 🔧 Configuration Details

### LoadBalancer IP Configuration

Static IP addresses are configured using the `loadBalancerIP` field in the service specifications:

```yaml
spec:
  type: LoadBalancer
  loadBalancerIP: "192.168.100.xxx"
  ports:
    - name: http
      port: xxxx
      targetPort: xxxx
      protocol: TCP
  selector:
    app.kubernetes.io/name: service-name
```

### Network Requirements

**Important**: Your LoadBalancer implementation must support static IP assignment:

1. **MetalLB**: Configure address pool to include the 192.168.100.99-101 range
2. **Cloud Provider**: Ensure IPs are available in your subnet/VPC
3. **pfSense BGP**: Update BGP advertisements if needed for the IP range

### Configuration Files Updated

**Main Configurations**:
- `networking/cilium/hubble-ui.yaml` - Hubble UI static IP
- `monitoring/prometheus/prometheus-deployment.yaml` - Prometheus static IP  
- `monitoring/grafana/grafana-deployment.yaml` - Grafana static IP

**Template Configurations**:
- `templates/networking/cilium/hubble-ui.yaml` - Template for multi-cluster
- `templates/monitoring/prometheus/prometheus-deployment.yaml` - Template for multi-cluster
- `templates/monitoring/grafana/grafana-deployment.yaml` - Template for multi-cluster

## 🔍 Verification Commands

### Check Static IP Configuration

```bash
# Verify static IP assignments in service specs
kubectl get service hubble-ui -n cilium -o jsonpath='{.spec.loadBalancerIP}'
kubectl get service prometheus -n monitoring -o jsonpath='{.spec.loadBalancerIP}'
kubectl get service grafana -n monitoring -o jsonpath='{.spec.loadBalancerIP}'
```

### Check Service Status

```bash
# Check all LoadBalancer services
kubectl get services --all-namespaces -o wide | grep LoadBalancer

# Check specific service status
kubectl get service hubble-ui -n cilium
kubectl get service prometheus -n monitoring  
kubectl get service grafana -n monitoring
```

### Test External Access

```bash
# Test connectivity (after deployment)
curl -I http://192.168.100.99        # Hubble UI
curl -I http://192.168.100.100:9090  # Prometheus
curl -I http://192.168.100.101:3000  # Grafana
```

## 🛡️ Security Considerations

### Network Access Control

1. **Firewall Rules**: Configure firewall to allow access from trusted networks only
2. **Network Policies**: Consider implementing Kubernetes NetworkPolicies for additional security
3. **Authentication**: Ensure Grafana authentication is properly configured
4. **TLS**: Consider adding TLS termination for production environments

### IP Range Management

- **Reserved Range**: 192.168.100.99-101 is now reserved for these services
- **Documentation**: Update network documentation to reflect static assignments
- **Conflict Prevention**: Ensure no other services use these IPs

## 🚀 Deployment

### CI/CD Pipeline Deployment

The static IP configuration will be automatically deployed when the CI/CD pipeline runs:

1. **Validation**: Pipeline validates service configurations
2. **Deployment**: Services are created/updated with static IPs
3. **Verification**: LoadBalancer assigns the specified static IPs

### Manual Verification Post-Deployment

```bash
# 1. Check services are running with static IPs
kubectl get svc -n cilium hubble-ui
kubectl get svc -n monitoring prometheus grafana

# 2. Verify external connectivity
ping 192.168.100.99
ping 192.168.100.100  
ping 192.168.100.101

# 3. Test web interfaces
curl http://192.168.100.99
curl http://192.168.100.100:9090
curl http://192.168.100.101:3000
```

## 🔧 Troubleshooting

### Static IP Not Assigned

1. **Check LoadBalancer Implementation**: Ensure MetalLB or cloud LB supports static IPs
2. **IP Range Configuration**: Verify IP range includes 192.168.100.99-101
3. **IP Conflicts**: Check no other services are using these IPs
4. **Service Status**: Check service events for assignment errors

```bash
kubectl describe service hubble-ui -n cilium
kubectl describe service prometheus -n monitoring
kubectl describe service grafana -n monitoring
```

### Connectivity Issues

1. **Service Status**: Ensure services are running and healthy
2. **Network Routing**: Verify network routes to 192.168.100.x range
3. **Firewall Rules**: Check firewall allows traffic to these IPs
4. **DNS Resolution**: Update DNS if using hostnames

---

**Note**: This configuration provides consistent, predictable access to monitoring and networking services through static IP addresses, improving operational reliability and simplifying network configuration.
