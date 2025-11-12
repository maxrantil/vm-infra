#!/bin/bash
# ABOUTME: Helper script to start VMs and connect via SSH in one command
# Usage: ./vm-ssh.sh <vm-name>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VM_NAME="$1"

# Function to list available VMs
list_vms() {
    echo -e "${BLUE}Available VMs:${NC}"
    sudo virsh list --all | tail -n +3 | while read -r _id name state rest; do
        if [ -n "$name" ]; then
            if [[ "$state" == "running" ]]; then
                echo -e "  ${GREEN}●${NC} $name (running)"
            else
                echo -e "  ${YELLOW}○${NC} $name ($state)"
            fi
        fi
    done
}

# Check if VM name provided
if [ -z "$VM_NAME" ]; then
    echo -e "${RED}[ERROR] No VM name provided${NC}" >&2
    echo ""
    echo "Usage: $0 <vm-name>"
    echo ""
    list_vms
    exit 1
fi

# Check if VM exists
if ! sudo virsh list --all | tail -n +3 | awk '{print $2}' | grep -q "^${VM_NAME}$"; then
    echo -e "${RED}[ERROR] VM '${VM_NAME}' not found${NC}" >&2
    echo ""
    list_vms
    exit 1
fi

# Check current VM state
STATE=$(sudo virsh list --all | grep -w "$VM_NAME" | awk '{print $3" "$4}' | sed 's/^ *//;s/ *$//')

if [[ "$STATE" == *"shut off"* ]] || [[ "$STATE" == "shut" ]]; then
    echo -e "${YELLOW}VM '${VM_NAME}' is shut off, starting...${NC}"
    if ! sudo virsh start "$VM_NAME"; then
        echo -e "${RED}[ERROR] Failed to start VM '${VM_NAME}'${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}[OK] VM started successfully${NC}"
    echo ""
    echo -e "${YELLOW}Waiting for network initialization...${NC}"
    sleep 5
elif [[ "$STATE" == "running" ]]; then
    echo -e "${GREEN}VM '${VM_NAME}' is already running${NC}"
else
    echo -e "${YELLOW}VM '${VM_NAME}' state: ${STATE}${NC}"
fi

# Get IP address with retry
echo ""
echo -e "${YELLOW}Getting IP address...${NC}"
VM_IP=""
for attempt in {1..10}; do
    VM_IP=$(sudo virsh domifaddr "$VM_NAME" 2>/dev/null | awk 'NR==3 {print $4}' | cut -d'/' -f1)

    if [ -n "$VM_IP" ] && [ "$VM_IP" != "pending" ]; then
        break
    fi

    if [ "$attempt" -lt 10 ]; then
        echo -e "${YELLOW}Waiting for IP address... (attempt $attempt/10)${NC}"
        sleep 2
    fi
done

if [ -z "$VM_IP" ] || [ "$VM_IP" == "pending" ]; then
    echo -e "${RED}[ERROR] Could not get IP address for '${VM_NAME}'${NC}" >&2
    echo ""
    echo "The VM may still be booting. Troubleshooting:" >&2
    echo "  1. Wait longer and retry: $0 $VM_NAME" >&2
    echo "  2. Check VM console: sudo virsh console $VM_NAME" >&2
    echo "  3. Check VM status: sudo virsh list --all" >&2
    exit 1
fi

echo -e "${GREEN}[OK] IP address: ${VM_IP}${NC}"
echo ""

# Test SSH connectivity before connecting
echo -e "${YELLOW}Testing SSH connectivity...${NC}"
if ! ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes mr@"$VM_IP" 'exit' 2>/dev/null; then
    echo -e "${YELLOW}[WARNING] SSH not ready yet, waiting for cloud-init...${NC}"

    # Wait for cloud-init to complete (with timeout)
    CLOUD_INIT_SUCCESS=false
    for attempt in {1..30}; do
        if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=yes mr@"$VM_IP" 'cloud-init status --wait' 2>/dev/null; then
            CLOUD_INIT_SUCCESS=true
            break
        fi
        sleep 2
    done

    if [ "$CLOUD_INIT_SUCCESS" = false ]; then
        echo -e "${RED}[ERROR] SSH connection failed${NC}" >&2
        echo ""
        echo "The VM is running but SSH is not responding. Troubleshooting:" >&2
        echo "  1. Wait longer: cloud-init may still be running" >&2
        echo "  2. Check VM console: sudo virsh console $VM_NAME" >&2
        echo "  3. Try manual SSH: ssh -i ~/.ssh/vm_key mr@$VM_IP" >&2
        exit 1
    fi
fi

echo -e "${GREEN}[OK] SSH connectivity verified${NC}"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Connecting to ${VM_NAME} at ${VM_IP}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Connect via SSH
ssh -i ~/.ssh/vm_key mr@"$VM_IP"
