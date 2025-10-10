## Problem

vm-infra has **ZERO GitHub Actions workflows** despite containing:
- 607 lines of security-critical Shell scripts (`provision-vm.sh`, `destroy-vm.sh`)
- Terraform configurations for VM provisioning
- Ansible playbook with 28 tasks
- 3 existing test scripts that aren't automated

**Impact**:
- Breaking Terraform changes can be merged
- Ansible syntax errors not caught pre-merge
- Security validations in provision-vm.sh not tested until execution
- Manual testing required for every change

**Risk**: CRITICAL - Infrastructure breakage affects all VM provisioning

## Solution

Add 5 GitHub Actions workflows to validate infrastructure changes before merge.

## Workflows to Create

### 1. Shell Quality Validation

**File**: `.github/workflows/shell-quality.yml`

```yaml
name: Shell Quality Checks
on:
  pull_request:
    branches: [master]

jobs:
  shellcheck:
    uses: maxrantil/.github/.github/workflows/shell-quality-reusable.yml@main
    with:
      shellcheck-severity: 'warning'
      shfmt-options: '-d -i 2 -ci'
```

**Validates**: `provision-vm.sh`, `destroy-vm.sh`, test scripts

---

### 2. Commit Format Check

**File**: `.github/workflows/commit-format.yml`

```yaml
name: Conventional Commit Check
on:
  pull_request:
    branches: [master]

jobs:
  check-commits:
    uses: maxrantil/.github/.github/workflows/conventional-commit-check-reusable.yml@main
```

---

### 3. Session Handoff Verification

**File**: `.github/workflows/verify-session-handoff.yml`

```yaml
name: Session Handoff Verification
on:
  pull_request:
    branches: [master]
    types: [opened, synchronize, reopened, ready_for_review]

jobs:
  verify:
    uses: maxrantil/.github/.github/workflows/session-handoff-check-reusable.yml@main
```

---

### 4. PR Title Check

**File**: `.github/workflows/pr-title-check.yml`

```yaml
name: PR Title Check
on:
  pull_request:
    types: [opened, edited, synchronize]

jobs:
  check-title:
    uses: maxrantil/.github/.github/workflows/pr-title-check-reusable.yml@main
```

---

### 5. Master Branch Protection

**File**: `.github/workflows/protect-master.yml`

```yaml
name: Protect Master Branch
on:
  push:
    branches:
      - master

jobs:
  block-direct-push:
    uses: maxrantil/.github/.github/workflows/protect-master-reusable.yml@main
```

---

## Implementation Checklist

- [ ] Create `.github/workflows/` directory
- [ ] Create `shell-quality.yml`
- [ ] Create `commit-format.yml`
- [ ] Create `verify-session-handoff.yml`
- [ ] Create `pr-title-check.yml`
- [ ] Create `protect-master.yml`
- [ ] Create test PR to validate all workflows
- [ ] Verify all workflows pass
- [ ] Merge workflows to master

## Future Enhancements (Separate Issues)

After basic workflows are working:
- Add Terraform validation (requires new reusable workflow)
- Add Ansible linting (requires new reusable workflow)
- Add automated test execution (tests/test_*.sh)

## Acceptance Criteria

- [ ] All 5 workflow files created
- [ ] ShellCheck validates shell scripts
- [ ] Conventional commits enforced
- [ ] Session handoff verified
- [ ] PR title format checked
- [ ] Direct push to master blocked
- [ ] All workflows pass on test PR
- [ ] No false positives
- [ ] CI completes in <2 minutes

## Testing Plan

1. Create feature branch
2. Add all 5 workflows
3. Create PR with intentional issues:
   - Shell syntax error (should fail ShellCheck)
   - Non-conventional commit (should fail commit check)
   - Missing session handoff (should fail if incomplete work)
   - Bad PR title (should fail title check)
4. Fix issues one by one
5. Verify all workflows pass
6. Merge to master

## Files to Create

```
.github/
└── workflows/
    ├── shell-quality.yml
    ├── commit-format.yml
    ├── verify-session-handoff.yml
    ├── pr-title-check.yml
    └── protect-master.yml
```

## Dependencies

None - uses existing reusable workflows from `.github` repository

## Priority

**CRITICAL** - Complete in Week 1 (highest risk gap)
