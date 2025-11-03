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

# Clean up provisioning.log before tests (ensures clean slate)
rm -f "$PROJECT_ROOT/ansible/provisioning.log"

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

# Helper: Provision test VM using Terraform and return its IP
provision_test_vm() {
    local vm_name="$1"
    local memory="${2:-2048}"  # Smaller for tests
    local vcpus="${3:-1}"

    echo -e "${BLUE}  Provisioning test VM: $vm_name${NC}" >&2

    cd "$PROJECT_ROOT/terraform" || return 1

    # Initialize terraform if needed
    if [[ ! -d ".terraform" ]]; then
        terraform init -upgrade > /dev/null 2>&1 || return 1
    fi

    # Apply terraform configuration
    if ! terraform apply -auto-approve \
        -var="vm_name=$vm_name" \
        -var="memory=$memory" \
        -var="vcpus=$vcpus" \
        > /dev/null 2>&1; then
        echo -e "${RED}  ✗ VM provisioning failed${NC}" >&2
        cd "$PROJECT_ROOT" || return 1
        return 1
    fi

    echo -e "${GREEN}  ✓ VM provisioned${NC}" >&2

    # Get VM IP with retry (DHCP takes time)
    echo -e "${BLUE}  Getting VM IP address...${NC}" >&2
    local vm_ip
    local retries=10
    for ((i=1; i<=retries; i++)); do
        vm_ip=$(terraform output -raw vm_ip 2>/dev/null || echo "pending")
        if [[ "$vm_ip" != "pending" && -n "$vm_ip" ]]; then
            echo -e "${GREEN}  ✓ VM IP: $vm_ip${NC}" >&2
            cd "$PROJECT_ROOT" || return 1
            echo "$vm_ip"  # Only the IP goes to stdout for capture
            return 0
        fi
        sleep 2
        terraform refresh -var="vm_name=$vm_name" -var="memory=$memory" -var="vcpus=$vcpus" > /dev/null 2>&1
    done

    echo -e "${RED}  ✗ Failed to get VM IP${NC}" >&2
    cd "$PROJECT_ROOT" || return 1
    return 1
}

# Helper: Wait for VM SSH and cloud-init (VM IP already known from provision)
wait_for_vm_ready() {
    local vm_ip="$1"
    local max_wait="${2:-180}"  # seconds
    local wait_interval=5

    echo -e "${BLUE}  Waiting for SSH access...${NC}" >&2

    # Wait for SSH access
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -o BatchMode=yes "mr@$vm_ip" "echo test" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ SSH accessible${NC}" >&2
            break
        fi

        sleep $wait_interval
        ((elapsed += wait_interval))
    done

    if [[ $elapsed -ge $max_wait ]]; then
        echo -e "${RED}  ✗ Timeout waiting for SSH${NC}" >&2
        return 1
    fi

    # Wait for cloud-init to complete
    echo -e "${BLUE}  Waiting for cloud-init...${NC}" >&2
    elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            "mr@$vm_ip" "cloud-init status --wait" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ Cloud-init complete${NC}" >&2
            return 0
        fi

        sleep $wait_interval
        ((elapsed += wait_interval))
    done

    echo -e "${RED}  ✗ Timeout waiting for cloud-init${NC}" >&2
    return 1
}

# Helper: Run Ansible playbook against VM
run_ansible_playbook() {
    local vm_name="$1"
    local vm_ip="$2"
    local output_file="${3:-/tmp/ansible-output-$$}"
    local dotfiles_path="${4:-}"  # Optional: local dotfiles path for testing

    echo -e "${BLUE}  Running Ansible playbook...${NC}" >&2

    # Create temporary inventory
    local inventory_file="/tmp/test-inventory-$$"
    cat > "$inventory_file" <<EOF
[$vm_name]
$vm_ip ansible_user=mr ansible_ssh_private_key_file=$HOME/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

    cd "$PROJECT_ROOT/ansible" || return 1

    # Run playbook (capture output, allow failure)
    local exit_code=0
    if [[ -n "$dotfiles_path" ]]; then
        # Use local dotfiles path for successful provisioning tests
        ansible-playbook -i "$inventory_file" -e "dotfiles_local_path=$dotfiles_path" playbook.yml > "$output_file" 2>&1 || exit_code=$?
    else
        # Normal playbook run (may fail on git clone for failure tests)
        ansible-playbook -i "$inventory_file" playbook.yml > "$output_file" 2>&1 || exit_code=$?
    fi

    cd "$PROJECT_ROOT" || return 1

    # Cleanup inventory
    rm -f "$inventory_file"

    echo "$exit_code"  # Only exit code goes to stdout for capture
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

    # Provision VM with Terraform (returns IP)
    if ! vm_ip=$(provision_test_vm "$vm_name"); then
        fail "Failed to provision test VM" "VM created with IP" "Terraform failed"
        return
    fi

    # Wait for VM to be ready (SSH + cloud-init)
    if ! wait_for_vm_ready "$vm_ip" 180; then
        fail "VM not accessible" "SSH and cloud-init ready" "Timeout"
        return
    fi

    # Run Ansible playbook (expect package failure, but rescue should handle it)
    # Note: Ansible returns exit code 0 when rescue block successfully handles errors
    # We verify rescue execution through output messages and logs, not exit codes
    run_ansible_playbook "$vm_name" "$vm_ip" "$ansible_output" > /dev/null

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

    local vm_name="test-vm-rescue-git-$$"
    local backup_file
    local vm_ip
    local ansible_output="/tmp/ansible-test2-$$"

    # Backup original playbook
    backup_file=$(backup_playbook)
    # shellcheck disable=SC2064  # backup_file expansion needed at trap set time
    trap "restore_playbook '$backup_file'" RETURN

    # Inject invalid git repository URL into playbook
    echo -e "${BLUE}  Injecting git clone failure...${NC}"
    sed -i 's|repo: ".*"|repo: "file:///nonexistent/path/that/does/not/exist"|' "$PLAYBOOK_PATH"

    # Provision VM with Terraform (returns IP)
    if ! vm_ip=$(provision_test_vm "$vm_name"); then
        fail "Failed to provision test VM" "VM created with IP" "Terraform failed"
        return
    fi

    # Wait for VM to be ready (SSH + cloud-init)
    if ! wait_for_vm_ready "$vm_ip" 180; then
        fail "VM not accessible" "SSH and cloud-init ready" "Timeout"
        return
    fi

    # Run Ansible playbook (expect git clone failure, but rescue should handle it)
    # Note: Ansible returns exit code 0 when rescue block successfully handles errors
    run_ansible_playbook "$vm_name" "$vm_ip" "$ansible_output" > /dev/null

    # Verify rescue block executed (look for "Rollback" in output)
    if ! grep -q "Rollback" "$ansible_output"; then
        fail "Rescue block did not execute" "Rollback messages in output" "No rollback found"
        rm -f "$ansible_output"
        return
    fi

    # Verify dotfiles directory was removed on the VM
    # The rescue block should remove ~/dotfiles after git clone fails
    if ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no "mr@$vm_ip" "test -d ~/dotfiles" 2>/dev/null; then
        fail "Dotfiles directory still exists after rescue" "Directory removed" "Directory found"
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

    pass "Rescue block removed dotfiles directory after git clone failure"
}

# Test 3: Verify always block logs success
test_always_logs_success() {
    test_start "Always block creates provisioning.log on successful provision"

    local vm_name="test-vm-log-success-$$"
    local vm_ip
    local ansible_output="/tmp/ansible-test3-$$"

    # Backup original playbook
    backup_file=$(backup_playbook)
    trap 'restore_playbook "$backup_file"' RETURN

    # Clean up old provisioning.log before test (ensure fresh state)
    rm -f "$PROJECT_ROOT/ansible/provisioning.log"

    # Skip heavy tasks for always block test (minimal playbook for speed/stability)
    echo -e "${BLUE}  Skipping heavy tasks to test always block in isolation...${NC}"

    # Skip git-delta tasks (GitHub API calls, downloads)
    sed -i '/- name: Get latest git-delta release URL/,/changed_when: false/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Install git-delta/,/mode:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Extract git-delta/,/remote_src: yes/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Move delta binary/,/creates: \/usr\/local\/bin\/delta/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Skip starship tasks (downloads)
    sed -i '/- name: Download starship installer/,/mode: .0755./ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Install starship/,/creates: \/usr\/local\/bin\/starship/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Skip SSH/deploy key tasks (not needed without dotfiles)
    sed -i '/- name: Create \.ssh directory for user/,/mode: .0700./ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Generate VM-specific deploy key/,/become_user:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Set deploy key permissions/,/group:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Display public deploy key/,/changed_when: false/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    # Remove deploy key instructions task (debug-only, no functional impact)
    # Delete from this task up to (but not including) the next task
    sed -i '/- name: Deploy key setup instructions/,/- name: Add GitHub to known hosts/{
      /- name: Add GitHub to known hosts/!d
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Add GitHub to known hosts/,/become_user:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Skip dotfiles tasks
    sed -i '/- name: Clone dotfiles repository/,/register: dotfiles_clone_result/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Run dotfiles install script/,/creates:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Mark dotfiles installation as complete/,/mode:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Skip zsh plugin tasks
    sed -i '/- name: Install zsh-syntax-highlighting/,/state: present/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Install zsh-autosuggestions/,/state: present/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Provision VM
    if ! vm_ip=$(provision_test_vm "$vm_name"); then
        fail "Failed to provision test VM"
        return
    fi

    # Wait for VM to be ready
    if ! wait_for_vm_ready "$vm_ip"; then
        fail "VM not ready for testing"
        return
    fi

    # Run Ansible playbook (should succeed with dotfiles clone skipped)
    local ansible_exit_code
    ansible_exit_code=$(run_ansible_playbook "$vm_name" "$vm_ip" "$ansible_output")

    # Verify playbook succeeded
    if [[ $ansible_exit_code -ne 0 ]]; then
        fail "Ansible playbook failed unexpectedly" "Exit code 0" "Exit code $ansible_exit_code"
        cat "$ansible_output" >&2
        rm -f "$ansible_output"
        return
    fi

    # Verify provisioning.log exists
    local log_file="$PROJECT_ROOT/ansible/provisioning.log"
    if [[ ! -f "$log_file" ]]; then
        fail "provisioning.log not created" "Log file exists" "File missing"
        rm -f "$ansible_output"
        return
    fi

    # Verify log contains COMPLETED status (not FAILED)
    if ! grep -q "COMPLETED" "$log_file"; then
        fail "provisioning.log missing COMPLETED status" "COMPLETED in log" "Not found"
        echo "Log contents:" >&2
        cat "$log_file" >&2
        rm -f "$ansible_output"
        return
    fi

    # Verify log does NOT contain FAILED status
    if grep -q "FAILED" "$log_file"; then
        fail "provisioning.log contains FAILED on successful provision" "No FAILED status" "FAILED found"
        echo "Log contents:" >&2
        cat "$log_file" >&2
        rm -f "$ansible_output"
        return
    fi

    # Verify log contains timestamp (ISO8601 format: YYYY-MM-DD)
    if ! grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$log_file"; then
        fail "provisioning.log missing timestamp" "ISO8601 timestamp" "Not found"
        echo "Log contents:" >&2
        cat "$log_file" >&2
        rm -f "$ansible_output"
        return
    fi

    # Cleanup output file
    rm -f "$ansible_output"

    pass "Always block created provisioning.log with COMPLETED status on success"
}

# Test 4: Verify always block logs failure
test_always_logs_failure() {
    test_start "Always block creates provisioning.log on failure with error details"

    local vm_name="test-vm-log-failure-$$"
    local vm_ip
    local ansible_output="/tmp/ansible-test4-$$"

    # Backup original playbook
    backup_file=$(backup_playbook)
    trap 'restore_playbook "$backup_file"' RETURN

    # Clean up old provisioning.log before test (ensure fresh state)
    rm -f "$PROJECT_ROOT/ansible/provisioning.log"

    # Skip heavy tasks (minimal playbook for speed/stability)
    echo -e "${BLUE}  Using minimal playbook to test always block on failure...${NC}"

    # Skip git-delta tasks
    sed -i '/- name: Get latest git-delta release URL/,/changed_when: false/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Install git-delta/,/mode:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Extract git-delta/,/remote_src: yes/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Move delta binary/,/creates: \/usr\/local\/bin\/delta/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Skip starship tasks
    sed -i '/- name: Download starship installer/,/mode: .0755./ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Install starship/,/creates: \/usr\/local\/bin\/starship/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Skip SSH/deploy key tasks
    sed -i '/- name: Create \.ssh directory for user/,/mode: .0700./ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Generate VM-specific deploy key/,/become_user:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Set deploy key permissions/,/group:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Deploy key setup instructions/,/- name: Add GitHub to known hosts/{
      /- name: Add GitHub to known hosts/!d
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Add GitHub to known hosts/,/become_user:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Skip dotfiles tasks
    sed -i '/- name: Clone dotfiles repository/,/register: dotfiles_clone_result/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Run dotfiles install script/,/creates:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Mark dotfiles installation as complete/,/mode:/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Skip zsh plugin tasks
    sed -i '/- name: Install zsh-syntax-highlighting/,/state: present/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"
    sed -i '/- name: Install zsh-autosuggestions/,/state: present/ {
      /^[^#]/s/^/          # /
    }' "$PLAYBOOK_PATH"

    # Inject package failure (invalid package)
    echo -e "${BLUE}  Injecting package failure to trigger always block...${NC}"
    sed -i 's/- git$/- git\n              - invalid-package-that-does-not-exist-12345/' "$PLAYBOOK_PATH"

    # Provision VM
    if ! vm_ip=$(provision_test_vm "$vm_name"); then
        fail "Failed to provision test VM"
        return
    fi

    # Wait for VM to be ready
    if ! wait_for_vm_ready "$vm_ip"; then
        fail "VM not ready for testing"
        return
    fi

    # Run Ansible playbook (expect failure, but always block should still execute)
    local ansible_exit_code
    ansible_exit_code=$(run_ansible_playbook "$vm_name" "$vm_ip" "$ansible_output")

    # Note: With rescue block, Ansible returns 0 even on failure
    # We verify failure through provisioning.log content, not exit code

    # Verify provisioning.log exists
    local log_file="$PROJECT_ROOT/ansible/provisioning.log"
    if [[ ! -f "$log_file" ]]; then
        fail "provisioning.log not created" "Log file exists" "File missing"
        rm -f "$ansible_output"
        return
    fi

    # Verify log contains FAILED status
    if ! grep -q "FAILED" "$log_file"; then
        fail "provisioning.log missing FAILED status" "FAILED in log" "Not found"
        echo "Log contents:" >&2
        cat "$log_file" >&2
        rm -f "$ansible_output"
        return
    fi

    # Verify log does NOT contain COMPLETED status (should be failure)
    if grep -q "COMPLETED" "$log_file"; then
        fail "provisioning.log shows COMPLETED on failure" "No COMPLETED status" "COMPLETED found"
        echo "Log contents:" >&2
        cat "$log_file" >&2
        rm -f "$ansible_output"
        return
    fi

    # Verify log contains failed task name
    if ! grep -q "Failed task:" "$log_file"; then
        fail "provisioning.log missing failed task name" "Failed task in log" "Not found"
        echo "Log contents:" >&2
        cat "$log_file" >&2
        rm -f "$ansible_output"
        return
    fi

    # Verify log contains timestamp
    if ! grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$log_file"; then
        fail "provisioning.log missing timestamp" "ISO8601 timestamp" "Not found"
        echo "Log contents:" >&2
        cat "$log_file" >&2
        rm -f "$ansible_output"
        return
    fi

    # Cleanup output file
    rm -f "$ansible_output"

    pass "Always block created provisioning.log with FAILED status and error details"
}

# Test 5: Verify rescue block is idempotent
test_rescue_idempotent() {
    test_start "Rescue block can be run multiple times without errors"

    local vm_name="test-vm-idempotent-$$"
    local vm_ip
    local ansible_output1="/tmp/ansible-test5-run1-$$"
    local ansible_output2="/tmp/ansible-test5-run2-$$"

    # Backup original playbook
    backup_file=$(backup_playbook)
    trap 'restore_playbook "$backup_file"' RETURN

    # Clean up old provisioning.log before test
    rm -f "$PROJECT_ROOT/ansible/provisioning.log"

    # Inject git clone failure (same as Test 2)
    echo -e "${BLUE}  Injecting git clone failure for idempotency test...${NC}"
    sed -i 's|repo: ".*"|repo: "file:///nonexistent/path/that/does/not/exist"|' "$PLAYBOOK_PATH"

    # Provision VM
    if ! vm_ip=$(provision_test_vm "$vm_name"); then
        fail "Failed to provision test VM"
        return
    fi

    # Wait for VM to be ready
    if ! wait_for_vm_ready "$vm_ip"; then
        fail "VM not ready for testing"
        return
    fi

    # First run: Execute playbook with failure (rescue block should execute)
    echo -e "${BLUE}  Running Ansible playbook (first run - rescue should execute)...${NC}"
    run_ansible_playbook "$vm_name" "$vm_ip" "$ansible_output1" > /dev/null

    # Verify first run executed rescue block
    if ! grep -q "Rollback" "$ansible_output1"; then
        fail "First run: Rescue block did not execute" "Rollback in output" "No rollback found"
        rm -f "$ansible_output1" "$ansible_output2"
        return
    fi

    # Second run: Execute playbook again with same failure (test idempotency)
    echo -e "${BLUE}  Running Ansible playbook (second run - testing idempotency)...${NC}"
    local ansible_exit_code
    ansible_exit_code=$(run_ansible_playbook "$vm_name" "$vm_ip" "$ansible_output2")

    # Verify second run also executed rescue block
    if ! grep -q "Rollback" "$ansible_output2"; then
        fail "Second run: Rescue block did not execute" "Rollback in output" "No rollback found"
        rm -f "$ansible_output1" "$ansible_output2"
        return
    fi

    # Verify second run succeeded (exit code 0)
    if [[ $ansible_exit_code -ne 0 ]]; then
        fail "Second run failed unexpectedly" "Exit code 0" "Exit code $ansible_exit_code"
        echo "Second run output:" >&2
        cat "$ansible_output2" >&2
        rm -f "$ansible_output1" "$ansible_output2"
        return
    fi

    # Verify VM still accessible after both runs
    if ! ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no "mr@$vm_ip" "echo 'VM accessible'" 2>/dev/null | grep -q "VM accessible"; then
        fail "VM not accessible after idempotency test" "SSH working" "SSH failed"
        rm -f "$ansible_output1" "$ansible_output2"
        return
    fi

    # Cleanup output files
    rm -f "$ansible_output1" "$ansible_output2"

    pass "Rescue block is idempotent (can run multiple times without errors)"
}

# Test 6: Verify rescue preserves VM usability
test_rescue_preserves_vm_usability() {
    test_start "VM remains SSH-accessible and usable after rescue block executes"

    local vm_name="test-vm-usability-$$"
    local vm_ip
    local ansible_output="/tmp/ansible-test6-$$"

    # Backup original playbook
    backup_file=$(backup_playbook)
    trap 'restore_playbook "$backup_file"' RETURN

    # Clean up old provisioning.log before test
    rm -f "$PROJECT_ROOT/ansible/provisioning.log"

    # Inject git clone failure (rescue block will clean up dotfiles)
    echo -e "${BLUE}  Injecting git clone failure to test VM usability after rescue...${NC}"
    sed -i 's|repo: ".*"|repo: "file:///nonexistent/path/that/does/not/exist"|' "$PLAYBOOK_PATH"

    # Provision VM
    if ! vm_ip=$(provision_test_vm "$vm_name"); then
        fail "Failed to provision test VM"
        return
    fi

    # Wait for VM to be ready
    if ! wait_for_vm_ready "$vm_ip"; then
        fail "VM not ready for testing"
        return
    fi

    # Run Ansible playbook with failure (rescue block should execute)
    run_ansible_playbook "$vm_name" "$vm_ip" "$ansible_output" > /dev/null

    # Verify rescue block executed
    if ! grep -q "Rollback" "$ansible_output"; then
        fail "Rescue block did not execute" "Rollback in output" "No rollback found"
        rm -f "$ansible_output"
        return
    fi

    # Test 1: Verify VM remains SSH-accessible
    echo -e "${BLUE}  Verifying SSH accessibility after rescue...${NC}"
    if ! ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no "mr@$vm_ip" "echo 'SSH test successful'" 2>/dev/null | grep -q "SSH test successful"; then
        fail "VM not SSH-accessible after rescue" "SSH working" "SSH failed"
        rm -f "$ansible_output"
        return
    fi

    # Test 2: Verify core packages still installed (from block: section before failure)
    echo -e "${BLUE}  Verifying core packages still installed...${NC}"
    if ! ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no "mr@$vm_ip" "which git && which zsh && which nvim" 2>/dev/null | grep -q "/usr/bin"; then
        fail "Core packages not installed after rescue" "git/zsh/nvim present" "Packages missing"
        rm -f "$ansible_output"
        return
    fi

    # Test 3: Verify user shell is zsh (from block: section before failure)
    echo -e "${BLUE}  Verifying user shell configuration...${NC}"
    if ! ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no "mr@$vm_ip" "grep '^mr:' /etc/passwd" 2>/dev/null | grep -q "/usr/bin/zsh"; then
        fail "User shell not configured after rescue" "mr using zsh" "Shell not zsh"
        rm -f "$ansible_output"
        return
    fi

    # Test 4: Verify VM can execute commands normally
    echo -e "${BLUE}  Verifying VM can execute commands...${NC}"
    if ! ssh -i "$HOME/.ssh/vm_key" -o StrictHostKeyChecking=no "mr@$vm_ip" "ls /home/mr && whoami && hostname" 2>/dev/null | grep -q "mr"; then
        fail "VM cannot execute commands after rescue" "Commands working" "Commands failed"
        rm -f "$ansible_output"
        return
    fi

    # Cleanup output file
    rm -f "$ansible_output"

    pass "VM remains fully usable and accessible after rescue block execution"
}

# Main execution (only run if executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
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
fi
