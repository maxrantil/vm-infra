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

# Test 1: Verify rescue block executes on package installation failure
test_rescue_executes_on_package_failure() {
    test_start "Rescue block executes when package installation fails"

    # shellcheck disable=SC2034  # vm_name will be used when test is implemented
    local vm_name="test-vm-rescue-pkg-$$"
    local backup_file

    # Backup original playbook
    backup_file=$(backup_playbook)
    # shellcheck disable=SC2064  # backup_file expansion needed at trap set time
    trap "restore_playbook '$backup_file'" RETURN

    # TODO: RED phase - This test will fail because implementation doesn't exist yet
    # Need to:
    # 1. Modify playbook to inject invalid package name
    # 2. Provision VM (expect failure)
    # 3. Capture ansible-playbook output
    # 4. Verify rescue block tasks executed (look for "Rollback" messages)
    # 5. Verify provisioning.log shows "FAILED" status

    # For RED phase, just fail immediately to show test infrastructure works
    fail "Test not implemented yet" "Implementation" "Placeholder"
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
