#!/usr/bin/env bash
# ABOUTME: Centralized cleanup functions for integration tests

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cleanup a test VM by destroying and undefining it
cleanup_test_vm() {
    local vm_name="${1:-}"

    if [[ -z "$vm_name" ]]; then
        echo -e "${RED}Error: VM name required${NC}" >&2
        return 1
    fi

    echo -e "${BLUE}Cleaning up test VM: $vm_name${NC}"

    # Check if VM exists
    if ! virsh list --all | grep -q "$vm_name"; then
        echo -e "${YELLOW}  VM not found (already cleaned up)${NC}"
        return 0
    fi

    # Destroy (force stop) VM if running
    if virsh list --state-running | grep -q "$vm_name"; then
        echo -e "  Destroying running VM..."
        if virsh destroy "$vm_name" 2>/dev/null; then
            echo -e "${GREEN}  ✓ VM destroyed${NC}"
        else
            echo -e "${YELLOW}  ⚠ Failed to destroy VM (may already be stopped)${NC}"
        fi
    fi

    # Undefine (remove) VM
    echo -e "  Undefining VM..."
    if virsh undefine "$vm_name" --remove-all-storage 2>/dev/null; then
        echo -e "${GREEN}  ✓ VM undefined${NC}"
    else
        # Try without --remove-all-storage if that failed
        if virsh undefine "$vm_name" 2>/dev/null; then
            echo -e "${GREEN}  ✓ VM undefined${NC}"
        else
            echo -e "${YELLOW}  ⚠ Failed to undefine VM (may already be removed)${NC}"
        fi
    fi

    return 0
}

# Cleanup test artifacts (ISOs, disk images, inventory files)
cleanup_test_artifacts() {
    local test_id="${1:-test}"

    echo -e "${BLUE}Cleaning up test artifacts for: $test_id${NC}"

    local artifacts_cleaned=0

    # Get project root (assuming this script is in tests/lib/)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root
    project_root="$(cd "$script_dir/../.." && pwd)"

    # Clean up cloud-init ISOs
    local iso_pattern="$project_root/terraform/cloud-init-*${test_id}*.iso"
    if compgen -G "$iso_pattern" > /dev/null 2>&1; then
        echo -e "  Removing cloud-init ISOs..."
        # shellcheck disable=SC2086
        rm -f $iso_pattern 2>/dev/null && ((++artifacts_cleaned))
        echo -e "${GREEN}  ✓ Cloud-init ISOs removed${NC}"
    fi

    # Clean up test inventory files
    local inventory_pattern="$project_root/ansible/inventory-*${test_id}*.ini"
    if compgen -G "$inventory_pattern" > /dev/null 2>&1; then
        echo -e "  Removing test inventory files..."
        # shellcheck disable=SC2086
        rm -f $inventory_pattern 2>/dev/null && ((++artifacts_cleaned))
        echo -e "${GREEN}  ✓ Test inventory files removed${NC}"
    fi

    # Clean up temporary test files
    local temp_pattern="/tmp/*${test_id}*"
    if compgen -G "$temp_pattern" > /dev/null 2>&1; then
        echo -e "  Removing temp files..."
        # shellcheck disable=SC2086
        rm -f $temp_pattern 2>/dev/null && ((++artifacts_cleaned))
        echo -e "${GREEN}  ✓ Temp files removed${NC}"
    fi

    # Clean up libvirt storage volumes for test VMs
    local pool_vols
    if pool_vols=$(virsh vol-list default 2>/dev/null | grep "$test_id"); then
        echo -e "  Removing storage volumes..."
        while IFS= read -r line; do
            local vol_name
            vol_name=$(echo "$line" | awk '{print $1}')
            if virsh vol-delete "$vol_name" --pool default 2>/dev/null; then
                ((++artifacts_cleaned))
            fi
        done <<< "$pool_vols"
        echo -e "${GREEN}  ✓ Storage volumes removed${NC}"
    fi

    if [[ $artifacts_cleaned -gt 0 ]]; then
        echo -e "${GREEN}  Cleaned up $artifacts_cleaned artifact(s)${NC}"
    else
        echo -e "${YELLOW}  No artifacts found to clean${NC}"
    fi

    return 0
}

# Register cleanup function to run on script exit
register_cleanup_on_exit() {
    local vm_name="${1:-}"
    local test_id="${2:-test}"

    if [[ -z "$vm_name" ]]; then
        echo -e "${RED}Error: VM name required for cleanup registration${NC}" >&2
        return 1
    fi

    # Define cleanup function for this specific VM
    cleanup_on_exit() {
        local exit_code=$?
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Cleanup triggered (exit code: $exit_code)${NC}"
        echo -e "${BLUE}========================================${NC}"

        cleanup_test_vm "$vm_name"
        cleanup_test_artifacts "$test_id"

        echo -e "${BLUE}========================================${NC}"
        echo -e "${GREEN}Cleanup complete${NC}"
        echo -e "${BLUE}========================================${NC}"
    }

    # Register cleanup for EXIT, INT (Ctrl+C), and TERM signals
    trap cleanup_on_exit EXIT INT TERM

    echo -e "${GREEN}✓ Cleanup registered for VM: $vm_name${NC}"
    return 0
}

# Cleanup all test resources (for use in test teardown)
cleanup_all_test_resources() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Cleaning up all test resources${NC}"
    echo -e "${BLUE}========================================${NC}"

    # List and cleanup all test VMs (names containing "test-")
    local test_vms
    test_vms=$(virsh list --all --name 2>/dev/null | grep "test-" || true)

    if [[ -n "$test_vms" ]]; then
        echo -e "${BLUE}Found test VMs to clean up:${NC}"
        while IFS= read -r vm_name; do
            if [[ -n "$vm_name" ]]; then
                cleanup_test_vm "$vm_name"
            fi
        done <<< "$test_vms"
    else
        echo -e "${YELLOW}No test VMs found${NC}"
    fi

    # Cleanup artifacts for common test patterns
    cleanup_test_artifacts "test-"

    echo -e "${GREEN}✓ All test resources cleaned${NC}"
    return 0
}

# Verify cleanup library is being sourced, not executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${YELLOW}Warning: This library should be sourced, not executed directly${NC}"
    echo -e "Usage: source tests/lib/cleanup.sh"
    echo ""
    echo "Available functions:"
    echo "  cleanup_test_vm <vm_name>              - Destroy and undefine a test VM"
    echo "  cleanup_test_artifacts <test_id>       - Remove test artifacts (ISOs, volumes)"
    echo "  register_cleanup_on_exit <vm_name>     - Register cleanup on script exit"
    echo "  cleanup_all_test_resources             - Cleanup all test VMs and artifacts"
    exit 1
fi
