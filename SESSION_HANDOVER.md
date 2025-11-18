# Session Handoff: Mullvad VM Setup & Multi-VM Bug Fix

**Date**: 2025-11-18
**Issues**: #120 (VM deletion bug), #121 (LibreWolf fix)
**Primary VM**: ubuntu (mullvad user, 192.168.122.178)
**Branch**: fix/librewolf-installation

---

## ✅ Completed Work

### 1. Mullvad VM Provisioned Successfully
- ✅ **VM Name**: ubuntu
- ✅ **Hostname**: ubuntu (auto-configured from VM name per PR #118)
- ✅ **Username**: mullvad
- ✅ **IP Address**: 192.168.122.178
- ✅ **Resources**: 4096MB RAM, 2 vCPUs
- ✅ **SSH Access**: `ssh -i ~/.ssh/vm_key mullvad@192.168.122.178`
- ✅ **Status**: Running and fully accessible

### 2. Development Environment Setup
**Tools Installed:**
- ✅ **Rust**: 1.91.0 (via rustup, toolchain configured automatically)
- ✅ **Node.js**: v24.11.1
- ✅ **npm**: 11.6.2
- ✅ **Go**: 1.18.1
- ✅ **Build tools**: gcc, libdbus-1-dev, rpm, protobuf-compiler, libprotobuf-dev
- ✅ **LibreWolf**: 144.0.2-1 (after fix)

**Mullvad VPN App:**
- ✅ Repository cloned: `~/mullvadvpn-app`
- ✅ Submodules initialized (wireguard-go, iOS/Android, Windows libs)
- ✅ Initial build started (Rust dependencies downloading)
- ✅ Ready for development contributions

### 3. Dotfiles Installation Fixed
**Problem:** Dotfiles weren't installed due to LibreWolf failure
**Root Cause:** Ansible playbook failed at LibreWolf installation (404 on GPG key)

**Resolution:**
- ✅ Re-ran Ansible playbook after LibreWolf fix
- ✅ Dotfiles copied from host `/home/mqx/workspace/dotfiles` to VM
- ✅ `install.sh` executed successfully
- ✅ Default shell changed to zsh
- ✅ Starship prompt configured
- ✅ All symlinks created (.zshrc, .aliases, .tmux.conf, starship.toml, etc.)

### 4. LibreWolf Installation Fixed (Issue #121)
**Problem:** LibreWolf GPG key URL returned 404 error
- Old URL: `https://deb.librewolf.net/keyring.gpg` (broken)
- Method: Manual GPG key download (deprecated)

**Solution:** Updated to official extrepo method
- ✅ Install `extrepo` package
- ✅ Run `extrepo enable librewolf`
- ✅ New repository: `https://repo.librewolf.net`
- ✅ Tested and verified: LibreWolf 144.0.2-1 installed successfully

**Git Workflow:**
- ✅ Created branch: `fix/librewolf-installation`
- ✅ Committed changes with proper message
- ✅ All pre-commit hooks passed
- ✅ Pushed to GitHub
- ✅ Created PR #121

### 5. Multi-VM Deletion Bug Identified (Issue #120)
**Critical Discovery:**
- ⚠️ **lightning-dev VM was destroyed** when provisioning ubuntu VM
- **Root Cause**: Terraform uses single state file managing one VM at a time
- **Impact**: All VM resources deleted (disk, cloud-init ISO, domain)
- **Data Loss**: lightning-dev.qcow2 permanently deleted

**Issue Created:**
- ✅ Issue #120: "Bug: Creating new VM destroys existing VM due to single Terraform state"
- ✅ Comprehensive documentation of problem, impact, and possible solutions
- ✅ Tagged with `bug` label

---

## 🎯 Current Project State

**VMs Running:**
- ✅ **ubuntu VM**: Running (192.168.122.178)
- ❌ **lightning-dev VM**: Destroyed (Issue #120)

**Tests**: ✅ All passing (vm-infra)
**Branches**:
- `master`: Clean (up to date)
- `fix/librewolf-installation`: Pushed, PR #121 created

**Open Issues:**
- 🔴 **Issue #120**: Multi-VM support broken (HIGH PRIORITY)
- 🟢 **PR #121**: LibreWolf fix ready for review

**Environment State:**
- ✅ ubuntu VM fully configured with dotfiles
- ✅ Mullvad development environment ready
- ✅ Rust/Node.js/Go toolchains installed
- ✅ mullvadvpn-app repository cloned and building

---

## 🚀 Next Session Priorities

**Immediate Next Steps (Doctor Hubert's Request):**
1. **FIX MULTI-VM SUPPORT** (Issue #120) - Highest Priority
2. Test creating new VM without destroying ubuntu VM
3. Verify both VMs can coexist

**Implementation Approach:**

**Option 1: Terraform Workspaces** (Recommended)
- Use `terraform workspace` to isolate VM state
- Each VM gets its own state in separate workspace
- Commands: `terraform workspace new vm-name`

**Option 2: Terraform Modules**
- Parameterize VM creation as a module
- Each VM instance independent
- Requires refactoring `terraform/main.tf`

**Option 3: Separate State Files**
- Use `-state=terraform-<vm-name>.tfstate` flag
- Modify `provision-vm.sh` to pass state file per VM
- Simplest implementation

**Roadmap Context:**
- Multi-VM support is critical for project usability
- Current docs (`MULTI-VM-WORKFLOW.md`) exist but implementation broken
- Need to restore lightning-dev VM after fixing multi-VM
- Mullvad VM ready for contributions after multi-VM fix

---

## 📝 Startup Prompt for Next Session

Read CLAUDE.md to understand our workflow, then fix Issue #120 (multi-VM deletion bug).

**Immediate priority**: Implement multi-VM support so creating new VMs doesn't destroy existing ones (3-5 hours)
**Context**: ubuntu VM running successfully, lightning-dev was destroyed when ubuntu created, Terraform uses single state file
**Reference docs**: Issue #120, docs/MULTI-VM-WORKFLOW.md, terraform/main.tf, provision-vm.sh
**Ready state**: Clean master branch, PR #121 (LibreWolf fix) pending review, ubuntu VM operational

**Expected scope**:
1. Choose multi-VM solution (workspace/modules/separate states)
2. Implement changes to terraform/main.tf and provision-vm.sh
3. Test by creating test-vm without destroying ubuntu
4. Document solution and update MULTI-VM-WORKFLOW.md
5. Create PR for multi-VM fix

**Success criteria**: Can run `./provision-vm.sh test-vm testuser 2048 1` and both ubuntu + test-vm coexist

---

## 📚 Key Reference Documents

### Issues & PRs
- **Issue #120**: https://github.com/maxrantil/vm-infra/issues/120 (Multi-VM bug)
- **PR #121**: https://github.com/maxrantil/vm-infra/pull/121 (LibreWolf fix)
- **PR #118**: Configurable username/hostname (merged)

### Code Files
- `provision-vm.sh`: Lines 1-100 (VM provisioning script)
- `terraform/main.tf`: Terraform VM configuration
- `ansible/playbook.yml`: Lines 163-184 (LibreWolf installation - FIXED)
- `docs/MULTI-VM-WORKFLOW.md`: Multi-VM documentation

### VM Access
```bash
# Access ubuntu/mullvad VM
ssh -i ~/.ssh/vm_key mullvad@192.168.122.178

# Check running VMs
sudo virsh list --all

# Check VM disks
ls -lh /var/lib/libvirt/images/
```

### Mullvad Development
```bash
# Inside VM
cd ~/mullvadvpn-app
source ~/.cargo/env
cargo build --bin mullvad-daemon  # Build daemon
cd desktop && npm install -w mullvad-vpn  # Desktop app
```

---

## Implementation Details

### LibreWolf Fix (PR #121)

**File**: `ansible/playbook.yml`

**Changes:**
```yaml
# Before (BROKEN):
- name: Download LibreWolf GPG key
  get_url:
    url: https://deb.librewolf.net/keyring.gpg
    dest: /usr/share/keyrings/librewolf.gpg

# After (WORKING):
- name: Install extrepo package
  apt:
    name: extrepo
    state: present
    update_cache: yes

- name: Enable LibreWolf repository via extrepo
  command: extrepo enable librewolf
  args:
    creates: /etc/apt/sources.list.d/extrepo_librewolf.sources
```

**Verification:**
- ✅ Tested on ubuntu VM (192.168.122.178)
- ✅ LibreWolf 144.0.2-1 installed successfully
- ✅ `librewolf --version` works
- ✅ Repository: https://repo.librewolf.net

---

## Multi-VM Bug Analysis (Issue #120)

### Current Terraform State Behavior

**Problem Code** (`terraform/main.tf`):
```hcl
resource "libvirt_domain" "vm" {
  name   = var.vm_name  # Single resource, replaced when name changes
  memory = var.memory
  vcpu   = var.vcpus
  ...
}
```

**What Happens:**
1. First run: `provision-vm.sh lightning-dev ...`
   - Creates `libvirt_domain.vm` with name="lightning-dev"
   - State stored in `terraform.tfstate`

2. Second run: `provision-vm.sh ubuntu ...`
   - Terraform sees `libvirt_domain.vm` with different name
   - **Destroys** lightning-dev VM
   - **Creates** ubuntu VM
   - State updated with ubuntu only

### Proposed Solutions

**Option 1: Terraform Workspaces** ⭐ RECOMMENDED
```bash
# In provision-vm.sh
cd terraform
terraform workspace new "$VM_NAME" || terraform workspace select "$VM_NAME"
terraform apply -var="vm_name=$VM_NAME" ...
```

**Pros:**
- ✅ Clean separation of VM states
- ✅ Built-in Terraform feature
- ✅ Easy to list/switch: `terraform workspace list`
- ✅ Minimal code changes

**Cons:**
- ❌ All workspaces share same backend
- ❌ Slightly more complex state management

**Option 2: Resource Count/For-Each**
```hcl
variable "vms" {
  type = map(object({
    memory = number
    vcpus  = number
  }))
}

resource "libvirt_domain" "vm" {
  for_each = var.vms
  name     = each.key
  memory   = each.value.memory
  vcpu     = each.value.vcpus
  ...
}
```

**Pros:**
- ✅ Single state file with all VMs
- ✅ Terraform best practice

**Cons:**
- ❌ Major refactoring required
- ❌ Must track all VMs in variables

**Option 3: Separate State Files**
```bash
# In provision-vm.sh
terraform apply \
  -state="terraform-${VM_NAME}.tfstate" \
  -var="vm_name=$VM_NAME" ...
```

**Pros:**
- ✅ Simplest implementation
- ✅ Complete isolation per VM
- ✅ Minimal changes needed

**Cons:**
- ❌ Manual state file management
- ❌ No centralized view of all VMs

---

## Testing Plan for Multi-VM Fix

### Test Case 1: Preserve Existing VM
```bash
# Current state: ubuntu VM running
sudo virsh list --all  # Should show: ubuntu

# Create new test VM
./provision-vm.sh test-vm testuser 2048 1

# Verify both exist
sudo virsh list --all  # Should show: ubuntu, test-vm
ls /var/lib/libvirt/images/  # Should have: ubuntu.qcow2, test-vm.qcow2
```

### Test Case 2: Independent VM Lifecycle
```bash
# Destroy test VM
./destroy-vm.sh test-vm

# Verify ubuntu still exists
sudo virsh list --all  # Should show: ubuntu (test-vm gone)
ssh -i ~/.ssh/vm_key mullvad@192.168.122.178  # Should work
```

### Test Case 3: Terraform State Isolation
```bash
# Verify separate states
ls terraform/  # Should show workspace dirs or separate .tfstate files
terraform workspace list  # Should show: ubuntu, test-vm (if using workspaces)
```

---

## Session Completion Summary

**What was accomplished:**
1. ✅ Provisioned ubuntu VM for Mullvad contributions
2. ✅ Installed full development environment (Rust, Node, Go, build tools)
3. ✅ Cloned and initialized mullvadvpn-app repository
4. ✅ Fixed LibreWolf installation (PR #121 created)
5. ✅ Fixed dotfiles installation (re-ran Ansible successfully)
6. ✅ Identified and documented multi-VM deletion bug (Issue #120)
7. ✅ Researched LibreWolf official installation method
8. ✅ Analyzed multi-VM solutions (workspaces, modules, separate states)

**Time taken:** ~2 hours (VM setup, debugging, research, fixes)

**Quality metrics:**
- ✅ **VM Setup**: Complete and operational
- ✅ **Bug Identification**: Thorough root cause analysis
- ✅ **LibreWolf Fix**: Tested and verified working
- ✅ **Documentation**: Issue #120 and PR #121 comprehensive
- ✅ **Git Hygiene**: Proper branch workflow, conventional commits

**Blockers for Mullvad work:** None - VM ready for development

**Critical Issue for Next Session:** Multi-VM support must be fixed before creating more VMs

---

✅ **Session Handoff Complete**

**Handoff documented**: SESSION_HANDOVER.md (updated)
**Status**:
- ✅ ubuntu VM operational and ready
- ✅ PR #121 (LibreWolf fix) created
- 🔴 Issue #120 (multi-VM bug) documented, needs implementation

**Environment**:
- ubuntu VM: Clean, dotfiles working, zsh configured, dev tools ready
- Repository: Clean master, fix/librewolf-installation branch pushed

**Ready for Doctor Hubert:** Next session should implement multi-VM fix (Issue #120) using workspaces/modules/separate states approach.
