# Network Segmentation Strategy for Cilium BGP

This document explains how to segment your networks using Cilium Load Balancer IP Pools with BGP peering to pfSense.

## Current Network Layout

- **Cluster network**: `192.168.1.x`
- **Load balancer network**: `192.168.100.0/24` (managed by pfSense at `192.168.1.99`)
- **BGP ASNs**: Kubernetes (64512) ↔ pfSense (64511)

## Segmentation Strategies

### 1. Environment-Based Segmentation (Recommended)

Split the `192.168.100.0/24` network into /27 subnets for different environments:

```
Production:  192.168.100.96-127   (/27, 32 IPs)
Development: 192.168.100.128-159  (/27, 32 IPs) 
Staging:     192.168.100.160-191  (/27, 32 IPs)
Shared:      192.168.100.192-223  (/27, 32 IPs)
```

**Usage Example:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  labels:
    environment: production  # This will get IP from 192.168.100.96-127
spec:
  type: LoadBalancer
  # ... rest of service config
```

### 2. Multiple /24 Networks

If you have more IP space available, assign each environment its own /24:

```
Production:  192.168.100.0/24  (254 IPs)
Development: 192.168.101.0/24  (254 IPs)
Staging:     192.168.102.0/24  (254 IPs)
```

**pfSense Configuration Required:**
- Route `192.168.101.0/24` and `192.168.102.0/24` through pfSense
- Update BGP advertisements to include new networks

### 3. Application-Type Segmentation

Organize by application components rather than environments:

```
Web Apps:   192.168.100.192-207  (/28, 16 IPs)
APIs:       192.168.100.208-223  (/28, 16 IPs)
Databases:  192.168.100.224-239  (/28, 16 IPs)
```

**Usage Example:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-api
  labels:
    app.kubernetes.io/component: api  # Gets IP from API pool
spec:
  type: LoadBalancer
  # ... rest of service config
```

### 4. Namespace-Based Segmentation

Give each namespace its own dedicated IP range:

```
vault:          192.168.100.88-95   (/29, 8 IPs)
monitoring:     192.168.100.80-87   (/29, 8 IPs)
github-actions: 192.168.100.72-79   (/29, 8 IPs)
```

## Implementation Steps

### Step 1: Choose Your Strategy

Select one of the segmentation strategies above based on your requirements:
- **Environment-based**: Best for traditional dev/staging/prod workflows
- **Multiple /24**: Best if you have plenty of IP space
- **Application-type**: Best for microservices architectures
- **Namespace-based**: Best for multi-tenant clusters

### Step 2: Update pfSense Configuration

1. **Configure BGP on pfSense** to peer with Kubernetes:
   - Local ASN: `64511`
   - Remote ASN: `64512` 
   - Neighbor: Kubernetes node IPs (192.168.1.x)

2. **Add static routes** (if using multiple /24 networks):
   ```
   192.168.101.0/24 via BGP
   192.168.102.0/24 via BGP
   ```

### Step 3: Apply IP Pool Configuration

Choose the appropriate configuration:

**For Environment-based (recommended):**
```bash
kubectl apply -f networking/cilium-bgp-config.yaml
```

**For other strategies:**
```bash
# Copy relevant sections from cilium-multi-network-examples.yaml
kubectl apply -f your-custom-config.yaml
```

### Step 4: Label Your Services

Add appropriate labels to your services to select the correct IP pool:

```yaml
# Environment-based
metadata:
  labels:
    environment: production  # or development, staging, shared

# Application-type based  
metadata:
  labels:
    app.kubernetes.io/component: web  # or api, database

# Namespace-based (automatic based on namespace)
# No additional labels needed
```

### Step 5: Verify Configuration

```bash
# Check IP pool status
kubectl get ciliumloadbalancerippool

# Check BGP peering
kubectl exec -n cilium cilium-xxxxx -- cilium bgp peers

# Check service IP allocation
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

## IP Pool Priority

When multiple pools could match a service, Cilium uses this precedence:

1. **Most specific selector match**
2. **Pool creation time** (older pools have priority)
3. **Alphabetical order** by pool name

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
