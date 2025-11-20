#!/bin/bash
# ABOUTME: Single test runner for vm-ssh.sh username extraction (Test 1 only)

set -e

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test infrastructure
source "$SCRIPT_DIR/lib/assertions.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"

# Source vm-ssh.sh to make get_vm_username available
source "$PROJECT_ROOT/vm-ssh.sh"

echo "========================================"
echo "vm-ssh.sh Username Tests (Test 1 ONLY)"
echo "========================================"
echo "⚠️  This test provisions a real VM and takes ~5-10 minutes"
echo ""

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

# Run single test
test_username_extraction

# Print summary
echo ""
print_test_summary
