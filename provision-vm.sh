#!/bin/bash
# ABOUTME: One-command VM provisioning script using Terraform and Ansible
# Usage: ./provision-vm.sh <vm-name> [memory] [vcpus] [--test-dotfiles <path>] [--dry-run]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test mode: Skip VM creation for testing (set via TEST_MODE=1 environment variable)
TEST_MODE="${TEST_MODE:-0}"

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

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"

# Source validation library
if [[ ! -f "$SCRIPT_DIR/lib/validation.sh" ]]; then
	echo -e "${RED}[ERROR] Required library not found: lib/validation.sh${NC}" >&2
	echo "Ensure lib/validation.sh exists in the project directory" >&2
	exit 1
fi

# shellcheck source=lib/validation.sh
source "$SCRIPT_DIR/lib/validation.sh"

# SEC-007: Rollback mechanism on failure (CVSS 5.0)
VM_CREATED=false

cleanup_on_failure() {
	local exit_code=$?
	if [ $exit_code -ne 0 ] && [ "$VM_CREATED" = true ]; then
		echo "" >&2
		echo -e "${YELLOW}[WARNING] Provisioning failed, cleaning up VM...${NC}" >&2
		cd "$TERRAFORM_DIR" && terraform destroy -auto-approve "${TERRAFORM_VARS[@]}" 2>/dev/null || true
		echo -e "${GREEN}[CLEANUP] VM resources destroyed${NC}" >&2
	fi
}

trap cleanup_on_failure EXIT

# Validation functions are now sourced from lib/validation.sh (Issue #38)

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

# Exit early in test mode or dry-run (after validation but before VM creation)
if [ "$TEST_MODE" = "1" ]; then
	echo -e "${YELLOW}[DRY RUN] Validation complete, skipping VM creation${NC}"
	exit 0
fi

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

# Mark VM as created for cleanup trap
VM_CREATED=true

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
for _ in {1..90}; do
	if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=2 mr@"$VM_IP" 'cloud-init status --wait' 2>/dev/null; then
		CLOUD_INIT_SUCCESS=true
		break
	fi
	sleep 2
done

if [ "$CLOUD_INIT_SUCCESS" = false ]; then
	echo -e "${RED}[ERROR] cloud-init did not complete within 180 seconds${NC}" >&2
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
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  📋 DEPLOY KEY SETUP REQUIRED${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Extract deploy key from VM
DEPLOY_KEY=$(ssh -i ~/.ssh/vm_key mr@$VM_IP 'cat ~/.ssh/id_ed25519.pub' 2>/dev/null)

if [ -n "$DEPLOY_KEY" ]; then
	echo "To complete dotfiles installation, add this deploy key to GitHub:"
	echo ""
	echo -e "${GREEN}$DEPLOY_KEY${NC}"
	echo ""
	echo "Steps:"
	echo "  1. Open: https://github.com/maxrantil/dotfiles/settings/keys"
	echo "  2. Click 'Add deploy key'"
	echo "  3. Title: ${VM_NAME}-deploy-key"
	echo "  4. Paste the key above"
	echo "  5. ✓ Check 'Allow write access' (if needed)"
	echo "  6. Click 'Add key'"
	echo ""
	echo -e "${YELLOW}Would you like to pause here to add the deploy key?${NC}"
	echo "Press ENTER after adding the key, or type 'skip' to continue without dotfiles:"
	read -r DEPLOY_KEY_RESPONSE

	if [ "$DEPLOY_KEY_RESPONSE" != "skip" ]; then
		echo ""
		echo -e "${YELLOW}Re-running Ansible to install dotfiles...${NC}"
		if ansible-playbook -i inventory.ini playbook.yml; then
			echo -e "${GREEN}✓ Dotfiles installation complete${NC}"
		else
			echo -e "${RED}⚠ Dotfiles installation failed - you can retry manually:${NC}" >&2
			echo "  cd ansible && ansible-playbook -i inventory.ini playbook.yml" >&2
		fi
	else
		echo -e "${YELLOW}⚠ Skipping dotfiles installation${NC}"
		echo "To install dotfiles later:"
		echo "  1. Add deploy key to GitHub (see above)"
		echo "  2. Run: cd ansible && ansible-playbook -i inventory.ini playbook.yml"
	fi
else
	echo -e "${RED}⚠ Could not retrieve deploy key from VM${NC}" >&2
	echo "You can retrieve it manually: ssh -i ~/.ssh/vm_key mr@$VM_IP 'cat ~/.ssh/id_ed25519.pub'" >&2
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
