#!/bin/bash
# ABOUTME: Clean VM removal script that destroys Terraform resources
# Usage: ./destroy-vm.sh <vm-name>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VM_NAME="${1:-dev-vm}"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

echo -e "${YELLOW}Destroying VM: $VM_NAME${NC}"
echo ""

cd "$TERRAFORM_DIR"

# Check if VM exists
if ! terraform show 2> /dev/null | grep -q "vm_name.*$VM_NAME"; then
    echo -e "${RED}VM '$VM_NAME' not found in Terraform state${NC}"
    exit 1
fi

# Confirm destruction
read -p "Are you sure you want to destroy VM '$VM_NAME'? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

terraform destroy -auto-approve -var="vm_name=$VM_NAME"

echo ""
echo -e "${GREEN}✓ VM '$VM_NAME' destroyed successfully${NC}"
