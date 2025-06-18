# GitHub Actions Troubleshooting Guide

## Common CI/CD Pipeline Issues and Solutions

### Issue: `kubectl: command not found`

**Symptoms:**
- GitHub Actions workflow fails with error: `/tmp/runner/_temp/xxx.sh: line 1: kubectl: command not found`
- Error code 127 in workflow execution

**Root Cause:**
The `azure/setup-kubectl@v3` action may not work properly on self-hosted ARM64 runners or there may be compatibility issues.

**Solution Applied:**
Replaced the action-based kubectl installation with direct binary download:

```yaml
- name: 'Setup kubectl'
  run: |
    # Install kubectl for ARM64
    curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/arm64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    kubectl version --client
```

**Verification Steps:**
```yaml
- name: 'Verify Cluster Connectivity'
  run: |
    # Test kubectl connectivity
    echo "Testing cluster connectivity..."
    kubectl cluster-info
    kubectl get nodes
    echo "✅ Cluster connectivity verified"
```

### Issue: Self-Hosted Runner Architecture Mismatch

**Symptoms:**
- Binary downloads fail with architecture errors
- Actions designed for x86_64 fail on ARM64 runners

**Diagnostic Commands:**
```bash
# Check runner architecture
uname -m    # Should show aarch64 for ARM64

# Check available binaries
curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | \
  jq -r '.assets[] | select(.name | contains("linux")) | .name'
```

**Solution:**
Ensure all binary downloads specify ARM64/aarch64 architecture:
- kubectl: `kubectl_linux_arm64` or `bin/linux/arm64/kubectl`
- kube-score: `kube-score_x.x.x_linux_arm64`
- Other tools: Check releases for `arm64` or `aarch64` variants

### Issue: Cluster Authentication Failures

**Symptoms:**
- `kubectl cluster-info` fails with authentication errors
- "Unable to connect to the server" messages

**Troubleshooting Steps:**

1. **Check KUBECONFIG Environment:**
   ```yaml
   env:
     KUBECONFIG: /tmp/kubeconfig
   ```

2. **Verify Kubeconfig File:**
   ```bash
   # Check if kubeconfig exists and is readable
   ls -la $KUBECONFIG
   kubectl config view
   ```

3. **Test Basic Connectivity:**
   ```bash
   # Test cluster connection
   kubectl cluster-info
   kubectl get nodes
   kubectl get namespaces
   ```

### Issue: GitHub Actions Runner Replacement

**Symptoms:**
- Runner goes offline during deployment
- Jobs fail when runner restarts
- Deployment interruptions

**Solution Pattern:**
The workflow handles runner replacement by:

1. **Completing Critical Operations First:**
   ```yaml
   - name: 'Deploy Base Resources'
     run: kubectl apply -k base/
   ```

2. **Runner Replacement in Background:**
   ```yaml
   - name: 'Deploy Production Applications'
     env:
       RUNNER_TOKEN: ${{ secrets.RUNNER_TOKEN }}
     run: |
       # Deploy new runner first
       kubectl apply -k apps/production/
   ```

3. **Graceful Handling:**
   - Base resources deployed before runner changes
   - New runner picks up subsequent operations
   - Stateless operations can resume

### Issue: Template Substitution Failures

**Symptoms:**
- Variables not replaced in manifests
- Template placeholders remain in deployed resources

**Troubleshooting:**

1. **Check Script Execution:**
   ```bash
   chmod +x scripts/detect-cluster-info.sh scripts/template-substitution.sh
   ```

2. **Verify Environment Variables:**
   ```bash
   # Debug cluster detection
   scripts/detect-cluster-info.sh config env
   
   # Check template processing
   scripts/template-substitution.sh substitute --dry-run
   ```

3. **Validate Generated Manifests:**
   ```bash
   # Check generated files
   find manifests -name "*.yaml" -exec grep -l "{{.*}}" {} \;
   ```

### Issue: Validation Failures

**Symptoms:**
- YAML validation fails
- kube-score reports errors
- kubectl dry-run failures

**Solutions:**

1. **Skip Non-Kubernetes Files:**
   ```bash
   find . -name "*.yaml" | grep -vE "\.github/workflows|base/talos|kustomization\.yaml"
   ```

2. **Handle CRD Dependencies:**
   ```bash
   kubectl apply --dry-run=client --validate=true -f "$file" || {
     echo "Skipping $file - validation failed (likely uses CRDs)"
   }
   ```

3. **Update kube-score Exclusions:**
   ```bash
   ./kube-score score --ignore-test pod-networkpolicy,pod-probes --output-format ci
   ```

### Monitoring and Maintenance

**Regular Health Checks:**
- Monitor workflow execution times
- Check runner resource usage
- Validate kubectl version compatibility
- Test cluster connectivity periodically

**Best Practices:**
1. Pin binary versions for reproducibility
2. Add verification steps after installations
3. Handle runner architecture explicitly
4. Include meaningful error messages
5. Test workflows on representative datasets

### Emergency Procedures

**If Workflow Completely Fails:**
1. Check runner status in GitHub Settings
2. Verify cluster accessibility from runner host
3. Manual deployment fallback:
   ```bash
   kubectl apply -k base/
   kubectl apply -k apps/production/
   ```

**If Runner Goes Offline:**
1. Runner will self-replace during deployment
2. Monitor pod status: `kubectl get pods -n github-actions`
3. Check new runner registration in GitHub

This guide covers the most common GitHub Actions issues in our Kubernetes deployment pipeline and provides tested solutions for each scenario.
