## Problem

vm-infra is a complex tool (Terraform + Ansible + libvirt) but README lacks troubleshooting section. Users struggle with common errors without guidance.

**Impact**: Poor user experience, repeated questions, difficult to debug issues

## Solution

Add comprehensive troubleshooting section to README.md covering common provisioning errors.

## Troubleshooting Section Content

### Structure

```markdown
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

# Or provision with smaller disk
./provision-vm.sh <vm-name> 4096 2 20  # 20GB instead of default 50GB
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
2. Verify all prerequisites installed (see Requirements section)
3. Open GitHub issue with:
   - Command run
   - Full error output
   - `terraform version`, `ansible --version`, `virsh version`
   - OS and distribution
```

## Implementation Checklist

- [ ] Create troubleshooting section in README
- [ ] Document 7-8 common errors
- [ ] Add solutions with commands
- [ ] Add logs and debugging section
- [ ] Add getting help section
- [ ] Test all commands work
- [ ] Verify solutions accurate
- [ ] Update table of contents

## Files to Update

- `README.md` (add Troubleshooting section)

## Acceptance Criteria

- [ ] Troubleshooting section added
- [ ] 7-8 common errors documented
- [ ] Each error has:
  - Error message example
  - Cause explanation
  - Solution with commands
- [ ] Logs and debugging documented
- [ ] Getting help section added
- [ ] Table of contents updated

## Priority

**HIGH** - Complete in Week 1 (improves user experience)
