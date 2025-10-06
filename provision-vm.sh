#!/bin/bash
# VM Provisioning Script
# Usage: ./provision-vm.sh <vm-name> [memory] [vcpus]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
VM_NAME="${1:-dev-vm}"
MEMORY="${2:-4096}"
VCPUS="${3:-2}"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  VM Provisioning Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "VM Name: $VM_NAME"
echo "Memory: ${MEMORY}MB"
echo "vCPUs: $VCPUS"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check for required SSH keys
if [ ! -f "$HOME/.ssh/vm_key" ]; then
    echo -e "${RED}[ERROR] VM access key not found: ~/.ssh/vm_key${NC}" >&2
    echo "" >&2
    echo "Generate with:" >&2
    echo "  ssh-keygen -t ed25519 -f ~/.ssh/vm_key -C 'vm-access'" >&2
    exit 1
fi

if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo -e "${RED}[ERROR] GitHub key not found: ~/.ssh/id_ed25519${NC}" >&2
    echo "" >&2
    echo "Generate with:" >&2
    echo "  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C 'your-email@example.com'" >&2
    exit 1
fi

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

# Create VM
terraform apply -auto-approve \
    -var="vm_name=$VM_NAME" \
    -var="memory=$MEMORY" \
    -var="vcpus=$VCPUS"

# Get VM IP (with retry)
echo ""
echo -e "${YELLOW}Waiting for VM IP address...${NC}"
for i in {1..10}; do
    VM_IP=$(terraform output -raw vm_ip 2>/dev/null || echo "pending")
    if [ "$VM_IP" != "pending" ] && [ -n "$VM_IP" ]; then
        break
    fi
    sleep 2
    terraform refresh -var="vm_name=$VM_NAME" -var="memory=$MEMORY" -var="vcpus=$VCPUS" >/dev/null 2>&1
    terraform apply -auto-approve -var="vm_name=$VM_NAME" -var="memory=$MEMORY" -var="vcpus=$VCPUS" >/dev/null 2>&1
done

if [ "$VM_IP" = "pending" ] || [ -z "$VM_IP" ]; then
    echo -e "${RED}Error: Failed to get VM IP${NC}"
    exit 1
fi

echo -e "${GREEN}✓ VM created successfully${NC}"
echo "IP Address: $VM_IP"
echo ""

# Step 2: Wait for cloud-init
echo -e "${YELLOW}Step 2: Waiting for cloud-init to complete...${NC}"
for i in {1..30}; do
    if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=2 mr@$VM_IP 'cloud-init status --wait' 2>/dev/null; then
        break
    fi
    sleep 2
done

echo -e "${GREEN}✓ Cloud-init completed${NC}"
echo ""

# Step 3: Ansible provisioning
echo -e "${YELLOW}Step 3: Provisioning with Ansible...${NC}"
cd "$ANSIBLE_DIR"

ansible-playbook -i inventory.ini playbook.yml

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
