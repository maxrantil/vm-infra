#!/bin/bash
# ABOUTME: Tests for vm-ssh.sh username retrieval functionality

set -e

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test infrastructure
source "$SCRIPT_DIR/lib/assertions.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"

# Source vm-ssh.sh to make get_vm_username available
source "$PROJECT_ROOT/vm-ssh.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "vm-ssh.sh Username Tests"
echo "========================================"

#####################################
# Test Case 1: Extract username for VM with custom username
# Purpose: Verify get_vm_username() extracts correct username from terraform workspace
# Preconditions: VM provisioned with custom username
# Expected Result: Function returns custom username (not default 'mr')
# Coverage: Functional requirement FR-1 (dynamic username detection)
#####################################
test_username_extraction() {
    echo ""
    echo "Test 1: Username extraction for custom username"

    local test_vm="test-username-$$"
    local test_user="customuser123"

    # Setup: Provision VM
    provision_test_vm "$test_vm" "$test_user" 2048 1 || return 1
    register_cleanup_on_exit "$test_vm"

    # Verify terraform workspace exists
    local workspace_exists
    workspace_exists=$(cd "$PROJECT_ROOT/terraform" && terraform workspace list | grep -c "$test_vm" || true)
    assert_not_equals 0 "$workspace_exists" "Terraform workspace should exist"

    # Test: Extract username
    local extracted_username
    extracted_username=$(get_vm_username "$test_vm")
    local exit_code=$?

    # Assert: Function succeeded
    assert_success "$exit_code" "get_vm_username should return 0"

    # Assert: Username matches provisioned value
    assert_equals "$test_user" "$extracted_username" "Username should match provisioned value"

    # Assert: Workspace returned to default
    local current_workspace
    current_workspace=$(cd "$PROJECT_ROOT/terraform" && terraform workspace show)
    assert_equals "default" "$current_workspace" "Should return to default workspace"

    # Cleanup
    destroy_test_vm "$test_vm"
}

#####################################
# Test Case 2: Error handling for non-existent VM
# Purpose: Verify get_vm_username() fails gracefully for non-existent workspace
# Expected Result: Function returns exit code 1, no stdout output
# Coverage: Error handling requirement (NFR-2)
#####################################
test_username_failure() {
    echo ""
    echo "Test 2: Error handling for non-existent VM"

    # Test: Attempt to get username for non-existent VM
    local exit_code
    get_vm_username "nonexistent-vm-$$" > /dev/null 2>&1
    exit_code=$?

    # Assert: Function returns non-zero exit code
    assert_failure "$exit_code" "Should fail for non-existent VM"

    # Assert: Workspace is still default (cleanup happened despite failure)
    local current_workspace
    current_workspace=$(cd "$PROJECT_ROOT/terraform" && terraform workspace show)
    assert_equals "default" "$current_workspace" "Should be in default workspace after failure"
}

#####################################
# Test Case 3: End-to-end SSH connection with custom username
# Purpose: Verify vm-ssh.sh successfully connects using extracted username
# Preconditions: VM fully provisioned and SSH-ready
# Expected Result: SSH connection succeeds, correct username used
# Coverage: End-to-end workflow (NFR-2)
#####################################
test_ssh_connection_with_custom_username() {
    echo ""
    echo "Test 3: End-to-end SSH connection with custom username"

    local test_vm="test-connect-$$"
    local test_user="testuser456"

    # Setup: Provision VM
    echo "[TEST] Provisioning VM (this may take 1-2 minutes)..."
    provision_test_vm "$test_vm" "$test_user" 2048 1 || return 1
    register_cleanup_on_exit "$test_vm"

    # Wait for SSH to be fully ready
    echo "[TEST] Waiting for SSH to be ready..."
    local vm_ip
    vm_ip=$(cd "$PROJECT_ROOT/terraform" && \
            terraform workspace select "$test_vm" 2>/dev/null && \
            terraform output -raw vm_ip)
    cd "$PROJECT_ROOT/terraform" && terraform workspace select default 2>/dev/null

    local max_wait=60
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no \
               -o ConnectTimeout=2 -o BatchMode=yes \
               "$test_user@$vm_ip" 'exit' 2>/dev/null; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done

    # Test: Verify username extraction works
    local extracted_username
    extracted_username=$(get_vm_username "$test_vm")
    assert_equals "$test_user" "$extracted_username" "Extracted username should match"

    # Test: Verify SSH connection using extracted username
    local ssh_result
    ssh_result=$(ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no \
                     -o ConnectTimeout=5 "$extracted_username@$vm_ip" 'whoami' 2>/dev/null)
    assert_equals "$test_user" "$ssh_result" "SSH should connect as correct user"

    # Cleanup
    destroy_test_vm "$test_vm"
}

#####################################
# Test Case 4: Username with special characters (hyphens, underscores)
# Purpose: Verify username extraction handles valid special characters
# Expected Result: Hyphens and underscores in username are preserved
# Coverage: Edge case handling
#####################################
test_username_special_chars() {
    echo ""
    echo "Test 4: Username with special characters"

    local test_vm="test-special-$$"
    local test_user="test-user"

    # Setup: Provision VM with special chars in username
    provision_test_vm "$test_vm" "$test_user" 2048 1 || return 1
    register_cleanup_on_exit "$test_vm"

    # Test: Extract username
    local extracted_username
    extracted_username=$(get_vm_username "$test_vm")
    local exit_code=$?

    # Assert: Extraction succeeded
    assert_success "$exit_code" "Should handle special characters"

    # Assert: Username preserved correctly
    assert_equals "$test_user" "$extracted_username" "Special characters should be preserved"

    # Cleanup
    destroy_test_vm "$test_vm"
}

#####################################
# Test Case 5: Invalid VM name (security)
# Purpose: Verify VM_NAME validation prevents path traversal
# Expected Result: Function rejects VM names with .. or invalid characters
# Coverage: Security requirement (SEC-002)
#####################################
test_invalid_vm_name() {
    echo ""
    echo "Test 5: Invalid VM name rejection (security)"

    # Test: Path traversal attempt
    local exit_code
    get_vm_username "../../../etc/passwd" > /dev/null 2>&1
    exit_code=$?

    assert_failure "$exit_code" "Should reject path traversal attempt"

    # Test: Invalid characters (space not allowed)
    get_vm_username "test vm" > /dev/null 2>&1
    exit_code=$?

    assert_failure "$exit_code" "Should reject VM name with spaces"
}

#####################################
# Test Case 6: Workspace cleanup guarantee
# Purpose: Verify workspace is always restored even if function returns early
# Expected Result: Workspace is default after get_vm_username call
# Coverage: Reliability requirement (BUG-002 fix verification)
#####################################
test_workspace_cleanup() {
    echo ""
    echo "Test 6: Workspace cleanup guarantee"

    local test_vm="test-cleanup-$$"
    local test_user="testuser789"

    # Setup: Provision VM
    provision_test_vm "$test_vm" "$test_user" 2048 1 || return 1
    register_cleanup_on_exit "$test_vm"

    # Test: Get username (should succeed)
    get_vm_username "$test_vm" > /dev/null

    # Assert: Workspace returned to default
    local current_workspace
    current_workspace=$(cd "$PROJECT_ROOT/terraform" && terraform workspace show)
    assert_equals "default" "$current_workspace" "Workspace should be default after success"

    # Test: Attempt to get username for non-existent VM (should fail)
    get_vm_username "nonexistent-$$" 2>/dev/null || true

    # Assert: Workspace still default (cleanup happened despite error)
    current_workspace=$(cd "$PROJECT_ROOT/terraform" && terraform workspace show)
    assert_equals "default" "$current_workspace" "Workspace should be default after failure"

    # Cleanup
    destroy_test_vm "$test_vm"
}

# Run all tests
test_username_extraction
test_username_failure
test_ssh_connection_with_custom_username
test_username_special_chars
test_invalid_vm_name
test_workspace_cleanup

# Print summary
echo ""
print_test_summary
