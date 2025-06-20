#!/bin/bash
# Quick setup script for Talos Kubernetes monitoring and network observability
# Ensures all secrets and configurations are properly applied

set -e

echo "🚀 Talos Kubernetes Cluster - Monitoring & Network Observability Setup"
echo "======================================================================"

# Load environment variables
if [ -f .env ]; then
    echo "📋 Loading environment variables from .env..."
    source .env
else
    echo "❌ Error: .env file not found. Please ensure .env file exists with required variables."
    exit 1
fi

# Function to check if command was successful
check_success() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ Failed: $1"
        exit 1
    fi
}

echo
echo "🔐 Setting up Grafana admin secret..."

# Check if secret exists and has correct value
CURRENT_PASSWORD=$(kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ "$CURRENT_PASSWORD" != "$GRAFANA_ADMIN_PASSWORD" ]; then
    echo "🔄 Creating/updating Grafana admin secret..."
    
    # Delete existing secret if it exists
    kubectl delete secret -n monitoring grafana-admin-secret 2>/dev/null || true
    
    # Create new secret
    kubectl create secret generic grafana-admin-secret -n monitoring \
        --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"
    check_success "Grafana admin secret created"
    
    # Restart Grafana to pick up new secret
    echo "🔄 Restarting Grafana deployment..."
    kubectl rollout restart deployment/grafana -n monitoring
    kubectl rollout status deployment/grafana -n monitoring --timeout=120s
    check_success "Grafana deployment restarted"
else
    echo "✅ Grafana admin secret already configured correctly"
fi

echo
echo "🌐 Validating Hubble network observability..."

# Check Hubble relay connectivity
echo "🔍 Checking Hubble relay logs..."
HUBBLE_LOGS=$(kubectl logs -n cilium deployment/hubble-relay --tail=5 2>/dev/null || echo "")
if echo "$HUBBLE_LOGS" | grep -q "Connected address="; then
    echo "✅ Hubble relay successfully connected to cluster nodes"
else
    echo "⚠️  Hubble relay may need configuration. Check troubleshooting guide."
fi

# Check Hubble UI status
HUBBLE_UI_STATUS=$(kubectl get pods -n cilium -l k8s-app=hubble-ui --no-headers | awk '{print $3}' | head -1)
if [ "$HUBBLE_UI_STATUS" = "Running" ]; then
    echo "✅ Hubble UI is running"
else
    echo "⚠️  Hubble UI status: $HUBBLE_UI_STATUS"
fi

echo
echo "📊 Checking monitoring stack..."

# Check Grafana status
GRAFANA_STATUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers | awk '{print $3}' | head -1)
if [ "$GRAFANA_STATUS" = "Running" ]; then
    echo "✅ Grafana is running"
    
    # Verify environment variables
    ADMIN_USER=$(kubectl exec -n monitoring deployment/grafana -- env | grep GF_SECURITY_ADMIN_USER | cut -d= -f2 2>/dev/null || echo "")
    ADMIN_PASS_SET=$(kubectl exec -n monitoring deployment/grafana -- env | grep GF_SECURITY_ADMIN_PASSWORD | cut -d= -f2 2>/dev/null || echo "")
    
    if [ "$ADMIN_USER" = "admin" ] && [ -n "$ADMIN_PASS_SET" ]; then
        echo "✅ Grafana admin credentials configured correctly"
    else
        echo "⚠️  Grafana admin credentials may need attention"
    fi
else
    echo "⚠️  Grafana status: $GRAFANA_STATUS"
fi

# Check Prometheus status
PROMETHEUS_STATUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | awk '{print $3}' | head -1)
if [ "$PROMETHEUS_STATUS" = "Running" ]; then
    echo "✅ Prometheus is running"
else
    echo "⚠️  Prometheus status: $PROMETHEUS_STATUS"
fi

echo
echo "🔒 Validating security contexts..."

# Check Grafana security context
GRAFANA_USER=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].spec.securityContext.runAsUser}' 2>/dev/null || echo "")
if [ "$GRAFANA_USER" = "472" ]; then
    echo "✅ Grafana security context (Talos compliant)"
else
    echo "⚠️  Grafana security context needs verification"
fi

# Check Prometheus security context  
PROMETHEUS_USER=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].spec.securityContext.runAsUser}' 2>/dev/null || echo "")
if [ "$PROMETHEUS_USER" = "65534" ]; then
    echo "✅ Prometheus security context (Talos compliant)"
else
    echo "⚠️  Prometheus security context needs verification"
fi

echo
echo "📋 Access Information:"
echo "======================"

# Get service information
GRAFANA_IP=$(kubectl get svc -n monitoring grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")
GRAFANA_PORT=$(kubectl get svc -n monitoring grafana -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "3000")

HUBBLE_UI_PORT=$(kubectl get svc -n cilium hubble-ui -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "31235")
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "<node-ip>")

echo "🖥️  Grafana Dashboard:"
echo "   URL: http://$GRAFANA_IP:$GRAFANA_PORT"
echo "   Username: admin"
echo "   Password: $GRAFANA_ADMIN_PASSWORD"
echo ""
echo "🌐 Hubble UI (Network Flows):"
echo "   URL: http://$NODE_IP:$HUBBLE_UI_PORT"
echo "   (Use any cluster node IP)"
echo ""
echo "📈 Prometheus (Internal):"
echo "   URL: http://prometheus.monitoring.svc.kub-cluster.local:9090"
echo "   Port-forward: kubectl port-forward -n monitoring svc/prometheus 9090:9090"

echo
echo "🎉 Setup validation complete!"
echo ""
echo "📚 For troubleshooting, see: docs/talos-troubleshooting-guide.md"
echo "📖 For operations guide, see: docs/operations-guide-2025.md"
