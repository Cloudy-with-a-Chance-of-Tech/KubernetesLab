# GitHub Actions Troubleshooting Guide

## Common CI/CD Pipeline Issues and Solutions

### Issue: GitHub Runner Pod Crashes with Permission Errors

**Symptoms:**
- Runner pod constantly restarting with CrashLoopBackOff status
- Logs show: "Access to the path '/actions-runner/_diag' is denied"
- Logs show: "./config.sh: No such file or directory"
- Logs show: "System.UnauthorizedAccessException"

**Root Causes and Solutions:**

#### 1. Filesystem Permission Issues
**Problem:** `readOnlyRootFilesystem: true` prevents runner from writing configuration files.

**Solution:**
```yaml
# In runner deployment security context
securityContext:
  readOnlyRootFilesystem: false  # Runner needs write access to /actions-runner
```

#### 2. User/Group Mismatch
**Problem:** Running as `nobody` user (65534) instead of runner user (1001).

**Solution:**
```yaml
# Pod-level security context
securityContext:
  runAsUser: 1001      # Match image's runner user
  runAsGroup: 1001     # Match image's runner group  
  fsGroup: 1001        # Ensure proper file ownership

# Container-level security context
containers:
- name: runner
  securityContext:
    runAsUser: 1001
    runAsGroup: 1001
```

#### 3. Volume Mount Masking Binaries
**Problem:** Mounting empty volume over `/actions-runner` hides pre-installed runner software.

**Solution:**
```yaml
# Remove /actions-runner volume mount
volumeMounts:
- name: runner-work
  mountPath: /tmp/runner
- name: tmp  
  mountPath: /tmp
# DO NOT mount: /actions-runner (masks pre-installed binaries)
```

#### 4. Deprecated Runner Version
**Problem:** Using outdated runner image version rejected by GitHub.

**Solution:**
```yaml
# Use latest image version
image: myoung34/github-runner:latest
# Instead of: myoung34/github-runner:2.321.0
```

**Complete Working Configuration:**
```yaml
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        runAsGroup: 1001
        fsGroup: 1001
      containers:
      - name: runner
        image: myoung34/github-runner:latest
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
          runAsUser: 1001
          runAsGroup: 1001
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: runner-work
          mountPath: /tmp/runner
        - name: tmp
          mountPath: /tmp
```

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

### Issue: Runner Session Conflicts

**Symptoms:**
- Pods crash with "Registration c20a62ee-3eee-4641-b42c-921d3653172b was not found"
- Error: "Failed to create a session. The runner registration has been deleted from the server"
- Multiple pods trying to use the same runner name
- CrashLoopBackOff status after pod restarts

**Root Cause:**
GitHub Actions runners register with a specific name, and session conflicts occur when:
1. Multiple pods try to use the same static runner name
2. Pod restarts cause stale registrations to conflict with new sessions
3. Kubernetes replica scaling creates multiple runners with identical names

**Solution: Dynamic Runner Names**
Use Kubernetes pod name as the runner name to ensure uniqueness:

```yaml
env:
- name: RUNNER_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name  # Uses pod name: github-runner-7d85f8c659-lsrjj
```

**Complete Working Configuration:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: github-runner
  namespace: github-actions
spec:
  replicas: 3  # Multiple replicas work without conflicts
  template:
    spec:
      containers:
      - name: runner
        image: myoung34/github-runner:latest
        env:
        - name: RUNNER_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name  # Dynamic name prevents conflicts
        - name: EPHEMERAL
          value: "1"  # Ephemeral runners clean up automatically
```

**Benefits:**
- Each pod gets a unique runner name (e.g., `github-runner-7d85f8c659-lsrjj`)
- No session conflicts between multiple replicas
- Automatic cleanup with ephemeral runners
- Scales seamlessly from 1 to N replicas

**Recovery Process:**
If runners are already in a conflicted state:
1. Delete the deployment to clean up stale registrations:
   ```bash
   kubectl delete deployment github-runner -n github-actions
   ```
2. Wait for cleanup (10-15 seconds)
3. Redeploy with dynamic runner names:
   ```bash
   kubectl apply -f apps/production/github-runner.yaml
   ```

**Verification:**
Check that each pod has a unique runner name:
```bash
# List all runner pods
kubectl get pods -n github-actions

# Check runner name for each pod
kubectl exec <pod-name> -n github-actions -- env | grep RUNNER_NAME
```

Each pod should show a unique name like:
- `RUNNER_NAME=github-runner-7d85f8c659-lsrjj`
- `RUNNER_NAME=github-runner-7d85f8c659-vgptx`
- `RUNNER_NAME=github-runner-7d85f8c659-vrfnx`

### Issue: `sudo: effective uid is not 0` in GitHub Actions

**Symptoms:**
- Workflow fails with error: "sudo: effective uid is not 0, is /usr/bin/sudo on a file system with the 'nosuid' option set or an NFS file system without root privileges?"
- kubectl installation step fails in GitHub Actions workflow
- Process completed with exit code 1

**Root Cause:**
Self-hosted GitHub Actions runners typically run in containers without sudo privileges or with sudo disabled for security reasons.

**Solution:**
Install binaries to user directory instead of system directories:

```yaml
- name: 'Setup kubectl'
  run: |
    # Install kubectl for ARM64 to user directory (no sudo needed)
    curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/arm64/kubectl"
    chmod +x kubectl
    mkdir -p ~/.local/bin
    mv kubectl ~/.local/bin/
    echo "$HOME/.local/bin" >> $GITHUB_PATH
    ~/.local/bin/kubectl version --client
```

**Key Changes:**
- Use `~/.local/bin` instead of `/usr/local/bin`
- Add directory to `$GITHUB_PATH` so subsequent steps can find the binary
- Reference full path initially (`~/.local/bin/kubectl`) until PATH is updated

**Alternative System-Wide Approach (if sudo is available):**
```yaml
# Only if your runner has sudo configured
- name: 'Setup kubectl with sudo'
  run: |
    curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/arm64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    kubectl version --client
```

This pattern works for any binary installation in GitHub Actions runners without sudo access.

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
