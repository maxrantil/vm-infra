# VM Infrastructure Architecture

**Last Updated**: 2025-11-11
**Issue**: #36 - Create ARCHITECTURE.md Pattern Document
**Purpose**: Document architectural patterns for implementing optional features in the VM provisioning system

## Table of Contents

1. [Overview](#overview)
2. [Optional Feature Pattern](#optional-feature-pattern)
3. [Flag Parsing Approach](#flag-parsing-approach)
4. [Validation Pipeline Structure](#validation-pipeline-structure)
5. [Terraform/Ansible Integration](#terraformansible-integration)
6. [Security Validation Approach](#security-validation-approach)
7. [Testing Strategy](#testing-strategy)
8. [Implementation Checklist](#implementation-checklist)
9. [Reference Implementation](#reference-implementation)

---

## Overview

This document describes the architectural patterns used in the vm-infra project, specifically the **optional feature pattern** demonstrated by the `--test-dotfiles` flag (Issue #19, PR #22). This pattern serves as a template for implementing similar optional features like `--test-ansible`, `--test-configs`, or any feature that modifies provisioning behavior.

### Key Principles

1. **Security by Default**: All optional features must include comprehensive security validation
2. **Defense in Depth**: Validation occurs at multiple layers (Bash → Terraform → Ansible)
3. **Early Validation**: Validate inputs before resource creation (fail fast)
4. **Rollback Safety**: Failed validation should not leave partial infrastructure
5. **Test-Driven Development**: All features follow RED→GREEN→REFACTOR workflow

### Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     provision-vm.sh                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 1. Flag Parsing (Bash Arguments)                       │ │
│  │    - Parse optional flags                              │ │
│  │    - Preserve positional arguments                     │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 2. Validation Pipeline (lib/validation.sh)            │ │
│  │    - Path validation                                   │ │
│  │    - Security checks                                   │ │
│  │    - Content inspection                                │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 3. Terraform Variable Passing                          │ │
│  │    - Optional variables with defaults                  │ │
│  │    - Infrastructure-level validation                   │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                  Terraform (Infrastructure)                 │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 4. Variable Validation (terraform/main.tf)             │ │
│  │    - Type checking                                     │ │
│  │    - Constraint validation                             │ │
│  │    - Default value handling                            │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 5. Inventory Generation (inventory.tpl)                │ │
│  │    - Conditional variable inclusion                    │ │
│  │    - Template rendering                                │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              Ansible (Configuration Management)             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 6. Conditional Logic (ansible/playbook.yml)            │ │
│  │    - Jinja2 conditionals                               │ │
│  │    - Variable-driven task execution                    │ │
│  │    - Idempotent operations                             │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Optional Feature Pattern

The optional feature pattern enables users to modify provisioning behavior through command-line flags while maintaining security and backward compatibility.

### Pattern Components

1. **Command-line Flag**: User-facing interface (e.g., `--test-dotfiles <path>`)
2. **Validation Layer**: Security checks and input sanitization
3. **Infrastructure Variable**: Terraform variable with validation constraints
4. **Configuration Injection**: Ansible variable for runtime behavior changes
5. **Testing Strategy**: Comprehensive test coverage (unit + integration + E2E)

### Design Goals

- **Backward Compatibility**: Optional features should not break existing workflows
- **Security First**: All inputs validated before use
- **Clear Defaults**: Sensible defaults when flag not provided
- **Fail Fast**: Invalid inputs rejected early (before resource creation)
- **Observable**: Clear user feedback about what mode is active

---

## Flag Parsing Approach

### Implementation Strategy

The flag parsing system uses a **dual-loop approach** to separate optional flags from positional arguments:

```bash
# Parse arguments
FEATURE_FLAG_VALUE=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --feature-flag)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}[ERROR] --feature-flag requires an argument${NC}" >&2
                exit 1
            fi
            FEATURE_FLAG_VALUE="$2"
            shift 2
            ;;
        --another-flag)
            ANOTHER_FLAG=1
            shift
            ;;
        -*)
            echo -e "${RED}[ERROR] Unknown flag: $1${NC}" >&2
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional args
set -- "${POSITIONAL_ARGS[@]}"

# Now access positional args normally
VM_NAME="${1:-dev-vm}"
MEMORY="${2:-4096}"
VCPUS="${3:-2}"
```

### Real Example: `--test-dotfiles` Flag

From `provision-vm.sh` (lines 16-48):

```bash
# Parse arguments
DOTFILES_LOCAL_PATH=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --test-dotfiles)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}[ERROR] --test-dotfiles flag requires a path argument${NC}" >&2
                echo "Usage: $0 <vm-name> [memory] [vcpus] [--test-dotfiles <path>] [--dry-run]" >&2
                exit 1
            fi
            DOTFILES_LOCAL_PATH="$2"
            shift 2
            ;;
        --dry-run)
            TEST_MODE=1
            shift
            ;;
        -*)
            echo -e "${RED}[ERROR] Unknown flag: $1${NC}" >&2
            echo "Usage: $0 <vm-name> [memory] [vcpus] [--test-dotfiles <path>] [--dry-run]" >&2
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional args
set -- "${POSITIONAL_ARGS[@]}"

# Default values
VM_NAME="${1:-dev-vm}"
MEMORY="${2:-4096}"
VCPUS="${3:-2}"
```

### Key Features

1. **Argument Validation**: Check for required flag arguments before processing
2. **Position Independence**: Flags can appear anywhere in command line
3. **Error Messages**: Clear usage instructions on invalid input
4. **Multiple Flags**: Support for multiple optional flags simultaneously
5. **Positional Preservation**: `POSITIONAL_ARGS` array maintains order

### Usage Examples

```bash
# Flag before positional args
./provision-vm.sh --test-dotfiles /path/to/dotfiles my-vm 4096 2

# Flag after positional args
./provision-vm.sh my-vm 4096 2 --test-dotfiles /path/to/dotfiles

# Multiple flags
./provision-vm.sh --test-dotfiles /path --dry-run my-vm

# Default behavior (no flag)
./provision-vm.sh my-vm
```

---

## Validation Pipeline Structure

The validation pipeline provides **defense in depth** through multiple layers of security checks. All validation functions are extracted into `lib/validation.sh` (Issue #38) for reusability.

### Validation Architecture

```
Input → Existence → Type → Security → Content → Output
         Check      Check    Checks    Inspection   (Validated)
```

### Validation Layers

#### 1. Existence and Type Validation

**Purpose**: Verify resource exists and is correct type

```bash
validate_dotfiles_path_exists() {
    local path="$1"

    if [ ! -e "$path" ]; then
        echo -e "${RED}[ERROR] Dotfiles path does not exist: $path${NC}" >&2
        exit 1
    fi

    if [ ! -d "$path" ]; then
        echo -e "${RED}[ERROR] Dotfiles path is not a directory: $path${NC}" >&2
        exit 1
    fi
}
```

**Validates**:
- Path exists in filesystem
- Path is directory (not file, socket, etc.)

#### 2. Security Validation

**Purpose**: Prevent attack vectors (symlinks, shell injection, TOCTOU)

##### Symlink Detection (CVE-1: CVSS 9.3)

```bash
validate_dotfiles_no_symlinks() {
    local path="$1"

    # Check if the path itself is a symlink
    if [ -L "$path" ]; then
        echo -e "${RED}[ERROR] Dotfiles path is a symlink (security risk)${NC}" >&2
        echo "Symlink attacks could redirect to sensitive system directories." >&2
        exit 1
    fi

    # Check if any component in the path is a symlink
    local current_path=""
    IFS='/' read -ra PARTS <<< "$path"
    for part in "${PARTS[@]}"; do
        if [ -n "$part" ]; then
            current_path="${current_path}/${part}"
            if [ -L "$current_path" ]; then
                echo -e "${RED}[ERROR] Dotfiles path contains symlink component: $current_path${NC}" >&2
                exit 1
            fi
        fi
    done

    # SEC-004: Recursive symlink detection (CVSS 5.5)
    if find "$path" -type l -print -quit 2> /dev/null | grep -q .; then
        echo -e "${RED}[ERROR] Symlinked files detected in dotfiles directory${NC}" >&2
        find "$path" -type l 2> /dev/null >&2
        exit 1
    fi
}
```

**Prevents**:
- Path itself being symlink to `/etc/passwd`
- Path components containing symlinks (`/tmp/link/dotfiles`)
- Nested symlinks within directory tree

##### Shell Injection Prevention (CVE-3: CVSS 7.8)

```bash
validate_dotfiles_no_shell_injection() {
    local path="$1"

    # CVE-3: Shell injection prevention (CVSS 7.8)
    # SEC-003: Comprehensive metacharacter coverage (CVSS 7.0)
    local pattern='[;\&|`$()<>{}*?#'\''"[:space:][:cntrl:]]|\\|\['
    if [[ "$path" =~ $pattern ]]; then
        echo -e "${RED}[ERROR] Dotfiles path contains prohibited characters (security risk)${NC}" >&2
        echo "Path: $path" >&2
        echo "Allowed characters: alphanumeric, hyphen, underscore, slash, period" >&2
        exit 1
    fi

    # Ensure path is printable ASCII
    if ! [[ "$path" =~ ^[[:print:]]+$ ]]; then
        echo -e "${RED}[ERROR] Dotfiles path contains non-printable characters (security risk)${NC}" >&2
        exit 1
    fi
}
```

**Blocks**:
- Semicolons: `; rm -rf /`
- Pipes: `| cat /etc/passwd`
- Command substitution: `` `whoami` `` or `$(whoami)`
- Redirections: `> /etc/passwd`
- Glob patterns: `*`, `?`, `[abc]`
- Control characters: newlines, tabs, null bytes

##### TOCTOU Protection (SEC-001: CVSS 6.8)

```bash
validate_dotfiles_canonical_path() {
    local path="$1"

    # SEC-001: TOCTOU race condition prevention (CVSS 6.8)
    # This check is intentionally DUPLICATED after validate_dotfiles_no_symlinks
    # to catch race conditions where the directory is replaced with a symlink
    if [ -L "$path" ]; then
        echo -e "${RED}[ERROR] Path is a symlink (TOCTOU protection)${NC}" >&2
        echo "Path may have been replaced after initial validation." >&2
        exit 1
    fi

    # Additional canonical path check using realpath
    if command -v realpath > /dev/null 2>&1; then
        local canonical_path
        canonical_path=$(realpath --no-symlinks "$path" 2> /dev/null)

        if [ "$canonical_path" != "$path" ]; then
            echo -e "${RED}[ERROR] Path contains symlink component (TOCTOU protection)${NC}" >&2
            echo "Expected: $path" >&2
            echo "Canonical: $canonical_path" >&2
            exit 1
        fi
    fi
}
```

**Prevents**: Attacker replacing validated directory with symlink between validation and use

#### 3. Content Inspection

**Purpose**: Inspect file contents for malicious patterns

##### install.sh Safety Checks (CVE-2: CVSS 9.0)

From `lib/validation.sh` (lines 293-351):

```bash
validate_install_sh() {
    local path="$1"
    local install_script="$path/install.sh"

    # SEC-005: Permission validation
    local perms
    perms=$(stat -c "%a" "$install_script")

    if [ $((8#$perms & 8#002)) -ne 0 ]; then
        echo -e "${RED}[ERROR] install.sh is world-writable (insecure permissions)${NC}" >&2
        exit 1
    fi

    # CVE-2: install.sh content inspection (CVSS 9.0)
    local dangerous_patterns=(
        # Destructive commands
        "rm.*-rf.*/"
        "rm -rf /"
        "dd if="
        "mkfs\."

        # Remote code execution
        "curl.*\|.*(bash|sh)"
        "wget.*\|.*(bash|sh)"
        "eval"
        "exec"

        # Privilege escalation
        "sudo"
        "su "
        "chown.*root"

        # Obfuscation indicators
        "\\\\x[0-9a-f]{2}"
        "base64.*-d.*\|"
        "\\\${IFS}"

        # Network access
        "nc "
        "netcat"
        "/dev/tcp/"

        # Crypto mining
        "xmrig"
        "miner"
    )

    for pattern in "${dangerous_patterns[@]}"; do
        if matched_line=$(grep -m 1 -E "$pattern" "$install_script" 2> /dev/null); then
            echo -e "${RED}[ERROR] Dangerous pattern detected in install.sh${NC}" >&2
            echo "Pattern: $pattern" >&2
            echo "Matched line: ${matched_line:0:100}" >&2
            exit 1
        fi
    done
}
```

**Detects**:
- Destructive commands: `rm -rf /`, `dd if=/dev/zero`
- Remote code execution: `curl | bash`
- Privilege escalation: `sudo`, `chown root`
- Obfuscation: Base64 encoding, hex escapes
- Network backdoors: Netcat, raw sockets
- Cryptominers: Known miner names

### Composite Validation Function

All validation layers are composed into a single entry point:

```bash
validate_and_prepare_dotfiles_path() {
    local path="$1"

    # Expand tilde
    path="${path/#\~/$HOME}"

    # Convert to absolute path
    if [[ "$path" != /* ]]; then
        path="$(cd "$path" && pwd)"
    fi

    # Run all security validations
    validate_dotfiles_path_exists "$path"
    validate_dotfiles_no_symlinks "$path"
    validate_dotfiles_canonical_path "$path"
    validate_dotfiles_no_shell_injection "$path"
    validate_dotfiles_git_repo "$path"
    validate_install_sh "$path"

    echo "$path"
}
```

**Usage in provision-vm.sh** (lines 87-93):

```bash
# Validate and prepare dotfiles path if provided
if [ -n "$DOTFILES_LOCAL_PATH" ]; then
    echo -e "${YELLOW}Validating local dotfiles path...${NC}"
    DOTFILES_LOCAL_PATH=$(validate_and_prepare_dotfiles_path "$DOTFILES_LOCAL_PATH")
    echo -e "${GREEN}[OK] Using local dotfiles: $DOTFILES_LOCAL_PATH${NC}"
fi
```

---

## Terraform/Ansible Integration

### Terraform Variable Layer

Optional features are exposed as **Terraform variables** with validation constraints.

#### Variable Definition

From `terraform/main.tf` (lines 52-61):

```hcl
variable "dotfiles_local_path" {
  description = "Local path to dotfiles for testing (optional)"
  type        = string
  default     = ""

  validation {
    condition     = var.dotfiles_local_path == "" || can(regex("^/", var.dotfiles_local_path))
    error_message = "dotfiles_local_path must be empty or an absolute path (starting with /)"
  }
}
```

**Key Features**:
1. **Optional with Default**: Empty string default enables normal workflow
2. **Type Safety**: String type prevents incorrect values
3. **Validation Block**: Enforces absolute path constraint at infrastructure level
4. **Clear Error Messages**: User-friendly validation errors

#### Variable Passing

From `provision-vm.sh` (lines 169-178):

```bash
# Create VM
TERRAFORM_VARS=(
    -var="vm_name=$VM_NAME"
    -var="memory=$MEMORY"
    -var="vcpus=$VCPUS"
)

if [ -n "$DOTFILES_LOCAL_PATH" ]; then
    TERRAFORM_VARS+=(-var="dotfiles_local_path=$DOTFILES_LOCAL_PATH")
fi

terraform apply -auto-approve "${TERRAFORM_VARS[@]}"
```

**Pattern**: Conditionally add variable only when set (uses Terraform default otherwise)

### Ansible Inventory Integration

#### Inventory Template

From `terraform/inventory.tpl`:

```ini
[vms]
${vm_ip} ansible_user=${vm_user} ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[vms:vars]
vm_name=${vm_name}
%{ if dotfiles_local_path != "" }dotfiles_local_path=${dotfiles_local_path}%{ endif }
```

**Key Features**:
- **Conditional Inclusion**: `%{ if ... }` only adds variable when non-empty
- **Variable Scope**: `[vms:vars]` makes variable available to all plays
- **Clean Defaults**: Omitted when not set (Ansible uses playbook defaults)

#### Inventory Generation

From `terraform/main.tf` (lines 166-174):

```hcl
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    vm_ip               = length(libvirt_domain.vm.network_interface[0].addresses) > 0 ? libvirt_domain.vm.network_interface[0].addresses[0] : ""
    vm_user             = "mr"
    vm_name             = var.vm_name
    dotfiles_local_path = var.dotfiles_local_path
  })
  filename = "${path.module}/../ansible/inventory.d/${var.vm_name}.ini"
}
```

### Ansible Playbook Integration

#### Conditional Logic

From `ansible/playbook.yml` (lines 229-240):

```yaml
- name: Clone dotfiles repository
  git:
    repo: "{% if dotfiles_local_path is defined and dotfiles_local_path != '' %}file://{{ dotfiles_local_path }}{% else %}{{ dotfiles_repo }}{% endif %}"
    dest: "{{ dotfiles_dir }}"
    clone: yes
    update: yes
    depth: 1
  become_user: "{{ ansible_user }}"
  register: dotfiles_clone_result
```

**Key Features**:
1. **Jinja2 Conditionals**: `{% if ... %}` checks variable existence and value
2. **File URL Scheme**: `file://` prefix for local repository paths
3. **Fallback to Default**: Uses `dotfiles_repo` when variable not set
4. **Shallow Clone**: `depth: 1` limits history exposure (CVE-4 mitigation)

---

## Security Validation Approach

### Defense in Depth Strategy

Security validation occurs at **three layers**:

```
Layer 1: Bash Script (provision-vm.sh + lib/validation.sh)
  → Comprehensive security checks
  → Early rejection of invalid inputs
  → User-friendly error messages

Layer 2: Terraform (main.tf)
  → Infrastructure-level constraints
  → Type safety
  → Validation blocks

Layer 3: Ansible (playbook.yml)
  → Variable existence checks
  → Safe default values
  → Idempotent operations
```

### CVE Coverage

The `--test-dotfiles` implementation includes mitigations for multiple CVE-level vulnerabilities:

#### CVE-1: Symlink Attack (CVSS 9.3)

**Threat**: Attacker provides symlink to `/etc/passwd`, VM copies system files to GitHub

**Mitigation**:
- Path itself checked for symlink
- All path components checked for symlinks
- Recursive directory scan for nested symlinks

**Code**: `lib/validation.sh:validate_dotfiles_no_symlinks()`

#### CVE-2: install.sh Malicious Content (CVSS 9.0)

**Threat**: Attacker provides dotfiles with malicious `install.sh` that runs arbitrary code

**Mitigation**:
- Blacklist validation (dangerous patterns)
- Whitelist validation (safe commands only)
- Permission checks (no world-writable files)
- Interactive confirmation for suspicious content

**Code**: `lib/validation.sh:validate_install_sh()`

#### CVE-3: Shell Injection (CVSS 7.8)

**Threat**: Attacker uses special characters to inject shell commands in path

**Mitigation**:
- Comprehensive metacharacter blocking
- Printable ASCII enforcement
- Regex validation before any shell expansion

**Code**: `lib/validation.sh:validate_dotfiles_no_shell_injection()`

#### CVE-4: Git History Exposure (CVSS 7.5)

**Threat**: Full git history copied from private repository exposes sensitive commits

**Mitigation**:
- Shallow clone (`depth: 1`)
- No history transfer
- Both local and remote modes use shallow clone

**Code**: `ansible/playbook.yml` (line 237: `depth: 1`)

### Security Pattern: Blacklist + Whitelist

The content inspection uses **dual validation**:

#### 1. Blacklist (Catch Known Bad)

```bash
dangerous_patterns=(
    "rm.*-rf.*/"
    "curl.*\|.*(bash|sh)"
    "eval"
    "sudo"
)

for pattern in "${dangerous_patterns[@]}"; do
    if grep -qE "$pattern" "$install_script"; then
        echo "ERROR: Dangerous pattern detected"
        exit 1
    fi
done
```

#### 2. Whitelist (Allow Known Good)

```bash
safe_pattern="^(#|$|[[:space:]]*(ln|cp|mv|mkdir|echo|cat|grep|sed|awk|printf|test|\\[|chmod|chown|git|stow))"

while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue  # Skip comments
    [[ -z "$line" ]] && continue                 # Skip empty

    if ! [[ "$line" =~ $safe_pattern ]]; then
        echo "WARNING: Potentially unsafe command: $line"
        ((unsafe_lines++))
    fi
done < "$install_script"

if [ "$unsafe_lines" -gt 0 ]; then
    read -p "Continue anyway? [y/N] " -n 1 -r
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi
```

**Strategy**: Block obviously dangerous, warn on unusual, allow clearly safe

---

## Testing Strategy

### Test Coverage Levels

The `--test-dotfiles` feature includes **69 automated tests** organized by type:

```
Unit Tests (33 tests)
├── Flag Parsing (4 tests)
│   ├── Default behavior without flag
│   ├── Parse flag with path argument
│   ├── Error on missing argument
│   └── Multiple flags in any order
├── Path Validation (6 tests)
│   ├── Non-existent path rejection
│   ├── File (not directory) rejection
│   ├── Valid directory acceptance
│   ├── Relative path conversion
│   ├── Path with spaces handling
│   └── Tilde expansion
├── Security Validations (20 tests)
│   ├── CVE-1: Symlink detection (3 tests)
│   ├── CVE-2: install.sh inspection (5 tests)
│   ├── CVE-3: Shell injection (12 tests)
│   └── SEC-001 to SEC-007 (various)
└── Content Validation (3 tests)
    ├── Git repository validation
    └── install.sh existence

Integration Tests (14 tests)
├── Terraform (5 tests)
│   ├── Variable passing
│   ├── Default value handling
│   └── Validation constraints
├── Ansible Inventory (2 tests)
│   ├── Variable inclusion when set
│   └── Variable omission when not set
└── Ansible Playbook (7 tests)
    ├── Local repository mode (file://)
    ├── GitHub default mode
    └── Conditional logic

End-to-End Tests (2 tests)
├── Full pipeline with local dotfiles
└── Full pipeline with GitHub default
```

### Test Structure: TDD Approach

All tests follow **RED→GREEN→REFACTOR** workflow:

#### RED Phase: Write Failing Tests

```bash
test_security_symlink_detection() {
    setup_test_env

    # Create symlink (malicious input)
    mkdir -p "$TEST_SYMLINK_TARGET"
    ln -s "$TEST_SYMLINK_TARGET" "$TEST_SYMLINK"

    # Validation should FAIL (reject symlink)
    validate_dotfiles_not_symlink "$TEST_SYMLINK" 2>&1 && result="pass" || result="fail"
    test_result "CVE-1: Symlink should be rejected" "fail" "$result"

    teardown_test_env
}
```

**Expected**: Test **fails** initially (validation function doesn't exist yet)

#### GREEN Phase: Minimal Implementation

```bash
validate_dotfiles_not_symlink() {
    local path="$1"

    if [ -L "$path" ]; then
        echo "ERROR: Path is a symlink (security risk)"
        return 1
    fi

    return 0
}
```

**Expected**: Test **passes** (minimal code to satisfy test)

#### REFACTOR Phase: Add Security Features

```bash
validate_dotfiles_not_symlink() {
    local path="$1"

    # CVE-1: Symlink detection (CVSS 9.3)
    if [ -L "$path" ]; then
        echo -e "${RED}[ERROR] Path is a symlink (security risk)${NC}" >&2
        echo "Symlink attacks could redirect to sensitive system directories." >&2
        exit 1
    fi

    # Check path components
    local current_path=""
    IFS='/' read -ra PARTS <<< "$path"
    for part in "${PARTS[@]}"; do
        if [ -n "$part" ]; then
            current_path="${current_path}/${part}"
            if [ -L "$current_path" ]; then
                echo -e "${RED}[ERROR] Dotfiles path contains symlink component: $current_path${NC}" >&2
                exit 1
            fi
        fi
    done

    return 0
}
```

**Expected**: Test **still passes** (enhanced security without breaking contract)

### Running Tests

From `tests/test_local_dotfiles.sh`:

```bash
# Run all 69 tests
./tests/test_local_dotfiles.sh

# Output example:
# ========================================
# Test Results Summary
# ========================================
# Total tests run: 69
# Passed: 69
# Failed: 0
#
# ALL TESTS PASSED!
```

### Test Isolation

Each test uses **temporary environments** to avoid side effects:

```bash
setup_test_env() {
    TEST_DIR=$(mktemp -d)
    export TEST_DOTFILES_DIR="$TEST_DIR/dotfiles"
}

teardown_test_env() {
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# Usage in test
test_some_feature() {
    setup_test_env
    # ... test code ...
    teardown_test_env
}
```

---

## Implementation Checklist

Use this checklist when implementing new optional features:

### Phase 1: Planning

- [ ] Define feature scope and use cases
- [ ] Identify security risks (threat modeling)
- [ ] Design flag syntax (`--feature-name <value>`)
- [ ] Document expected behavior

### Phase 2: TDD Test Suite (RED)

- [ ] Write unit tests for flag parsing
- [ ] Write unit tests for validation logic
- [ ] Write integration tests for Terraform variable passing
- [ ] Write integration tests for Ansible integration
- [ ] Write E2E tests for full pipeline
- [ ] Verify all tests **fail** (RED phase complete)

### Phase 3: Implementation (GREEN)

- [ ] Add flag parsing to `provision-vm.sh`
  - [ ] Add flag to while loop case statement
  - [ ] Validate required arguments
  - [ ] Store in variable
- [ ] Create validation functions in `lib/validation.sh`
  - [ ] Existence/type checks
  - [ ] Security validations
  - [ ] Content inspection
- [ ] Add Terraform variable to `terraform/main.tf`
  - [ ] Define variable with type
  - [ ] Add validation block
  - [ ] Document with description
- [ ] Update inventory template (`terraform/inventory.tpl`)
  - [ ] Add conditional variable inclusion
- [ ] Add conditional logic to `ansible/playbook.yml`
  - [ ] Use Jinja2 conditionals
  - [ ] Implement fallback to defaults
- [ ] Verify all tests **pass** (GREEN phase complete)

### Phase 4: Security Hardening (REFACTOR)

- [ ] Run security scanner (gitleaks, checkov, trivy)
- [ ] Add comprehensive input validation
- [ ] Implement defense in depth (multiple validation layers)
- [ ] Document CVE mitigations in code comments
- [ ] Add error handling and rollback
- [ ] Update security documentation

### Phase 5: Documentation

- [ ] Update `README.md` with feature description
- [ ] Add usage examples
- [ ] Document security validations
- [ ] Update this `ARCHITECTURE.md` if pattern changes
- [ ] Create session handoff document

### Phase 6: Integration

- [ ] Test with real infrastructure
- [ ] Validate backward compatibility
- [ ] Test error scenarios
- [ ] Verify rollback mechanisms
- [ ] Update pre-commit hooks if needed

---

## Reference Implementation

### Complete Example: `--test-dotfiles` Flag

This section shows the complete implementation flow for reference when building new features.

#### 1. Flag Parsing (`provision-vm.sh`)

```bash
# Parse arguments
DOTFILES_LOCAL_PATH=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --test-dotfiles)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}[ERROR] --test-dotfiles flag requires a path argument${NC}" >&2
                echo "Usage: $0 <vm-name> [memory] [vcpus] [--test-dotfiles <path>] [--dry-run]" >&2
                exit 1
            fi
            DOTFILES_LOCAL_PATH="$2"
            shift 2
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}"
VM_NAME="${1:-dev-vm}"
```

#### 2. Validation (`lib/validation.sh`)

```bash
validate_and_prepare_dotfiles_path() {
    local path="$1"

    # Expand tilde
    path="${path/#\~/$HOME}"

    # Convert to absolute path
    if [[ "$path" != /* ]]; then
        path="$(cd "$path" && pwd)"
    fi

    # Security validations
    validate_dotfiles_path_exists "$path"
    validate_dotfiles_no_symlinks "$path"
    validate_dotfiles_canonical_path "$path"
    validate_dotfiles_no_shell_injection "$path"
    validate_dotfiles_git_repo "$path"
    validate_install_sh "$path"

    echo "$path"
}
```

#### 3. Terraform Variable (`terraform/main.tf`)

```hcl
variable "dotfiles_local_path" {
  description = "Local path to dotfiles for testing (optional)"
  type        = string
  default     = ""

  validation {
    condition     = var.dotfiles_local_path == "" || can(regex("^/", var.dotfiles_local_path))
    error_message = "dotfiles_local_path must be empty or an absolute path (starting with /)"
  }
}
```

#### 4. Variable Passing (`provision-vm.sh`)

```bash
if [ -n "$DOTFILES_LOCAL_PATH" ]; then
    echo -e "${YELLOW}Validating local dotfiles path...${NC}"
    DOTFILES_LOCAL_PATH=$(validate_and_prepare_dotfiles_path "$DOTFILES_LOCAL_PATH")
    echo -e "${GREEN}[OK] Using local dotfiles: $DOTFILES_LOCAL_PATH${NC}"
fi

TERRAFORM_VARS=(
    -var="vm_name=$VM_NAME"
    -var="memory=$MEMORY"
    -var="vcpus=$VCPUS"
)

if [ -n "$DOTFILES_LOCAL_PATH" ]; then
    TERRAFORM_VARS+=(-var="dotfiles_local_path=$DOTFILES_LOCAL_PATH")
fi

terraform apply -auto-approve "${TERRAFORM_VARS[@]}"
```

#### 5. Inventory Template (`terraform/inventory.tpl`)

```ini
[vms]
${vm_ip} ansible_user=${vm_user} ansible_ssh_private_key_file=~/.ssh/vm_key

[vms:vars]
vm_name=${vm_name}
%{ if dotfiles_local_path != "" }dotfiles_local_path=${dotfiles_local_path}%{ endif }
```

#### 6. Ansible Playbook (`ansible/playbook.yml`)

```yaml
- name: Clone dotfiles repository
  git:
    repo: "{% if dotfiles_local_path is defined and dotfiles_local_path != '' %}file://{{ dotfiles_local_path }}{% else %}{{ dotfiles_repo }}{% endif %}"
    dest: "{{ dotfiles_dir }}"
    clone: yes
    update: yes
    depth: 1
  become_user: "{{ ansible_user }}"
```

---

## Related Documentation

- **Issue #19**: Original `--test-dotfiles` feature request
- **PR #22**: Implementation with retrospective TDD
- **Issue #38**: Validation function extraction to `lib/validation.sh`
- **lib/README.md**: Complete validation function reference
- **tests/test_local_dotfiles.sh**: 69-test comprehensive test suite
- **TESTING.md**: Overall testing strategy and philosophy

---

## Future Patterns

### Potential Optional Features

This pattern can be extended to implement:

1. **`--test-ansible <path>`**: Test local Ansible playbooks before commit
2. **`--test-configs <path>`**: Test local configuration files
3. **`--custom-base-image <path>`**: Use custom VM base image
4. **`--cloud-provider <name>`**: Support multiple cloud providers
5. **`--security-level <level>`**: Adjust security validation strictness

### Pattern Evolution

As new features are added, consider:

- **Centralizing flag parsing**: Extract to `lib/flags.sh` if flags become numerous
- **Plugin architecture**: Support external validation plugins
- **Configuration files**: Allow `.vm-infra.yaml` for complex configurations
- **API mode**: Expose functionality as API for programmatic use

---

**End of Document**

*This architecture document is a living document. Update it whenever the optional feature pattern evolves or new insights are gained from implementation experience.*
