# CHANGELOG - KubernetesLab

## [Unreleased] - June 2025

### Major Improvements - GitOps Pipeline Hardening

#### 🔧 **Fixed: Deployment Selector Immutability Issues**
- **Problem**: Local-path-provisioner deployment failed due to Kubernetes selector immutability constraints when kustomize tried to add `commonLabels`
- **Solution**: 
  - Separated storage deployment from base kustomization to avoid selector conflicts
  - Maintained centralized label management for other base resources using modern `labels` syntax
  - Updated CI/CD workflow to deploy storage independently: `kubectl apply -k base/storage/`
- **Files Changed**: `base/kustomization.yaml`, `base/storage/kustomization.yaml`, `.github/workflows/gitops-deploy.yml`

#### 🔧 **Fixed: Sudo Permission Denied in CI/CD Pipeline**
- **Problem**: GitHub Actions runners don't have sudo privileges, causing tool installation failures
- **Solution**: 
  - Replaced all system package management with user-local installations
  - kubectl, trivy, kube-score now install to `~/.local/bin`
  - No sudo required for any pipeline operations
- **Files Changed**: `.github/workflows/gitops-deploy.yml`

#### 🔧 **Fixed: Bash Syntax Errors in Workflow**
- **Problem**: Missing `fi` statements in complex shell scripts caused pipeline failures
- **Solution**: Added proper closing statements for all nested if-else blocks
- **Files Changed**: `.github/workflows/gitops-deploy.yml`

#### 🔧 **Fixed: Missing Kustomization Files**
- **Problem**: `kubectl apply -k networking/` failed due to missing kustomization.yaml
- **Solution**: Created proper kustomization for networking configuration including BGP peering and load balancer IP pools
- **Files Changed**: `networking/kustomization.yaml` (new file)

### Security Enhancements

#### 🛡️ **Enhanced Security Context Configuration**
- **Fixed**: Moved `fsGroup` from container-level to pod-level security context in local-path-provisioner
- **Added**: Proper `seccompProfile: RuntimeDefault` for enhanced runtime security
- **Verified**: All deployments run as non-root with proper security constraints

#### 🛡️ **Improved Security Validation Pipeline**
- **Enhanced**: Security-focused linting that blocks on critical issues but allows non-critical warnings
- **Added**: Critical security validation step that prevents deployment with missing security contexts
- **Maintained**: Comprehensive RBAC validation and network policy enforcement

### Infrastructure Improvements

#### 🌐 **Formalized Networking Configuration**
- **Created**: Structured kustomization for networking components
- **Included**: BGP peering configuration with pfSense integration
- **Added**: Load balancer IP pool management for multiple environments
- **Enhanced**: Network policy enforcement with proper labeling

#### 📦 **Modular Storage Architecture**
- **Separated**: Storage provisioner from base infrastructure to avoid conflicts
- **Maintained**: Centralized configuration while preventing selector immutability issues
- **Enhanced**: Storage security with proper user/group configurations

### Developer Experience

#### 🔄 **Enhanced GitOps Workflow**
- **Added**: Comprehensive validation steps with early failure detection
- **Improved**: Deployment verification to confirm resource presence after deployment
- **Enhanced**: Error handling with fallback mechanisms and clear error messages
- **Added**: Progressive deployment strategy with clear stage separation

#### 📚 **Updated Documentation**
- **Updated**: README.md with recent major improvements section
- **Enhanced**: GitHub Actions troubleshooting guide with new scenarios
- **Created**: Comprehensive operations guide for June 2025 updates
- **Updated**: Quick reference with current commands and procedures
- **Added**: Detailed changelog for tracking improvements

### Template System Enhancements

#### 🏗️ **Portable Deployment Improvements**
- **Enhanced**: Cluster detection and template substitution robustness
- **Improved**: Error handling in template processing
- **Added**: Validation steps for generated manifests
- **Maintained**: Security-first approach in all generated configurations

### Files Added/Modified

#### New Files
- `networking/kustomization.yaml` - Networking configuration structure
- `docs/operations-guide-2025.md` - Updated operations procedures
- `CHANGELOG.md` - This changelog

#### Modified Files
- `.github/workflows/gitops-deploy.yml` - Major pipeline improvements
- `base/kustomization.yaml` - Modular approach, updated labels syntax
- `base/storage/local-path-provisioner.yaml` - Security context fixes
- `README.md` - Recent improvements summary
- `PORTABLE_DEPLOYMENT_SUMMARY.md` - Critical fixes documentation
- `docs/github-actions-troubleshooting.md` - New troubleshooting scenarios
- `docs/quick-reference.md` - Updated commands and procedures

### Breaking Changes
- **Storage deployment** must now be applied separately: `kubectl apply -k base/storage/`
- **Networking deployment** now requires kustomization.yaml (automatically created)
- **Tool installation** changed from system-wide to user-local paths in CI/CD

### Migration Notes
- Existing clusters continue working without changes
- New deployments automatically use improved modular architecture
- No manual intervention required for most users

### Testing and Validation
- ✅ All changes tested with comprehensive dry-run validations
- ✅ Security contexts verified across all deployments
- ✅ Pipeline tested end-to-end with various failure scenarios
- ✅ Networking configuration validated with BGP peering
- ✅ Storage provisioner tested with proper selector preservation

---

## Previous Versions

### [2.0.0] - May 2025
- Portable template system implementation
- Cluster-agnostic deployment capability
- Enhanced security configurations
- Comprehensive monitoring and observability

### [1.0.0] - Initial Release
- Base Talos Kubernetes cluster setup
- Cilium CNI with BGP integration
- GitHub Actions runners on ARM64
- Basic monitoring and security configurations

---

*For detailed technical information, see individual component documentation in the `docs/` directory.*
