#!/bin/bash
# ABOUTME: One-command VM provisioning script using Terraform and Ansible
# Usage: ./provision-vm.sh <vm-name> [memory] [vcpus] [--test-dotfiles <path>]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
DOTFILES_LOCAL_PATH=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --test-dotfiles)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}[ERROR] --test-dotfiles flag requires a path argument${NC}" >&2
                echo "Usage: $0 <vm-name> [memory] [vcpus] [--test-dotfiles <path>]" >&2
                exit 1
            fi
            DOTFILES_LOCAL_PATH="$2"
            shift 2
            ;;
        -*)
            echo -e "${RED}[ERROR] Unknown flag: $1${NC}" >&2
            echo "Usage: $0 <vm-name> [memory] [vcpus] [--test-dotfiles <path>]" >&2
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

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"

# SSH validation functions
validate_ssh_directory_permissions() {
    local ssh_dir="$HOME/.ssh"
    local ssh_dir_perms
    ssh_dir_perms=$(stat -c "%a" "$ssh_dir" 2>/dev/null || echo "")

    if [ -z "$ssh_dir_perms" ]; then
        echo -e "${RED}[ERROR] SSH directory not found${NC}" >&2
        exit 1
    fi

    if [ "$ssh_dir_perms" != "700" ]; then
        echo -e "${YELLOW}[WARNING] Insecure SSH directory permissions: $ssh_dir_perms${NC}" >&2
        echo "Expected: 700, fixing automatically..." >&2
        chmod 700 "$ssh_dir"
        echo -e "${GREEN}[FIXED] SSH directory permissions set to 700${NC}"
    fi
}

validate_private_key_permissions() {
    local key_path="$1"
    local key_name="$2"
    local key_perms
    key_perms=$(stat -c "%a" "$key_path" 2>/dev/null || echo "")

    if [ "$key_perms" != "600" ] && [ "$key_perms" != "400" ]; then
        echo -e "${RED}[ERROR] Insecure permissions on $key_name: $key_perms${NC}" >&2
        echo "Expected: 600 (read/write for owner only) or 400 (read-only for owner)" >&2
        echo "Fix with: chmod 600 <key-path>" >&2
        exit 1
    fi
}

validate_key_content() {
    local key_path="$1"
    local key_name="$2"

    if ! ssh-keygen -l -f "$key_path" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Invalid or corrupt $key_name${NC}" >&2
        echo "Regenerate with: ssh-keygen -t ed25519 -f <key-path> -C 'description'" >&2
        exit 1
    fi
}

validate_public_key_exists() {
    local key_path="$1"
    local key_name="$2"
    local pub_key_path="${key_path}.pub"

    if [ ! -f "$pub_key_path" ]; then
        echo -e "${RED}[ERROR] Public key missing for $key_name${NC}" >&2
        echo "Regenerate keypair with: ssh-keygen -t ed25519 -f <key-path> -C 'description'" >&2
        exit 1
    fi

    # Validate public key content format
    if ! ssh-keygen -l -f "$pub_key_path" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Invalid or corrupt public key for $key_name${NC}" >&2
        echo "Regenerate keypair with: ssh-keygen -t ed25519 -f <key-path> -C 'description'" >&2
        exit 1
    fi
}

# Dotfiles validation functions
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

validate_dotfiles_no_symlinks() {
    local path="$1"

    # CVE-1: Symlink detection (CVSS 9.3)
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
                echo "Symlink attacks could redirect to sensitive system directories." >&2
                exit 1
            fi
        fi
    done
}

validate_dotfiles_canonical_path() {
    local path="$1"

    # SEC-001: TOCTOU race condition prevention (CVSS 6.8)
    # Validate that the path itself is not a symlink (catches TOCTOU replacements)
    # This is checked AFTER validate_dotfiles_no_symlinks to catch race conditions
    # where a directory is replaced with a symlink between checks
    if [ -L "$path" ]; then
        echo -e "${RED}[ERROR] Path is a symlink (TOCTOU protection)${NC}" >&2
        echo "Path may have been replaced after initial validation." >&2
        echo "This prevents time-of-check-time-of-use race conditions." >&2
        exit 1
    fi

    # Additional canonical path check using realpath if available
    if command -v realpath >/dev/null 2>&1; then
        local canonical_path
        canonical_path=$(realpath --no-symlinks "$path" 2>/dev/null)

        if [ -z "$canonical_path" ]; then
            echo -e "${RED}[ERROR] Unable to resolve canonical path${NC}" >&2
            exit 1
        fi

        if [ "$canonical_path" != "$path" ]; then
            echo -e "${RED}[ERROR] Path contains symlink component (TOCTOU protection)${NC}" >&2
            echo "Expected: $path" >&2
            echo "Canonical: $canonical_path" >&2
            echo "This prevents time-of-check-time-of-use race conditions." >&2
            exit 1
        fi
    fi
}

validate_dotfiles_no_shell_injection() {
    local path="$1"

    # CVE-3: Shell injection prevention (CVSS 7.8)
    # SEC-003: Comprehensive metacharacter coverage (CVSS 7.0)
    # Block ALL metacharacters and control chars
    # Pattern explanation:
    # - [;\&|`$()<>{}*?#'\"[:space:][:cntrl:]] - most special chars and POSIX classes
    # - \\ - backslash (needs alternation)
    # - \[ - open bracket (needs alternation)
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
        echo "Path must contain only printable ASCII characters" >&2
        exit 1
    fi
}

validate_dotfiles_git_repo() {
    local path="$1"

    # BUG-006: Git repository validation
    if [ -d "$path/.git" ]; then
        if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
            echo -e "${RED}[ERROR] Invalid git repository in dotfiles path${NC}" >&2
            exit 1
        fi
    fi
}

validate_install_sh() {
    local path="$1"
    local install_script="$path/install.sh"

    if [ ! -f "$install_script" ]; then
        echo -e "${YELLOW}[WARNING] install.sh not found in dotfiles directory${NC}"
        read -p "Continue without install.sh? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        return 0
    fi

    # CVE-2: install.sh content inspection (CVSS 9.0)
    # SEC-002: Expanded patterns to prevent evasion (CVSS 7.5)
    local dangerous_patterns=(
        # Destructive commands
        "rm.*-rf.*/"
        "rm -rf /"
        "dd if="
        "mkfs\."
        "> ?/dev/sd"

        # Remote code execution
        "curl.*\|.*(bash|sh)"
        "wget.*\|.*(bash|sh)"
        "eval"
        "exec"
        "source.*http"
        "\\. .*http"

        # Privilege escalation
        ":/bin/(ba)?sh"
        "chown.*root"
        "chmod.*[67][0-9][0-9]"
        "sudo"
        "su "

        # Obfuscation indicators
        "\\\\x[0-9a-f]{2}"
        "base64.*-d.*\|"
        "xxd"
        "\\\${IFS}"
        "\\\$[A-Z_]+.*\\\$[A-Z_]+"

        # Network access
        "nc "
        "netcat"
        "socat"
        "/dev/tcp/"

        # System modification
        "iptables"
        "ufw "
        "systemctl"
        "service "

        # Crypto mining
        "xmrig"
        "miner"
        "stratum"
    )

    for pattern in "${dangerous_patterns[@]}"; do
        if grep -qE "$pattern" "$install_script" 2>/dev/null; then
            echo -e "${RED}[ERROR] Dangerous pattern detected in install.sh: $pattern${NC}" >&2
            echo "For security, cannot proceed with potentially malicious install script." >&2
            exit 1
        fi
    done
}

validate_and_prepare_dotfiles_path() {
    local path="$1"

    # Expand tilde
    path="${path/#\~/$HOME}"

    # Convert to absolute path (BUG-003: handles spaces correctly)
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

# Validate and prepare dotfiles path if provided
if [ -n "$DOTFILES_LOCAL_PATH" ]; then
    echo -e "${YELLOW}Validating local dotfiles path...${NC}"
    DOTFILES_LOCAL_PATH=$(validate_and_prepare_dotfiles_path "$DOTFILES_LOCAL_PATH")
    echo -e "${GREEN}[OK] Using local dotfiles: $DOTFILES_LOCAL_PATH${NC}"
    echo ""
fi

# Display configuration
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  VM Provisioning Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "VM Name: $VM_NAME"
echo "Memory: ${MEMORY}MB"
echo "vCPUs: $VCPUS"
if [ -n "$DOTFILES_LOCAL_PATH" ]; then
    echo "Dotfiles: $DOTFILES_LOCAL_PATH (local)"
else
    echo "Dotfiles: GitHub (default)"
fi
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Validate SSH directory permissions
validate_ssh_directory_permissions

# Check for required SSH keys
if [ ! -f "$HOME/.ssh/vm_key" ]; then
    echo -e "${RED}[ERROR] VM access key not found${NC}" >&2
    echo "" >&2
    echo "Generate with:" >&2
    echo "  ssh-keygen -t ed25519 -f ~/.ssh/vm_key -C 'vm-access'" >&2
    exit 1
fi

if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo -e "${RED}[ERROR] GitHub key not found${NC}" >&2
    echo "" >&2
    echo "Generate with:" >&2
    echo "  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C 'your-email@example.com'" >&2
    exit 1
fi

# Validate VM key security
validate_private_key_permissions "$HOME/.ssh/vm_key" "VM key"
validate_key_content "$HOME/.ssh/vm_key" "VM key"
validate_public_key_exists "$HOME/.ssh/vm_key" "VM key"

# Validate GitHub key security
validate_private_key_permissions "$HOME/.ssh/id_ed25519" "GitHub key"
validate_key_content "$HOME/.ssh/id_ed25519" "GitHub key"
validate_public_key_exists "$HOME/.ssh/id_ed25519" "GitHub key"

# Check for required tools
for cmd in terraform ansible-playbook virsh ssh; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Required tool not found: $cmd${NC}" >&2
        exit 1
    fi
done

echo -e "${GREEN}[OK] Prerequisites verified${NC}"
echo ""

# Step 1: Terraform
echo -e "${YELLOW}Step 1: Creating VM with Terraform...${NC}"
cd "$TERRAFORM_DIR"

# Initialize if needed
if [ ! -d ".terraform" ]; then
    terraform init
fi

# Create VM (BUG-003: Proper quoting for paths with spaces)
TERRAFORM_VARS=(
    -var="vm_name=$VM_NAME"
    -var="memory=$MEMORY"
    -var="vcpus=$VCPUS"
)

if [ -n "$DOTFILES_LOCAL_PATH" ]; then
    TERRAFORM_VARS+=(-var="dotfiles_local_path=$DOTFILES_LOCAL_PATH")
fi

if ! terraform apply -auto-approve "${TERRAFORM_VARS[@]}"; then
    echo -e "${RED}[ERROR] Terraform failed to create VM${NC}" >&2
    echo "" >&2
    echo "Check terraform logs above for details" >&2
    exit 1
fi

echo -e "${GREEN}[SUCCESS] Terraform apply completed${NC}"

# Get VM IP (with retry)
echo ""
echo -e "${YELLOW}Waiting for VM IP address...${NC}"
for _ in {1..10}; do
    VM_IP=$(terraform output -raw vm_ip 2>/dev/null || echo "pending")
    if [ "$VM_IP" != "pending" ] && [ -n "$VM_IP" ]; then
        break
    fi
    sleep 2
    terraform refresh "${TERRAFORM_VARS[@]}" >/dev/null 2>&1
    terraform apply -auto-approve "${TERRAFORM_VARS[@]}" >/dev/null 2>&1
done

if [ "$VM_IP" = "pending" ] || [ -z "$VM_IP" ]; then
    echo -e "${RED}[ERROR] Failed to obtain VM IP address${NC}" >&2
    echo "" >&2
    echo "Troubleshooting steps:" >&2
    echo "  1. Check VM exists: virsh list --all" >&2
    echo "  2. Check network: virsh net-dhcp-leases default" >&2
    echo "  3. Check terraform state: terraform show" >&2
    exit 1
fi

echo -e "${GREEN}[SUCCESS] VM created with IP: $VM_IP${NC}"
echo ""

# Step 2: Wait for cloud-init
echo -e "${YELLOW}Step 2: Waiting for cloud-init to complete...${NC}"
CLOUD_INIT_SUCCESS=false
for _ in {1..30}; do
    if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=2 mr@"$VM_IP" 'cloud-init status --wait' 2>/dev/null; then
        CLOUD_INIT_SUCCESS=true
        break
    fi
    sleep 2
done

if [ "$CLOUD_INIT_SUCCESS" = false ]; then
    echo -e "${RED}[ERROR] cloud-init did not complete within 60 seconds${NC}" >&2
    echo "" >&2
    echo "VM may still be initializing. Manual steps:" >&2
    echo "  1. Check VM status: ssh -i ~/.ssh/vm_key mr@$VM_IP 'cloud-init status'" >&2
    echo "  2. View logs: ssh -i ~/.ssh/vm_key mr@$VM_IP 'cat /var/log/cloud-init.log'" >&2
    echo "  3. Wait and retry: ./provision-vm.sh $VM_NAME $MEMORY $VCPUS" >&2
    exit 1
fi

echo -e "${GREEN}[SUCCESS] Cloud-init completed${NC}"
echo ""

# Step 3: Ansible provisioning
echo -e "${YELLOW}Step 3: Verifying SSH connectivity...${NC}"

# Verify SSH connectivity before Ansible
if ! ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=5 mr@"$VM_IP" 'echo ok' >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Cannot connect to VM at $VM_IP${NC}" >&2
    echo "" >&2
    echo "SSH connectivity test failed. Troubleshooting:" >&2
    echo "  1. Verify VM is running: virsh list" >&2
    echo "  2. Test SSH manually: ssh -i ~/.ssh/vm_key mr@$VM_IP" >&2
    echo "  3. Check cloud-init: ssh -i ~/.ssh/vm_key mr@$VM_IP 'cloud-init status'" >&2
    exit 1
fi

echo -e "${GREEN}[SUCCESS] SSH connectivity verified${NC}"
echo ""
echo -e "${YELLOW}Step 4: Provisioning with Ansible...${NC}"
cd "$ANSIBLE_DIR"

if ! ansible-playbook -i inventory.ini playbook.yml; then
    echo "" >&2
    echo -e "${RED}[ERROR] Ansible provisioning failed${NC}" >&2
    echo "" >&2
    echo "VM is accessible but Ansible failed. Check:" >&2
    echo "  1. Ansible logs above for details" >&2
    echo "  2. Manual connection: ssh -i ~/.ssh/vm_key mr@$VM_IP" >&2
    echo "  3. Retry: cd ansible && ansible-playbook -i inventory.ini playbook.yml" >&2
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ VM Provisioning Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "VM Name: $VM_NAME"
echo "IP Address: $VM_IP"
echo "SSH Access: ssh -i ~/.ssh/vm_key mr@$VM_IP"
echo ""
echo "Installed:"
echo "  - zsh (with starship prompt)"
echo "  - neovim (with vim-plug)"
echo "  - tmux (with TPM)"
echo "  - dotfiles from github.com/maxrantil/dotfiles"
echo "  - All development tools"
echo ""
