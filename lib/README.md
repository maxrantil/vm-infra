# VM Infrastructure Libraries

Reusable shell libraries for VM provisioning scripts.

## Available Libraries

### validation.sh

Security-hardened validation functions for VM provisioning.

**Functions:**

#### SSH Key Validation
- `validate_ssh_directory_permissions()` - Validate ~/.ssh permissions (must be 700)
- `validate_private_key_permissions(key_path, key_name)` - Validate SSH key permissions (600 or 400)
- `validate_key_content(key_path, key_name)` - Validate SSH key format using ssh-keygen
- `validate_public_key_exists(key_path, key_name)` - Validate keypair completeness

#### Dotfiles Path Validation
- `validate_dotfiles_path_exists(path)` - Validate dotfiles directory exists
- `validate_dotfiles_no_symlinks(path)` - Detect symlink attacks (CVE-1, SEC-004)
- `validate_dotfiles_canonical_path(path)` - Prevent TOCTOU attacks (SEC-001)
- `validate_dotfiles_no_shell_injection(path)` - Block shell metacharacters (CVE-3, SEC-003)
- `validate_dotfiles_git_repo(path)` - Validate git repository integrity (BUG-006)

#### install.sh Safety Scanning
- `validate_install_sh(path)` - Scan install.sh for malicious patterns (CVE-2, SEC-002, SEC-005, SEC-006)

#### Composite Validation
- `validate_and_prepare_dotfiles_path(path)` - Complete validation pipeline with tilde expansion and absolute path conversion

**Security Coverage:**
- CVE-1: Symlink attack prevention (CVSS 9.3)
- CVE-2: install.sh content inspection (CVSS 9.0)
- CVE-3: Shell injection prevention (CVSS 7.8)
- SEC-001: TOCTOU race condition mitigation (CVSS 6.8)
- SEC-002: Pattern evasion detection (CVSS 7.5)
- SEC-003: Comprehensive metacharacter blocking (CVSS 7.0)
- SEC-004: Recursive symlink detection (CVSS 5.5)
- SEC-005: Permission validation (CVSS 4.0)
- SEC-006: Whitelist validation (CVSS 5.0)

**Usage:**

```bash
#!/bin/bash
# Source the validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/validation.sh"

# Use validation functions
validate_dotfiles_path_exists "/path/to/dotfiles"
validate_dotfiles_no_symlinks "/path/to/dotfiles"
```

**Testing:**

Run the comprehensive test suite:

```bash
./tests/test_local_dotfiles.sh
# Expected: 69/69 tests passing
```

**Error Handling:**

All validation functions exit with code 1 on failure and print error messages to stderr. This is intentional for use in provisioning scripts where validation failures should terminate execution.

For testing scenarios where you need to catch failures without exiting, use command substitution in a subshell:

```bash
# Capture exit code without terminating script
if output=$(validate_dotfiles_path_exists "/path" 2>&1); then
    echo "Validation passed"
else
    echo "Validation failed: $output"
fi
```

## Future Libraries (Planned)

- `common.sh` - Shared utilities (logging, colors, error handling)
- `ssh.sh` - SSH connection helpers
- `terraform-helpers.sh` - Terraform wrapper functions

## Design Principles

1. **Non-executable libraries** - Libraries should be sourced, not executed directly (644 permissions)
2. **Absolute path sourcing** - Always use `$SCRIPT_DIR/lib/validation.sh` to prevent path hijacking
3. **Color code independence** - Libraries define color codes with defaults if not provided by caller
4. **Single responsibility** - Each function validates one concern
5. **Security first** - All CVE mitigations preserved with inline comments
6. **Consistent naming** - Functions prefixed by purpose (validate_*, check_*, get_*)

## References

- Issue #38: Extract Validation Library
- CLAUDE.md Section 3: Code Standards
- provision-vm.sh: Primary consumer of validation functions
