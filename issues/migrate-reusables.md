## Problem

vm-infra currently uses basic workflow references. Once infrastructure-specific reusable workflows are created in `.github`, vm-infra should migrate to use them.

**Dependencies**: This issue blocks on:
- .github Issue: "Create terraform-validate-reusable.yml workflow"
- .github Issue: "Create ansible-lint-reusable.yml workflow"

## Solution

Replace basic CI workflows with new infrastructure reusable workflows from `.github`.

## Workflows to Add/Update

### 1. Add Terraform Validation

**File**: `.github/workflows/terraform-validate.yml` (NEW)

```yaml
name: Terraform Validation
on:
  pull_request:
    branches: [master]
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-validate.yml'

jobs:
  validate:
    uses: maxrantil/.github/.github/workflows/terraform-validate-reusable.yml@main
    with:
      working-directory: 'terraform'
      terraform-version: 'latest'
```

---

### 2. Add Ansible Linting

**File**: `.github/workflows/ansible-lint.yml` (NEW)

```yaml
name: Ansible Linting
on:
  pull_request:
    branches: [master]
    paths:
      - 'ansible/**'
      - '.github/workflows/ansible-lint.yml'

jobs:
  lint:
    uses: maxrantil/.github/.github/workflows/ansible-lint-reusable.yml@main
    with:
      working-directory: 'ansible'
      playbook-path: 'playbook.yml'
```

---

### 3. Ensure Shell Quality Uses Latest

**File**: `.github/workflows/shell-quality.yml` (VERIFY)

Ensure using latest reusable:

```yaml
name: Shell Quality Checks
on:
  pull_request:
    branches: [master]
    paths:
      - '**.sh'
      - 'tests/**'
      - '.github/workflows/shell-quality.yml'

jobs:
  shellcheck:
    uses: maxrantil/.github/.github/workflows/shell-quality-reusable.yml@main
    with:
      shellcheck-severity: 'warning'
      shfmt-options: '-d -i 2 -ci'
```

---

## Implementation Checklist

- [ ] Wait for .github terraform reusable workflow to be created
- [ ] Wait for .github ansible reusable workflow to be created
- [ ] Create `terraform-validate.yml` in vm-infra
- [ ] Create `ansible-lint.yml` in vm-infra
- [ ] Verify `shell-quality.yml` uses latest reusable
- [ ] Create test PR to validate all workflows
- [ ] Verify Terraform validation works
- [ ] Verify Ansible linting works
- [ ] Verify all workflows pass
- [ ] Update README with new workflows

## Expected Validations

**Terraform workflow will check**:
- `terraform fmt` - Formatting consistency
- `terraform validate` - Configuration validity
- Syntax errors
- Provider configuration

**Ansible workflow will check**:
- `ansible-lint` - Best practices
- YAML syntax
- Playbook syntax check
- Task naming conventions

## Testing Plan

1. Wait for dependency issues to complete
2. Create feature branch in vm-infra
3. Add both new workflows
4. Introduce intentional issues:
   - Unformatted Terraform file
   - Ansible syntax error
5. Create PR
6. Verify workflows fail appropriately
7. Fix issues
8. Verify workflows pass
9. Merge to master

## Benefits

- **Infrastructure Validation**: Terraform and Ansible checked before merge
- **Consistent Standards**: Same validation across all infrastructure repos
- **Fast Feedback**: Errors caught in CI, not during provisioning
- **Documentation**: Workflows document expected infrastructure quality

## Files to Create

```
.github/workflows/
├── terraform-validate.yml    (NEW)
└── ansible-lint.yml          (NEW)
```

## Files to Update

- `README.md` (document new workflows in CI/CD section)

## Acceptance Criteria

- [ ] Both new workflows created
- [ ] Terraform validation runs on terraform/** changes
- [ ] Ansible linting runs on ansible/** changes
- [ ] Workflows use reusables from .github
- [ ] All workflows pass on test PR
- [ ] README documented
- [ ] CI completes in <3 minutes

## Dependencies

**BLOCKED BY**:
- .github repository: Create terraform-validate-reusable.yml
- .github repository: Create ansible-lint-reusable.yml

**After unblocked**: Can be completed in 1 hour

## Priority

**HIGH** - Complete in Week 2 (after dependencies resolved)
