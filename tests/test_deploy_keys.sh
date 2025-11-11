#!/usr/bin/env bash
# ABOUTME: Behavior tests for VM-specific deploy key generation (Issue #49 - CVE-2024-ANSIBLE-001)
# Refactored from grep anti-patterns to behavior tests (Issue #63)

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Path constants (reduces duplication)
readonly PLAYBOOK_PATH="$SCRIPT_DIR/../ansible/playbook.yml"
readonly PROVISION_SCRIPT="$SCRIPT_DIR/../provision-vm.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Cached dry-run output (performance optimization)
DRY_RUN_OUTPUT=""

# Helper: Cache dry-run output for all tests
cache_dry_run_output() {
    if [ -z "$DRY_RUN_OUTPUT" ]; then
        set +e
        DRY_RUN_OUTPUT=$("$PROVISION_SCRIPT" test-vm --dry-run 2>&1)
        set -e
    fi
}

# Helper: Check if playbook has a specific task
playbook_has_task() {
    local task_name="$1"
    grep -q "$task_name" "$PLAYBOOK_PATH"
}

# Test 1: No host SSH key copying (BEHAVIOR + IMPLEMENTATION)
test_no_ssh_key_copy() {
    info "Test 1: Verify playbook does not copy SSH private keys from host"

    # BEHAVIOR TEST: Check dry-run output
    cache_dry_run_output

    # Negative assertion: Should NOT mention host key copying
    if echo "$DRY_RUN_OUTPUT" | grep -qi "copy.*host.*ssh.*key\|copying.*id_ed25519\|src:.*~/.ssh/id_"; then
        fail "Dry-run output mentions host SSH key copying (SECURITY VULNERABILITY)"
        return 1
    fi

    # IMPLEMENTATION VERIFICATION: Confirm playbook lacks dangerous tasks
    if grep -q "Copy GitHub SSH private key to VM" "$PLAYBOOK_PATH"; then
        fail "Playbook still contains 'Copy GitHub SSH private key to VM' task (SECURITY VULNERABILITY)"
        return 1
    fi

    if grep -q "src: ~/.ssh/id_ed25519" "$PLAYBOOK_PATH"; then
        fail "Playbook still references ~/.ssh/id_ed25519 (host SSH key should not be copied)"
        return 1
    fi

    pass "Playbook does not copy host SSH keys (behavior + implementation verified)"
}

# Test 2: Deploy key generation (BEHAVIOR + IMPLEMENTATION)
test_deploy_key_generation() {
    info "Test 2: Verify playbook generates VM-specific deploy keys"

    # BEHAVIOR TEST: Verify dry-run completes successfully
    cache_dry_run_output

    # Configuration should be valid (dry-run exits 0)
    local exit_code
    set +e
    "$PROVISION_SCRIPT" test-vm --dry-run > /dev/null 2>&1
    exit_code=$?
    set -e

    if [ $exit_code -ne 0 ]; then
        fail "Dry-run validation failed (exit code: $exit_code)"
        return 1
    fi

    # IMPLEMENTATION VERIFICATION: Confirm playbook has deploy key task
    if ! playbook_has_task "Generate VM-specific deploy key"; then
        fail "Playbook missing 'Generate VM-specific deploy key' task"
        return 1
    fi

    if ! grep -q "ssh-keygen.*vm-deploy" "$PLAYBOOK_PATH"; then
        fail "Playbook missing ssh-keygen command for deploy key generation"
        return 1
    fi

    pass "Playbook generates VM-specific deploy keys (behavior + implementation verified)"
}

# Test 3: Deploy key setup instructions (IMPLEMENTATION)
test_deploy_key_instructions() {
    info "Test 3: Verify playbook displays manual setup instructions"

    # NOTE: Dry-run exits BEFORE Ansible runs, so we verify implementation only

    # IMPLEMENTATION VERIFICATION: Confirm playbook has instruction task
    if ! playbook_has_task "Deploy key setup instructions"; then
        fail "Playbook missing deploy key setup instructions"
        return 1
    fi

    if ! grep -q "MANUAL STEP REQUIRED" "$PLAYBOOK_PATH"; then
        fail "Playbook missing manual step warning"
        return 1
    fi

    # Verify instructions mention GitHub repository
    if ! grep -q "github.com/maxrantil/dotfiles" "$PLAYBOOK_PATH"; then
        fail "Playbook instructions missing GitHub repository URL"
        return 1
    fi

    pass "Playbook displays deploy key setup instructions (implementation verified)"
}

# Test 4: Deploy key permissions (IMPLEMENTATION)
test_deploy_key_permissions() {
    info "Test 4: Verify deploy key has correct permissions (0600)"

    # IMPLEMENTATION VERIFICATION: More robust check for mode 0600 near ssh_key_path
    # Avoids brittleness of exact line count (-A 5)
    if ! grep -B 2 -A 2 "mode.*'0600'" "$PLAYBOOK_PATH" | grep -q "path.*ssh_key_path"; then
        fail "Deploy key permissions not set to 0600 or not associated with ssh_key_path"
        return 1
    fi

    pass "Deploy key permissions set correctly (restrictive 0600, owner-only)"
}

# Test 5: Deploy key VM-specific identifier (IMPLEMENTATION)
test_deploy_key_identifier() {
    info "Test 5: Verify deploy key includes VM hostname identifier"

    # IMPLEMENTATION VERIFICATION: Confirm VM-specific identifier
    if ! grep -q "vm-deploy.*ansible_hostname" "$PLAYBOOK_PATH"; then
        fail "Deploy key does not include VM-specific identifier"
        return 1
    fi

    pass "Deploy key includes VM-specific identifier (unique per VM)"
}

# Test 6: Deploy key algorithm (IMPLEMENTATION)
test_deploy_key_algorithm() {
    info "Test 6: Verify deploy key uses ed25519 algorithm"

    # IMPLEMENTATION VERIFICATION: Confirm ed25519 algorithm
    if ! grep -q "ssh-keygen -t ed25519" "$PLAYBOOK_PATH"; then
        fail "Deploy key does not use ed25519 algorithm"
        return 1
    fi

    pass "Deploy key uses ed25519 algorithm (modern, secure)"
}

# Test 7: Validate script dependencies exist
test_dependencies_exist() {
    info "Test 7: Verify required scripts and files exist"

    if [ ! -x "$PROVISION_SCRIPT" ]; then
        fail "provision-vm.sh not found or not executable"
        return 1
    fi

    if [ ! -f "$PLAYBOOK_PATH" ]; then
        fail "ansible/playbook.yml not found"
        return 1
    fi

    pass "Required scripts and files exist"
}

# Main test execution
main() {
    echo "========================================"
    echo "Deploy Key Security Tests (Issue #49)"
    echo "CVE-2024-ANSIBLE-001: SSH Key Credential Proliferation"
    echo "Refactored: Behavior tests (Issue #63)"
    echo "========================================"
    echo ""

    # Run all tests (continue on failure to see all results)
    test_dependencies_exist || true
    test_no_ssh_key_copy || true
    test_deploy_key_generation || true
    test_deploy_key_instructions || true
    test_deploy_key_permissions || true
    test_deploy_key_identifier || true
    test_deploy_key_algorithm || true

    echo ""
    echo "========================================"
    echo "Test Results:"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo "========================================"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}TESTS FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}ALL TESTS PASSED${NC}"
        exit 0
    fi
}

main "$@"
