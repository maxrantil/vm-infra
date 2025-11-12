# Session Handoff: Local Dotfiles Testing & Multi-VM Infrastructure

**Date**: 2025-11-12
**Session Focus**: Implement `--test-dotfiles` flag + provision first persistent work VM
**Branch**: master
**Status**: ✅ Feature complete and committed (db46abc)

---

## ✅ Completed Work

### 1. Local Dotfiles Testing Implementation (Commit: db46abc)

**Three-part implementation:**

#### Part A: SKIP_WHITELIST_CHECK Bypass (lib/validation.sh:404-408)
- **Problem**: SEC-006 whitelist only allows ~12 commands, blocks normal bash (if/for/functions)
- **Solution**: `SKIP_WHITELIST_CHECK=1` environment variable for trusted local dotfiles
- **Behavior**: Auto-approves 59 "potentially unsafe" commands (legitimate bash constructs)
- **Security**: Only use for trusted local dotfiles, never remote sources

#### Part B: Synchronize Module (ansible/playbook.yml:228-250)
- **Problem**: `git file://` doesn't work (host path not accessible from VM)
- **Solution**: Ansible `synchronize` module (copies dotfiles host → VM)
- **Fallback**: GitHub clone when `dotfiles_local_path` not defined (backward compatible)
- **Result**: Dotfiles copied successfully, no GitHub access needed

#### Part C: TPM Temporarily Disabled (ansible/playbook.yml:305-313)
- **Issue**: TMux Plugin Manager clone conflicts with dotfiles `.gitconfig`
- **Root cause**: User's `.gitconfig` rewrites `https://github.com/` → `git@github.com:`
- **Workaround**: Commented out TPM installation task
- **TODO**: Fix git URL rewriting or use `GIT_CONFIG_GLOBAL=/dev/null`

### 2. Validation Results

**test-vm** (first validation):
- ✅ 35/35 Ansible tasks passed
- ✅ Dotfiles synchronized successfully
- ✅ Pragma system working (7 patterns allowed)
- ✅ SKIP_WHITELIST_CHECK functioning (59 commands auto-approved)

**work-vm-1** (persistent VM test):
- ✅ 35/35 Ansible tasks passed
- ✅ IP: 192.168.122.188
- ✅ Dotfiles synchronized successfully
- ⚠️ Auto-destroyed after deploy key timeout (expected)

### 3. Explored project-templates Repository

**Purpose**: Starter templates for new projects (Python/Shell + CI/CD)
**Location**: `/home/mqx/workspace/project-templates`
**Contents**:
- `python-project/` - Python project with pyproject.toml, pytest, pre-commit
- `shell-project/` - Shell scripts with ShellCheck, shfmt
- Centralized GitHub Actions workflows

**Usage Pattern**: Copy template → customize → start new project
**Relationship to dotfiles**:
- dotfiles = base environment (zsh, git, vim, starship)
- project-templates = project scaffolding (CI/CD, tooling, structure)

---

## 🎯 Current Project State

**Branch**: master
**Working Directory**: Clean (all changes committed)
**Last Commit**: `db46abc` - feat: implement local dotfiles synchronization for testing
**Tests**: All passing (validated with test-vm + work-vm-1)
**CI/CD**: Not applicable (no remote push yet)

### Usage Command

```bash
# Provision VM with local dotfiles (for testing dotfiles changes)
SKIP_WHITELIST_CHECK=1 ./provision-vm.sh <vm-name> 4096 2 --test-dotfiles /home/mqx/workspace/dotfiles

# When prompted for deploy key, type "skip" (not needed for local testing)
```

---

## 🔍 Deploy Key Explanation (Doctor Hubert's Question)

**What is the deploy key prompt for?**

The provisioning script generates a **VM-specific SSH deploy key** and prompts you to add it to your GitHub dotfiles repository. Here's the full picture:

**Purpose**: Allow the VM to clone your **private** dotfiles repo from GitHub
**Security**: Each VM gets unique key (isolation principle)
**When generated**: Always (even with `--test-dotfiles`)
**When needed**: Only for regular (non-`--test-dotfiles`) provisioning

**Current Behavior:**
```
--test-dotfiles mode:
  1. Ansible generates deploy key (always happens)
  2. Ansible uses synchronize to copy dotfiles (host → VM)
  3. Script prompts for deploy key (unnecessary, can type "skip")
  4. VM fully functional regardless of deploy key

Regular mode (no --test-dotfiles):
  1. Ansible generates deploy key
  2. Script prompts to add key to GitHub
  3. Ansible clones dotfiles from GitHub using deploy key
  4. Deploy key REQUIRED for this workflow
```

**Why you can skip it**: When using `--test-dotfiles`, dotfiles are already copied via `synchronize`, so GitHub access isn't needed.

**Current inefficiency**: The deploy key prompt appears even in `--test-dotfiles` mode where it's not needed.

---

## 🚀 Next Session Priorities

### Immediate Tasks

**1. Explore --non-interactive Flag** (Doctor Hubert's question)
- **Context**: Deploy key prompt appears even when using `--test-dotfiles`
- **Current workaround**: User types "skip" manually
- **Options to explore**:
  - Option A: `--non-interactive` flag to auto-skip deploy key prompt
  - Option B: Smart detection (skip prompt when `--test-dotfiles` used)
  - Option C: Separate the deploy key generation from the prompt
- **Analysis needed**: When would we want interactive vs non-interactive?

**2. Document Multi-VM Workflow** (Doctor Hubert requested)
- **Purpose**: Document how to manage 4-5 VMs for isolated open source work
- **Content needed**:
  - VM naming convention (work-vm-1, work-vm-2, etc.)
  - How to provision multiple VMs
  - How to SSH into specific VMs
  - How to destroy VMs when done
  - How to use project-templates inside VMs
  - Best practices for VM isolation
- **Location**: Create `docs/MULTI-VM-WORKFLOW.md` or add to README.md?

### Follow-Up Tasks

**3. Provision Persistent work-vm-1**
- Previous attempt auto-destroyed after deploy key timeout
- Next session: provision and keep it running (type "skip" at prompt)
- Test SSH access and verify dotfiles work

**4. Fix TPM Installation**
- **Issue**: `.gitconfig` rewrites HTTPS → SSH for all GitHub URLs
- **Impact**: Public repos fail to clone (no deploy key for public repos)
- **Solutions to explore**:
  - Use `GIT_CONFIG_GLOBAL=/dev/null` when cloning TPM
  - Clone TPM before dotfiles install (before `.gitconfig` applied)
  - Fix `.gitconfig` to not rewrite public HTTPS URLs
  - Make TPM optional/skippable

---

## 📝 Startup Prompt for Next Session

Read CLAUDE.md to understand our workflow, then continue VM infrastructure multi-VM workflow implementation.

**Previous session**: Local dotfiles testing feature complete (commit db46abc), work-vm-1 validated successfully
**Context**: Doctor Hubert wants to run 4-5 isolated VMs for open source work (one repo per VM)
**Reference docs**: SESSION_HANDOVER.md, lib/validation.sh:404-408, ansible/playbook.yml:228-250
**Ready state**: Clean master branch, all tests passing, feature fully functional

**Immediate priorities**:
1. Explore --non-interactive flag options (deploy key prompt even with --test-dotfiles)
2. Document multi-VM workflow (how to manage 4-5 isolated work VMs)
3. Provision persistent work-vm-1 for testing

**Expected scope**:
- Analyze --non-interactive flag pros/cons (when to use interactive vs non-interactive?)
- Create multi-VM workflow documentation (VM naming, provisioning, SSH access, isolation best practices)
- Provision and verify work-vm-1 stays persistent

---

## 📚 Key Reference Documents

- **lib/validation.sh** - SKIP_WHITELIST_CHECK implementation
- **ansible/playbook.yml** - synchronize module + TPM workaround
- **provision-vm.sh** - `--test-dotfiles` flag handling
- **/home/mqx/workspace/dotfiles** - Local dotfiles being tested
- **/home/mqx/workspace/project-templates** - Project starter templates

---

## ⚠️ Known Issues & TODOs

### Issue 1: Deploy Key Prompt in --test-dotfiles Mode
**Problem**: Deploy key prompt appears even when not needed (using synchronize)
**Impact**: User must manually type "skip" every time
**Workaround**: Type "skip" at the prompt
**Solutions to explore**:
1. --non-interactive flag
2. Smart detection (auto-skip when --test-dotfiles used)
3. Separate deploy key generation from prompt

### Issue 2: TPM Installation Disabled
**Problem**: `.gitconfig` rewrites all GitHub HTTPS → SSH (breaks public repos)
**Impact**: TPM cannot clone from public GitHub repo
**Workaround**: Temporarily disabled TPM installation
**Solutions to explore**:
1. `GIT_CONFIG_GLOBAL=/dev/null` when cloning TPM
2. Clone TPM before dotfiles install
3. Fix `.gitconfig` URL rewriting logic
4. Make TPM optional

### Issue 3: Whitelist Too Narrow for Real Shell Scripts
**Problem**: SEC-006 whitelist only allows ~12 commands, blocks normal bash
**Impact**: Any real install script requires bypass or interactive approval
**Workaround**: `SKIP_WHITELIST_CHECK=1` for trusted local dotfiles
**Solutions to explore**:
1. Expand whitelist to include basic bash constructs
2. Add pragma support for whitelist (like blacklist has)
3. Separate validation level for local vs remote dotfiles

---

## 💬 Doctor Hubert's Questions for Next Session

**Question 1**: Should we add `--non-interactive` flag?
- **Context**: Deploy key prompt appears even with `--test-dotfiles`
- **Current behavior**: User must type "skip" manually
- **Analysis needed**: When do we want interactive vs non-interactive provisioning?

**Question 2**: How should multi-VM workflow be documented?
- **Use case**: 4-5 VMs, each working on one open source repo
- **VM lifecycle**: Provision → use → destroy (ephemeral environments)
- **Documentation needs**: Naming, provisioning, SSH access, isolation practices

**Question 3**: What about project-templates integration?
- **Current understanding**: project-templates used INSIDE VMs (manual copy after provision)
- **Not needed**: Auto-provisioning of project-templates (use them ad-hoc)
- **Workflow**: SSH into VM → copy template → start project

---

## 🔄 Multi-VM Workflow (Planned)

Doctor Hubert's long-term setup:

```
work-vm-1 (192.168.122.XXX) → Clone & work on Repo A
work-vm-2 (192.168.122.XXX) → Clone & work on Repo B
work-vm-3 (192.168.122.XXX) → Clone & work on Repo C
work-vm-4 (192.168.122.XXX) → Clone & work on Repo D
work-vm-5 (192.168.122.XXX) → Clone & work on Repo E
```

**Each VM has:**
- ✅ Base environment (dotfiles: zsh, starship, git, vim)
- ✅ SSH access via `~/.ssh/vm_key`
- ✅ Isolated from other VMs
- ✅ Full dev tools (git, neovim, zsh-plugins, etc.)

**Workflow:**
1. Provision VM: `SKIP_WHITELIST_CHECK=1 ./provision-vm.sh work-vm-X 4096 2 --test-dotfiles /path`
2. SSH into VM: `ssh -i ~/.ssh/vm_key mr@<IP>`
3. Clone target repo: `git clone https://github.com/org/repo.git`
4. Work on issues in isolation
5. When done: `./destroy-vm.sh work-vm-X`

**To use project-templates inside VM:**
```bash
ssh -i ~/.ssh/vm_key mr@<VM_IP>
cp -r ~/project-templates/python-project ~/my-new-project
cd ~/my-new-project
git init && git add . && git commit -m "Initial commit from template"
# Start working!
```

---

**Session completed**: 2025-11-12
**Next session focus**: --non-interactive flag analysis + multi-VM documentation
