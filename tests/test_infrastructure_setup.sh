#!/usr/bin/env bash
# ABOUTME: Test suite for test infrastructure setup and validation

set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup_test_environment.sh"

# Test helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((++TESTS_PASSED))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    echo -e "  ${RED}Expected:${NC} $2"
    echo -e "  ${RED}Got:${NC} $3"
    ((++TESTS_FAILED))
}

test_start() {
    ((++TESTS_RUN))
    echo -e "\n${YELLOW}Test $TESTS_RUN:${NC} $1"
}

# Test 1: Setup script exists and is executable
test_setup_script_exists() {
    test_start "Setup script exists and is executable"

    if [[ -f "$SETUP_SCRIPT" ]]; then
        if [[ -x "$SETUP_SCRIPT" ]]; then
            pass "setup_test_environment.sh exists and is executable"
        else
            fail "setup_test_environment.sh should be executable" "chmod +x" "not executable"
        fi
    else
        fail "setup_test_environment.sh should exist" "$SETUP_SCRIPT" "file not found"
    fi
}

# Test 2: Setup script has required functions
test_setup_script_has_functions() {
    test_start "Setup script has required validation functions"

    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        fail "Cannot test functions" "$SETUP_SCRIPT exists" "file not found"
        return
    fi

    local required_functions=(
        "check_libvirt"
        "check_disk_space"
        "install_test_dependencies"
        "validate_ssh_keys"
    )

    local missing_functions=()
    for func in "${required_functions[@]}"; do
        if ! grep -q "^${func}()" "$SETUP_SCRIPT" && ! grep -q "^function ${func}" "$SETUP_SCRIPT"; then
            missing_functions+=("$func")
        fi
    done

    if [[ ${#missing_functions[@]} -eq 0 ]]; then
        pass "All required functions present: ${required_functions[*]}"
    else
        fail "Missing required functions" "${required_functions[*]}" "missing: ${missing_functions[*]}"
    fi
}

# Test 3: Setup script validates libvirt/KVM
test_setup_validates_libvirt() {
    test_start "Setup script validates libvirt/KVM availability"

    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        fail "Cannot test libvirt check" "$SETUP_SCRIPT exists" "file not found"
        return
    fi

    if grep -q "virsh" "$SETUP_SCRIPT" && grep -q "libvirtd" "$SETUP_SCRIPT"; then
        pass "Libvirt/KVM validation logic present"
    else
        fail "Should check libvirt/KVM" "virsh and libvirtd checks" "checks missing"
    fi
}

# Test 4: Setup script validates disk space
test_setup_validates_disk_space() {
    test_start "Setup script validates sufficient disk space"

    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        fail "Cannot test disk space check" "$SETUP_SCRIPT exists" "file not found"
        return
    fi

    if grep -q "df" "$SETUP_SCRIPT" || grep -q "disk" "$SETUP_SCRIPT"; then
        pass "Disk space validation logic present"
    else
        fail "Should check disk space" "df or disk check" "checks missing"
    fi
}

# Test 5: Setup script validates SSH keys
test_setup_validates_ssh_keys() {
    test_start "Setup script validates SSH keys exist"

    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        fail "Cannot test SSH key check" "$SETUP_SCRIPT exists" "file not found"
        return
    fi

    if grep -q "vm_key" "$SETUP_SCRIPT" || grep -q "\.ssh" "$SETUP_SCRIPT"; then
        pass "SSH key validation logic present"
    else
        fail "Should check SSH keys" "\$HOME/.ssh/vm_key check" "checks missing"
    fi
}

# Test 6: Setup script can be run with --check flag
test_setup_check_mode() {
    test_start "Setup script supports --check flag for dry-run"

    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        fail "Cannot test --check flag" "$SETUP_SCRIPT exists" "file not found"
        return
    fi

    if grep -q "\-\-check" "$SETUP_SCRIPT" || grep -q "check_only" "$SETUP_SCRIPT"; then
        pass "Check/dry-run mode supported"
    else
        fail "Should support --check flag" "--check or check_only flag" "flag support missing"
    fi
}

# Test 7: Cleanup library exists
test_cleanup_library_exists() {
    test_start "Cleanup library exists at tests/lib/cleanup.sh"

    local cleanup_lib="$SCRIPT_DIR/lib/cleanup.sh"

    if [[ -f "$cleanup_lib" ]]; then
        if [[ -r "$cleanup_lib" ]]; then
            pass "Cleanup library exists and is readable"
        else
            fail "Cleanup library should be readable" "chmod +r" "not readable"
        fi
    else
        fail "Cleanup library should exist" "$cleanup_lib" "file not found"
    fi
}

# Test 8: Cleanup library has required functions
test_cleanup_library_has_functions() {
    test_start "Cleanup library has required cleanup functions"

    local cleanup_lib="$SCRIPT_DIR/lib/cleanup.sh"

    if [[ ! -f "$cleanup_lib" ]]; then
        fail "Cannot test cleanup functions" "$cleanup_lib exists" "file not found"
        return
    fi

    local required_functions=(
        "cleanup_test_vm"
        "cleanup_test_artifacts"
        "register_cleanup_on_exit"
    )

    local missing_functions=()
    for func in "${required_functions[@]}"; do
        if ! grep -q "^${func}()" "$cleanup_lib" && ! grep -q "^function ${func}" "$cleanup_lib"; then
            missing_functions+=("$func")
        fi
    done

    if [[ ${#missing_functions[@]} -eq 0 ]]; then
        pass "All required cleanup functions present: ${required_functions[*]}"
    else
        fail "Missing required cleanup functions" "${required_functions[*]}" "missing: ${missing_functions[*]}"
    fi
}

# Run all tests
main() {
    echo "=========================================="
    echo "Test Infrastructure Validation Tests"
    echo "=========================================="

    test_setup_script_exists
    test_setup_script_has_functions
    test_setup_validates_libvirt
    test_setup_validates_disk_space
    test_setup_validates_ssh_keys
    test_setup_check_mode
    test_cleanup_library_exists
    test_cleanup_library_has_functions

    # Print summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo -e "Total tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        exit 1
    fi
}

main "$@"
