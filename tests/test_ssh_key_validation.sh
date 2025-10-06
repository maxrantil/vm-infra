#!/bin/bash
# ABOUTME: Tests for SSH key security validation in provision-vm.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Inline validation functions for testing (copied from provision-vm.sh)
validate_ssh_directory_permissions() {
    local ssh_dir="$HOME/.ssh"
    local ssh_dir_perms
    ssh_dir_perms=$(stat -c "%a" "$ssh_dir" 2>/dev/null || echo "")

    if [ -z "$ssh_dir_perms" ]; then
        return 1
    fi

    if [ "$ssh_dir_perms" != "700" ]; then
        chmod 700 "$ssh_dir" 2>/dev/null || return 1
        echo "fixed"
        return 0
    fi
    return 0
}

validate_private_key_permissions() {
    local key_path="$1"
    local key_perms
    key_perms=$(stat -c "%a" "$key_path" 2>/dev/null || echo "")

    if [ "$key_perms" != "600" ] && [ "$key_perms" != "400" ]; then
        return 1
    fi
    return 0
}

validate_key_content() {
    local key_path="$1"

    if ! ssh-keygen -l -f "$key_path" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

validate_public_key_exists() {
    local key_path="$1"
    local pub_key_path="${key_path}.pub"

    if [ ! -f "$pub_key_path" ]; then
        return 1
    fi
    return 0
}

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Setup test environment
setup_test_env() {
    TEST_SSH_DIR=$(mktemp -d)
    export HOME_BACKUP="$HOME"
    local parent_dir
    parent_dir="$(dirname "$TEST_SSH_DIR")"
    export HOME="$parent_dir"
    mkdir -p "$TEST_SSH_DIR"
    mv "$TEST_SSH_DIR" "$HOME/.ssh"
    TEST_SSH_DIR="$HOME/.ssh"
}

# Teardown test environment
teardown_test_env() {
    if [ -d "$TEST_SSH_DIR" ]; then
        rm -rf "$TEST_SSH_DIR"
    fi
    export HOME="$HOME_BACKUP"
}

# Test: SSH directory permissions validation
test_ssh_dir_permissions() {
    setup_test_env

    # Create SSH directory with wrong permissions
    chmod 755 "$TEST_SSH_DIR"

    # Test validation function
    local result
    local final_perms
    result=$(validate_ssh_directory_permissions 2>&1)
    final_perms=$(stat -c "%a" "$TEST_SSH_DIR")

    test_result "SSH directory with 755 permissions should be fixed to 700" "700" "$final_perms"

    teardown_test_env
}

# Test: Private key permission validation (600)
test_private_key_permissions_600() {
    setup_test_env

    # Create a test key with wrong permissions
    ssh-keygen -t ed25519 -f "$TEST_SSH_DIR/vm_key" -N "" -C "test" >/dev/null 2>&1
    chmod 644 "$TEST_SSH_DIR/vm_key"

    # Test validation function
    validate_private_key_permissions "$TEST_SSH_DIR/vm_key" 2>&1 && result="passed" || result="failed"
    test_result "Private key with 644 permissions should fail validation" "failed" "$result"

    teardown_test_env
}

# Test: Private key permission validation (400)
test_private_key_permissions_400() {
    setup_test_env

    # Create a test key with correct permissions (400)
    ssh-keygen -t ed25519 -f "$TEST_SSH_DIR/vm_key" -N "" -C "test" >/dev/null 2>&1
    chmod 400 "$TEST_SSH_DIR/vm_key"

    # Test validation function
    validate_private_key_permissions "$TEST_SSH_DIR/vm_key" 2>&1 && result="passed" || result="failed"
    test_result "Private key with 400 permissions should pass validation" "passed" "$result"

    teardown_test_env
}

# Test: Key content validation with ssh-keygen
test_key_content_validation() {
    setup_test_env

    # Create an invalid key file
    echo "not-a-real-ssh-key" > "$TEST_SSH_DIR/vm_key"
    chmod 600 "$TEST_SSH_DIR/vm_key"

    # Test validation function
    validate_key_content "$TEST_SSH_DIR/vm_key" 2>&1 && result="passed" || result="failed"
    test_result "Invalid key content should fail validation" "failed" "$result"

    teardown_test_env
}

# Test: Valid key content passes validation
test_valid_key_content() {
    setup_test_env

    # Create a valid key
    ssh-keygen -t ed25519 -f "$TEST_SSH_DIR/vm_key" -N "" -C "test" >/dev/null 2>&1
    chmod 600 "$TEST_SSH_DIR/vm_key"

    # Test validation function
    validate_key_content "$TEST_SSH_DIR/vm_key" 2>&1 && result="passed" || result="failed"
    test_result "Valid key content should pass validation" "passed" "$result"

    teardown_test_env
}

# Test: Public key existence check
test_public_key_exists() {
    setup_test_env

    # Create private key but delete public key
    ssh-keygen -t ed25519 -f "$TEST_SSH_DIR/vm_key" -N "" -C "test" >/dev/null 2>&1
    rm -f "$TEST_SSH_DIR/vm_key.pub"
    chmod 600 "$TEST_SSH_DIR/vm_key"

    # Test validation function
    validate_public_key_exists "$TEST_SSH_DIR/vm_key" 2>&1 && result="passed" || result="failed"
    test_result "Missing public key should fail validation" "failed" "$result"

    teardown_test_env
}

# Test: Public key exists with private key
test_public_key_present() {
    setup_test_env

    # Create complete keypair
    ssh-keygen -t ed25519 -f "$TEST_SSH_DIR/vm_key" -N "" -C "test" >/dev/null 2>&1
    chmod 600 "$TEST_SSH_DIR/vm_key"

    # Test validation function
    validate_public_key_exists "$TEST_SSH_DIR/vm_key" 2>&1 && result="passed" || result="failed"
    test_result "Present public key should pass validation" "passed" "$result"

    teardown_test_env
}

# Run all tests
main() {
    echo "========================================"
    echo "SSH Key Security Validation Tests"
    echo "========================================"
    echo ""

    test_ssh_dir_permissions
    test_private_key_permissions_600
    test_private_key_permissions_400
    test_key_content_validation
    test_valid_key_content
    test_public_key_exists
    test_public_key_present

    echo ""
    echo "========================================"
    echo "Test Results"
    echo "========================================"
    echo "Tests run: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}

# Run tests if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
