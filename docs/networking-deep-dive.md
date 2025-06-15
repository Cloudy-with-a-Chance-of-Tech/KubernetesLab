# Networking Deep Dive - BGP, Cilium, and Load Balancing

*Welcome to the part where we make packets dance through your home lab like they're at a networking conference.*

## The Network Story

When I first started this lab, I made the classic mistake of treating networking as an afterthought. "I'll just use NodePort services," I thought, "how hard can it be?" Three months later, after manually updating countless port mappings and dealing with the inevitable port conflicts, I decided to do networking properly.

The result is a networking stack that would make enterprise engineers jealous - BGP load balancing, microsegmentation, and observability that actually tells you what's happening when things go wrong.

## Architecture Overview

Let's start with the big picture:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Home Network                                 │
│                                                                 │
│  ┌─────────────────┐           ┌─────────────────┐             │
│  │   pfSense       │           │   Client        │             │
│  │   Router        │           │   Devices       │             │
│  │   - BGP         │           │   - Phones      │             │
│  │   - ECMP        │    ┌──────┤   - Laptops     │             │
│  │   - Firewall    │    │      │   - IoT         │             │
│  └─────────────────┘    │      └─────────────────┘             │
│           │              │                                      │
│           │              │ Traffic Flow                         │
│           │              │                                      │
│  ┌────────┴──────────────┴─────────────────────────────────────┐ │
│  │                    Kubernetes Cluster                       │ │
│  │                                                             │ │
│  │ ┌─────────────────────────────────────────────────────────┐ │ │
│  │ │                   Cilium CNI                            │ │ │
│  │ │                                                         │ │ │
│  │ │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │ │ │
│  │ │  │   Node 1    │  │   Node 2    │  │   Node 3    │    │ │ │
│  │ │  │             │  │             │  │             │    │ │ │
│  │ │  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │    │ │ │
│  │ │  │ │Pod A    │ │  │ │Pod B    │ │  │ │Pod C    │ │    │ │ │
│  │ │  │ │Service  │ │  │ │Service  │ │  │ │Service  │ │    │ │ │
│  │ │  │ │IP: X.X  │ │  │ │IP: Y.Y  │ │  │ │IP: Z.Z  │ │    │ │ │
│  │ │  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │    │ │ │
│  │ │  └─────────────┘  └─────────────┘  └─────────────┘    │ │ │
│  │ │                                                         │ │ │
│  │ │  BGP Advertisements ↑                                   │ │ │
│  │ │  Service IPs: X.X, Y.Y, Z.Z                           │ │ │
│  │ └─────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## The Magic of BGP Load Balancing

### Traditional Approach (What We Avoid)

```
Client Request → Router → NodePort (32000) → Node → Service → Pod
                                 ↓
                        Manual port management
                        Port conflicts
                        No health checking
                        Single point of failure
```

### BGP Approach (What We Use)

```
Client Request → Router → Service IP (Direct) → Healthy Pod
                    ↓
              BGP Route Table
              - 192.168.1.100 → Node1, Node2, Node3
              - 192.168.1.101 → Node2, Node3
              - 192.168.1.102 → Node1, Node3
              Auto-updated based on pod health
```

### How BGP Integration Works

When you create a LoadBalancer service in Kubernetes, here's what happens:

1. **Service Creation**
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: my-web-app
   spec:
     type: LoadBalancer
     selector:
       app: web-app
     ports:
     - port: 80
       targetPort: 8080
   ```

2. **Cilium Allocates IP**
   ```bash
   # Cilium picks an IP from the configured pool
   ALLOCATED_IP="192.168.1.100"
   
   # Updates service status
   kubectl get svc my-web-app
   NAME         TYPE           EXTERNAL-IP      PORT(S)
   my-web-app   LoadBalancer   192.168.1.100    80:32123/TCP
   ```

3. **BGP Advertisement**
   ```bash
   # Cilium advertises the route to pfSense
   BGP UPDATE:
   - Network: 192.168.1.100/32
   - Next Hop: [Node1_IP, Node2_IP, Node3_IP]
   - Path: Healthy endpoints only
   ```

4. **Router Updates**
   ```bash
   # pfSense installs ECMP routes
   ip route add 192.168.1.100/32 \
     nexthop via 192.168.1.10 \
     nexthop via 192.168.1.11 \
     nexthop via 192.168.1.12
   ```

5. **Traffic Flow**
   ```bash
   # Client request automatically load balanced
   curl http://192.168.1.100
   # → Router chooses healthy node
   # → Node forwards to healthy pod
   # → Response returns same path
   ```

## Cilium Configuration Deep Dive

### BGP Peering Configuration

Here's how we configure Cilium to peer with pfSense:

```yaml
# networking/cilium-bgp-config.yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: homelab-bgp-peering
spec:
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/worker: ""
  virtualRouters:
  - localASN: 64512
    exportPodCIDR: false
    serviceSelector:
      matchExpressions:
      - key: somekey
        operator: NotIn
        values: ['never-used-value']
    neighbors:
    - peerAddress: "192.168.1.1"
      peerASN: 64512
      eBGPMultihop: 1
      connectRetryTimeSeconds: 120
      holdTimeSeconds: 90
      keepAliveTimeSeconds: 30
      gracefulRestart:
        enabled: true
        restartTimeSeconds: 120
```

**What this configuration does:**
- **localASN**: Our cluster's BGP AS number
- **exportPodCIDR**: Whether to advertise pod networks (we don't)
- **serviceSelector**: Which LoadBalancer services to advertise
- **peerAddress**: pfSense router IP
- **peerASN**: Router's BGP AS number
- **eBGPMultihop**: Allows multi-hop BGP (usually 1 for direct connections)

### Service IP Pool Configuration

```yaml
# networking/cilium-service-pool.yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: homelab-pool
spec:
  cidrs:
  - cidr: "192.168.1.100/28"  # 192.168.1.100-192.168.1.115
  serviceSelector:
    matchLabels:
      io.cilium/lb-ipam-ips: pool-homelab
```

**Pool Design Considerations:**
- **Size**: 16 IPs should be enough for home lab services
- **Range**: Outside DHCP range to avoid conflicts
- **Subnet**: Same subnet as nodes for direct routing
- **Future Growth**: Easy to expand by adding more CIDRs

### Network Policies

Cilium's network policies provide microsegmentation at the application layer:

```yaml
# Example: Web tier policy
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: web-tier-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: web
  policyTypes: ["Ingress", "Egress"]
  
  ingress:
  # Allow from load balancer
  - fromEndpoints:
    - matchLabels:
        app: nginx-ingress
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
  
  # Allow from other web pods
  - fromEndpoints:
    - matchLabels:
        tier: web
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
  
  egress:
  # Allow to database tier
  - toEndpoints:
    - matchLabels:
        tier: database
    toPorts:
    - ports:
      - port: "5432"
        protocol: TCP
  
  # Allow to external APIs
  - toFQDNs:
    - matchName: "api.github.com"
  - toFQDNs:
    - matchName: "registry.npmjs.org"
```

**Policy Features:**
- **Layer 7 aware**: Can filter on HTTP methods, paths, headers
- **DNS-based**: Use FQDNs instead of IP addresses
- **Automatic updates**: Policies update as pods scale
- **Observability**: Built-in monitoring and alerting

## pfSense Configuration

### BGP Setup on pfSense

1. **Install OpenBGPD Package**
   ```bash
   # Via pfSense Web UI
   System → Package Manager → Available Packages
   Search: openbgpd
   Install: OpenBGPD
   ```

2. **Configure BGP Settings**
   ```bash
   # Services → OpenBGPD → Settings
   AS Number: 64512
   Router ID: 192.168.1.1
   Networks: (leave empty - we only receive routes)
   
   # Neighbors tab
   Neighbor: 192.168.1.10  # First node IP
   Remote AS: 64512
   Description: K8s Node 1
   
   # Repeat for each node
   ```

3. **Firewall Rules**
   ```bash
   # Allow BGP traffic (port 179)
   Protocol: TCP
   Source: Kubernetes Node Network
   Destination: pfSense IP
   Port: 179
   ```

### Verification Commands

```bash
# Check BGP neighbor status
bgpctl show neighbor

# Check received routes
bgpctl show rib

# Check routing table
netstat -rn | grep 192.168.1.1
```

Expected output:
```bash
$ bgpctl show neighbor
Neighbor                   AS    MsgRcvd    MsgSent  OutQ Up/Down  State/PrfRcvd
192.168.1.10            64512      12345       1234     0 01:23:45      3
192.168.1.11            64512      12346       1235     0 01:23:46      3  
192.168.1.12            64512      12347       1236     0 01:23:47      3

$ bgpctl show rib
flags: * = Valid, > = Selected, I = via IBGP, A = Announced,
       S = Stale, E = Error
flags destination          gateway          lpref   med aspath origin
*>    192.168.1.100/32     192.168.1.10      100     0 i
*>    192.168.1.101/32     192.168.1.11      100     0 i
*>    192.168.1.102/32     192.168.1.12      100     0 i
```

## Load Balancing Behavior

### ECMP (Equal-Cost Multi-Path) Routing

When pfSense receives multiple routes to the same destination, it uses ECMP:

```bash
# pfSense routing table with ECMP
Destination        Gateway            Flags   Refs      Use   Mtu  Netif
192.168.1.100/32   192.168.1.10       UGS        0      123  1500   em0
192.168.1.100/32   192.168.1.11       UGS        0      145  1500   em0
192.168.1.100/32   192.168.1.12       UGS        0      132  1500   em0
```

**Load Balancing Algorithms:**
- **Round Robin**: Cycles through available paths
- **Hash-based**: Uses packet hash for consistent routing
- **Weighted**: Can prefer certain paths (not used in our setup)

### Health Checking

BGP provides automatic health checking:

1. **Pod Failure**: Cilium detects unhealthy pod
2. **Route Withdrawal**: BGP withdraws route for failed node
3. **Router Update**: pfSense removes failed route from table
4. **Traffic Rerouting**: New requests go to healthy nodes only

```bash
# Example: Pod failure on Node 2
# Before failure:
192.168.1.100/32 → [Node1, Node2, Node3]

# After failure:
192.168.1.100/32 → [Node1, Node3]

# Automatic healing when pod recovers:
192.168.1.100/32 → [Node1, Node2, Node3]
```

## Observability and Troubleshooting

### Cilium Observability

```bash
# Check Cilium status
kubectl get ciliumnode -o wide

# Check BGP status
kubectl get ciliumbgppeeringpolicy
kubectl get ciliumbgpadvertisement

# Check endpoint health
kubectl get ciliumendpoint -A

# Check service load balancer status
kubectl get svc -A -o wide
```

### Network Flow Monitoring

Cilium provides incredible network observability:

```bash
# Install hubble (Cilium's observability platform)
cilium hubble enable

# Port forward to hubble relay
kubectl port-forward -n kube-system svc/hubble-relay 4245:80

# Monitor network flows
hubble observe --from-pod production/web-app --to-pod production/database
```

Example output:
```bash
TIMESTAMP             SOURCE                    DESTINATION               TYPE      VERDICT
2024-01-15T10:30:15Z  production/web-app-123    production/database-456   L4        ALLOWED
2024-01-15T10:30:15Z  production/web-app-123    production/database-456   L7        ALLOWED
2024-01-15T10:30:16Z  production/web-app-123    8.8.8.8:53               L4        ALLOWED
2024-01-15T10:30:16Z  production/web-app-123    api.github.com:443       L7        ALLOWED
```

### Debugging Network Issues

**1. Service Not Accessible**
```bash
# Check service has external IP
kubectl get svc my-service
# Should show EXTERNAL-IP, not <pending>

# Check BGP advertisements
kubectl get ciliumbgpadvertisement
# Should show your service IP

# Check pfSense routing table
# Should show route to service IP
```

**2. BGP Peering Issues**
```bash
# Check Cilium BGP status
kubectl logs -n kube-system ds/cilium | grep -i bgp

# Check connectivity to pfSense
kubectl exec -it -n kube-system ds/cilium -- ping 192.168.1.1

# Check BGP port connectivity
kubectl exec -it -n kube-system ds/cilium -- telnet 192.168.1.1 179
```

**3. Network Policy Blocking Traffic**
```bash
# Check if policy is blocking traffic
hubble observe --verdict DENIED

# Check policy configuration
kubectl get cnp -A -o yaml

# Temporarily disable policy for testing
kubectl annotate cnp my-policy policy.cilium.io/disabled=true
```

## Performance Characteristics

### Throughput Benchmarks

Here's what you can expect from this networking setup:

**Single Stream Performance:**
```bash
# Node-to-node (same switch)
iperf3 -c 192.168.1.11
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-10.00  sec  1.10 GBytes   941 Mbits/sec

# Pod-to-pod (same node)
iperf3 -c pod-ip-same-node
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-10.00  sec  1.09 GBytes   939 Mbits/sec

# Pod-to-pod (different nodes)
iperf3 -c pod-ip-different-node
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-10.00  sec  1.08 GBytes   931 Mbits/sec
```

**Multi-Stream Performance:**
```bash
# 4 parallel streams
iperf3 -c 192.168.1.11 -P 4
[SUM]   0.00-10.00  sec  1.09 GBytes   935 Mbits/sec
```

**Latency Measurements:**
```bash
# Local network latency
ping 192.168.1.11
PING 192.168.1.11: 56 data bytes
64 bytes from 192.168.1.11: icmp_seq=0 time=0.234 ms

# Service latency (BGP load balanced)
ping 192.168.1.100
PING 192.168.1.100: 56 data bytes  
64 bytes from 192.168.1.100: icmp_seq=0 time=0.287 ms
```

**Performance Factors:**
- **Hardware**: Gigabit Ethernet limits throughput
- **BGP Overhead**: ~1-2% performance impact
- **Cilium eBPF**: Minimal overhead compared to iptables
- **Network Policies**: ~5-10% overhead when active

### Scaling Characteristics

**Service Scaling:**
- New services get IPs from pool automatically
- BGP advertisements happen within 30 seconds
- pfSense routing table updates immediately
- No manual port management required

**Node Scaling:**
- New nodes automatically peer with pfSense
- BGP sessions establish within 2 minutes
- Load balancing includes new nodes automatically
- No manual router configuration needed

## Advanced Configurations

### Multi-Cluster Networking

If you expand to multiple clusters:

```yaml
# Cluster mesh configuration
apiVersion: cilium.io/v2alpha1
kind: CiliumClusterMesh
metadata:
  name: homelab-mesh
spec:
  clusters:
  - name: cluster-1
    address: 192.168.1.10:2379
  - name: cluster-2
    address: 192.168.2.10:2379
  serviceDiscovery:
    enabled: true
    crossCluster: true
```

### IPv6 Support

Cilium supports dual-stack networking:

```yaml
# IPv6 BGP peering
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
spec:
  virtualRouters:
  - localASN: 64512
    neighbors:
    - peerAddress: "2001:db8::1"  # IPv6 router
      peerASN: 64512
      ipFamily: ipv6
```

### Service Mesh Integration

Enable Cilium service mesh features:

```yaml
# Cilium service mesh
apiVersion: v1
kind: ConfigMap
metadata:
  name: cilium-config
  namespace: kube-system
data:
  enable-envoy-config: "true"
  enable-ingress-controller: "true"
  enable-gateway-api: "true"
```

## Security Considerations

### BGP Security

**Potential Threats:**
- Route hijacking
- BGP session hijacking
- Denial of service attacks

**Mitigation Strategies:**
```yaml
# Use authentication
neighbors:
- peerAddress: "192.168.1.1"
  peerASN: 64512
  password: "<REDACTED_BGP_PASSWORD>"
  
# Limit prefixes
- maxPrefixes: 100
  
# Use route filters
- importFilter: "deny any"
- exportFilter: "permit 192.168.1.0/24"
```

### Network Segmentation

**Implement defense in depth:**
```yaml
# Strict network policies
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
  # No ingress/egress rules = deny all
  # Specific policies then allow required traffic
```

**Monitor for anomalies:**
```bash
# Watch for unusual traffic patterns
hubble observe --verdict DENIED -f

# Monitor BGP sessions
watch kubectl get ciliumbgppeeringpolicy -o wide
```

## Disaster Recovery

### BGP Failure Scenarios

**1. pfSense BGP Daemon Failure**
```bash
# Symptoms: All LoadBalancer services unreachable
# Diagnosis: BGP neighbor down
# Recovery: Restart OpenBGPD service

# On pfSense
service openbgpd restart
```

**2. Cilium BGP Agent Failure**
```bash
# Symptoms: New services don't get external IPs
# Diagnosis: Cilium pods crashlooping
# Recovery: Restart Cilium

kubectl rollout restart daemonset/cilium -n kube-system
```

**3. Network Partition**
```bash
# Symptoms: Some services unreachable from some clients
# Diagnosis: Asymmetric routing
# Recovery: Check network connectivity and BGP sessions
```

### Backup and Recovery

**Configuration Backup:**
```bash
# Export Cilium configurations
kubectl get ciliumbgppeeringpolicy -o yaml > bgp-policies-backup.yaml
kubectl get ciliumloadbalancerippool -o yaml > ip-pools-backup.yaml

# Export pfSense configuration
# System → Configuration → Backup/Restore
```

**Recovery Procedures:**
```bash
# Restore Cilium configuration
kubectl apply -f bgp-policies-backup.yaml
kubectl apply -f ip-pools-backup.yaml

# Verify BGP sessions
kubectl get ciliumbgppeeringpolicy
kubectl logs -n kube-system ds/cilium | grep -i bgp
```

## Future Enhancements

### Planned Improvements

**1. Enhanced Monitoring**
- Prometheus metrics for BGP sessions
- Grafana dashboards for network health
- Alerting for BGP neighbor down events

**2. Advanced Load Balancing**
- Geographic load balancing
- Application-aware routing
- Circuit breaker integration

**3. Security Enhancements**
- mTLS between all services
- Network policy automation
- Threat detection and response

### Experimental Features

**1. eBPF XDP for DDoS Protection**
```yaml
# Experimental: XDP load balancer
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: ddos-protection
spec:
  podSelector:
    matchLabels:
      app: web-server
  ingress:
  - fromCIDR: ["0.0.0.0/0"]
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
        rateLimit:
          requestsPerSecond: 1000
```

**2. Service Mesh Observability**
```yaml
# Experimental: Service mesh metrics
apiVersion: cilium.io/v2
kind: CiliumEnvoyConfig
metadata:
  name: prometheus-metrics
spec:
  services:
  - name: web-service
    listener: web-service-listener
    routes:
    - name: web-service-route
      http:
        match:
        - prefix: "/"
        route:
          cluster: web-service-cluster
        stats:
          enabled: true
```

## Conclusion

This networking setup provides enterprise-grade capabilities at home lab scale. The combination of Cilium's eBPF-powered CNI with BGP load balancing creates a robust, scalable, and observable network infrastructure.

Key benefits:
- **No more NodePort management**: LoadBalancer services just work
- **Automatic load balancing**: Traffic distributes across healthy nodes
- **Deep observability**: See every network flow in real-time
- **Microsegmentation**: Network policies protect your workloads
- **Enterprise patterns**: Same technologies used in production environments

The beauty of this setup is that it scales with your needs. Whether you're running a few services or dozens, the networking layer handles the complexity automatically.

---

*Have questions about BGP configuration? Want to discuss alternative CNI choices? Network engineering is one of my favorite topics - reach out anytime.*
