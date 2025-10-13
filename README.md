# VM Infrastructure

Automated Ubuntu VM provisioning using Terraform (libvirt) and Ansible.

## Overview

This infrastructure automates the setup of Ubuntu 24.04 VMs with:
- Core development tools (zsh, neovim, tmux, git, etc.)
- Starship prompt and git-delta
- Personal dotfiles from [maxrantil/dotfiles](https://github.com/maxrantil/dotfiles)
- Tmux Plugin Manager (TPM) and vim-plug

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
- ✅ Validates dotfiles directory exists
- ✅ Warns if install.sh missing
- ✅ Converts relative to absolute paths
- ✅ Falls back to GitHub if flag not provided
- ✅ Security validations (symlink detection, shell injection prevention)

### Security Validations

The `--test-dotfiles` flag includes automatic security checks:

- **Symlink Detection**: Prevents symlink attacks that could redirect to system directories
- **Shell Injection Prevention**: Blocks paths with shell metacharacters (`;`, `|`, `` ` ``, `$()`)
- **install.sh Content Inspection**: Detects dangerous patterns (`rm -rf /`, `curl | bash`, etc.)
- **Git Repository Validation**: Ensures valid .git directory if present

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

### After Provisioning

When Ansible completes, it will display the public deploy key. Follow these steps:

1. Copy the displayed public key
2. Go to: https://github.com/maxrantil/dotfiles/settings/keys
3. Click "Add deploy key"
4. Title: `vm-<hostname>-deploy-key`
5. Paste the key
6. ✓ Check "Allow write access" (only if pushing from VM)
7. Click "Add key"

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
│   ├── playbook.yml      # Main Ansible playbook
│   └── inventory.ini     # Auto-generated by Terraform
└── README.md
```

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

## License

MIT
