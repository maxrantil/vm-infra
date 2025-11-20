#!/bin/bash
# ABOUTME: Test cleanup utilities for VM test lifecycle management

# Array to track VMs that need cleanup
CLEANUP_VMS=()

#####################################
# Register a VM for automatic cleanup on script exit
#
# Arguments:
#   $1 - VM name to register for cleanup
#
# Side Effects:
#   - Adds VM to CLEANUP_VMS array
#   - Sets EXIT trap to destroy all registered VMs
#####################################
register_cleanup_on_exit() {
    local vm_name="$1"

    # Add to cleanup array
    CLEANUP_VMS+=("$vm_name")

    # Set trap to cleanup all VMs on exit
    trap cleanup_registered_vms EXIT
}

#####################################
# Cleanup all registered VMs
#
# Called automatically on script exit via trap
# Destroys all VMs in CLEANUP_VMS array
#####################################
cleanup_registered_vms() {
    if [ ${#CLEANUP_VMS[@]} -gt 0 ]; then
        echo ""
        echo "========================================="
        echo "Cleaning up test VMs..."
        echo "========================================="

        for vm in "${CLEANUP_VMS[@]}"; do
            if echo "y" | "$PROJECT_ROOT/destroy-vm.sh" "$vm" > /dev/null 2>&1; then
                echo "✓ Cleaned up VM: $vm"
            else
                echo "⚠ Failed to cleanup VM: $vm (may need manual cleanup)"
            fi
        done
    fi
}

# Export functions
export -f register_cleanup_on_exit
export -f cleanup_registered_vms
