# Network Segmentation with Cilium BGP: Practical Home Lab Networking

Network segmentation in a home lab teaches you enterprise networking concepts in a safe environment. Here's how I approach it—starting simple and building complexity as you learn.

The goal isn't just to make things work, but to understand *why* they work and how to troubleshoot when they don't.

## Understanding Your Network Layout

Let's start with what we have and why it's designed this way:

- **Cluster network**: `192.168.1.x` (your existing home network)
- **Load balancer network**: `192.168.100.0/24` (managed by pfSense at `192.168.1.99`)
- **BGP ASNs**: Kubernetes (64512) ↔ pfSense (64511)

**Why this separation matters:**
Your cluster needs to expose services to the outside world, but you don't want to consume your main network's IP space. The load balancer network gives you a dedicated pool of IPs that pfSense can route, while keeping your cluster isolated.

Think of it like having a separate network segment for servers in an enterprise—same concept, smaller scale.

## Segmentation Strategies: Choose Your Adventure

### Strategy 1: Environment-Based Segmentation (Start Here)

This is what I recommend for most home labs. It's simple, practical, and teaches you subnet math.

**Split the `/24` into `/27` subnets:**
```
Production:  192.168.100.96-127   (/27, 30 usable IPs)
Development: 192.168.100.128-159  (/27, 30 usable IPs) 
Staging:     192.168.100.160-191  (/27, 30 usable IPs)
Shared:      192.168.100.192-223  (/27, 30 usable IPs)
```

**Why /27 subnets?**
- 32 total IPs per subnet (30 usable after network and broadcast)
- 30 IPs is plenty for most home lab services
- Clean, predictable ranges that are easy to remember
- Leaves room for growth (you could add more environments)

**Implementation with Cilium:**
```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: production-pool
spec:
  cidrs:
  - cidr: "192.168.100.96/27"
  serviceSelector:
    matchLabels:
      environment: production

---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: development-pool
spec:
  cidrs:
  - cidr: "192.168.100.128/27"
  serviceSelector:
    matchLabels:
      environment: development
```

**Using the pools:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  labels:
    environment: production  # This gets an IP from 192.168.100.96-127
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: my-app
```

**Pro tip:** Use consistent labeling across all your resources. If a service is labeled `environment: production`, its deployment, configmaps, and secrets should be too.

### Strategy 2: Multiple /24 Networks (Advanced)

If you have more IP space available or want to learn advanced routing, assign each environment its own /24:

```
Production:  192.168.100.0/24  (254 usable IPs)
Development: 192.168.101.0/24  (254 usable IPs)
Staging:     192.168.102.0/24  (254 usable IPs)
```

**When to use this approach:**
- You have multiple VLANs in your home lab
- You want to learn enterprise-style network segmentation
- You plan to have many services per environment
- You want physical separation at the network layer

**pfSense Configuration Requirements:**
```bash
# Add static routes for the new networks
# In pfSense: System → Routing → Static Routes
Destination: 192.168.101.0/24
Gateway: 192.168.1.101 (your first k8s node)

Destination: 192.168.102.0/24
Gateway: 192.168.1.101 (your first k8s node)
```

**BGP Configuration Update:**
```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: bgp-peering-policy
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  virtualRouters:
  - localASN: 64512
    neighbors:
    - peerAddress: "192.168.1.99"
      peerASN: 64511
    serviceSelector: {}
    advertisedNetworks:
    - "192.168.100.0/24"
    - "192.168.101.0/24"  # Add new networks
    - "192.168.102.0/24"
```

**Trade-offs to consider:**
- **Pros**: True network isolation, enterprise-like setup, room for growth
- **Cons**: More complex routing, requires more IP space, harder to troubleshoot

### Strategy 3: Application-Type Segmentation (Alternative Approach)

Instead of environments, organize by application types. This works well if you have fewer environments but more diverse applications:

```
Web Apps:    192.168.100.192-207  (/28, 14 usable IPs)
APIs:        192.168.100.208-223  (/28, 14 usable IPs)
Databases:   192.168.100.224-239  (/28, 14 usable IPs)
Monitoring:  192.168.100.240-255  (/28, 14 usable IPs)
```

**Why /28 subnets?**
- 16 total IPs per subnet (14 usable)
- Perfect for focused application types
- Easier to implement network policies by application type
- Matches common enterprise segmentation patterns

**Implementation:**
```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: web-apps-pool
spec:
  cidrs:
  - cidr: "192.168.100.192/28"
  serviceSelector:
    matchLabels:
      app-type: web

---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: database-pool
spec:
  cidrs:
  - cidr: "192.168.100.224/28"
  serviceSelector:
    matchLabels:
      app-type: database
```

**Service examples:**
```yaml
# Web application
apiVersion: v1
kind: Service
metadata:
  name: frontend-app
  labels:
    app-type: web
spec:
  type: LoadBalancer
  # Gets IP from 192.168.100.192-207 range

---
# Database service
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  labels:
    app-type: database
spec:
  type: LoadBalancer
  # Gets IP from 192.168.100.224-239 range
```

**When to use this approach:**
- Single environment (like most home labs)
- Clear application architecture boundaries
- Want to learn network policies by application type
- Prefer logical over environmental separation
kind: Service
metadata:
  name: my-api
  labels:
    app.kubernetes.io/component: api  # Gets IP from API pool
spec:
  type: LoadBalancer
  # ... rest of service config
```

### Strategy 4: Namespace-Based Segmentation (Kubernetes-Native)

This approach aligns network segments with Kubernetes namespaces—a natural fit that makes troubleshooting easier:

```
vault:          192.168.100.88-95   (/29, 6 usable IPs)
monitoring:     192.168.100.80-87   (/29, 6 usable IPs)
github-actions: 192.168.100.72-79   (/29, 6 usable IPs)
shared:         192.168.100.64-71   (/29, 6 usable IPs)
```

**Why /29 subnets?**
- 8 total IPs per subnet (6 usable)
- Perfect size for namespace-scoped services
- Most namespaces only need 1-3 load balancer IPs
- Easy mental math (8 IPs per namespace)

**Implementation:**
```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: monitoring-pool
spec:
  cidrs:
  - cidr: "192.168.100.80/29"
  serviceSelector:
    matchExpressions:
    - key: "kubernetes.io/metadata.name"
      operator: In
      values: ["monitoring"]

---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: github-actions-pool
spec:
  cidrs:
  - cidr: "192.168.100.72/29"
  serviceSelector:
    matchExpressions:
    - key: "kubernetes.io/metadata.name"
      operator: In
      values: ["github-actions"]
```

**Benefits of namespace-based segmentation:**
- Intuitive alignment with Kubernetes boundaries
- Easy to track which IPs belong to which namespace
- Simplified network policy creation
- Natural fit for RBAC and resource quotas

## Implementation Guide: Step by Step

### Step 1: Choose Your Strategy

Pick the approach that matches your learning goals:

- **Environment-based** (/27 subnets): Best for traditional dev/staging/prod workflows
- **Multiple /24 networks**: Best for learning enterprise routing and VLAN concepts
- **Application-type** (/28 subnets): Best for microservices architectures
- **Namespace-based** (/29 subnets): Best for Kubernetes-native approaches

**My recommendation:** Start with environment-based segmentation. It's the most practical for home labs and teaches you concepts you'll use professionally.
- **Multiple /24**: Best if you have plenty of IP space
- **Application-type**: Best for microservices architectures
- **Namespace-based**: Best for multi-tenant clusters

### Step 2: Update pfSense Configuration

**BGP Configuration (Required for all strategies):**

1. **Install the FRR package** in pfSense:
   - Go to System → Package Manager → Available Packages
   - Install `frr` package

2. **Configure BGP peering**:
   - Go to Services → FRR → Global Settings
   - Enable FRR and BGP
   - Router ID: `192.168.1.99` (pfSense IP)
   - AS Number: `64511`

3. **Add BGP neighbors** (your Kubernetes nodes):
   ```
   # For each Kubernetes node
   Neighbor: 192.168.1.101  # Control plane node
   Remote AS: 64512
   Neighbor: 192.168.1.102  # Worker node 1
   Remote AS: 64512
   # Add all your nodes...
   ```

**Static Routes (Only for multiple /24 networks):**
If you chose Strategy 2 (multiple /24 networks), add static routes in pfSense:

```bash
# In pfSense: System → Routing → Static Routes
Destination: 192.168.101.0/24
Gateway: Dynamic_Gateway (BGP will handle this)

Destination: 192.168.102.0/24
Gateway: Dynamic_Gateway (BGP will handle this)
```

**Firewall Rules:**
Create rules to allow traffic between your network segments:
- Go to Firewall → Rules → LAN
- Add rules to allow traffic to/from 192.168.100.0/24 (and additional networks)

**Pro tip:** Start with "allow all" rules for testing, then tighten them down once everything works.
   192.168.102.0/24 via BGP
   ```

### Step 3: Create and Apply IP Pool Configuration

Now let's create the actual Cilium configuration. I'll show you the environment-based approach since it's the most practical:

**Create `networking/ip-pools.yaml`:**
```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: production-pool
spec:
  cidrs:
  - cidr: "192.168.100.96/27"
  serviceSelector:
    matchLabels:
      environment: production

---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: development-pool
spec:
  cidrs:
  - cidr: "192.168.100.128/27"
  serviceSelector:
    matchLabels:
      environment: development

---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: staging-pool
spec:
  cidrs:
  - cidr: "192.168.100.160/27"
  serviceSelector:
    matchLabels:
      environment: staging

---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: shared-pool
spec:
  cidrs:
  - cidr: "192.168.100.192/27"
  serviceSelector:
    matchLabels:
      environment: shared
```

**Apply the configuration:**
```bash
kubectl apply -f networking/ip-pools.yaml
```

**Verify the pools are created:**
```bash
kubectl get ciliumloadbalancerippool
# Should show all four pools with their CIDR ranges
```

### Step 4: Label Your Services for Pool Selection

The magic happens in the service labels. Here's how to use them:

**Production service example:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: production-web-app
  labels:
    environment: production  # This selects the production pool
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: web-app
```

**Development service example:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: dev-api-service
  labels:
    environment: development  # This selects the development pool
spec:
  type: LoadBalancer
  ports:
  - port: 443
    targetPort: 8443
  selector:
    app: api-service
```

**Consistent labeling strategy:**
```yaml
# Label everything consistently
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  labels:
    environment: production  # Same label as the service
spec:
  template:
    metadata:
      labels:
        environment: production  # And the pods
        app: web-app
```

### Step 5: Verify Everything Works

**Check IP pool allocation:**
```bash
# See which services got which IPs
kubectl get svc -A -o wide --field-selector spec.type=LoadBalancer

# Should show IPs from the correct ranges based on labels
```

**Check BGP peering status:**
```bash
# Get a Cilium pod name
kubectl get pods -n cilium-system

# Check BGP status
kubectl exec -n cilium-system cilium-xxxxx -- cilium bgp peers
```

**Test connectivity:**
```bash
# From your local machine, test accessing the services
curl http://192.168.100.100  # Should reach a production service
curl http://192.168.100.130  # Should reach a development service
```

**Common troubleshooting commands:**
```bash
# Check if pools are properly configured
kubectl describe ciliumloadbalancerippool production-pool

# Check service events for IP allocation issues
kubectl describe svc your-service-name

# Check BGP route advertisement
kubectl exec -n cilium-system cilium-xxxxx -- cilium bgp routes
```

## Understanding IP Pool Priority

When multiple pools could potentially match a service, Cilium follows these rules:

1. **Most specific selector match** wins
2. **Pool creation time** (older pools have priority)  
3. **Alphabetical order** by pool name (as a tiebreaker)

**Example scenario:**
```yaml
# Pool 1: Very specific
serviceSelector:
  matchLabels:
    environment: production
    app: web-server

# Pool 2: Less specific  
serviceSelector:
  matchLabels:
    environment: production

# A service with both labels will use Pool 1 (more specific)
```

**Pro tip:** Be intentional about your selectors. Overlapping pools can cause confusing behavior where services don't get the IPs you expect.

## Network Policies for Segmented Networks

Network segmentation isn't complete without network policies. Here's how to secure your segmented networks:

### Basic Network Policy Template

**Production environment isolation:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: production-isolation
  namespace: production
spec:
  podSelector: {}  # Apply to all pods in namespace
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: production
    - namespaceSelector:
        matchLabels:
          name: shared  # Allow access from shared services
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: production
    - namespaceSelector:
        matchLabels:
          name: shared
  - to: []  # Allow internet access
    ports:
    - protocol: TCP
      port: 443
    - protocol: UDP
      port: 53
```

### Cross-Environment Communication

Sometimes you need controlled communication between environments:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-access
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web-app
  policyTypes:
  - Ingress
## Troubleshooting Network Segmentation

Here are the most common issues and how to fix them:

### Services Not Getting Expected IPs

**Symptom:** Service gets an IP from the wrong pool or no IP at all.

**Diagnosis:**
```bash
# Check if your service labels match pool selectors
kubectl get svc your-service -o yaml | grep -A 10 labels
kubectl get ciliumloadbalancerippool -o yaml | grep -A 10 serviceSelector

# Check pool capacity
kubectl describe ciliumloadbalancerippool pool-name
```

**Common causes:**
- Label mismatch between service and pool selector
- Pool is full (all IPs allocated)
- Multiple pools matching with unexpected priority

### BGP Peering Issues

**Symptom:** External clients can't reach load balancer IPs.

**Diagnosis:**
```bash
# Check BGP peering status
kubectl exec -n cilium-system cilium-xxxxx -- cilium bgp peers

# Check route advertisement
kubectl exec -n cilium-system cilium-xxxxx -- cilium bgp routes advertised

# Check pfSense BGP status
# In pfSense: Status → FRR → BGP → IPv4
```

**Common fixes:**
- Verify ASN numbers match (64511 for pfSense, 64512 for Kubernetes)
- Check firewall rules allow BGP traffic (TCP port 179)
- Ensure all Kubernetes nodes are configured as BGP neighbors

### Network Policy Blocking Traffic

**Symptom:** Services unreachable despite correct IP allocation.

**Diagnosis:**
```bash
# Check if network policies are blocking traffic
kubectl get networkpolicy -A

# Check Cilium policy verdicts
kubectl exec -n cilium-system cilium-xxxxx -- cilium policy get
```

**Quick test:**
```bash
# Temporarily remove all network policies in a namespace
kubectl delete networkpolicy --all -n problem-namespace
# If traffic works now, the issue is in your network policies
```

## Advanced Segmentation Patterns

### Multi-Cluster Load Balancer Pools

If you expand to multiple clusters, you can coordinate IP allocation:

```yaml
# Cluster 1: Production East
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: production-east-pool
spec:
  cidrs:
  - cidr: "192.168.100.96/28"  # First half of production range

# Cluster 2: Production West  
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: production-west-pool
spec:
  cidrs:
  - cidr: "192.168.100.112/28"  # Second half of production range
```

### VLAN Integration

For advanced home labs with managed switches:

```yaml
# Different pools for different VLANs
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: dmz-pool
spec:
  cidrs:
  - cidr: "192.168.200.0/24"  # DMZ VLAN
  serviceSelector:
    matchLabels:
      network-zone: dmz

---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: internal-pool
spec:
  cidrs:
  - cidr: "192.168.100.0/24"  # Internal VLAN
  serviceSelector:
    matchLabels:
      network-zone: internal
```

## Next Steps: Building on Network Segmentation

Once you have basic segmentation working:

1. **Implement service mesh** (Istio/Linkerd) for application-layer segmentation
2. **Add certificate management** (cert-manager) for TLS everywhere
3. **Deploy ingress controllers** with proper TLS termination
4. **Implement zero-trust networking** with mutual TLS
5. **Add network observability** with Hubble (Cilium's observability layer)

## Learning Resources

### Hands-On Exercises
1. **Set up environment-based segmentation** following this guide
2. **Create network policies** that allow only necessary communication
3. **Test failover scenarios** by taking down BGP peers
4. **Monitor network traffic** with Cilium Hubble
5. **Implement traffic shaping** with Cilium bandwidth management

### Recommended Reading
- [Cilium BGP Documentation](https://docs.cilium.io/en/stable/network/bgp/)
- [Kubernetes Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [pfSense BGP Configuration Guide](https://docs.netgate.com/pfsense/en/latest/packages/frr.html)

### Community Resources
- **Cilium Slack**: Join #bgp channel for BGP-specific questions
- **r/homelab**: Share your network diagrams and get feedback
- **GitHub Issues**: Report bugs and request features for Cilium BGP

---

*Network segmentation is a journey. Start simple, learn the concepts, then gradually add complexity. Every enterprise network you encounter will use these same principles at scale.*

## Migration Strategy

To migrate from your current single pool setup:

1. **Deploy new pools** alongside existing one
2. **Update services gradually** by adding environment labels
3. **Monitor IP allocation** to ensure proper segregation
4. **Remove legacy pool** once all services are migrated

## Troubleshooting

### Service not getting IP from expected pool

```bash
# Check service labels
kubectl get svc <service-name> -o yaml

# Check pool selectors
kubectl get ciliumloadbalancerippool <pool-name> -o yaml

# Check IP pool status
kubectl describe ciliumloadbalancerippool <pool-name>
```

### BGP routes not being advertised

```bash
# Check BGP peering status
kubectl exec -n cilium cilium-xxxxx -- cilium bgp peers

# Check BGP route advertisements
kubectl exec -n cilium cilium-xxxxx -- cilium bgp routes advertised ipv4 unicast
```

## Example Service Configurations

### Production Web Application
```yaml
apiVersion: v1
kind: Service
metadata:
  name: webapp-prod
  namespace: production
  labels:
    environment: production
    app.kubernetes.io/component: web
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: webapp
```

### Development API Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-dev
  namespace: development
  labels:
    environment: development
    app.kubernetes.io/component: api
spec:
  type: LoadBalancer
  ports:
  - port: 443
    targetPort: 8443
  selector:
    app: api
```

This approach gives you fine-grained control over IP allocation while maintaining clear network boundaries between different environments and applications.
