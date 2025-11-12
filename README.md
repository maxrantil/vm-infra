# VM Infrastructure

Automated Ubuntu VM provisioning using Terraform (libvirt) and Ansible.

## Overview

This infrastructure automates the setup of Ubuntu 24.04 VMs with:
- Core development tools (zsh, neovim, tmux, git, etc.)
- Starship prompt and git-delta
- Personal dotfiles from [maxrantil/dotfiles](https://github.com/maxrantil/dotfiles)
- Tmux Plugin Manager (TPM) and vim-plug

## Architecture & Patterns

For detailed information about the project's architectural patterns, see:

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Comprehensive guide to implementing optional features
  - Optional feature pattern (demonstrated by `--test-dotfiles`)
  - Security validation approach with CVE mitigations
  - Testing strategy (TDD workflow with 69 automated tests)
  - Complete implementation checklist for new features

This document serves as a template for implementing similar features like `--test-ansible`, `--test-configs`, or any feature that modifies provisioning behavior while maintaining security and backward compatibility.

## Prerequisites

- **libvirt/KVM** - Virtualization
- **Terraform** - Infrastructure provisioning
- **Ansible** - Configuration management
- **SSH keys**:
  - `vm_key` - For SSH access to VMs
  - **Deploy keys** - VM-specific GitHub keys (generated automatically)

## Quick Start

### One-Command Provisioning

```bash
# Clone the repository
git clone https://github.com/maxrantil/vm-infra.git
cd vm-infra

# Generate VM access key (if needed)
ssh-keygen -t ed25519 -f ~/.ssh/vm_key -C "vm-access"

# Provision a VM
./provision-vm.sh my-vm-name

# Or with custom resources
./provision-vm.sh my-vm 8192 4  # 8GB RAM, 4 vCPUs
```

### Multi-VM Provisioning

Provision and manage multiple VMs in the same environment:

```bash
# Provision multiple VMs
./provision-vm.sh web-vm 4096 2
./provision-vm.sh db-vm 8192 4
./provision-vm.sh cache-vm 2048 1

# All VMs are now in the shared inventory
cat ansible/inventory.ini

# Run playbook against all VMs
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml

# Or target specific VM
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --limit web-vm

# Destroy individual VMs (others remain)
./destroy-vm.sh web-vm
```

**How it works**: Each VM writes to its own inventory fragment (`ansible/inventory.d/${vm_name}.ini`), which are merged into `ansible/inventory.ini` automatically. Destroying a VM removes its fragment and regenerates the inventory.

That's it! The script will:
1. Create the VM with Terraform
2. Wait for cloud-init to complete
3. Run Ansible playbook
4. Generate VM-specific deploy key
5. Display deploy key setup instructions
6. Display SSH connection info

### Destroy a VM

```bash
./destroy-vm.sh my-vm-name
```

## Manual Setup

### 1. Install Dependencies

```bash
# Arch Linux
sudo pacman -S terraform ansible libvirt qemu-base

# Ubuntu/Debian
sudo apt install terraform ansible libvirt-daemon-system qemu-kvm
```

### 2. Generate SSH Keys

```bash
# VM access key
ssh-keygen -t ed25519 -f ~/.ssh/vm_key -C "vm-access"

# Note: Deploy keys for GitHub are generated automatically per-VM
# See "Deploy Key Setup" section below
```

### 3. Create a VM

```bash
cd terraform
terraform init
terraform apply -var="vm_name=my-vm"
```

The VM IP will be output and automatically added to `ansible/inventory.ini`.

### 4. Provision with Ansible

```bash
cd ../ansible
ansible-playbook -i inventory.ini playbook.yml
```

## Configuration

### Terraform Variables

Create `terraform/terraform.tfvars` (gitignored):

```hcl
vm_name = "dev-vm"
memory = 4096          # MB
vcpus = 2
disk_size = 21474836480  # 20GB in bytes

# Optional: override SSH key
# ssh_public_key_file = "~/.ssh/custom_key.pub"
```

### Cloud-init

Customize `cloud-init/user-data.yaml` for:
- User configuration
- Package installation
- Timezone settings

### Ansible Playbook

The playbook (`ansible/playbook.yml`) installs:
- Core packages (git, curl, build-essential, python3)
- CLI tools (fzf, bat, ripgrep, fd-find, jq, tree, htop)
- Development tools (neovim, zsh, tmux, starship, git-delta)
- Your dotfiles and configurations

#### Customizing Ansible Variables

All paths in the Ansible playbook are configurable via variables. Override defaults in `ansible/group_vars/all.yml` (uncomment and modify variables as needed):

```yaml
---
# Use your own dotfiles repository
dotfiles_repo: "git@github.com:your-username/dotfiles.git"

# Change dotfiles location
dotfiles_dir: "{{ user_home }}/.config/dotfiles"

# Customize SSH key paths
ssh_key_path: "{{ user_home }}/.ssh/custom_key"
ssh_pub_key_path: "{{ user_home }}/.ssh/custom_key.pub"
```

**Available variables** (from `playbook.yml` defaults):
- `user_home` - User home directory (computed from `ansible_user`)
- `ssh_key_path` - SSH private key destination on VM
- `ssh_pub_key_path` - SSH public key destination on VM
- `ssh_dir` - SSH directory path (for known_hosts and config files)
- `dotfiles_repo` - Git repository URL for dotfiles
- `dotfiles_dir` - Dotfiles clone destination
- `nvim_undo_dir` - Neovim undo directory
- `nvim_autoload_dir` - Neovim autoload directory
- `tmux_plugins_dir` - Tmux Plugin Manager directory

## Testing Dotfiles Changes

Test local dotfiles changes before pushing to GitHub:

### Quick Test Workflow

```bash
# 1. Make changes in your local dotfiles repo
cd ../dotfiles
# ... make changes to .zshrc, starship config, etc. ...

# 2. Test in fresh VM without committing/pushing
cd ../vm-infra
./provision-vm.sh test-vm --test-dotfiles ../dotfiles

# 3. SSH and validate changes
ssh -i ~/.ssh/vm_key mr@<VM_IP>
# ... test your changes ...

# 4. Destroy VM when done
./destroy-vm.sh test-vm
```

### Test Mode Features

- ✅ Uses local dotfiles (no git push needed)
- ✅ **Auto-skips deploy key prompt** (no manual "skip" needed)
- ✅ Validates dotfiles directory exists
- ✅ Warns if install.sh missing
- ✅ Converts relative to absolute paths
- ✅ Falls back to GitHub if flag not provided
- ✅ Security validations (symlink detection, shell injection prevention)

### Security Validations

The `--test-dotfiles` flag includes automatic security checks:

- **Terraform Variable Validation**: Enforces absolute paths at infrastructure level (rejects relative paths like `../dotfiles`)
- **Symlink Detection**: Prevents symlink attacks that could redirect to system directories
- **Shell Injection Prevention**: Blocks paths with shell metacharacters (`;`, `|`, `` ` ``, `$()`)
- **install.sh Content Inspection**: Detects dangerous patterns (`rm -rf /`, `curl | bash`, etc.)
- **Git Repository Validation**: Ensures valid .git directory if present

**Note**: Path validation occurs at multiple layers (Terraform → Bash → Ansible) for defense in depth.

### Use Cases

- Testing starship configuration changes
- Validating new shell aliases
- Debugging dotfiles installation issues
- Rapid iteration on complex changes
- Testing PR branches locally

### Examples

```bash
# Test with relative path
./provision-vm.sh test-vm --test-dotfiles ../dotfiles

# Test with absolute path
./provision-vm.sh test-vm --test-dotfiles /home/user/dotfiles

# Test with path containing spaces
./provision-vm.sh test-vm --test-dotfiles "/home/user/my dotfiles"

# Normal provisioning (uses GitHub)
./provision-vm.sh prod-vm
```

## Deploy Key Setup

VMs use repository-specific deploy keys instead of copying your personal SSH keys. This improves security by:
- **Isolating credentials** - Each VM has a unique key
- **Enabling revocation** - Revoke single VM key without affecting others
- **Providing audit trails** - Track which VM accessed repositories
- **Following least privilege** - Deploy keys are repository-specific
- **Protecting your account** - Your personal SSH key never leaves your machine

### Automatic Skip in Test Mode

When using `--test-dotfiles` with local dotfiles, the deploy key prompt is **automatically skipped** since GitHub access is not needed (dotfiles are copied directly from your host machine):

```bash
./provision-vm.sh test-vm --test-dotfiles ../dotfiles
# ... provisioning happens ...
# Deploy key setup automatically skipped (no manual interaction needed)
```

This smart detection eliminates unnecessary manual steps when testing local dotfiles changes.

### Interactive Setup (Regular Mode)

The provision script includes an **interactive deploy key setup** that pauses after Ansible runs:

```bash
./provision-vm.sh my-vm
# ... provisioning happens ...
# Script will pause and display:

========================================
  📋 DEPLOY KEY SETUP REQUIRED
========================================

To complete dotfiles installation, add this deploy key to GitHub:

ssh-ed25519 AAAAC3Nza... vm-my-vm-deploy-key

Steps:
  1. Open: https://github.com/maxrantil/dotfiles/settings/keys
  2. Click 'Add deploy key'
  3. Title: my-vm-deploy-key
  4. Paste the key above
  5. ✓ Check 'Allow write access' (if needed)
  6. Click 'Add key'

Would you like to pause here to add the deploy key?
Press ENTER after adding the key, or type 'skip' to continue without dotfiles:
```

**Options:**
- Press **ENTER**: Script will wait for you to add the key, then automatically re-run Ansible to install dotfiles
- Type **skip**: Continue without dotfiles (you can install them manually later)

### Manual Setup (Alternative)

If you skipped the interactive setup or need to add the key later:

1. Retrieve the deploy key from the VM:
   ```bash
   ssh -i ~/.ssh/vm_key mr@<VM_IP> 'cat ~/.ssh/id_ed25519.pub'
   ```

2. Go to: https://github.com/maxrantil/dotfiles/settings/keys
3. Click "Add deploy key"
4. Title: `<vm-name>-deploy-key`
5. Paste the key
6. ✓ Check "Allow write access" (only if pushing from VM)
7. Click "Add key"

8. Re-run Ansible to install dotfiles:
   ```bash
   cd ansible
   ansible-playbook -i inventory.ini playbook.yml
   ```

### Key Rotation

To rotate a deploy key:

```bash
# 1. Delete old key from GitHub repository settings
# 2. Remove old key from VM
ssh -i ~/.ssh/vm_key mr@<VM_IP> "rm ~/.ssh/id_ed25519*"

# 3. Re-run Ansible to generate new key
cd ansible
ansible-playbook -i inventory.ini playbook.yml

# 4. Add new deploy key to GitHub (follow steps above)
```

### Security Benefits

- **VM compromise ≠ GitHub account compromise**
- **Independent key revocation** per VM
- **No credential proliferation**
- **Audit trail** of repository access
- **Reduced blast radius** of security incidents

## SSH Access

```bash
ssh -i ~/.ssh/vm_key mr@<VM_IP>
```

## Directory Structure

```
vm-infrastructure/
├── terraform/
│   ├── main.tf           # Main Terraform configuration
│   ├── inventory.tpl     # Ansible inventory template
│   └── terraform.tfvars  # Your variables (gitignored)
├── cloud-init/
│   └── user-data.yaml    # Cloud-init configuration
├── ansible/
│   ├── inventory.d/      # Per-VM inventory fragments (generated)
│   ├── playbook.yml      # Main Ansible playbook
│   └── inventory.ini     # Merged inventory (auto-generated)
└── README.md
```

## Library Organization

The project uses a modular library structure for shared functionality:

### lib/validation.sh

Security-hardened validation functions for:

- **SSH key validation**: Directory permissions, key content, keypair completeness
- **Dotfiles security**: Symlink detection (CVE-1), shell injection prevention (CVE-3), TOCTOU protection (SEC-001)
- **install.sh safety**: Malicious pattern detection (CVE-2), permission validation (SEC-005), whitelist validation (SEC-006)
- **Git repository validation**: Repository integrity checks (BUG-006)

**Usage:**

```bash
#!/bin/bash
source "$(dirname "$0")/lib/validation.sh"
validate_dotfiles_path_exists "/path/to/dotfiles"
```

**Documentation**: See [lib/README.md](lib/README.md) for complete function reference and security coverage.

**Testing**: The validation library is validated via `tests/test_local_dotfiles.sh` (69 tests, 100% passing).

## Security Notes

- **Never commit**:
  - Private SSH keys
  - Terraform state files (`*.tfstate`)
  - `terraform.tfvars` if it contains sensitive data
- **Safe to commit**:
  - Public SSH keys
  - Configuration templates
  - Example files

## Destroying VMs

```bash
cd terraform
terraform destroy -var="vm_name=my-vm"
```

## Error Handling and Rollback

The Ansible playbook includes automatic error handling and rollback mechanisms:

### Automatic Rollback on Failure

If provisioning fails, the playbook automatically attempts to:
- **Remove partially installed packages** (if tracked)
- **Delete dotfiles directory** (if cloning was attempted)
- **Display recovery guidance** with clear next steps

### Recovery Options

When provisioning fails, you have two options:

**Option 1: Destroy and Recreate (Recommended)**
```bash
./destroy-vm.sh <vm-name>
./provision-vm.sh <vm-name>
```

**Option 2: Fix and Re-run**
```bash
# Fix the underlying issue, then:
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

### Provisioning Logs

All provisioning attempts (success or failure) are logged to `provisioning.log` in the ansible directory with timestamps and failure details.

## Integration Tests

The project includes comprehensive integration tests that validate the Ansible playbook's error handling and rollback mechanisms using real VM provisioning.

### Test Coverage

The integration test suite (`tests/test_rollback_integration.sh`) includes 6 tests:

1. **Rescue block executes on package failure** - Verifies rollback when package installation fails
2. **Rescue cleans dotfiles on git clone failure** - Ensures dotfiles directory is removed when cloning fails
3. **Always block logs success** - Confirms `provisioning.log` is created with COMPLETED status on success
4. **Always block logs failure** - Confirms `provisioning.log` is created with FAILED status and error details on failure
5. **Rescue block is idempotent** - Verifies rescue can run multiple times without errors
6. **VM usability after rescue** - Ensures VM remains SSH-accessible and functional after rollback

### Running Tests

#### Full Test Suite

Run all 6 integration tests (estimated runtime: 15-30 minutes):

```bash
cd tests
./test_rollback_integration.sh
```

**Requirements**:
- libvirt/KVM running
- Terraform and Ansible installed
- SSH key at `~/.ssh/vm_key`
- Sufficient disk space for test VMs (6 VMs × 20GB)

**What happens**:
- Provisions real VMs using Terraform
- Runs Ansible playbook with injected failures
- Validates rollback behavior
- Cleans up test VMs automatically (even on Ctrl+C)

#### Isolated Test Execution

Run individual tests for faster iteration:

```bash
# Test 2 only (git clone failure rescue)
./test_rollback_integration_test2_only.sh

# Test 3 only (success logging)
./test_rollback_integration_test3_only.sh

# Test 4 only (failure logging)
./test_rollback_integration_test4_only.sh

# Test 5 only (idempotency)
./test_rollback_integration_test5_only.sh

# Test 6 only (VM usability)
./test_rollback_integration_test6_only.sh
```

**Runtime**: 2-5 minutes per isolated test

### Test Patterns

The integration tests use these patterns:

1. **Playbook Mutation** - Temporarily injects failures into `playbook.yml` (e.g., invalid package names, broken git URLs)
2. **Real VM Provisioning** - Creates actual VMs using Terraform to test against real infrastructure
3. **Automatic Restoration** - Restores original playbook after each test using bash traps
4. **Cleanup on Exit** - Destroys test VMs even on interruption (Ctrl+C) or failure
5. **Output Validation** - Checks Ansible output, log files, and VM state for expected behavior

### Troubleshooting Test Failures

#### Test VMs Not Cleaning Up

**Symptom**: Test VMs remain after test failure

**Solution**:
```bash
# List test VMs
virsh list --all | grep "test-vm-"

# Manually clean up
sudo virsh destroy test-vm-rescue-pkg-<PID>
sudo virsh undefine test-vm-rescue-pkg-<PID>

# Clean up storage volumes
sudo virsh vol-list default | grep "test-vm-"
sudo virsh vol-delete <volume-name> default
```

#### Tests Timing Out

**Symptom**: Tests hang waiting for cloud-init or SSH

**Cause**: Network issues or slow VM startup

**Solution**:
```bash
# Check VM console
virsh console test-vm-<name>
# Exit console: Ctrl+]

# Check cloud-init status in VM
sudo cloud-init status

# Increase timeout in test (edit test_rollback_integration.sh)
# Change: wait_for_vm_ready "$vm_ip" 180
# To:     wait_for_vm_ready "$vm_ip" 300
```

#### Playbook Not Restored

**Symptom**: `ansible/playbook.yml` contains test mutations after failure

**Cause**: Trap didn't execute or backup file missing

**Solution**:
```bash
# Check for backup file
ls -la /tmp/playbook-backup-*

# Restore manually from git
git checkout ansible/playbook.yml

# Or restore from backup
mv /tmp/playbook-backup-<PID> ansible/playbook.yml
```

#### Insufficient Disk Space

**Symptom**: Terraform fails with volume creation errors

**Cause**: Not enough space for 6 test VMs

**Solution**:
```bash
# Check available space
virsh pool-info default

# Run tests individually instead of full suite
./test_rollback_integration_test2_only.sh  # Uses 1 VM at a time
```

### CI/CD Integration

Integration tests are **not** run automatically in CI/CD due to resource requirements (real VMs). Run them manually before major releases or after changes to:
- Ansible playbook structure
- Error handling logic
- Rollback mechanisms
- Logging functionality

## Troubleshooting

### Common Issues

#### 1. libvirt Connection Failed

**Error**:
```
Error: error connecting to libvirt: Failed to connect socket to '/var/run/libvirt/libvirt-sock'
```

**Cause**: libvirt daemon not running or user lacks permissions

**Solutions**:
```bash
# Start libvirt
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

# Add user to libvirt group
sudo usermod -aG libvirt $USER
newgrp libvirt

# Verify connection
virsh list --all
```

---

#### 2. SSH Key Permission Error

**Error**:
```
ERROR: SSH key /home/user/.ssh/id_ed25519 has insecure permissions (644)
```

**Cause**: SSH key file permissions too permissive

**Solution**:
```bash
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

---

#### 3. Terraform Provider Not Found

**Error**:
```
Error: Failed to query available provider packages
```

**Cause**: Terraform libvirt provider not installed

**Solution**:
```bash
# Terraform will download on first run
terraform -chdir=terraform init

# Or manually specify version
terraform -chdir=terraform init -upgrade
```

---

#### 4. VM Already Exists

**Error**:
```
Error: error creating libvirt domain: virError(Code=9, Domain=20)
```

**Cause**: VM with same name already exists

**Solution**:
```bash
# List existing VMs
virsh list --all

# Destroy existing VM
./destroy-vm.sh <vm-name>

# Or manually
virsh destroy <vm-name>
virsh undefine <vm-name>
```

---

#### 5. Ansible Inventory Not Generated

**Error**:
```
ERROR! Ansible could not read inventory file: ansible/inventory.ini
```

**Cause**: Terraform didn't complete successfully

**Solution**:
```bash
# Check Terraform state
terraform -chdir=terraform show

# Regenerate inventory manually
terraform -chdir=terraform output -raw ansible_inventory > ansible/inventory.ini

# Or re-run provision script
./provision-vm.sh <vm-name>
```

---

#### 6. Cloud-init Timeout

**Symptom**: Ansible hangs waiting for SSH connection

**Cause**: Cloud-init taking too long or failed

**Solution**:
```bash
# Check VM console
virsh console <vm-name>
# Press Ctrl+] to exit console

# Check cloud-init status in VM
virsh console <vm-name>
# After login:
sudo cloud-init status

# View cloud-init logs
sudo cat /var/log/cloud-init.log
```

---

#### 7. Dotfiles Clone Failed

**Error**:
```
fatal: could not read from remote repository
```

**Cause**: SSH deploy key not added to GitHub

**Solution**:
1. Check Ansible output for deploy key public key
2. Add key to GitHub: https://github.com/maxrantil/dotfiles/settings/keys
3. Re-run Ansible: `ansible-playbook -i ansible/inventory.ini ansible/playbook.yml`

---

#### 8. Disk Space Full

**Error**:
```
Error: error creating libvirt volume: virError(Code=1, Domain=18)
```

**Cause**: Insufficient disk space in libvirt pool

**Solution**:
```bash
# Check pool space
virsh pool-info default

# Clean up old images
virsh vol-list default
virsh vol-delete <old-image> default

# Or provision with smaller disk (requires terraform.tfvars modification)
# Edit terraform/terraform.tfvars:
# disk_size = 10737418240  # 10GB instead of default 20GB
terraform -chdir=terraform apply -var="vm_name=<vm-name>" -var="disk_size=10737418240"
```

---

### Logs and Debugging

**Terraform Logs**:
```bash
# Enable debug logging
TF_LOG=DEBUG terraform -chdir=terraform apply
```

**Ansible Logs**:
```bash
# Verbose output
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -vvv
```

**VM Console Access**:
```bash
# Connect to VM console
virsh console <vm-name>
# Exit: Ctrl+]
```

**SSH Access**:
```bash
# SSH to VM (after provisioning)
ssh mr@$(virsh domifaddr <vm-name> | awk '/192/ {print $4}' | cut -d/ -f1)
```

---

### Getting Help

If issues persist:
1. Check logs in `terraform/` and `ansible/` directories
2. Verify all prerequisites installed (see Prerequisites section)
3. Open GitHub issue with:
   - Command run
   - Full error output
   - `terraform version`, `ansible --version`, `virsh version`
   - OS and distribution

## Known Issues

### libvirt Provider Cloud-Init Race Condition

**Issue**: The terraform-provider-libvirt has a race condition bug where `libvirt_cloudinit_disk` resources fail with "Storage volume not found" errors when the VM domain tries to reference the cloudinit ISO before it's fully uploaded.

**Error Message**:
```
Error: can't retrieve volume /var/lib/libvirt/images/<vm-name>-cloudinit.iso;<UUID>:
Storage volume not found: no storage vol with matching key
```

**Upstream Tracking**:
- GitHub Issue: [dmacvicar/terraform-provider-libvirt#973](https://github.com/dmacvicar/terraform-provider-libvirt/issues/973)
- Affected Versions: 0.7.x - 0.8.3 (current)

**Root Cause**: The provider generates random UUID suffixes for cloudinit volumes, but the domain creation races with ISO upload, causing lookup failures.

**Our Workaround**: Manual ISO creation using `genisoimage` bypasses the provider's cloudinit_disk resource entirely:
- `terraform/create-cloudinit-iso.sh` - Generates cloud-init ISO manually
- `terraform/main.tf` - Uses `null_resource` + `libvirt_volume` instead of `libvirt_cloudinit_disk`
- This approach eliminates the race condition and UUID suffix issues

**When to Remove Workaround**: Monitor the upstream issue. When a fix is released (likely > v0.8.3), we can migrate back to native `libvirt_cloudinit_disk` resources.

**Testing**: Our workaround has been validated to work reliably across multiple VM provisions. Cloud-init completes successfully within 30 seconds in normal conditions.

---

## License

MIT
