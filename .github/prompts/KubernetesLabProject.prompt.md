# VSCode Copilot Chat Prompt

## Initial Setup Prompt
```
I'm building a production-grade Talos Kubernetes cluster with these specs:

**Infrastructure:**
- 3x x86_64 control plane nodes  
- 6x Raspberry Pi CM4 worker nodes
- Cilium CNI with BGP peering to pfSense (192.168.1.99)
- GitHub Actions CI/CD with self-hosted runner

**Requirements:**
- Security-first: ALL Talos security standards must be met (zero tolerance for warnings)
- Self-replacing runner during deployments
- Dynamic cluster name discovery (non-standard naming)
- Documentation for junior sysadmin level

I need help with [SPECIFIC TASK]. Please provide complete configurations with security explanations and validation steps.
```

## Task-Specific Follow-up Prompts

### For Machine Configs:
```
@workspace Create Talos machine configs for my cluster. I need separate configs for x86_64 masters and Pi CM4 workers with maximum security hardening. Include CNI configuration for Cilium.
```

### For GitHub Actions:
```
@workspace Create a GitHub Actions workflow that deploys to my Talos cluster, a Talos cluster on a cloud provider, or private cloud in a datacenter. The local runner replaces itself during deployment and must handle the dynamic cluster name. Include all security validations. The cloud provider will use the GitHub hosted runner all other deployments will use the self-hosted runner. 
```

### For Cilium BGP:
```
@workspace Configure Cilium with BGP peering to pfSense at 192.168.1.99. Show both the Cilium config and the pfSense BGP setup. Include network policies for security. Cilium is located in the
cilium namespace.
```

### For Documentation:
```
@workspace Generate step-by-step documentation for [SPECIFIC PROCESS]. Write for a junior sysadmin following our security-first approach. Include troubleshooting sections.
```

## MCP GitHub Integration Prompts

### Repository Setup:
```
Using the GitHub MCP server, create a new repository structure for my Talos cluster project. Include:
- .github/workflows/ for CI/CD
- configs/ for Talos machine configs
- docs/ for documentation
- scripts/ for automation
Set up branch protection rules and required status checks.
```

### Issue and Project Management:
```
Create GitHub issues for each phase of the Talos deployment:
1. Machine configuration creation
2. Cilium BGP setup
3. GitHub Actions workflow
4. Security hardening validation
5. Documentation completion
Link them to a project board with proper labels.
```

### Automated PR Creation:
```
When I complete a configuration, use the MCP server to create a PR with:
- Security checklist in the description
- Talos validation results
- Documentation updates
- Automatic reviewer assignment
```

## MCP Action Prompts

### Project Initialization Actions:
```
Action: Set up the complete Talos cluster repository
- Create repo "talos-secure-cluster" with description "Production Talos K8s cluster - Security First"
- Initialize folder structure: configs/, docs/, scripts/, .github/workflows/
- Create initial README with project overview
- Set up branch protection on main requiring PR reviews
- Create GitHub environment "production" with required reviewers
- Add repository secrets placeholders for cluster credentials
```

### Issue Management Actions:
```
Action: Create deployment milestone and issues
- Create milestone "v1.0 - Initial Cluster Deployment" 
- Create epic issue "Talos Cluster Setup" with full task breakdown
- Create issues for each phase:
  * "Generate Talos machine configurations" (label: config, priority: high)
  * "Set up Cilium with BGP integration" (label: networking, priority: high)  
  * "Create self-replacing GitHub Actions runner" (label: cicd, priority: medium)
  * "Implement security hardening validation" (label: security, priority: critical)
  * "Create operational documentation" (label: docs, priority: medium)
- Assign all issues to current milestone
- Create project board "Cluster Deployment" and link all issues
```

### Workflow Automation Actions:  
```
Action: Create GitHub Actions workflow templates
- Create .github/workflows/talos-deploy.yml with:
  * Trigger on push to main and PR
  * Self-hosted runner configuration
  * Dynamic cluster name detection step
  * Talos security validation gates
  * Rollback capabilities on failure
- Create .github/workflows/runner-replacement.yml for runner lifecycle
- Set up workflow permissions with minimum required scopes
- Add required status checks to branch protection
```

### Security Compliance Actions:
```
Action: Set up security automation
- Create security policy template in .github/SECURITY.md
- Set up Dependabot for dependency scanning
- Create issue template for security findings
- Add GitHub security advisory monitoring
- Create automated security checklist for PRs:
  * Talos security standards compliance
  * No hardcoded secrets or credentials  
  * Network policies properly configured
  * RBAC follows least privilege
  * All security warnings addressed
```

### Documentation Actions:
```
Action: Initialize documentation structure
- Create docs/README.md as documentation index
- Create docs/architecture.md with cluster design
- Create docs/deployment.md with step-by-step procedures
- Create docs/troubleshooting.md with common issues
- Create docs/security.md with security standards reference
- Set up GitHub Pages for documentation hosting
- Create PR template requiring documentation updates
```

### Monitoring and Alerting Actions:
```
Action: Set up operational monitoring
- Create monitoring namespace issue
- Set up GitHub issue templates for:
  * Incident reports
  * Change requests  
  * Security findings
- Create labels: incident, security, networking, hardware, performance
- Set up notification rules for critical security labels
- Create dashboard configuration issues for Grafana/Prometheus
```

### Maintenance Actions:
```
Action: Create maintenance automation
- Create recurring issues for:
  * Monthly security updates (1st of month)
  * Quarterly cluster health checks  
  * Biannual disaster recovery testing
- Set up GitHub Actions for automated dependency updates
- Create maintenance runbook issues with checklists
- Schedule regular backup validation workflows
```

## Usage Tips

1. **Start with the context** - Use the initial setup prompt first
2. **Use @workspace** - This helps the agent understand your project structure  
3. **Leverage MCP GitHub** - Let it handle repo management, issues, and PRs
4. **Be specific** - Ask for one component at a time
5. **Reference files** - Use @filename.yaml when working on specific configs
6. **Ask for validation** - Always request verification steps
7. **Automate workflows** - Use MCP to create issues, PRs, and project tracking

## Example Conversation Flow

1. Start with setup prompt above
2. "First, help me create the Talos machine configuration"
3. "Now show me the GitHub Actions workflow" 
4. "Add the Cilium BGP configuration"
5. "Create documentation for the deployment process"

Each response should build on the previous context while maintaining security focus.