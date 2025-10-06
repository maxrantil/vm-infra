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
if ! terraform apply -auto-approve \
    -var="vm_name=$VM_NAME" \
    -var="memory=$MEMORY" \
    -var="vcpus=$VCPUS"; then
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
    terraform refresh -var="vm_name=$VM_NAME" -var="memory=$MEMORY" -var="vcpus=$VCPUS" >/dev/null 2>&1
    terraform apply -auto-approve -var="vm_name=$VM_NAME" -var="memory=$MEMORY" -var="vcpus=$VCPUS" >/dev/null 2>&1
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
