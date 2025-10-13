#!/usr/bin/env bash
# ABOUTME: Test script for VM-specific deploy key generation (Issue #49 - CVE-2024-ANSIBLE-001)

set -euo pipefail

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

# Test 1: Playbook should NOT contain SSH key copy tasks
test_no_ssh_key_copy() {
    info "Test 1: Verify playbook does not copy SSH private keys from host"

    if grep -q "Copy GitHub SSH private key to VM" ansible/playbook.yml; then
        fail "Playbook still contains 'Copy GitHub SSH private key to VM' task (SECURITY VULNERABILITY)"
        return 1
    fi

    if grep -q "src: ~/.ssh/id_ed25519" ansible/playbook.yml; then
        fail "Playbook still references ~/.ssh/id_ed25519 (host SSH key should not be copied)"
        return 1
    fi

    pass "Playbook does not copy host SSH keys"
}

# Test 2: Playbook should contain deploy key generation task
test_deploy_key_generation() {
    info "Test 2: Verify playbook generates VM-specific deploy keys"

    if ! grep -q "Generate VM-specific deploy key" ansible/playbook.yml; then
        fail "Playbook missing 'Generate VM-specific deploy key' task"
        return 1
    fi

    if ! grep -q "ssh-keygen.*vm-deploy" ansible/playbook.yml; then
        fail "Playbook missing ssh-keygen command for deploy key generation"
        return 1
    fi

    pass "Playbook generates VM-specific deploy keys"
}

# Test 3: Playbook should display deploy key instructions
test_deploy_key_instructions() {
    info "Test 3: Verify playbook displays manual setup instructions"

    if ! grep -q "Deploy key setup instructions" ansible/playbook.yml; then
        fail "Playbook missing deploy key setup instructions"
        return 1
    fi

    if ! grep -q "MANUAL STEP REQUIRED" ansible/playbook.yml; then
        fail "Playbook missing manual step warning"
        return 1
    fi

    pass "Playbook displays deploy key setup instructions"
}

# Test 4: Playbook should set correct permissions on deploy key
test_deploy_key_permissions() {
    info "Test 4: Verify deploy key has correct permissions (0600)"

    if ! grep -A 5 "Set deploy key permissions" ansible/playbook.yml | grep -q "mode.*0600"; then
        fail "Deploy key permissions not set to 0600"
        return 1
    fi

    pass "Deploy key permissions set correctly"
}

# Test 5: Verify deploy key has VM-specific identifier
test_deploy_key_identifier() {
    info "Test 5: Verify deploy key includes VM hostname identifier"

    if ! grep -q "vm-deploy.*ansible_hostname" ansible/playbook.yml; then
        fail "Deploy key does not include VM-specific identifier"
        return 1
    fi

    pass "Deploy key includes VM-specific identifier"
}

# Test 6: Verify deploy key uses ed25519 algorithm
test_deploy_key_algorithm() {
    info "Test 6: Verify deploy key uses ed25519 algorithm"

    if ! grep -q "ssh-keygen -t ed25519" ansible/playbook.yml; then
        fail "Deploy key does not use ed25519 algorithm"
        return 1
    fi

    pass "Deploy key uses ed25519 algorithm"
}

# Main test execution
main() {
    echo "========================================"
    echo "Deploy Key Security Tests (Issue #49)"
    echo "CVE-2024-ANSIBLE-001: SSH Key Credential Proliferation"
    echo "========================================"
    echo ""

    # Run all tests (continue on failure to see all results)
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
