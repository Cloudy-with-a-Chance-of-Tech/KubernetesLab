# Practical Operations Guide - Day-to-Day Cluster Management

*Because running Kubernetes is 10% initial setup and 90% keeping it running smoothly.*

## The Operations Story

After six months of running this cluster, I've learned that the real work begins after the initial deployment. This isn't a "set it and forget it" infrastructure - it's a living system that needs regular care, feeding, and the occasional stern talking-to when it misbehaves.

This guide covers the practical, day-to-day operations that keep the cluster healthy and your family happy (because nobody likes explaining why the smart home is "temporarily stupid").

## Daily Operations

### Morning Health Check (5 minutes)

Start every day with a quick cluster health assessment:

```bash
#!/bin/bash
# daily-health-check.sh - Run this every morning with your coffee

echo "=== Kubernetes Cluster Health Check ==="
echo "Date: $(date)"
echo

# Check node status
echo "📊 Node Status:"
kubectl get nodes -o wide
echo

# Check system pods
echo "🔧 System Pods:"
kubectl get pods -n kube-system --field-selector=status.phase!=Running
echo

# Check storage usage
echo "💾 Storage Usage:"
kubectl top nodes --sort-by=storage.available
echo

# Check recent events
echo "⚠️  Recent Warning Events:"
kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.metadata.creationTimestamp' | tail -5
echo

# Check GitHub runners
echo "🏃 GitHub Runners:"
kubectl get pods -n github-actions -o wide
echo

# Check Vault status
echo "🔐 Vault Status:"
kubectl get pods -n vault -o wide
echo

# Quick Vault health check
if kubectl get pod -n vault -l app.kubernetes.io/name=vault &>/dev/null; then
    VAULT_POD=$(kubectl get pod -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
    echo "Vault Health:"
    kubectl exec -n vault $VAULT_POD -- vault status 2>/dev/null || echo "Vault not accessible"
fi
echo

# Check BGP status (if Cilium is available)
echo "🌐 BGP Status:"
kubectl get ciliumbgppeeringpolicy -o wide 2>/dev/null || echo "Cilium BGP not available"
echo

echo "=== Health Check Complete ==="
```

**What to look for:**
- **All nodes Ready**: Any NotReady nodes need immediate attention
- **System pods running**: kube-system namespace should be clean
- **Storage capacity**: Any node over 80% needs cleanup
- **Warning events**: Investigate anything unusual
- **BGP peering**: Should show Established status

### Quick Smoke Tests

```bash
#!/bin/bash
# smoke-test.sh - Verify core functionality

# Test service resolution
kubectl run test-pod --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes.default

# Test internet connectivity
kubectl run test-pod --image=busybox:1.28 --rm -it --restart=Never -- nslookup google.com

# Test storage provisioning
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF

# Wait and check PVC status
kubectl wait --for=condition=Bound pvc/test-pvc --timeout=60s
kubectl delete pvc test-pvc
```

## Weekly Maintenance

### Storage Cleanup (Every Sunday)

```bash
#!/bin/bash
# weekly-storage-cleanup.sh

echo "🧹 Starting weekly storage cleanup..."

# Clean up completed jobs
kubectl delete jobs --field-selector status.successful=1 --all-namespaces

# Clean up failed jobs older than 7 days
kubectl get jobs --all-namespaces -o go-template='{{range .items}}{{.metadata.namespace}}/{{.metadata.name}} {{.metadata.creationTimestamp}}{{"\n"}}{{end}}' | \
while read namespace_job timestamp; do
    if [[ $(date -d "$timestamp" +%s) -lt $(date -d '7 days ago' +%s) ]]; then
        echo "Deleting old job: $namespace_job"
        kubectl delete job $(echo $namespace_job | tr '/' ' ' | awk '{print "-n " $1 " " $2}')
    fi
done

# Clean up evicted pods
kubectl get pods --all-namespaces --field-selector=status.phase=Failed -o name | xargs -r kubectl delete

# Clean up unused Docker images on nodes
for node in $(kubectl get nodes -o name | cut -d/ -f2); do
    echo "Cleaning up images on $node..."
    kubectl debug node/$node -it --image=busybox -- chroot /host docker image prune -f
done

# Report storage usage
echo "📊 Storage usage after cleanup:"
kubectl top nodes --sort-by=storage.available
```

### Security Updates

```bash
#!/bin/bash
# weekly-security-update.sh

# Update Talos nodes (rolling update)
echo "🔒 Checking for Talos updates..."
talosctl upgrade --image=ghcr.io/siderolabs/talos:latest --wait

# Update container images
echo "🐳 Updating container images..."
kubectl set image deployment/github-runner runner=sumologic/kubernetes-tools:latest -n github-actions
kubectl set image deployment/phoenix-runner runner=sumologic/kubernetes-tools:latest -n github-actions

# Restart deployments to pick up security updates
kubectl rollout restart deployment/github-runner -n github-actions
kubectl rollout restart deployment/phoenix-runner -n github-actions

# Wait for rollouts to complete
kubectl rollout status deployment/github-runner -n github-actions
kubectl rollout status deployment/phoenix-runner -n github-actions
```

### Certificate Management

```bash
#!/bin/bash
# check-certificates.sh

echo "🔐 Checking certificate expiration..."

# Check Kubernetes certificates
for cert in $(find /etc/kubernetes/pki -name "*.crt"); do
    echo "Checking $cert..."
    openssl x509 -in $cert -noout -dates
done

# Check etcd certificates
talosctl get certificates

# Alert if any certificates expire within 30 days
kubectl get certificates --all-namespaces -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,READY:.status.conditions[0].status,EXPIRES:.status.notAfter
```

## Monthly Operations

### Capacity Planning Review

```bash
#!/bin/bash
# monthly-capacity-review.sh

echo "📈 Monthly Capacity Planning Review"
echo "Date: $(date)"
echo

# CPU usage trends
echo "🏃 CPU Usage by Node (30 day average):"
kubectl top nodes --sort-by=cpu
echo

# Memory usage trends  
echo "🧠 Memory Usage by Node (30 day average):"
kubectl top nodes --sort-by=memory
echo

# Storage growth analysis
echo "💾 Storage Growth Analysis:"
for node in $(kubectl get nodes -o name | cut -d/ -f2); do
    echo "Node: $node"
    kubectl describe node $node | grep -A 5 "Allocated resources"
done
echo

# Pod distribution analysis
echo "🏠 Pod Distribution:"
kubectl get pods --all-namespaces -o wide | awk 'NR>1 {nodes[$7]++} END {for (node in nodes) print node ": " nodes[node] " pods"}'
echo

# Resource quotas and limits
echo "🚧 Resource Quotas:"
kubectl get resourcequota --all-namespaces
echo

# Recommendations
echo "💡 Recommendations:"
echo "- Review resource requests and limits"
echo "- Consider scaling if any node consistently >80% utilization"
echo "- Plan for growth based on usage trends"
echo "- Update resource quotas if needed"
```

### Backup Verification

```bash
#!/bin/bash
# monthly-backup-verification.sh

echo "🔍 Monthly Backup Verification"

# Test backup restoration (in staging namespace)
kubectl create namespace backup-test --dry-run=client -o yaml | kubectl apply -f -

# Restore a sample backup
echo "Testing backup restoration..."
kubectl run backup-test \
    --image=postgres:14 \
    --namespace=backup-test \
    --rm -it --restart=Never \
    --command -- psql -h backup-db -U postgres -c "SELECT count(*) FROM pg_database;"

# Clean up test namespace
kubectl delete namespace backup-test

# Verify backup files exist and are recent
echo "📁 Backup file verification:"
ls -la /mnt/nfs/backups/kubernetes/ | head -10

# Check backup file integrity
echo "🔍 Testing backup file integrity:"
gzip -t /mnt/nfs/backups/kubernetes/latest/*.gz && echo "✅ Backup files are valid" || echo "❌ Backup corruption detected"
```

## Incident Response Procedures

### Pod Crashloop Investigation

```bash
#!/bin/bash
# investigate-crashloop.sh <namespace> <pod-name>

NAMESPACE=${1:-default}
POD_NAME=${2:-}

if [ -z "$POD_NAME" ]; then
    echo "Usage: $0 <namespace> <pod-name>"
    exit 1
fi

echo "🔍 Investigating crashloop for $POD_NAME in $NAMESPACE"
echo

# Get pod status
echo "📊 Pod Status:"
kubectl get pod $POD_NAME -n $NAMESPACE -o wide
echo

# Check recent events
echo "📰 Recent Events:"
kubectl describe pod $POD_NAME -n $NAMESPACE | grep -A 10 "Events:"
echo

# Get current logs
echo "📋 Current Logs:"
kubectl logs $POD_NAME -n $NAMESPACE --tail=50
echo

# Get previous logs (if pod restarted)
echo "📋 Previous Logs:"
kubectl logs $POD_NAME -n $NAMESPACE --previous --tail=50 2>/dev/null || echo "No previous logs available"
echo

# Check resource usage
echo "📈 Resource Usage:"
kubectl top pod $POD_NAME -n $NAMESPACE
echo

# Check node resources
NODE=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.nodeName}')
echo "🖥️  Node Resources ($NODE):"
kubectl describe node $NODE | grep -A 5 "Allocated resources"
echo

# Suggested next steps
echo "💡 Suggested Actions:"
echo "1. Check if resource limits are too low"
echo "2. Verify configuration and secrets"
echo "3. Check node disk space and memory"
echo "4. Review application health checks"
echo "5. Check for network connectivity issues"
```

### Service Connectivity Issues

```bash
#!/bin/bash
# debug-service-connectivity.sh <service-name> <namespace>

SERVICE_NAME=${1:-}
NAMESPACE=${2:-default}

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> [namespace]"
    exit 1
fi

echo "🌐 Debugging service connectivity for $SERVICE_NAME"
echo

# Check service exists and has endpoints
echo "🎯 Service Status:"
kubectl get svc $SERVICE_NAME -n $NAMESPACE -o wide
echo

echo "🔗 Service Endpoints:"
kubectl get endpoints $SERVICE_NAME -n $NAMESPACE -o wide
echo

# Check if pods are ready
echo "🚀 Pod Readiness:"
SELECTOR=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.selector}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')
kubectl get pods -n $NAMESPACE -l "$SELECTOR" -o wide
echo

# Test service from within cluster
echo "🧪 Internal Connectivity Test:"
kubectl run debug-pod --image=busybox:1.28 --rm -it --restart=Never -- nslookup $SERVICE_NAME.$NAMESPACE.svc.cluster.local
echo

# Check network policies
echo "🛡️  Network Policies:"
kubectl get networkpolicies -n $NAMESPACE
echo

# Check BGP advertisement (if LoadBalancer)
SERVICE_TYPE=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.type}')
if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
    echo "🌍 BGP Advertisement:"
    kubectl get ciliumbgpadvertisement | grep -E "(NAME|$SERVICE_NAME)"
fi
```

### Node Not Ready Investigation

```bash
#!/bin/bash
# investigate-node-not-ready.sh <node-name>

NODE_NAME=${1:-}

if [ -z "$NODE_NAME" ]; then
    echo "Usage: $0 <node-name>"
    exit 1
fi

echo "🖥️  Investigating NotReady node: $NODE_NAME"
echo

# Check node status and conditions
echo "📊 Node Status:"
kubectl describe node $NODE_NAME | grep -A 20 "Conditions:"
echo

# Check node resource usage
echo "📈 Node Resources:"
kubectl top node $NODE_NAME
echo

# Check system pods on the node
echo "🔧 System Pods on Node:"
kubectl get pods --all-namespaces --field-selector spec.nodeName=$NODE_NAME | grep -E "(kube-system|cilium)"
echo

# Check Talos health
echo "🔍 Talos Health:"
talosctl health --nodes $NODE_NAME
echo

# Check disk space
echo "💾 Disk Space:"
talosctl df --nodes $NODE_NAME
echo

# Check system logs
echo "📋 Recent System Logs:"
talosctl logs --tail 20 --nodes $NODE_NAME kubelet
echo

# Suggested recovery actions
echo "💡 Recovery Actions:"
echo "1. Check if node is physically accessible"
echo "2. Restart kubelet: talosctl restart kubelet --nodes $NODE_NAME"
echo "3. Reboot node: talosctl reboot --nodes $NODE_NAME"
echo "4. Check network connectivity"
echo "5. Verify etcd cluster health"
```

## Performance Optimization

### Resource Right-Sizing

```bash
#!/bin/bash
# resource-right-sizing.sh

echo "📏 Resource Right-Sizing Analysis"
echo

# Find pods with no resource requests
echo "⚠️  Pods without resource requests:"
kubectl get pods --all-namespaces -o json | jq -r '
.items[] | 
select(.spec.containers[].resources.requests == null) |
"\(.metadata.namespace)/\(.metadata.name)"'
echo

# Find overprovisionned pods (using <50% of requests)
echo "💸 Potentially Over-provisioned Pods:"
kubectl top pods --all-namespaces --sort-by=cpu | awk 'NR>1 {print $1"/"$2" CPU:"$3}' | head -10
echo

# Find resource-constrained pods (consistently at limits)
echo "🔥 Resource-Constrained Pods:"
kubectl get events --all-namespaces --field-selector reason=OOMKilled --sort-by='.metadata.creationTimestamp' | tail -5
echo

# Node utilization summary
echo "🎯 Node Utilization Summary:"
kubectl describe nodes | grep -E "(Name:|cpu|memory)" | grep -A 2 "Name:"
```

### Performance Tuning Recommendations

```bash
#!/bin/bash
# performance-tuning-recommendations.sh

echo "🚀 Performance Tuning Recommendations"
echo

# Check for CPU throttling
echo "🌡️  CPU Throttling Analysis:"
kubectl top pods --all-namespaces --sort-by=cpu | head -10
echo

# Memory pressure analysis
echo "🧠 Memory Pressure Analysis:"
kubectl get events --all-namespaces --field-selector reason=MemoryPressure --sort-by='.metadata.creationTimestamp' | tail -5
echo

# Storage I/O analysis
echo "💾 Storage I/O Patterns:"
for node in $(kubectl get nodes -o name | cut -d/ -f2); do
    echo "Node: $node"
    kubectl describe node $node | grep -A 3 "Allocated resources:"
done
echo

# Network performance indicators
echo "🌐 Network Performance Indicators:"
kubectl get pods --all-namespaces -o wide | awk 'NR>1 {nodes[$7]++} END {for (node in nodes) print node ": " nodes[node] " pods"}'
echo

# Recommendations
echo "💡 Performance Recommendations:"
echo "1. Pods using >80% CPU consistently should have limits increased"
echo "2. Pods with OOMKilled events need more memory"
echo "3. Nodes with >20 pods may have scheduling pressure"
echo "4. Consider node affinity for I/O intensive workloads"
echo "5. Use local storage for database workloads"
```

## Automation Scripts

### Automated Healing

```bash
#!/bin/bash
# auto-healing.sh - Run via cron every 5 minutes

# Restart pods that have been crashlooping for >10 minutes
kubectl get pods --all-namespaces -o json | jq -r '
.items[] | 
select(.status.containerStatuses[]?.restartCount > 5) |
select(.status.containerStatuses[]?.state.waiting.reason == "CrashLoopBackOff") |
select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 600) |
"\(.metadata.namespace) \(.metadata.name)"' | \
while read namespace pod; do
    echo "Restarting crashlooping pod: $namespace/$pod"
    kubectl delete pod $pod -n $namespace
done

# Clean up completed jobs older than 1 hour
kubectl get jobs --all-namespaces -o json | jq -r '
.items[] | 
select(.status.conditions[]?.type == "Complete") |
select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 3600) |
"\(.metadata.namespace) \(.metadata.name)"' | \
while read namespace job; do
    echo "Cleaning up completed job: $namespace/$job"
    kubectl delete job $job -n $namespace
done
```

### Health Check Automation

```bash
#!/bin/bash
# health-check-automation.sh - Run via cron every hour

LOG_FILE="/var/log/k8s-health-check.log"

{
    echo "=== Health Check $(date) ==="
    
    # Check cluster health
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "❌ Cluster API not responsive"
        # Send alert via webhook/email
        curl -X POST "https://your-webhook-url" -d '{"text":"Kubernetes cluster API not responsive"}'
    fi
    
    # Check node health
    NOT_READY=$(kubectl get nodes | grep -c NotReady)
    if [ $NOT_READY -gt 0 ]; then
        echo "❌ $NOT_READY nodes not ready"
        # Send alert
    fi
    
    # Check storage usage
    HIGH_STORAGE=$(kubectl top nodes | awk 'NR>1 && $4 > 80 {count++} END {print count+0}')
    if [ $HIGH_STORAGE -gt 0 ]; then
        echo "⚠️  $HIGH_STORAGE nodes with high storage usage"
        # Send warning
    fi
    
    echo "✅ Health check complete"
    echo
} >> $LOG_FILE

# Rotate log file if it gets too large
if [ $(stat -c%s "$LOG_FILE") -gt 10485760 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    touch "$LOG_FILE"
fi
```

## Monitoring and Alerting

### Essential Alerts

```yaml
# prometheus-alerts.yaml
groups:
- name: kubernetes-cluster
  rules:
  - alert: NodeNotReady
    expr: kube_node_status_ready{condition="Ready"} == 0
    for: 5m
    annotations:
      summary: "Node {{ $labels.node }} is not ready"
      
  - alert: PodCrashLooping
    expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
    for: 5m
    annotations:
      summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping"
      
  - alert: HighNodeCPU
    expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 10m
    annotations:
      summary: "High CPU usage on {{ $labels.instance }}"
      
  - alert: HighNodeMemory
    expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
    for: 10m
    annotations:
      summary: "High memory usage on {{ $labels.instance }}"
      
  - alert: DiskSpaceLow
    expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 85
    for: 5m
    annotations:
      summary: "Low disk space on {{ $labels.instance }}"
```

### Custom Dashboards

```json
// grafana-dashboard.json - Kubernetes Cluster Overview
{
  "dashboard": {
    "title": "Kubernetes Cluster Overview",
    "panels": [
      {
        "title": "Node Status",
        "type": "stat",
        "targets": [
          {
            "expr": "kube_node_status_ready{condition=\"Ready\"}"
          }
        ]
      },
      {
        "title": "Pod Status by Namespace",
        "type": "table",
        "targets": [
          {
            "expr": "sum by (namespace) (kube_pod_status_phase{phase=\"Running\"})"
          }
        ]
      },
      {
        "title": "Resource Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
          }
        ]
      }
    ]
  }
}
```

## Disaster Recovery Procedures

### Cluster Backup

```bash
#!/bin/bash
# cluster-backup.sh

BACKUP_DIR="/mnt/nfs/backups/kubernetes/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "🔄 Starting cluster backup to $BACKUP_DIR"

# Backup etcd
echo "📦 Backing up etcd..."
talosctl etcd snapshot "$BACKUP_DIR/etcd-snapshot.db"

# Backup cluster configuration
echo "⚙️  Backing up cluster configuration..."
kubectl get all --all-namespaces -o yaml > "$BACKUP_DIR/all-resources.yaml"
kubectl get pv -o yaml > "$BACKUP_DIR/persistent-volumes.yaml"
kubectl get secrets --all-namespaces -o yaml > "$BACKUP_DIR/secrets.yaml"
kubectl get configmaps --all-namespaces -o yaml > "$BACKUP_DIR/configmaps.yaml"

# Backup Talos configuration
echo "🔧 Backing up Talos configuration..."
cp base/talos/*.yaml "$BACKUP_DIR/"

# Create backup manifest
cat > "$BACKUP_DIR/backup-manifest.txt" << EOF
Kubernetes Cluster Backup
Created: $(date)
Cluster Version: $(kubectl version --short --client)
Nodes: $(kubectl get nodes -o name | wc -l)
Namespaces: $(kubectl get namespaces -o name | wc -l)
PVs: $(kubectl get pv -o name | wc -l)
EOF

echo "✅ Backup complete: $BACKUP_DIR"
```

### Disaster Recovery

```bash
#!/bin/bash
# disaster-recovery.sh

echo "🚨 Starting disaster recovery procedure"
echo "⚠️  This will rebuild the entire cluster!"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Disaster recovery cancelled"
    exit 1
fi

BACKUP_DIR=${1:-/mnt/nfs/backups/kubernetes/latest}

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo "🔄 Rebuilding cluster from backup: $BACKUP_DIR"

# 1. Rebuild cluster infrastructure
echo "🏗️  Rebuilding cluster..."
./scripts/destroy-cluster.sh
./scripts/setup-complete-cluster.sh

# 2. Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s

# 3. Restore etcd from backup
echo "📦 Restoring etcd..."
talosctl etcd restore "$BACKUP_DIR/etcd-snapshot.db"

# 4. Restore configurations
echo "⚙️  Restoring configurations..."
kubectl apply -f "$BACKUP_DIR/configmaps.yaml"
kubectl apply -f "$BACKUP_DIR/secrets.yaml"

# 5. Restore applications
echo "🚀 Restoring applications..."
kubectl apply -f "$BACKUP_DIR/all-resources.yaml"

# 6. Verify recovery
echo "🔍 Verifying recovery..."
kubectl get nodes
kubectl get pods --all-namespaces

echo "✅ Disaster recovery complete"
echo "📋 Manual steps remaining:"
echo "1. Verify all services are accessible"
echo "2. Check data integrity"
echo "3. Test critical workflows"
echo "4. Update monitoring alerts"
```

## Best Practices Summary

### Daily Habits
- Run morning health check
- Monitor cluster resource usage
- Check for failed pods or jobs
- Review security events

## Vault Operations

### Daily Vault Checks

```bash
# Check Vault seal status
scripts/manage-vault.sh status

# Quick health check
curl -s http://192.168.100.102:8200/v1/sys/health | jq

# Check for seal issues
kubectl logs -n vault deployment/vault --tail=50 | grep -i "seal\|error\|warn"
```

### Vault Emergency Procedures

**If Vault becomes sealed:**
```bash
# Check seal status
scripts/manage-vault.sh status

# Unseal if needed (requires unseal key)
scripts/manage-vault.sh unseal

# Or manually
kubectl exec -n vault deployment/vault -- vault operator unseal
```

**Vault Backup (Monthly):**
```bash
# Create backup
scripts/manage-vault.sh backup

# Verify backup exists
ls -la /tmp/vault-backups/
```

### Weekly Vault Maintenance

**Check Vault logs for issues:**
```bash
kubectl logs -n vault deployment/vault --since=168h | grep -E "ERROR|WARN" | tail -20
```

**Verify external access:**
```bash
curl -s http://192.168.100.102:8200/v1/sys/health | jq .initialized
```

**Check network policies:**
```bash
kubectl get ciliumnetworkpolicy -n vault
```

## Maintenance Schedules

### Weekly Routines
- Clean up old resources
- Update container images
- Review capacity trends
- Test backup procedures

### Monthly Tasks
- Security updates and patches
- Capacity planning review
- Disaster recovery testing
- Performance optimization

### Emergency Procedures
- Document all major incidents
- Post-mortem analysis for outages
- Update runbooks based on lessons learned
- Practice disaster recovery regularly

## Conclusion

Running a production Kubernetes cluster at home is an ongoing journey, not a destination. The key to success is establishing good operational habits early and sticking to them consistently.

Remember:
- **Automate the boring stuff**: Health checks, cleanup, and routine maintenance
- **Monitor everything**: You can't fix what you can't see
- **Practice disaster recovery**: When you need it, it's too late to learn it
- **Document your procedures**: Future you will thank present you
- **Keep it simple**: Complex solutions break in complex ways

The most important lesson I've learned: consistency beats perfection. A simple monitoring system that you actually use is worth more than a complex one that you ignore.

---

*Have operational questions? Want to share your own war stories? Operations is where theory meets reality - let's compare notes.*
