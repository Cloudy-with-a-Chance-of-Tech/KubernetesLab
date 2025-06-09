#!/bin/bash
set -euo pipefail

# Install local-path-provisioner for persistent storage on Talos/Raspberry Pi
# This provides dynamic provisioning of local storage for pods

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STORAGE_DIR="${REPO_ROOT}/base/storage"

echo "💾 Installing local-path-provisioner for Talos/Pi cluster..."

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Test cluster access
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cannot access Kubernetes cluster"
    echo "   Make sure kubeconfig is properly configured"
    echo "   Run: ./scripts/bootstrap-cluster.sh first"
    exit 1
fi

echo "✅ Cluster access confirmed"

# Check if local-path-provisioner is already installed
if kubectl get namespace local-path-storage &>/dev/null; then
    echo "⚠️  local-path-provisioner namespace already exists"
    echo "   This may indicate it's already installed"
    
    # Check if deployment exists and is running
    if kubectl get deployment -n local-path-storage local-path-provisioner &>/dev/null; then
        running_pods=$(kubectl get pods -n local-path-storage -l app=local-path-provisioner --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [[ $running_pods -gt 0 ]]; then
            echo "✅ local-path-provisioner is already running ($running_pods pods)"
            echo "   StorageClass status:"
            kubectl get storageclass local-path -o wide 2>/dev/null || echo "   ❌ local-path StorageClass not found"
            exit 0
        else
            echo "⚠️  local-path-provisioner deployment exists but not running"
            echo "   Proceeding with reinstallation..."
        fi
    fi
else
    echo "📦 Installing local-path-provisioner..."
fi

# Apply the local-path-provisioner configuration
echo "🔧 Applying local-path-provisioner manifests..."
if kubectl apply -k "${STORAGE_DIR}"; then
    echo "✅ local-path-provisioner manifests applied"
else
    echo "❌ Failed to apply local-path-provisioner manifests"
    exit 1
fi

# Wait for namespace to be created
echo "⏳ Waiting for namespace to be ready..."
kubectl wait --for=condition=Ready namespace/local-path-storage --timeout=60s

# Wait for deployment to be ready
echo "⏳ Waiting for local-path-provisioner deployment to be ready..."
kubectl wait --for=condition=available deployment/local-path-provisioner -n local-path-storage --timeout=300s

if [[ $? -eq 0 ]]; then
    echo "✅ local-path-provisioner deployment is ready!"
else
    echo "❌ local-path-provisioner deployment failed to become ready"
    echo "   Check status: kubectl get pods -n local-path-storage"
    echo "   Check logs: kubectl logs -n local-path-storage -l app=local-path-provisioner"
    exit 1
fi

# Verify StorageClass
echo "🔍 Verifying StorageClass..."
if kubectl get storageclass local-path &>/dev/null; then
    echo "✅ local-path StorageClass created"
    
    # Check if it's set as default
    is_default=$(kubectl get storageclass local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null || echo "false")
    if [[ "$is_default" == "true" ]]; then
        echo "✅ local-path is set as default StorageClass"
    else
        echo "⚠️  local-path is not set as default StorageClass"
    fi
else
    echo "❌ local-path StorageClass not found"
    exit 1
fi

# Test storage provisioning with a simple PVC
echo "🧪 Testing storage provisioning..."
cat > /tmp/test-pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-path-test
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
EOF

echo "   📝 Creating test PVC..."
kubectl apply -f /tmp/test-pvc.yaml

# Wait for PVC to be bound (it should remain pending until a pod uses it due to WaitForFirstConsumer)
sleep 5
pvc_status=$(kubectl get pvc local-path-test -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [[ "$pvc_status" == "Pending" ]]; then
    echo "✅ Test PVC created and pending (WaitForFirstConsumer mode)"
elif [[ "$pvc_status" == "Bound" ]]; then
    echo "✅ Test PVC created and bound immediately"
else
    echo "⚠️  Test PVC status: $pvc_status"
fi

# Clean up test PVC
echo "   🧹 Cleaning up test PVC..."
kubectl delete -f /tmp/test-pvc.yaml
rm -f /tmp/test-pvc.yaml

# Show final status
echo ""
echo "📊 local-path-provisioner Status:"
echo "   Namespace: local-path-storage"
kubectl get pods -n local-path-storage -l app=local-path-provisioner
echo ""
echo "   StorageClass:"
kubectl get storageclass local-path -o wide
echo ""

echo "✅ local-path-provisioner installation complete!"
echo ""
echo "💡 Usage notes:"
echo "   • Storage path on nodes: /opt/local-path-provisioner"
echo "   • Volume binding mode: WaitForFirstConsumer"
echo "   • Reclaim policy: Delete"
echo "   • Default StorageClass: Yes"
echo ""
echo "🎯 Next steps:"
echo "   • Test with a pod that uses PVC storage"
echo "   • Monitor storage usage: kubectl get pv,pvc --all-namespaces"
echo "   • Check logs if issues: kubectl logs -n local-path-storage -l app=local-path-provisioner"
