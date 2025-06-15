# Storage Deep Dive - Performance, Persistence, and Pragmatism

*Because nobody wants to explain to their family why the home automation system forgot all their settings because of a "little storage issue."*

## The Storage Journey

Let me start with a confession: my first Kubernetes storage setup was a disaster. I thought "how hard can it be?" and threw some NFS shares at the cluster, configured everything to use ReadWriteMany, and called it a day. Six months later, I was dealing with split-brain scenarios, performance issues that would make a 56k modem look fast, and corruption that made me question my life choices.

This document covers the storage architecture that emerged from those lessons - a hybrid approach that balances performance, reliability, and the unique constraints of running Kubernetes on Raspberry Pi hardware at home.

## Storage Philosophy

Every storage decision in this lab follows three principles:

1. **Performance Matters**: If your database takes 30 seconds to start because of slow storage, you've lost the agility that Kubernetes promises
2. **Data Durability is Non-Negotiable**: Home lab or not, losing data is unacceptable
3. **Complexity Has a Cost**: Elegant solutions beat complex ones, even if they're not "enterprise grade"

## Architecture Overview

Here's the storage stack we've built:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Application Layer                             │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────┐ │
│  │ Stateless   │  │ Database    │  │ Monitoring  │  │ Backup │ │
│  │ Workloads   │  │ Workloads   │  │ (Prometheus)│  │ Jobs   │ │
│  │ (No PVs)    │  │ (Fast PVs)  │  │ (Local PVs) │  │(NFS PVs)│ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └────────┘ │
│         │                 │                 │            │     │
└─────────┼─────────────────┼─────────────────┼────────────┼─────┘
          │                 │                 │            │
          │                 │                 │            │
┌─────────┼─────────────────┼─────────────────┼────────────┼─────┐
│         │        Kubernetes Storage Layer   │            │     │
│         │                 │                 │            │     │
│      No Storage     ┌─────────────┐  ┌─────────────┐  ┌────────┴┐
│                     │ local-path  │  │ local-path  │  │   NFS   │
│                     │ StorageClass│  │ StorageClass│  │   PVs   │
│                     │ (Default)   │  │ (Default)   │  │(Manual) │
│                     └─────────────┘  └─────────────┘  └─────────┘
│                            │                 │            │     │
└────────────────────────────┼─────────────────┼────────────┼─────┘
                             │                 │            │
                             │                 │            │
┌────────────────────────────┼─────────────────┼────────────┼─────┐
│                  Node Storage Layer          │            │     │
│                             │                 │            │     │
│  ┌─────────────┐   ┌────────┴─────┐  ┌────────┴─────┐     │     │
│  │   Node 1    │   │   Node 2     │  │   Node 3     │     │     │
│  │             │   │              │  │              │     │     │
│  │ ┌─────────┐ │   │ ┌──────────┐ │  │ ┌──────────┐ │     │     │
│  │ │ NVMe    │ │   │ │  NVMe    │ │  │ │  NVMe    │ │     │     │
│  │ │ 256GB   │ │   │ │  256GB   │ │  │ │  256GB   │ │     │     │
│  │ │/opt/lpp │ │   │ │ /opt/lpp │ │  │ │ /opt/lpp │ │     │     │
│  │ └─────────┘ │   │ └──────────┘ │  │ └──────────┘ │     │     │
│  └─────────────┘   └──────────────┘  └──────────────┘     │     │
│                                                           │     │
└───────────────────────────────────────────────────────────┼─────┘
                                                            │
                                                            │
┌───────────────────────────────────────────────────────────┼─────┐
│                Network Storage Layer                      │     │
│                                                           │     │
│  ┌─────────────────────────────────────────────────────┐  │     │
│  │              Synology NAS                           │  │     │
│  │                                                     │  │     │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │  │     │
│  │  │   Volume1   │  │   Volume2   │  │   Backups   │ │  │     │
│  │  │   (RAID 1)  │  │   (RAID 1)  │  │   (RAID 1)  │ │  │     │
│  │  │  /k8s-data  │  │ /k8s-backup │  │  /snapshots │ │  │     │
│  │  │  (Active)   │  │ (Archive)   │  │  (DR)       │ │  │     │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │  │     │
│  └─────────────────────────────────────────────────────┘  │     │
│                                                           │     │
│                    Ethernet (1Gbps)                      │     │
└───────────────────────────────────────────────────────────┘     │
                                                                  │
                    ┌─────────────────────────────────────────────┘
                    │
┌───────────────────┴─────────────────────────────────────────────┐
│                  External Backup Layer                          │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐ │
│  │   USB Drive    │    │   Cloud Backup  │    │   Offsite    │ │
│  │   (Weekly)     │    │   (Encrypted)   │    │   (Monthly)  │ │
│  └─────────────────┘    └─────────────────┘    └──────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Local Storage with local-path-provisioner

### Why Local Storage?

When you're running on Raspberry Pi hardware, every millisecond matters. Network storage introduces latency that can make applications feel sluggish, especially databases. Local NVMe storage gives us:

- **Sub-millisecond latency**: Perfect for databases and caches
- **High IOPS**: Essential for random I/O workloads
- **Consistent performance**: No network congestion issues
- **Cost effective**: Use the storage you already have

### How local-path-provisioner Works

```yaml
# What happens when you create a PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-storage
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

**Behind the scenes:**
1. **Scheduler**: Kubernetes scheduler picks a node for the pod
2. **Provisioner**: local-path-provisioner creates directory on that node
3. **Mount**: Directory is bind-mounted into the pod
4. **Cleanup**: Directory is deleted when PVC is deleted

**Actual file system layout:**
```bash
# On each worker node
/opt/local-path-provisioner/
├── pvc-12345678-1234-1234-1234-123456789abc_production_database-storage/
│   ├── lost+found/
│   └── data/                    # Your application data lives here
├── pvc-87654321-4321-4321-4321-cba987654321_monitoring_prometheus-storage/
│   └── wal/                     # Prometheus WAL files
└── pvc-abcdef12-3456-7890-abcd-ef1234567890_development_test-storage/
    └── temp/                    # Temporary test data
```

### Performance Characteristics

Let's talk numbers, because performance claims without data are just marketing:

**Sequential I/O Performance:**
```bash
# Testing with fio on Pi CM4 with NVMe
fio --name=seq-read --rw=read --bs=1M --size=1G --numjobs=1
READ: bw=523MiB/s, iops=523

fio --name=seq-write --rw=write --bs=1M --size=1G --numjobs=1  
WRITE: bw=487MiB/s, iops=487
```

**Random I/O Performance:**
```bash
# 4K random reads (database-like workload)
fio --name=rand-read --rw=randread --bs=4k --size=1G --numjobs=4
READ: bw=89.2MiB/s, iops=22.8k

# 4K random writes (log writes, updates)
fio --name=rand-write --rw=randwrite --bs=4k --size=1G --numjobs=4
WRITE: bw=76.3MiB/s, iops=19.5k
```

**Real-world application performance:**
```bash
# PostgreSQL pgbench results
pgbench -c 10 -j 2 -T 60 database_name
tps = 1,247.382 (average latency = 8.02 ms)

# Redis benchmark
redis-benchmark -h redis-service -p 6379 -q
PING_INLINE: 47,348.49 requests per second
SET: 44,742.73 requests per second
GET: 46,511.63 requests per second
```

**Comparison with network storage:**
```bash
# Same PostgreSQL test over NFS
pgbench -c 10 -j 2 -T 60 database_name
tps = 312.847 (average latency = 31.98 ms)

# Performance difference: 4x faster with local storage
```

### Storage Classes Configuration

We use multiple storage classes for different use cases:

```yaml
# Primary storage class (default)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: false
parameters:
  nodePath: "/opt/local-path-provisioner"
```

**Key configuration decisions:**

**`volumeBindingMode: WaitForFirstConsumer`**
- Delays PV creation until pod is scheduled
- Ensures PV is created on the same node as the pod
- Prevents scheduling conflicts

**`reclaimPolicy: Delete`**
- Automatically cleans up storage when PVC is deleted
- Prevents storage leaks in a dynamic environment
- Can be overridden per-PVC if needed

**`allowVolumeExpansion: false`**
- Local storage can't be expanded online
- Forces thoughtful resource planning
- Can be worked around with backup/restore if needed

### Advanced local-path-provisioner Configuration

For specialized workloads, we can create targeted storage classes:

```yaml
# High-performance storage for databases
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path-ssd
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain  # Keep data for important workloads
parameters:
  nodePath: "/opt/local-path-provisioner"
  helperPod: '{"nodeSelector":{"node-type":"ssd"}}'  # Only use SSD nodes
```

```yaml
# Development storage with different cleanup policy
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path-dev
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
parameters:
  nodePath: "/opt/local-path-provisioner/dev"  # Separate directory
  helperPod: '{"activeDeadlineSeconds":300}'   # Faster cleanup
```

## Network Storage with NFS

### When to Use Network Storage

Local storage is great, but it has limitations:
- **Node affinity**: Pods are tied to specific nodes
- **No redundancy**: Node failure = data loss
- **Backup complexity**: Data is scattered across nodes

Network storage solves these problems at the cost of performance and complexity.

### NFS Configuration

**Synology NAS Setup:**
```bash
# Create shared folders
/volume1/k8s-data          # Active application data
/volume1/k8s-backup        # Backup storage
/volume1/k8s-logs          # Log aggregation

# NFS permissions
- Squash: Map root user to admin
- Security: sys (authentication through system credentials)
- Async: Better performance for bulk operations
- Allow connections from: 192.168.1.0/24
```

**Kubernetes NFS StorageClass:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage
provisioner: nfs.csi.k8s.io
parameters:
  server: synology-nas.local
  share: /volume1/k8s-data
  mountPermissions: "0755"
volumeBindingMode: Immediate
allowVolumeExpansion: true
reclaimPolicy: Retain
```

**Manual NFS PersistentVolumes:**
```yaml
# For critical data that needs explicit control
apiVersion: v1
kind: PersistentVolume
metadata:
  name: backup-storage
spec:
  capacity:
    storage: 100Gi
  accessModes: ["ReadWriteMany"]
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /volume1/k8s-backup
    server: synology-nas.local
  mountOptions:
    - nfsvers=4.1
    - hard
    - intr
    - rsize=1048576
    - wsize=1048576
```

### NFS Performance Optimization

**Mount Options Explained:**
- `nfsvers=4.1`: Use NFSv4.1 for better performance and security
- `hard`: Don't give up on temporary network issues
- `intr`: Allow interruption of hung NFS operations
- `rsize=1048576`: 1MB read buffer size
- `wsize=1048576`: 1MB write buffer size

**Network Optimization:**
```bash
# On NAS: Jumbo frames for better throughput
# Network → General → Enable Jumbo Frame: 9000

# On Kubernetes nodes: Match MTU
sudo ip link set dev eth0 mtu 9000

# Verify performance
dd if=/dev/zero of=/mnt/nfs/test.img bs=1M count=1000
1000+0 records in
1000+0 records out
1048576000 bytes (1.0 GB) copied, 11.2 seconds, 93.6 MB/s
```

### Network Storage Use Cases

**1. Backup and Archive Storage**
```yaml
# Backup job that needs persistent storage
apiVersion: batch/v1
kind: CronJob
metadata:
  name: database-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:14
            command: ["pg_dump"]
            args: ["-h", "postgres", "-U", "backup_user", "-d", "production"]
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: nfs-backup-pvc
          restartPolicy: OnFailure
```

**2. Shared Configuration Storage**
```yaml
# Configuration that multiple pods need to access
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-config
spec:
  accessModes: ["ReadWriteMany"]
  storageClassName: nfs-storage
  resources:
    requests:
      storage: 1Gi
---
# Multiple pods can mount this PVC
apiVersion: apps/v1
kind: Deployment
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: web-app
        volumeMounts:
        - name: config
          mountPath: /etc/config
          readOnly: true
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: shared-config
```

## Storage Patterns and Best Practices

### Stateful Application Patterns

**1. Database with Local Storage**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  template:
    spec:
      containers:
      - name: postgres
        image: postgres:14
        env:
        - name: POSTGRES_DB
          value: "production"
        - name: PGDATA
          value: "/var/lib/postgresql/data/pgdata"
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
  volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: local-path
      resources:
        requests:
          storage: 20Gi
```

**Why StatefulSet?**
- Stable pod names (postgres-0, postgres-1, etc.)
- Ordered deployment and termination
- Stable storage (PVC follows the pod)
- Graceful scaling operations

**2. Cache with Ephemeral Storage**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-cache
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        command: ["redis-server", "--appendonly", "no"]
        volumeMounts:
        - name: redis-data
          mountPath: /data
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: redis-data
        emptyDir:
          sizeLimit: 1Gi
```

**When to use emptyDir:**
- Cache data that can be regenerated
- Temporary processing space
- Session storage
- Fast local storage without persistence

**3. Log Aggregation with Network Storage**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
spec:
  template:
    spec:
      containers:
      - name: fluentd
        image: fluentd:latest
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: log-storage
          mountPath: /fluentd/log
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: log-storage
        persistentVolumeClaim:
          claimName: log-aggregation-pvc
```

### Storage Resource Management

**Resource Quotas for Storage:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: production
spec:
  hard:
    requests.storage: "100Gi"
    persistentvolumeclaims: "10"
    local-path.storageclass.storage.k8s.io/requests.storage: "80Gi"
    nfs-storage.storageclass.storage.k8s.io/requests.storage: "20Gi"
```

**LimitRanges for PVC Sizes:**
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: storage-limits
  namespace: production
spec:
  limits:
  - type: PersistentVolumeClaim
    max:
      storage: 50Gi
    min:
      storage: 1Gi
    default:
      storage: 10Gi
```

### Backup Strategies

**1. Application-Level Backups**
```yaml
# PostgreSQL backup CronJob
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 1 * * *"  # Daily at 1 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:14
            env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
            command:
            - /bin/bash
            - -c
            - |
              BACKUP_FILE="/backup/postgres-$(date +%Y%m%d-%H%M%S).sql"
              pg_dump -h postgres -U postgres production > "$BACKUP_FILE"
              gzip "$BACKUP_FILE"
              
              # Keep only last 7 days
              find /backup -name "postgres-*.sql.gz" -mtime +7 -delete
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
```

**2. Volume Snapshots (Future Enhancement)**
```yaml
# Using CSI volume snapshots (when available)
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot
spec:
  source:
    persistentVolumeClaimName: postgres-storage
  volumeSnapshotClassName: local-path-snapshots
```

**3. File-Level Backups**
```bash
#!/bin/bash
# Backup script for local-path-provisioner data

BACKUP_DIR="/mnt/nfs/backups/kubernetes"
SOURCE_DIR="/opt/local-path-provisioner"
DATE=$(date +%Y%m%d-%H%M%S)

# Create backup with rsync
rsync -av --delete \
  --exclude="lost+found" \
  "$SOURCE_DIR/" \
  "$BACKUP_DIR/local-path-$DATE/"

# Create symlink to latest
ln -sfn "$BACKUP_DIR/local-path-$DATE" "$BACKUP_DIR/latest"

# Clean up old backups (keep 7 days)
find "$BACKUP_DIR" -name "local-path-*" -type d -mtime +7 -exec rm -rf {} \;
```

## Monitoring and Observability

### Storage Metrics

**Key metrics to monitor:**
```yaml
# Prometheus alerting rules for storage
groups:
- name: storage-alerts
  rules:
  - alert: DiskSpaceRunningLow
    expr: (node_filesystem_avail_bytes{mountpoint="/opt/local-path-provisioner"} / node_filesystem_size_bytes{mountpoint="/opt/local-path-provisioner"}) < 0.1
    for: 5m
    annotations:
      summary: "Disk space running low on {{ $labels.instance }}"
      
  - alert: PVCAlmostFull
    expr: kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.1
    for: 10m
    annotations:
      summary: "PVC {{ $labels.persistentvolumeclaim }} almost full"
      
  - alert: HighIOWait
    expr: rate(node_cpu_seconds_total{mode="iowait"}[5m]) > 0.5
    for: 10m
    annotations:
      summary: "High IO wait on {{ $labels.instance }}"
```

**Grafana Dashboard Queries:**
```promql
# Storage usage by node
(
  node_filesystem_size_bytes{mountpoint="/opt/local-path-provisioner"} -
  node_filesystem_avail_bytes{mountpoint="/opt/local-path-provisioner"}
) / node_filesystem_size_bytes{mountpoint="/opt/local-path-provisioner"}

# PVC usage by namespace
sum by (namespace) (kubelet_volume_stats_used_bytes)

# IOPS by node
rate(node_disk_reads_completed_total[5m]) + rate(node_disk_writes_completed_total[5m])

# Storage latency
rate(node_disk_read_time_seconds_total[5m]) / rate(node_disk_reads_completed_total[5m])
```

### Health Checks

**Storage health monitoring:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: storage-health-check
spec:
  containers:
  - name: health-checker
    image: busybox
    command:
    - /bin/sh
    - -c
    - |
      while true; do
        # Test local storage write performance
        dd if=/dev/zero of=/local-test/test.img bs=1M count=100 oflag=direct
        
        # Test NFS connectivity
        touch /nfs-test/health-check
        
        # Sleep for 5 minutes
        sleep 300
      done
    volumeMounts:
    - name: local-test
      mountPath: /local-test
    - name: nfs-test
      mountPath: /nfs-test
  volumes:
  - name: local-test
    persistentVolumeClaim:
      claimName: health-check-local
  - name: nfs-test
    persistentVolumeClaim:
      claimName: health-check-nfs
```

## Troubleshooting Common Issues

### Issue: Pod Stuck in Pending with Storage

**Symptoms:**
```bash
$ kubectl get pods
NAME                    READY   STATUS    RESTARTS   AGE
my-app-5d4b7c8f9-xyz    0/1     Pending   0          5m

$ kubectl describe pod my-app-5d4b7c8f9-xyz
Events:
  Warning  FailedScheduling  pod has unbound immediate PersistentVolumeClaims
```

**Diagnosis:**
```bash
# Check PVC status
kubectl get pvc
NAME              STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
my-app-storage    Pending                                     local-path     5m

# Check available storage on nodes
kubectl get nodes -o custom-columns=NAME:.metadata.name,STORAGE:.status.allocatable.ephemeral-storage
```

**Common causes and solutions:**
1. **No nodes have space**: Scale up or clean up old PVs
2. **Wrong storage class**: Check if storage class exists
3. **Node affinity conflicts**: Verify pod can be scheduled on nodes with storage

### Issue: Poor Storage Performance

**Symptoms:**
```bash
# Application logs showing slow operations
[2024-01-15 10:30:15] WARNING: Database query took 30.2 seconds
[2024-01-15 10:30:45] ERROR: Connection timeout after 30 seconds
```

**Diagnosis:**
```bash
# Check IO statistics
kubectl exec -it postgres-0 -- iostat -x 1 5

# Check for high IO wait
kubectl top nodes

# Check storage latency
kubectl exec -it postgres-0 -- dd if=/dev/zero of=/var/lib/postgresql/data/test.img bs=1M count=100 oflag=direct
```

**Solutions:**
1. **Move to local storage**: Migrate from NFS to local-path
2. **Optimize mount options**: Tune NFS parameters
3. **Add more storage**: Scale out nodes with more storage
4. **Application tuning**: Optimize database configuration

### Issue: Storage Corruption

**Symptoms:**
```bash
# Pod logs showing corruption
[2024-01-15 10:30:15] FATAL: database "production" does not exist
[2024-01-15 10:30:15] ERROR: could not read block 0 in file "base/16384/1247": read only 0 of 8192 bytes
```

**Emergency Response:**
```bash
# 1. Stop the application immediately
kubectl scale deployment my-app --replicas=0

# 2. Create a backup of current state (even if corrupted)
kubectl exec -it my-app-0 -- tar -czf /backup/emergency-$(date +%s).tar.gz /var/lib/postgresql/data

# 3. Check filesystem
kubectl exec -it my-app-0 -- fsck /dev/disk/by-uuid/...

# 4. Restore from last known good backup
kubectl exec -it my-app-0 -- restore-from-backup.sh
```

**Prevention:**
- Regular backups with verification
- Monitoring for storage errors
- Graceful shutdown procedures
- File system consistency checks

### Issue: Node Failure with Local Storage

**Symptoms:**
```bash
$ kubectl get nodes
NAME       STATUS     ROLES    AGE   VERSION
worker-1   NotReady   worker   10d   v1.28.2
worker-2   Ready      worker   10d   v1.28.2
worker-3   Ready      worker   10d   v1.28.2

$ kubectl get pods -o wide | grep worker-1
postgres-0   0/1   Pending   0   5m   <none>   <none>   worker-1
```

**Recovery Procedures:**

**1. For Replaceable Data (caches, logs):**
```bash
# Delete the PVC to allow rescheduling
kubectl delete pvc cache-storage-0

# Scale down and up to recreate
kubectl scale statefulset cache --replicas=0
kubectl scale statefulset cache --replicas=1
```

**2. For Critical Data (databases):**
```bash
# 1. Attempt node recovery first
ssh worker-1 "sudo systemctl status kubelet"

# 2. If node is truly dead, restore from backup
kubectl apply -f restore-job.yaml

# 3. Update application to point to new storage
kubectl patch statefulset postgres -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"worker-2"}}}}}'
```

**3. For High Availability Setup:**
```yaml
# Deploy with anti-affinity to spread across nodes
apiVersion: apps/v1
kind: StatefulSet
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: postgres
            topologyKey: kubernetes.io/hostname
```

## Advanced Storage Patterns

### Multi-Tier Storage

**Hot/Warm/Cold storage strategy:**
```yaml
# Hot storage (local NVMe)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hot-storage
provisioner: rancher.io/local-path
parameters:
  nodePath: "/opt/hot-storage"

# Warm storage (local HDD)  
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: warm-storage
provisioner: rancher.io/local-path
parameters:
  nodePath: "/opt/warm-storage"

# Cold storage (NFS)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cold-storage
provisioner: nfs.csi.k8s.io
parameters:
  server: nas.local
  share: /volume1/cold-storage
```

**Application with tiered storage:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: database-with-tiers
spec:
  template:
    spec:
      containers:
      - name: postgres
        volumeMounts:
        - name: hot-data
          mountPath: /var/lib/postgresql/data
        - name: warm-data
          mountPath: /var/lib/postgresql/archive
        - name: cold-data
          mountPath: /var/lib/postgresql/backup
  volumeClaimTemplates:
  - metadata:
      name: hot-data
    spec:
      storageClassName: hot-storage
      resources:
        requests:
          storage: 20Gi
  - metadata:
      name: warm-data
    spec:
      storageClassName: warm-storage
      resources:
        requests:
          storage: 100Gi
  - metadata:
      name: cold-data
    spec:
      storageClassName: cold-storage
      resources:
        requests:
          storage: 500Gi
```

### Storage Migration

**Live migration from NFS to local storage:**
```bash
#!/bin/bash
# Migration script for zero-downtime storage migration

APP_NAME="my-database"
NAMESPACE="production"
OLD_PVC="database-nfs-storage"
NEW_PVC="database-local-storage"

# 1. Create new PVC with local storage
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $NEW_PVC
  namespace: $NAMESPACE
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 50Gi
EOF

# 2. Create migration job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: storage-migration
  namespace: $NAMESPACE
spec:
  template:
    spec:
      containers:
      - name: migrate
        image: rsync:latest
        command:
        - rsync
        - -av
        - --progress
        - /old-data/
        - /new-data/
        volumeMounts:
        - name: old-storage
          mountPath: /old-data
        - name: new-storage
          mountPath: /new-data
      volumes:
      - name: old-storage
        persistentVolumeClaim:
          claimName: $OLD_PVC
      - name: new-storage
        persistentVolumeClaim:
          claimName: $NEW_PVC
      restartPolicy: Never
EOF

# 3. Wait for migration to complete
kubectl wait --for=condition=complete job/storage-migration -n $NAMESPACE --timeout=3600s

# 4. Update application to use new storage
kubectl patch statefulset $APP_NAME -n $NAMESPACE -p '
{
  "spec": {
    "template": {
      "spec": {
        "volumes": [
          {
            "name": "data",
            "persistentVolumeClaim": {
              "claimName": "'$NEW_PVC'"
            }
          }
        ]
      }
    }
  }
}'

# 5. Clean up old PVC
kubectl delete pvc $OLD_PVC -n $NAMESPACE
```

## Future Enhancements

### Planned Storage Improvements

**1. CSI Driver Integration**
- Implement custom CSI driver for local storage
- Add volume expansion capabilities
- Integrate with external backup systems

**2. Automated Data Management**
- Implement storage lifecycle policies
- Automatic data tiering based on access patterns
- Intelligent backup scheduling

**3. Enhanced Monitoring**
- Real-time storage performance metrics
- Predictive failure detection
- Automated remediation for common issues

### Experimental Features

**1. Distributed Storage**
```yaml
# Experimental: Longhorn for distributed storage
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "2880"
  fromBackup: ""
```

**2. Storage Acceleration**
```yaml
# Experimental: OpenEBS for storage acceleration
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-local
provisioner: openebs.io/local
parameters:
  cas-type: "localpv"
  hostpath: "/opt/openebs"
```

## Conclusion

Storage is the foundation that everything else builds on. Get it wrong, and your entire cluster becomes unreliable. Get it right, and you have a platform that can handle anything you throw at it.

This hybrid approach - local storage for performance, network storage for durability - gives us the best of both worlds. It's not the simplest possible solution, but it's the right solution for running production workloads on home lab hardware.

Key takeaways:
- **Local storage for performance**: NVMe gives you enterprise-grade speed
- **Network storage for durability**: NFS ensures data survives node failures  
- **Monitoring is essential**: You can't manage what you can't measure
- **Backup everything**: Hardware fails, humans make mistakes
- **Plan for growth**: Storage needs tend to expand faster than you expect

Remember: storage is not just about capacity and performance - it's about reliability, observability, and operational simplicity. Every decision should be made with the understanding that at 2 AM when something breaks, you need to be able to fix it quickly and confidently.

---

*Questions about storage architecture? Want to discuss alternative approaches? I love talking about storage systems - it's where the rubber meets the road in infrastructure.*
