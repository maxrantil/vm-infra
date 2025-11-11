# shellcheck shell=bash
# ABOUTME: Convenience shell functions for VM management
# Source this file in your .zshrc or .bashrc: source ~/vm-infrastructure/vm-aliases.sh
# Or copy individual aliases to your dotfiles .aliases file

# =============================================================================
# QUICK SSH ACCESS
# =============================================================================

# SSH to a specific VM by IP
# Usage: vm 192.168.122.122
alias vm='ssh -i ~/.ssh/vm_key mr@'

# SSH into the current VM (from terraform state)
# Usage: vmssh
alias vmssh='ssh -i ~/.ssh/vm_key mr@$(cd ~/vm-infrastructure/terraform && terraform output -raw vm_ip 2>/dev/null || echo "no-vm")'

# Get current VM IP address
# Usage: vmip
alias vmip='cd ~/vm-infrastructure/terraform && terraform output -raw vm_ip'

# =============================================================================
# VM LIFECYCLE MANAGEMENT
# =============================================================================

# Create a new VM (wrapper for provision-vm.sh)
# Usage: vmnew <vm-name> [memory] [vcpus]
# Examples:
#   vmnew dev-vm              # Default: 4GB RAM, 2 vCPUs
#   vmnew prod-vm 8192 4      # Custom: 8GB RAM, 4 vCPUs
alias vmnew='~/vm-infrastructure/provision-vm.sh'

# Destroy a VM (wrapper for destroy-vm.sh)
# Usage: vmkill <vm-name>
alias vmkill='~/vm-infrastructure/destroy-vm.sh'

# Start a stopped VM
# Usage: vmstart <vm-name>
alias vmstart='virsh start'

# Shutdown a running VM (graceful)
# Usage: vmstop <vm-name>
alias vmstop='virsh shutdown'

# Force stop a VM (ungraceful)
# Usage: vmforce <vm-name>
alias vmforce='virsh destroy'

# Restart a VM
# Usage: vmrestart <vm-name>
alias vmrestart='virsh reboot'

# =============================================================================
# VM INFORMATION & MONITORING
# =============================================================================

# List all VMs (running and stopped)
# Usage: vmls
alias vmls='virsh list --all'

# Show detailed VM info
# Usage: vmstat <vm-name>
alias vmstat='virsh dominfo'

# Show VM CPU info
# Usage: vmcpu <vm-name>
alias vmcpu='virsh vcpuinfo'

# Show VM memory stats
# Usage: vmmem <vm-name>
alias vmmem='virsh dommemstat'

# Show VM console (useful for debugging boot issues)
# Usage: vmconsole <vm-name>
alias vmconsole='virsh console'

# =============================================================================
# NAVIGATION SHORTCUTS
# =============================================================================

# Jump to terraform directory
# Usage: vmtf
alias vmtf='cd ~/vm-infrastructure/terraform'

# Jump to ansible directory
# Usage: vmans
alias vmans='cd ~/vm-infrastructure/ansible'

# Jump to vm-infrastructure root
# Usage: vmdir
alias vmdir='cd ~/vm-infrastructure'

# =============================================================================
# ANSIBLE & PROVISIONING
# =============================================================================

# Run ansible playbook on current inventory
# Usage: vmpb
alias vmpb='cd ~/vm-infrastructure/ansible && ansible-playbook -i inventory.ini playbook.yml'

# Re-provision a specific VM (same as vmpb)
# Usage: vmansible
alias vmansible='cd ~/vm-infrastructure/ansible && ansible-playbook -i inventory.ini playbook.yml'

# Show current ansible inventory
# Usage: vminv
alias vminv='cat ~/vm-infrastructure/ansible/inventory.ini'

# =============================================================================
# TERRAFORM SHORTCUTS
# =============================================================================

# Show terraform state
# Usage: vmstate
alias vmstate='cd ~/vm-infrastructure/terraform && terraform show'

# Refresh terraform state
# Usage: vmrefresh
alias vmrefresh='cd ~/vm-infrastructure/terraform && terraform refresh'

# Show terraform plan
# Usage: vmplan
alias vmplan='cd ~/vm-infrastructure/terraform && terraform plan'

# =============================================================================
# ADVANCED / DEBUGGING
# =============================================================================

# Copy files to current VM
# Usage: vmcp <local-file> <remote-path>
# Example: vmcp ~/file.txt /home/mr/
vmcp() {
    local vm_ip
    vm_ip=$(cd ~/vm-infrastructure/terraform && terraform output -raw vm_ip 2> /dev/null)
    if [ "$vm_ip" = "pending" ] || [ -z "$vm_ip" ]; then
        echo "Error: No VM IP found"
        return 1
    fi
    scp -i ~/.ssh/vm_key "$1" "mr@${vm_ip}:$2"
}

# Copy files from current VM
# Usage: vmget <remote-file> <local-path>
# Example: vmget /home/mr/file.txt ~/
vmget() {
    local vm_ip
    vm_ip=$(cd ~/vm-infrastructure/terraform && terraform output -raw vm_ip 2> /dev/null)
    if [ "$vm_ip" = "pending" ] || [ -z "$vm_ip" ]; then
        echo "Error: No VM IP found"
        return 1
    fi
    scp -i ~/.ssh/vm_key "mr@${vm_ip}:$1" "$2"
}

# Execute command on current VM
# Usage: vmrun <command>
# Example: vmrun "ls -la"
vmrun() {
    local vm_ip
    vm_ip=$(cd ~/vm-infrastructure/terraform && terraform output -raw vm_ip 2> /dev/null)
    if [ "$vm_ip" = "pending" ] || [ -z "$vm_ip" ]; then
        echo "Error: No VM IP found"
        return 1
    fi
    ssh -i ~/.ssh/vm_key mr@${vm_ip} "$@"
}

# Port forward from VM to localhost
# Usage: vmport <vm-port> [local-port]
# Example: vmport 8080 3000  # Forward VM's 8080 to localhost:3000
vmport() {
    local vm_ip
    vm_ip=$(cd ~/vm-infrastructure/terraform && terraform output -raw vm_ip 2> /dev/null)
    if [ "$vm_ip" = "pending" ] || [ -z "$vm_ip" ]; then
        echo "Error: No VM IP found"
        return 1
    fi
    local vm_port=$1
    local local_port=${2:-$vm_port}
    echo "Forwarding localhost:${local_port} -> ${vm_ip}:${vm_port}"
    ssh -i ~/.ssh/vm_key -L ${local_port}:localhost:${vm_port} -N mr@${vm_ip}
}

# =============================================================================
# USAGE EXAMPLES
# =============================================================================

# Create and connect to a new VM:
#   vmnew my-vm
#   vmssh
#
# Create a VM with custom resources:
#   vmnew big-vm 8192 4
#
# List all VMs and their status:
#   vmls
#
# Get info about a specific VM:
#   vmstat test-vm
#
# Copy a file to the current VM:
#   vmcp ~/myfile.txt /home/mr/
#
# Run a command on the current VM:
#   vmrun "sudo apt update"
#
# Forward a port from VM to localhost:
#   vmport 8080 3000
#
# Destroy a VM:
#   vmkill my-vm
