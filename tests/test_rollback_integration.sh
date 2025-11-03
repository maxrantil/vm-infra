#!/usr/bin/env bash
# ABOUTME: Integration tests for Ansible playbook rollback handlers with real VM provisioning

set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAYBOOK_PATH="$PROJECT_ROOT/ansible/playbook.yml"

# Source cleanup library
# shellcheck source=tests/lib/cleanup.sh
source "$SCRIPT_DIR/lib/cleanup.sh"

# Test ID for resource tracking
TEST_ID="rollback-integration-$$"

# Cleanup function for this test suite
cleanup_on_exit() {
    local exit_code=$?
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Cleanup triggered (exit code: $exit_code)${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Clean up any test VMs
    cleanup_test_vm "test-vm-rescue-pkg-$$"
    cleanup_test_vm "test-vm-dotfiles-$$"
    cleanup_test_vm "test-vm-log-success-$$"
    cleanup_test_vm "test-vm-log-failure-$$"
    cleanup_test_vm "test-vm-idempotent-$$"
    cleanup_test_vm "test-vm-usability-$$"

    # Clean up test artifacts
    cleanup_test_artifacts "$TEST_ID"

    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}Cleanup complete${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Register cleanup for EXIT, INT (Ctrl+C), and TERM signals
trap cleanup_on_exit EXIT INT TERM

# Test helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((++TESTS_PASSED))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    if [[ $# -ge 2 ]]; then
        echo -e "  ${RED}Expected:${NC} $2"
    fi
    if [[ $# -ge 3 ]]; then
        echo -e "  ${RED}Got:${NC} $3"
    fi
    ((++TESTS_FAILED))
}

test_start() {
    ((++TESTS_RUN))
    echo -e "\n${YELLOW}Test $TESTS_RUN:${NC} $1"
}

# Helper: Backup playbook for mutation tests
backup_playbook() {
    local backup_file="/tmp/playbook-backup-$$"
    cp "$PLAYBOOK_PATH" "$backup_file"
    echo "$backup_file"
}

# Helper: Restore playbook after mutation test
restore_playbook() {
    local backup_file="$1"
    if [[ -f "$backup_file" ]]; then
        mv "$backup_file" "$PLAYBOOK_PATH"
        echo -e "${GREEN}  ✓ Playbook restored${NC}"
    fi
}

# Helper: Provision test VM using Terraform
provision_test_vm() {
    local vm_name="$1"
    local memory="${2:-2048}"  # Smaller for tests
    local vcpus="${3:-1}"

    echo -e "${BLUE}  Provisioning test VM: $vm_name${NC}"

    cd "$PROJECT_ROOT/terraform" || return 1

    # Initialize terraform if needed
    if [[ ! -d ".terraform" ]]; then
        terraform init -upgrade > /dev/null 2>&1 || return 1
    fi

    # Apply terraform configuration
    terraform apply -auto-approve \
        -var="vm_name=$vm_name" \
        -var="memory=$memory" \
        -var="vcpus=$vcpus" \
        > /dev/null 2>&1

    local result=$?
    cd "$PROJECT_ROOT" || return 1

    if [[ $result -eq 0 ]]; then
        echo -e "${GREEN}  ✓ VM provisioned${NC}"
        return 0
    else
        echo -e "${RED}  ✗ VM provisioning failed${NC}"
        return 1
    fi
}

# Helper: Wait for VM to be accessible via SSH and cloud-init to complete
wait_for_vm() {
    local vm_name="$1"
    local max_wait="${2:-180}"  # seconds
    local wait_interval=5

    echo -e "${BLUE}  Waiting for VM to be ready...${NC}"

    # Get VM IP from virsh (use sudo for system libvirt)
    local vm_ip
    local elapsed=0

    # First wait for IP and SSH access
    while [[ $elapsed -lt $max_wait ]]; do
        vm_ip=$(sudo virsh domifaddr "$vm_name" 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1)

        if [[ -n "$vm_ip" ]]; then
            # Try SSH connection
            if ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
                -o BatchMode=yes "ubuntu@$vm_ip" "echo test" > /dev/null 2>&1; then
                echo -e "${GREEN}  ✓ SSH accessible at $vm_ip${NC}"
                break
            fi
        fi

        sleep $wait_interval
        ((elapsed += wait_interval))
    done

    if [[ $elapsed -ge $max_wait ]]; then
        echo -e "${RED}  ✗ Timeout waiting for SSH${NC}"
        return 1
    fi

    # Wait for cloud-init to complete
    echo -e "${BLUE}  Waiting for cloud-init...${NC}"
    elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            "ubuntu@$vm_ip" "cloud-init status --wait" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ Cloud-init complete${NC}"
            echo "$vm_ip"
            return 0
        fi

        sleep $wait_interval
        ((elapsed += wait_interval))
    done

    echo -e "${RED}  ✗ Timeout waiting for cloud-init${NC}"
    return 1
}

# Helper: Run Ansible playbook against VM
run_ansible_playbook() {
    local vm_name="$1"
    local vm_ip="$2"
    local output_file="${3:-/tmp/ansible-output-$$}"

    echo -e "${BLUE}  Running Ansible playbook...${NC}"

    # Create temporary inventory
    local inventory_file="/tmp/test-inventory-$$"
    cat > "$inventory_file" <<EOF
[$vm_name]
$vm_ip ansible_user=ubuntu ansible_ssh_private_key_file=$HOME/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

    cd "$PROJECT_ROOT/ansible" || return 1

    # Run playbook (capture output, allow failure)
    local exit_code=0
    ansible-playbook -i "$inventory_file" playbook.yml > "$output_file" 2>&1 || exit_code=$?

    cd "$PROJECT_ROOT" || return 1

    # Cleanup inventory
    rm -f "$inventory_file"

    echo "$exit_code"
    return 0
}

# Test 1: Verify rescue block executes on package installation failure
test_rescue_executes_on_package_failure() {
    test_start "Rescue block executes when package installation fails"

    local vm_name="test-vm-rescue-pkg-$$"
    local backup_file
    local vm_ip
    local ansible_output="/tmp/ansible-test1-$$"

    # Backup original playbook
    backup_file=$(backup_playbook)
    # shellcheck disable=SC2064  # backup_file expansion needed at trap set time
    trap "restore_playbook '$backup_file'" RETURN

    # Inject invalid package name into playbook
    echo -e "${BLUE}  Injecting package failure...${NC}"
    sed -i 's/- git$/- git\n              - invalid-package-that-does-not-exist-12345/' "$PLAYBOOK_PATH"

    # Provision VM with Terraform
    if ! provision_test_vm "$vm_name"; then
        fail "Failed to provision test VM" "VM created" "Terraform failed"
        return
    fi

    # Wait for VM to be ready
    if ! vm_ip=$(wait_for_vm "$vm_name" 180); then
        fail "VM not accessible" "SSH connection" "Timeout"
        return
    fi

    # Run Ansible playbook (expect failure due to invalid package)
    local ansible_exit_code
    ansible_exit_code=$(run_ansible_playbook "$vm_name" "$vm_ip" "$ansible_output")

    # Verify playbook failed (exit code != 0)
    if [[ $ansible_exit_code -eq 0 ]]; then
        fail "Ansible should have failed" "Non-zero exit code" "Exit code: $ansible_exit_code"
        rm -f "$ansible_output"
        return
    fi

    # Verify rescue block executed (look for "Rollback" in output)
    if ! grep -q "Rollback" "$ansible_output"; then
        fail "Rescue block did not execute" "Rollback messages in output" "No rollback found"
        rm -f "$ansible_output"
        return
    fi

    # Verify provisioning.log exists and contains "FAILED"
    local log_file="$PROJECT_ROOT/ansible/provisioning.log"
    if [[ ! -f "$log_file" ]]; then
        fail "provisioning.log not created" "Log file exists" "File missing"
        rm -f "$ansible_output"
        return
    fi

    if ! grep -q "FAILED" "$log_file"; then
        fail "provisioning.log missing FAILED status" "FAILED in log" "Not found"
        rm -f "$ansible_output"
        return
    fi

    # Cleanup output file
    rm -f "$ansible_output"

    pass "Rescue block executed and logged failure correctly"
}

# Test 2: Verify rescue cleans dotfiles directory on git clone failure
test_rescue_cleans_dotfiles_on_failure() {
    test_start "Rescue block removes dotfiles directory when git clone fails"

    # TODO: Implement in next iteration
    fail "Test not implemented yet" "Implementation" "Placeholder"
}

# Test 3: Verify always block logs success
test_always_logs_success() {
    test_start "Always block creates provisioning.log on successful provision"

    # TODO: Implement in next iteration
    fail "Test not implemented yet" "Implementation" "Placeholder"
}

# Test 4: Verify always block logs failure
test_always_logs_failure() {
    test_start "Always block creates provisioning.log on failure with error details"

    # TODO: Implement in next iteration
    fail "Test not implemented yet" "Implementation" "Placeholder"
}

# Test 5: Verify rescue block is idempotent
test_rescue_idempotent() {
    test_start "Rescue block can be run multiple times without errors"

    # TODO: Implement in next iteration
    fail "Test not implemented yet" "Implementation" "Placeholder"
}

# Test 6: Verify rescue preserves VM usability
test_rescue_preserves_vm_usability() {
    test_start "VM remains SSH-accessible and usable after rescue block executes"

    # TODO: Implement in next iteration
    fail "Test not implemented yet" "Implementation" "Placeholder"
}

# Main execution
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Ansible Rollback Integration Tests${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "${BLUE}Test ID: $TEST_ID${NC}"
echo ""
echo -e "${YELLOW}⚠️  WARNING: These tests provision real VMs${NC}"
echo -e "${YELLOW}    Estimated runtime: 15-30 minutes${NC}"
echo -e "${YELLOW}    Requires: libvirt/KVM, Terraform, Ansible${NC}"
echo ""

# Run all tests
test_rescue_executes_on_package_failure
test_rescue_cleans_dotfiles_on_failure
test_always_logs_success
test_always_logs_failure
test_rescue_idempotent
test_rescue_preserves_vm_usability

# Print summary
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}Test Summary${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "Tests run:    $TESTS_RUN"
echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
else
    echo -e "Tests failed: $TESTS_FAILED"
fi

# Exit with appropriate code
if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
else
    exit 0
fi
