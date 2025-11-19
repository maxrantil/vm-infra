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

#####################################
# Get VM username from terraform workspace state
#
# Switches to the VM's terraform workspace, extracts the configured
# username from terraform output, and returns to default workspace.
# Uses trap to guarantee workspace cleanup in all exit paths.
#
# This function queries terraform state (single source of truth) rather
# than hardcoding username='mr'. Supports the configurable username
# feature introduced in PR #118.
#
# Arguments:
#   $1 - VM name (must match terraform workspace name)
#
# Returns:
#   0 - Success (username printed to stdout)
#   1 - Failure (terraform not found, VM not found, workspace error, username invalid)
#
# Outputs:
#   stdout - VM username (on success)
#   stderr - Error messages (on failure)
#
# Side Effects:
#   - Temporarily switches terraform workspace (always restored via trap)
#   - Takes ~1.0s due to terraform operations (acceptable for convenience script)
#
# Security:
#   - Validates terraform command exists
#   - Validates VM name format (prevents path traversal)
#   - Validates extracted username format (prevents command injection)
#   - Uses trap for guaranteed cleanup (prevents TOCTOU race)
#
# Example:
#   if ! VM_USERNAME=$(get_vm_username "$VM_NAME"); then
#       echo "[ERROR] Failed to get username" >&2
#       exit 1
#   fi
#####################################
get_vm_username() {
    local vm_name="$1"
    local terraform_dir="terraform"
    local original_workspace
    local username

    # SEC-002: Validate terraform is available
    if ! command -v terraform >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Terraform not found in PATH${NC}" >&2
        echo "Install terraform: https://developer.hashicorp.com/terraform/downloads" >&2
        return 1
    fi

    # SEC-002: Validate VM name format (prevent path traversal)
    if [[ ! "$vm_name" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ "$vm_name" == *".."* ]]; then
        echo -e "${RED}[ERROR] Invalid VM name format: '$vm_name'${NC}" >&2
        echo "VM name must contain only alphanumeric characters, dots, hyphens, and underscores" >&2
        return 1
    fi

    # Validate terraform directory exists
    if [ ! -d "$terraform_dir" ]; then
        echo -e "${RED}[ERROR] Terraform directory not found: $terraform_dir${NC}" >&2
        return 1
    fi

    # Capture original workspace for cleanup
    original_workspace=$(cd "$terraform_dir" && terraform workspace show 2>/dev/null)

    # BUG-002: Set cleanup trap - guarantees workspace restoration in ALL exit paths
    # This prevents state pollution if function exits early (error, interrupt, SIGTERM)
    # Similar to TOCTOU protection in lib/validation.sh (SEC-001)
    trap 'cd "$terraform_dir" && terraform workspace select "$original_workspace" 2>/dev/null' RETURN

    # Switch to VM-specific workspace to access isolated terraform state
    # Each VM has its own workspace (created in provision-vm.sh) to support
    # multiple concurrent VMs without state conflicts. See PR #122 for details.
    if ! (cd "$terraform_dir" && terraform workspace select "$vm_name" 2>/dev/null); then
        return 1
    fi

    # BUG-001: Separate declaration from assignment to avoid masking return values (SC2155)
    # Extract username from terraform output (proper interface, not string parsing)
    username=$(cd "$terraform_dir" && terraform output -raw vm_username 2>/dev/null)
    local extract_status=$?

    # Validate extraction succeeded
    if [ $extract_status -ne 0 ]; then
        return 1
    fi

    # SEC-001: Validate extracted username format (prevent command injection)
    # Username regex matches terraform validation: ^[a-z][a-z0-9_-]{0,31}$
    # This prevents malicious usernames from corrupted terraform state
    if [[ ! "$username" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || [ -z "$username" ]; then
        echo -e "${RED}[ERROR] Invalid username format from terraform state: '$username'${NC}" >&2
        echo "Expected: lowercase letter followed by lowercase letters, digits, underscores, or hyphens (max 32 chars)" >&2
        return 1
    fi

    echo "$username"
    return 0
    # Trap automatically restores original workspace here
}

# Main execution (skip if being sourced for testing)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
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

    # Get VM username from terraform state
    echo -e "${YELLOW}Retrieving VM username from terraform...${NC}"
    if ! VM_USERNAME=$(get_vm_username "$VM_NAME"); then
        # BUG-003: Match validation.sh error message pattern
        echo -e "${RED}[ERROR] Could not determine VM username${NC}" >&2
        echo "" >&2
        echo "VM: $VM_NAME" >&2
        echo "" >&2
        echo "This VM may have been created before workspace-based provisioning (PR #122)." >&2
        echo "" >&2
        echo "Troubleshooting:" >&2
        echo "  1. Verify VM exists:" >&2
        echo "     sudo virsh list --all | grep $VM_NAME" >&2
        echo "" >&2
        echo "  2. Verify terraform workspace exists:" >&2
        echo "     cd terraform && terraform workspace list | grep $VM_NAME" >&2
        echo "" >&2
        echo "  3. Verify username in terraform state:" >&2
        echo "     cd terraform && terraform workspace select $VM_NAME && terraform output vm_username" >&2
        echo "" >&2
        echo "  4. Manual SSH connection (if you know the username):" >&2
        echo "     ssh -i ~/.ssh/vm_key <username>@\$(sudo virsh domifaddr $VM_NAME | awk 'NR==3 {print \$4}' | cut -d'/' -f1)" >&2
        echo "" >&2
        echo "If VM is orphaned (no workspace), destroy and recreate:" >&2
        echo "  sudo virsh destroy $VM_NAME && sudo virsh undefine $VM_NAME" >&2
        echo "  ./provision-vm.sh $VM_NAME <username> [memory] [vcpus]" >&2
        exit 1
    fi

    echo -e "${GREEN}[OK] Username retrieved from terraform workspace: ${VM_USERNAME}${NC}"
    echo ""

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
        VM_IP=$(sudo virsh domifaddr "$VM_NAME" 2> /dev/null | awk 'NR==3 {print $4}' | cut -d'/' -f1)

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
    if ! ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "$VM_USERNAME"@"$VM_IP" 'exit' 2> /dev/null; then
        echo -e "${YELLOW}[WARNING] SSH not ready yet, waiting for cloud-init...${NC}"

        # Wait for cloud-init to complete (with timeout)
        CLOUD_INIT_SUCCESS=false
        for attempt in {1..30}; do
            if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=yes "$VM_USERNAME"@"$VM_IP" 'cloud-init status --wait' 2> /dev/null; then
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
            echo "  3. Try manual SSH: ssh -i ~/.ssh/vm_key $VM_USERNAME@$VM_IP" >&2
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
    ssh -i ~/.ssh/vm_key "$VM_USERNAME"@"$VM_IP"

fi  # End of main execution guard
