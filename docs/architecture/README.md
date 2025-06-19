# KubernetesLab Architecture Deep Dive

*Welcome to the technical deep dive - this is where we get into the nitty-gritty details that make this lab tick.*

## The Story Behind the Architecture

Every good infrastructure story starts with a problem. Mine was simple: I needed a way to run production-grade workloads at home without breaking the bank or turning my house into a data center. What I ended up with is a hybrid approach that combines the best of cloud-native technologies with the constraints (and benefits) of home lab hardware.

## Architecture Overview

### The Physical Layer

Let's start with what you can actually touch:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Home Network                               │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐  │
│  │   pfSense       │    │   Synology NAS  │    │   Switch     │  │
│  │   Router/FW     │    │   (NFS/Backup)  │    │   (24-port)  │  │
│  └─────────────────┘    └─────────────────┘    └──────────────┘  │
│           │                       │                     │        │
│  ┌────────┴───────────────────────┴─────────────────────┴──────┐ │
│  │                  Kubernetes Cluster                          │ │
│  │                                                               │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │               Control Plane                             │ │ │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐      │ │ │
│  │  │  │ Master-01   │ │ Master-02   │ │ Master-03   │      │ │ │
│  │  │  │ x86_64      │ │ x86_64      │ │ x86_64      │      │ │ │
│  │  │  │ 16GB RAM    │ │ 16GB RAM    │ │ 16GB RAM    │      │ │ │
│  │  │  └─────────────┘ └─────────────┘ └─────────────┘      │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  │                                                               │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │                 Worker Nodes                            │ │ │
│  │  │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌────────┐ │ │ │
│  │  │  │ Worker-01 │ │ Worker-02 │ │ Worker-03 │ │  ...   │ │ │ │
│  │  │  │ Pi CM4    │ │ Pi CM4    │ │ Pi CM4    │ │  ...   │ │ │ │
│  │  │  │ ARM64     │ │ ARM64     │ │ ARM64     │ │  ...   │ │ │ │
│  │  │  │ 8GB RAM   │ │ 8GB RAM   │ │ 8GB RAM   │ │  ...   │ │ │ │
│  │  │  └───────────┘ └───────────┘ └───────────┘ └────────┘ │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### The Software Stack

This is where things get interesting. Every component has been chosen for a specific reason:

#### Operating System: Talos Linux

**Why Talos?** Because traditional Linux distributions on Kubernetes nodes are like bringing a Swiss Army knife to perform surgery - they have too many features you don't need and create too many attack vectors.

**What makes it special:**
- **Immutable**: The OS can't be modified at runtime (no SSH, no shell access)
- **API-Driven**: Everything is managed through APIs, not shell scripts
- **Minimal**: Purpose-built for Kubernetes with minimal attack surface
- **Declarative**: Configuration is declared in YAML, not imperatively managed

**Real-world benefits:**
- No more "works on my machine" - every node is identical
- Zero configuration drift over time
- Automatic security updates without manual intervention
- Impossible to accidentally break by running the wrong command

#### Container Network Interface: Cilium

**Why Cilium?** Because iptables-based networking is showing its age, and eBPF is the future.

**The magic of eBPF:**
```
Traditional Path:           eBPF Path:
User Space                  User Space
    |                           |
Kernel Space                Kernel Space
    |                           |
iptables → netfilter       eBPF → Direct kernel
    |                           |
Network Stack               Network Stack
    |                           |
Hardware                    Hardware
```

**Concrete advantages:**
- **Performance**: 10x faster than iptables for large rule sets
- **Observability**: Deep packet inspection without performance penalty
- **Load Balancing**: Native load balancing with BGP integration
- **Network Policies**: Microsegmentation that actually works
- **Service Mesh**: Built-in service mesh capabilities

#### BGP Integration

Here's where things get really interesting. Instead of relying on external load balancers or cloud provider integration, we use BGP to advertise service IPs directly to the network infrastructure.

```
┌─────────────────┐    BGP Peering    ┌─────────────────┐
│   pfSense       │ ←─────────────────→ │   Cilium        │
│   Router        │                    │   Agent         │
│   - ECMP        │                    │   - Service IPs │
│   - Load Bal    │                    │   - Health Chk  │
└─────────────────┘                    └─────────────────┘
```

**How it works:**
1. Service gets created with LoadBalancer type
2. Cilium allocates an IP from the configured pool
3. Cilium advertises the IP via BGP to pfSense
4. pfSense installs route with ECMP for load balancing
5. Traffic flows directly to healthy pod endpoints

**Why this is better than NodePort:**
- No need to remember port mappings
- Native load balancing at the network level
- Health checking ensures traffic only goes to healthy pods
- Scales without manual intervention

### Storage Architecture

Storage in a home lab is always a compromise between performance, redundancy, and cost. Here's how I've approached it:

#### Local-Path-Provisioner for Hot Storage

**The problem:** Traditional shared storage (NFS, iSCSI) is often the bottleneck in home labs.

**The solution:** Local NVMe storage on worker nodes only with dynamic provisioning.

```yaml
# How it works under the hood
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fast-storage
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
---
# Result: PV created on a worker node where pod gets scheduled
# Path: /var/mnt/local-path-provisioner/{pvc-name}_{namespace}_{pv-name}
# Architecture: DaemonSet runs on worker nodes only (excludes control-plane)
```

**Performance characteristics:**
- **Sequential Read**: ~500MB/s (NVMe on Pi CM4)
- **Sequential Write**: ~400MB/s
- **Random IOPS**: 10,000+ (small block sizes)
- **Latency**: <1ms (local storage)
- **Node Isolation**: Storage provisioning isolated to worker nodes for better architecture separation

**Trade-offs:**
- ✅ High performance for single-node workloads
- ✅ No network overhead
- ✅ Simple to manage
- ❌ No redundancy (node failure = data loss)
- ❌ Pod pinned to specific node

#### NFS for Cold Storage and Backups

For data that needs to survive node failures, we use traditional NFS:

```yaml
# Example: Backup storage that survives node failures
apiVersion: v1
kind: PersistentVolume
metadata:
  name: backup-storage
spec:
  capacity:
    storage: 100Gi
  accessModes: ["ReadWriteMany"]
  nfs:
    path: /volume1/k8s-backups
    server: synology-nas.local
  persistentVolumeReclaimPolicy: Retain
```

### Security Architecture

Security isn't an afterthought - it's baked into every layer:

#### Network Security

**Cilium Network Policies:**
```yaml
# Example: Deny all, allow specific
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: production-isolation
spec:
  podSelector:
    matchLabels:
      app: web-server
  policyTypes: ["Ingress"]
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: load-balancer
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
```

**Why this matters:**
- Default deny means compromised pods can't phone home
- Microsegmentation limits blast radius
- Application-aware policies (Layer 7)
- Automatic policy enforcement

#### Pod Security

Every pod runs with restricted security contexts:

```yaml
# Standard pod security template
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
```

#### RBAC (Role-Based Access Control)

Principle of least privilege applies to everything:

```yaml
# GitHub Actions runner - minimal permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
  # No delete permissions - prevents accidental destruction
```

## Performance Characteristics

### Baseline Metrics

Here's what you can expect from this architecture:

**Cluster Bootstrapping:**
- Full cluster deployment: 15-20 minutes
- Talos boot time: 2-3 minutes per node
- Cilium ready: 3-5 minutes
- First pod scheduled: <1 minute

**Resource Utilization:**
- Control plane overhead: ~2GB RAM per master
- Cilium agent: ~200MB RAM per node
- System pods total: ~1GB RAM per node
- Available for workloads: ~7GB RAM per Pi worker

**Network Performance:**
- Pod-to-pod (same node): 1Gbps+ (limited by network card)
- Pod-to-pod (different nodes): 1Gbps (limited by switch)
- Service-to-pod: 900Mbps+ (BGP load balancing overhead)
- External access: 1Gbps (pfSense routing)

**Storage Performance:**
- Local PV creation: <5 seconds
- NFS mount time: 10-15 seconds
- Local storage throughput: 400MB/s write, 500MB/s read
- NFS throughput: 100MB/s (limited by gigabit network)

### Scaling Characteristics

**Horizontal Pod Autoscaling:**
- Metric collection interval: 15 seconds
- Scale-up decision time: 3 minutes
- Scale-down decision time: 5 minutes
- Pod startup time: 30-60 seconds (depends on image size)

**Node Scaling:**
- Adding a worker node: 10-15 minutes (mostly Talos boot time)
- Node registration: <1 minute after boot
- Pod scheduling: Immediate after node ready

## Monitoring and Observability

### The Three Pillars

**1. Metrics (Prometheus)**
```yaml
# Key metrics we track
- kubernetes_api_server_request_duration_seconds
- container_cpu_usage_seconds_total
- container_memory_working_set_bytes
- cilium_endpoint_state
- node_filesystem_avail_bytes
```

**2. Logs (Built-in Kubernetes Logging)**
```bash
# Centralized log collection
kubectl logs -f deployment/app-name -n production
journalctl -u kubelet -f  # Node-level logs via Talos
```

**3. Traces (Application-Level)**
```yaml
# OpenTelemetry integration for distributed tracing
# (Implemented per application)
```

### Health Checks and Alerts

**Cluster Health:**
- Node status (Ready/NotReady)
- Control plane component health
- Cilium agent connectivity
- BGP peering status

**Application Health:**
- Pod restart count
- Resource utilization trends
- Response time percentiles
- Error rate monitoring

## Disaster Recovery

### Backup Strategy

**What gets backed up:**
1. **Cluster state**: etcd snapshots (automated via Talos)
2. **Application data**: Persistent volumes (via Velero)
3. **Configuration**: Git repository (this repo)
4. **Secrets**: External secrets manager (planned)

**Recovery scenarios:**
- **Single node failure**: Automatic pod rescheduling
- **Control plane failure**: HA masters ensure continuity
- **Total cluster loss**: Rebuild from configuration + restore data

### Testing Disaster Recovery

```bash
# Simulate node failure
sudo shutdown -h now  # On a worker node

# Verify pod rescheduling
kubectl get pods -o wide --watch

# Full cluster recovery test
./scripts/destroy-cluster.sh
./scripts/setup-complete-cluster.sh
# Restore from backups
```

## Common Pitfalls and Solutions

### Issue: Pods Stuck in Pending

**Symptoms:**
```bash
$ kubectl get pods
NAME                    READY   STATUS    RESTARTS   AGE
my-app-5d4b7c8f9-xyz    0/1     Pending   0          5m
```

**Diagnosis:**
```bash
$ kubectl describe pod my-app-5d4b7c8f9-xyz
Events:
  Warning  FailedScheduling  pod has insufficient memory
```

**Common causes:**
1. **Resource constraints**: Increase node resources or decrease pod requests
2. **Node selector issues**: Verify labels match
3. **Taints and tolerations**: Check if pods can be scheduled on available nodes
4. **Storage issues**: Verify storage class and PVC status

### Issue: Service Not Accessible

**Symptoms:**
```bash
$ curl http://my-service.example.com
curl: (7) Failed to connect to my-service.example.com port 80: Connection refused
```

**Diagnosis:**
```bash
$ kubectl get svc my-service
NAME         TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
my-service   LoadBalancer   10.96.123.45    <pending>     80:30123/TCP   10m
```

**Common causes:**
1. **BGP not configured**: Check Cilium BGP policies
2. **pfSense routing**: Verify BGP peering and route advertisement
3. **Network policies**: Check if policies are blocking traffic
4. **Pod not ready**: Verify backend pods are healthy

### Issue: High Memory Usage

**Symptoms:**
```bash
$ kubectl top nodes
NAME        CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
worker-01   2000m        50%    7500Mi          95%
```

**Diagnosis:**
```bash
$ kubectl top pods --sort-by=memory -A
```

**Common causes:**
1. **Memory leaks**: Check application logs and metrics
2. **Misconfigured resource limits**: Review pod specifications
3. **Too many pods per node**: Consider scaling out instead of up

## Next Steps

This architecture is designed to grow with your needs:

### Short-term Enhancements
- **External Secrets Operator**: Integrate with HashiCorp Vault
- **Service Mesh**: Enable Cilium service mesh features
- **Advanced Monitoring**: Add distributed tracing with Jaeger
- **Backup Automation**: Implement Velero for application backups

### Long-term Evolution
- **Multi-cluster Setup**: Federate with cloud Kubernetes clusters
- **GitOps Pipeline**: Full GitOps with ArgoCD or Flux
- **CI/CD Integration**: Enhanced pipeline with security scanning
- **Machine Learning Workloads**: GPU integration for ML/AI workloads

### Hardware Upgrades
- **Faster Networking**: 10Gbps switches and NICs
- **More Storage**: NVMe over Fabrics for shared high-performance storage
- **Additional Nodes**: Scale out compute capacity
- **Dedicated GPU Nodes**: For ML/AI workloads

## Conclusion

This architecture represents the culmination of years of iteration and real-world testing. It's not the simplest possible setup, but it's designed to handle production workloads reliably while maintaining the flexibility and cost-effectiveness that makes home labs special.

The key insight is that modern cloud-native technologies can absolutely run at home scale - you just need to understand the trade-offs and design for your specific constraints. Whether you're running development workloads, home automation, or even small-scale production services, this architecture provides a solid foundation that can grow with your needs.

---

*Have questions about specific architectural decisions? Want to discuss alternative approaches? Reach out - I love talking about infrastructure design.*
