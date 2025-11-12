# Multi-VM Workflow Guide

**Purpose**: Managing 4-5 isolated VMs for independent open source project work

**Last Updated**: 2025-11-12

---

## Overview

This guide explains how to provision and manage multiple VMs simultaneously, each dedicated to a single open source repository. This workflow provides complete isolation between projects while maintaining a consistent development environment.

## Use Case

**Doctor Hubert's Setup**: Maintain 4-5 VMs, each working on a different open source repository:

```
work-vm-1 → Repository A (e.g., pytest)
work-vm-2 → Repository B (e.g., django)
work-vm-3 → Repository C (e.g., ansible)
work-vm-4 → Repository D (e.g., terraform)
work-vm-5 → Repository E (e.g., kubernetes)
```

**Benefits**:
- **Complete isolation** - Each VM is independent
- **No dependency conflicts** - Different Python/Node versions per VM
- **Clean slate** - Destroy/recreate VMs without affecting others
- **Parallel work** - Work on multiple projects simultaneously
- **Easy context switching** - SSH into the VM for that project

---

## VM Naming Convention

### Recommended Naming Pattern

```bash
# Pattern: <purpose>-vm-<number>
work-vm-1
work-vm-2
work-vm-3
work-vm-4
work-vm-5

# Alternative patterns
<project-name>-vm        # pytest-vm, django-vm
<org>-<repo>-vm          # apache-kafka-vm
test-vm                  # For testing dotfiles/configs
sandbox-vm               # Experimental work
```

### Naming Best Practices

- **Use descriptive prefixes** (`work-`, `test-`, `prod-`)
- **Sequential numbering** for similar VMs (`work-vm-1`, `work-vm-2`)
- **Avoid special characters** (stick to alphanumeric and hyphens)
- **Keep names short** (<20 characters for easy typing)

---

## Provisioning Multiple VMs

### Sequential Provisioning

Provision VMs one at a time (recommended for first-time setup):

```bash
# Provision 5 work VMs with local dotfiles testing
SKIP_WHITELIST_CHECK=1 ./provision-vm.sh work-vm-1 4096 2 --test-dotfiles /home/mqx/workspace/dotfiles
SKIP_WHITELIST_CHECK=1 ./provision-vm.sh work-vm-2 4096 2 --test-dotfiles /home/mqx/workspace/dotfiles
SKIP_WHITELIST_CHECK=1 ./provision-vm.sh work-vm-3 4096 2 --test-dotfiles /home/mqx/workspace/dotfiles
SKIP_WHITELIST_CHECK=1 ./provision-vm.sh work-vm-4 4096 2 --test-dotfiles /home/mqx/workspace/dotfiles
SKIP_WHITELIST_CHECK=1 ./provision-vm.sh work-vm-5 4096 2 --test-dotfiles /home/mqx/workspace/dotfiles
```

**Note**: Deploy key prompt is automatically skipped when using `--test-dotfiles` (smart detection).

### Resource Allocation

Adjust memory and vCPUs based on project needs:

```bash
# Light projects (documentation, scripts)
./provision-vm.sh light-vm 2048 1

# Standard projects (web apps, CLI tools)
./provision-vm.sh standard-vm 4096 2

# Heavy projects (databases, compilers)
./provision-vm.sh heavy-vm 8192 4
```

### Parallel Provisioning (Advanced)

For experienced users, provision multiple VMs in parallel:

```bash
# Background provisioning (use with caution)
for i in {1..5}; do
    SKIP_WHITELIST_CHECK=1 ./provision-vm.sh work-vm-$i 4096 2 --test-dotfiles /home/mqx/workspace/dotfiles &
done

# Wait for all to complete
wait
```

**Warning**: Parallel provisioning can strain system resources. Monitor with:
```bash
# Watch resource usage
htop

# Check VM status
virsh list --all
```

---

## SSH Access Patterns

### Direct IP Access

Each VM gets a unique IP address. Access via:

```bash
# Basic SSH access
ssh -i ~/.ssh/vm_key mr@<VM_IP>

# Example: work-vm-1 at 192.168.122.188
ssh -i ~/.ssh/vm_key mr@192.168.122.188
```

### Get VM IP Address

```bash
# Method 1: From Terraform output
cd terraform
terraform output vm_ip

# Method 2: From virsh
virsh domifaddr work-vm-1

# Method 3: From merged inventory
grep work-vm-1 ansible/inventory.ini
```

### SSH Config for Easy Access

Create `~/.ssh/config` entries for quick access:

```ssh
# work-vm-1
Host work-vm-1
    HostName 192.168.122.188
    User mr
    IdentityFile ~/.ssh/vm_key
    StrictHostKeyChecking no

# work-vm-2
Host work-vm-2
    HostName 192.168.122.189
    User mr
    IdentityFile ~/.ssh/vm_key
    StrictHostKeyChecking no

# ... repeat for other VMs
```

Then simply:
```bash
ssh work-vm-1
ssh work-vm-2
```

### SSH Access Script (Helper)

Create a helper script `vm-ssh.sh`:

```bash
#!/bin/bash
# ABOUTME: Helper script to SSH into VMs by name

VM_NAME="$1"

if [ -z "$VM_NAME" ]; then
    echo "Usage: $0 <vm-name>"
    echo "Example: $0 work-vm-1"
    exit 1
fi

# Get IP from merged inventory
VM_IP=$(grep "^$VM_NAME " ansible/inventory.ini | awk '{print $2}' | cut -d'=' -f2)

if [ -z "$VM_IP" ]; then
    echo "ERROR: VM '$VM_NAME' not found in inventory"
    exit 1
fi

ssh -i ~/.ssh/vm_key mr@"$VM_IP"
```

Usage:
```bash
chmod +x vm-ssh.sh
./vm-ssh.sh work-vm-1
```

---

## VM Lifecycle Management

### Check VM Status

```bash
# List all VMs
virsh list --all

# Check specific VM
virsh dominfo work-vm-1

# Check all work VMs
virsh list --all | grep work-vm
```

### Start/Stop VMs

```bash
# Stop VM (keep data)
virsh shutdown work-vm-1

# Force stop (if graceful shutdown fails)
virsh destroy work-vm-1

# Start stopped VM
virsh start work-vm-1
```

### Destroy Individual VMs

```bash
# Destroy single VM (other VMs unaffected)
./destroy-vm.sh work-vm-1

# Manual destruction
virsh destroy work-vm-1
virsh undefine work-vm-1
sudo virsh vol-delete work-vm-1.qcow2 default
sudo virsh vol-delete work-vm-1-cloudinit.iso default
```

### Bulk Operations

```bash
# Stop all work VMs
for i in {1..5}; do virsh shutdown work-vm-$i; done

# Destroy all work VMs
for i in {1..5}; do ./destroy-vm.sh work-vm-$i; done

# List all work VM IPs
grep work-vm ansible/inventory.ini
```

---

## Isolation Best Practices

### 1. One Repository Per VM

**Pattern**:
```bash
# SSH into VM
ssh -i ~/.ssh/vm_key mr@<work-vm-1-ip>

# Clone single repository
git clone https://github.com/org/repo.git
cd repo

# Work exclusively in this repo
# ... make changes, test, commit ...
```

**Benefits**:
- No dependency conflicts between projects
- Clean git history per project
- Easy to nuke and start fresh

### 2. Avoid Shared State

**Don't**:
- Share SSH keys between VMs (use VM-specific deploy keys)
- Mount shared filesystems across VMs
- Run services that bind to host network

**Do**:
- Keep each VM completely independent
- Use Ansible to sync configs if needed
- Destroy and recreate VMs regularly

### 3. Resource Isolation

```bash
# Monitor resource usage
virsh domstats work-vm-1

# Adjust resources if needed (requires shutdown)
virsh shutdown work-vm-1
virsh setmem work-vm-1 8192M --config
virsh setvcpus work-vm-1 4 --config
virsh start work-vm-1
```

### 4. Network Isolation

All VMs share the `default` libvirt network (192.168.122.0/24):
- VMs can communicate with each other
- VMs have internet access via NAT
- Host can access VMs
- External networks cannot access VMs (good for security)

For stricter isolation, create separate networks (advanced).

---

## Workflow Examples

### Example 1: Daily Multi-Project Work

```bash
# Morning routine: SSH into work-vm-2 (django project)
ssh work-vm-2
cd django
git pull
# ... work on Issue #123 ...
git add .
git commit -m "Fix #123: Add CSRF validation"
git push
exit

# Afternoon: Switch to work-vm-3 (ansible project)
ssh work-vm-3
cd ansible
git pull
# ... work on Issue #456 ...
git add .
git commit -m "Fix #456: Update playbook"
git push
exit
```

### Example 2: Testing Changes Across VMs

```bash
# Test same script across multiple VMs
for i in {1..5}; do
    echo "Testing on work-vm-$i"
    ssh work-vm-$i 'cd repo && ./run-tests.sh'
done
```

### Example 3: Recreating a Single VM

```bash
# Issue with work-vm-2, nuke and recreate
./destroy-vm.sh work-vm-2
SKIP_WHITELIST_CHECK=1 ./provision-vm.sh work-vm-2 4096 2 --test-dotfiles /home/mqx/workspace/dotfiles

# Other VMs (work-vm-1, work-vm-3, work-vm-4, work-vm-5) unaffected
```

### Example 4: Using project-templates in VMs

```bash
# SSH into VM
ssh work-vm-1

# Copy project template
cp -r ~/project-templates/python-project ~/my-new-cli-tool
cd ~/my-new-cli-tool

# Initialize project
git init
git add .
git commit -m "Initial commit from template"

# Start working
# ... implement your tool ...
```

---

## Integration with project-templates

The [project-templates](https://github.com/maxrantil/project-templates) repository provides starter templates for new projects. Use them **inside VMs** for isolated project setup:

### Setup project-templates in VM

```bash
# SSH into VM
ssh work-vm-1

# Clone project-templates (one-time setup)
cd ~
git clone https://github.com/maxrantil/project-templates.git

# Use templates for new projects
cp -r ~/project-templates/python-project ~/my-new-project
cd ~/my-new-project
git init && git add . && git commit -m "Initial commit from template"
```

### Available Templates

- **python-project/** - Python with pyproject.toml, pytest, pre-commit
- **shell-project/** - Shell scripts with ShellCheck, shfmt
- Centralized GitHub Actions workflows

### Relationship to dotfiles

```
dotfiles/           → Base environment (zsh, git, vim, starship)
                     → Installed automatically during VM provisioning

project-templates/ → Project scaffolding (CI/CD, tooling, structure)
                     → Copied manually when starting new projects
```

---

## Troubleshooting Multi-VM Setups

### VM IP Conflicts

**Symptom**: Two VMs get the same IP address

**Solution**:
```bash
# Restart libvirt network
sudo virsh net-destroy default
sudo virsh net-start default

# Restart VMs
virsh shutdown work-vm-1
virsh start work-vm-1
```

### Out of Disk Space

**Symptom**: Cannot provision new VMs

**Solution**:
```bash
# Check libvirt pool space
virsh pool-info default

# Destroy unused VMs
./destroy-vm.sh old-test-vm

# Clean up old volumes
virsh vol-list default
virsh vol-delete old-volume.qcow2 default
```

### SSH Connection Refused

**Symptom**: Cannot SSH into VM after provisioning

**Solutions**:
```bash
# 1. Check VM is running
virsh list --all

# 2. Verify cloud-init completed
virsh console work-vm-1
# Check: cloud-init status

# 3. Test network connectivity
ping <VM_IP>

# 4. Verify SSH key permissions
ls -la ~/.ssh/vm_key
# Should be 600

# 5. Check SSH service in VM
ssh -i ~/.ssh/vm_key mr@<VM_IP> 'sudo systemctl status sshd'
```

### Merged Inventory Out of Sync

**Symptom**: `ansible/inventory.ini` doesn't reflect current VMs

**Solution**:
```bash
# Regenerate merged inventory
cd terraform
for vm in work-vm-*; do
    terraform apply -var="vm_name=$vm"
done

# Or manually merge fragments
cat ansible/inventory.d/*.ini > ansible/inventory.ini
```

---

## Resource Planning

### Disk Space Requirements

| VM Count | Base Images | VM Disks (20GB each) | Total Minimum |
|----------|-------------|----------------------|---------------|
| 1 VM     | ~5GB        | 20GB                 | ~25GB         |
| 3 VMs    | ~5GB        | 60GB                 | ~65GB         |
| 5 VMs    | ~5GB        | 100GB                | ~105GB        |

**Recommendation**: 150GB free space for 5 VMs + overhead

### Memory Requirements

| VM Count | Per-VM RAM | Host RAM Needed | Recommended Total RAM |
|----------|------------|-----------------|----------------------|
| 1 VM     | 4GB        | 4GB             | 8GB                  |
| 3 VMs    | 4GB        | 12GB            | 16GB                 |
| 5 VMs    | 4GB        | 20GB            | 32GB                 |

**Note**: Assumes other VMs running simultaneously. Use `virsh shutdown` to free memory.

### CPU Allocation

```bash
# Check host CPU count
nproc

# Rule of thumb: Don't allocate more vCPUs than physical cores
# Example: 8-core host → Max 8 vCPUs total across all VMs

# For 5 VMs on 8-core host:
# Option A: 5 VMs × 1 vCPU = 5 vCPUs (light workload)
# Option B: 5 VMs × 2 vCPUs = 10 vCPUs (overcommit acceptable)
```

---

## Maintenance Tasks

### Weekly Cleanup

```bash
# Destroy test/sandbox VMs
./destroy-vm.sh test-vm
./destroy-vm.sh sandbox-vm

# Update base Ubuntu image
sudo virsh vol-delete ubuntu-22.04-base.qcow2 default
# Re-download base image (see main README)
```

### Monthly Review

```bash
# List all VMs and their uptime
for vm in $(virsh list --name); do
    echo "$vm: $(virsh dominfo $vm | grep 'CPU time')"
done

# Review disk usage
virsh pool-info default

# Archive or destroy unused VMs
```

---

## Advanced: Custom Multi-VM Script

For frequent multi-VM operations, create `provision-work-vms.sh`:

```bash
#!/bin/bash
# ABOUTME: Provision all work VMs in sequence

set -e

VM_COUNT=5
MEMORY=4096
VCPUS=2
DOTFILES_PATH="/home/mqx/workspace/dotfiles"

for i in $(seq 1 $VM_COUNT); do
    VM_NAME="work-vm-$i"
    echo "========================================"
    echo "Provisioning $VM_NAME ($i/$VM_COUNT)"
    echo "========================================"

    SKIP_WHITELIST_CHECK=1 ./provision-vm.sh "$VM_NAME" "$MEMORY" "$VCPUS" --test-dotfiles "$DOTFILES_PATH"

    echo ""
    echo "✓ $VM_NAME provisioned successfully"
    echo ""
done

echo "========================================"
echo "✓ All $VM_COUNT VMs provisioned!"
echo "========================================"
echo ""
echo "Access VMs:"
for i in $(seq 1 $VM_COUNT); do
    VM_IP=$(grep "work-vm-$i " ansible/inventory.ini | awk '{print $2}' | cut -d'=' -f2)
    echo "  work-vm-$i: ssh -i ~/.ssh/vm_key mr@$VM_IP"
done
```

Usage:
```bash
chmod +x provision-work-vms.sh
./provision-work-vms.sh
```

---

## Summary

**Key Takeaways**:
- ✅ Use descriptive VM names (work-vm-1, work-vm-2, etc.)
- ✅ One repository per VM for maximum isolation
- ✅ SSH via VM-specific IPs or SSH config aliases
- ✅ Destroy and recreate VMs freely (others unaffected)
- ✅ Monitor resources (disk, RAM, CPU) regularly
- ✅ Use `--test-dotfiles` for streamlined provisioning (auto-skips deploy key prompt)

**Next Steps**:
1. Provision your first work VM: `./provision-vm.sh work-vm-1 4096 2 --test-dotfiles /path`
2. SSH into it: `ssh -i ~/.ssh/vm_key mr@<IP>`
3. Clone your target repository
4. Start working on issues in isolation!
