## Problem

Infrastructure code (Terraform, Ansible) not scanned for security issues. Potential vulnerabilities:
- Insecure Terraform configurations
- Ansible playbook security anti-patterns
- Hardcoded secrets
- Overly permissive security groups
- Missing encryption

**Impact**: Security issues not detected until post-deployment audits

## Solution

Add security scanning workflow using Trivy and Checkov to detect IaC security issues.

## Workflow to Create

**File**: `.github/workflows/security-scan.yml`

```yaml
name: Infrastructure Security Scanning
on:
  pull_request:
    branches: [master]
    paths:
      - 'terraform/**'
      - 'ansible/**'
      - '.github/workflows/security-scan.yml'
  push:
    branches: [master]

jobs:
  trivy-scan:
    name: Trivy Security Scan
    runs-on: ubuntu-latest
    permissions:
      contents: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run Trivy vulnerability scanner in IaC mode
        uses: aquasecurity/trivy-action@<COMMIT_SHA>  # Pin to commit SHA
        with:
          scan-type: 'config'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-results.sarif'

      - name: Display Trivy results
        run: |
          cat trivy-results.sarif

  checkov-scan:
    name: Checkov IaC Security Scan
    runs-on: ubuntu-latest
    permissions:
      contents: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run Checkov
        uses: bridgecrewio/checkov-action@<COMMIT_SHA>  # Pin to commit SHA
        with:
          directory: .
          framework: terraform,ansible
          quiet: false
          soft_fail: true  # Don't fail build, just report
          output_format: cli

  ansible-security:
    name: Ansible Security Lint
    runs-on: ubuntu-latest
    permissions:
      contents: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install ansible-lint with security profile
        run: pip install ansible-lint

      - name: Run ansible-lint with security rules
        run: |
          cd ansible
          ansible-lint --profile production playbook.yml || true  # Report only
```

## Security Checks

### Trivy Scanning
- Terraform misconfigurations
- Insecure defaults
- Missing encryption
- Overly permissive access
- Known vulnerabilities in modules

### Checkov Scanning
- CIS benchmark compliance
- Security best practices
- Resource-specific checks
- Policy violations
- Secret detection

### Ansible Security Linting
- Hardcoded credentials
- Insecure task patterns
- Missing privilege escalation checks
- Dangerous module usage
- Production readiness

## Implementation Checklist

- [ ] Research latest Trivy action commit SHA
- [ ] Research latest Checkov action commit SHA
- [ ] Create `.github/workflows/security-scan.yml`
- [ ] Add Trivy scan job
- [ ] Add Checkov scan job
- [ ] Add Ansible security lint job
- [ ] Test workflow with intentional security issue
- [ ] Establish security baseline
- [ ] Configure soft-fail vs hard-fail
- [ ] Document findings in README

## Baseline Establishment

1. Run initial scan
2. Review all findings
3. Create exceptions file for accepted risks
4. Document baseline in README
5. Set threshold for future PRs

### Example Baseline Documentation

```markdown
## Security Baseline

**Last Scan**: 2025-10-10
**Trivy Findings**: 2 (low severity, accepted)
**Checkov Findings**: 3 (informational, accepted)
**Ansible Findings**: 0

**Accepted Risks**:
1. Trivy: DS002 (Root user in container) - Local VMs, acceptable
2. Checkov: CKV_TF_1 (Missing description) - Terraform outputs, low priority
```

## Configuration Files

### .trivyignore (optional)

```yaml
# Ignore specific vulnerabilities
DS002  # Root user in container (local VMs)
```

### .checkov.yml (optional)

```yaml
# Checkov configuration
skip-check:
  - CKV_TF_1  # Terraform outputs missing description (low priority)
```

## Testing Plan

1. Create security scan workflow
2. Run initial scan
3. Review all findings
4. Introduce intentional security issue:
   - Unencrypted Terraform resource
   - Ansible task with hardcoded password
5. Verify scan detects issues
6. Fix issues
7. Establish baseline
8. Document accepted risks

## Expected Findings (Initial Scan)

Based on current code:
- Potential: Unencrypted libvirt volumes (acceptable for local VMs)
- Potential: SSH key permissions checks (already handled in provision-vm.sh)
- Potential: Cloud-init password auth (already disabled)

**Expected**: Low findings, mostly informational

## Files to Create

- `.github/workflows/security-scan.yml`
- `.trivyignore` (optional)
- `.checkov.yml` (optional)

## Files to Update

- `README.md` (add Security Scanning section)

## Acceptance Criteria

- [ ] Security scan workflow created
- [ ] Trivy scanning works
- [ ] Checkov scanning works
- [ ] Ansible security lint works
- [ ] Actions pinned to commit SHAs
- [ ] Baseline established
- [ ] Findings documented
- [ ] Scan runs on PRs and pushes
- [ ] README updated

## Performance

**Expected Scan Time**:
- Trivy: ~30 seconds
- Checkov: ~20 seconds
- Ansible lint: ~10 seconds
- **Total**: ~1 minute

## Priority

**MEDIUM** - Complete in Month 2 (security enhancement, not critical)
