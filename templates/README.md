# Template System for Portable Kubernetes Deployments

This directory contains template manifests that can be deployed to any Kubernetes cluster by dynamically detecting cluster configuration and substituting template variables.

## Overview

The template system allows for portable deployments across different Kubernetes clusters with varying:
- DNS domains (e.g., `cluster.local`, `kub-cluster.local`, `my-company.local`)
- Cluster names (e.g., `kubernetes`, `kub`, `prod-cluster`)
- Geographic locations and environments
- Service URLs and endpoints

## How It Works

1. **Cluster Detection**: The `scripts/detect-cluster-info.sh` script automatically detects:
   - Cluster DNS domain from CoreDNS configuration
   - Cluster name from kubectl context
   - Environment (production, development, staging)
   - Region/zone information

2. **Template Substitution**: The `scripts/template-substitution.sh` script:
   - Reads templates from this directory
   - Substitutes template variables with detected values
   - Generates cluster-specific manifests in the `manifests/` directory

3. **CI/CD Integration**: The GitHub Actions workflow automatically:
   - Detects cluster configuration during deployment
   - Generates manifests from templates
   - Deploys the cluster-specific manifests

## Template Variables

The following template variables are available for use in manifests:

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `{{CLUSTER_DOMAIN}}` | Cluster DNS domain | `kub-cluster.local` |
| `{{CLUSTER_NAME}}` | Cluster name | `kub` |
| `{{CLUSTER_REGION}}` | Cluster region/zone | `us-west-2` |
| `{{CLUSTER_ENVIRONMENT}}` | Environment type | `production` |
| `{{CLUSTER_FQDN}}` | Full cluster FQDN | `kub.kub-cluster.local` |
| `{{KUBERNETES_SERVICE_FQDN}}` | Kubernetes service FQDN | `kubernetes.default.svc.kub-cluster.local` |
| `{{GRAFANA_EXTERNAL_URL}}` | Grafana external URL | `http://grafana.kub.local` |
| `{{PROMETHEUS_EXTERNAL_URL}}` | Prometheus external URL | `http://prometheus.kub.local` |
| `{{VAULT_EXTERNAL_URL}}` | Vault external URL | `https://vault.kub.local:8200` |
| `{{TIMESTAMP}}` | Generation timestamp | `2025-06-18T01:58:32Z` |

## Directory Structure

```
templates/
├── monitoring/
│   ├── grafana/
│   │   └── grafana-deployment.yaml      # Grafana with templated URLs
│   └── prometheus/
│       └── prometheus-deployment.yaml   # Prometheus with templated URLs
├── networking/
│   └── cilium-config.yaml               # Cilium configuration with cluster name
└── security/
    └── external-secrets-vault.yaml      # Vault integration with templated server URL
```

## Usage

### Manual Generation

Generate manifests for the current cluster:
```bash
./scripts/template-substitution.sh substitute
```

View what would be generated (dry run):
```bash
./scripts/template-substitution.sh --dry-run substitute
```

List available templates:
```bash
./scripts/template-substitution.sh list-templates
```

### CI/CD Integration

The GitHub Actions workflow automatically:
1. Detects cluster configuration
2. Generates manifests from templates
3. Deploys the generated manifests

This ensures that the same template can be deployed to different clusters with appropriate configuration.

## Creating New Templates

1. Create a new YAML file in the appropriate subdirectory
2. Use template variables where cluster-specific values are needed
3. Test the template with the substitution script

Example template:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-config
  namespace: default
data:
  cluster_domain: "{{CLUSTER_DOMAIN}}"
  cluster_name: "{{CLUSTER_NAME}}"
  grafana_url: "{{GRAFANA_EXTERNAL_URL}}"
  vault_url: "{{VAULT_EXTERNAL_URL}}"
```

## Benefits

- **Portability**: Deploy the same configuration to any cluster
- **Consistency**: Automatic detection prevents configuration errors
- **Security**: No hardcoded credentials or endpoints
- **Maintenance**: Single template maintains multiple deployments
- **CI/CD Ready**: Seamless integration with automated deployments

## Security Considerations

- Templates should not contain sensitive information
- Secrets are managed separately through the CI/CD pipeline
- Template variables are resolved at deployment time
- Generated manifests are ephemeral (not committed to git)
