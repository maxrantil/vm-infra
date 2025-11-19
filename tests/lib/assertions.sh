#!/bin/bash
# ABOUTME: Test assertion library for bash test scripts

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters (exported for test scripts)
export TESTS_RUN=0
export TESTS_PASSED=0
export TESTS_FAILED=0

#####################################
# Assert two values are equal
#
# Arguments:
#   $1 - Expected value
#   $2 - Actual value
#   $3 - Optional failure message
#
# Returns:
#   0 - Assertion passed
#   1 - Assertion failed
#####################################
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    ((TESTS_RUN++))
    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}  ✓${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗${NC} $message"
        echo -e "${RED}    Expected: '$expected'${NC}"
        echo -e "${RED}    Actual:   '$actual'${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

#####################################
# Assert two values are not equal
#
# Arguments:
#   $1 - First value
#   $2 - Second value
#   $3 - Optional failure message
#
# Returns:
#   0 - Assertion passed
#   1 - Assertion failed
#####################################
assert_not_equals() {
    local value1="$1"
    local value2="$2"
    local message="${3:-Values should not be equal}"

    ((TESTS_RUN++))
    if [ "$value1" != "$value2" ]; then
        echo -e "${GREEN}  ✓${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗${NC} $message"
        echo -e "${RED}    Both values: '$value1'${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

#####################################
# Assert value is empty
#
# Arguments:
#   $1 - Value to check
#   $2 - Optional failure message
#
# Returns:
#   0 - Assertion passed
#   1 - Assertion failed
#####################################
assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"

    ((TESTS_RUN++))
    if [ -z "$value" ]; then
        echo -e "${GREEN}  ✓${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗${NC} $message"
        echo -e "${RED}    Value: '$value'${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

#####################################
# Assert value is not empty
#
# Arguments:
#   $1 - Value to check
#   $2 - Optional failure message
#
# Returns:
#   0 - Assertion passed
#   1 - Assertion failed
#####################################
assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"

    ((TESTS_RUN++))
    if [ -n "$value" ]; then
        echo -e "${GREEN}  ✓${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗${NC} $message"
        ((TESTS_FAILED++))
        return 1
    fi
}

#####################################
# Assert exit code is zero
#
# Arguments:
#   $1 - Exit code to check
#   $2 - Optional failure message
#
# Returns:
#   0 - Assertion passed
#   1 - Assertion failed
#####################################
assert_success() {
    local exit_code="$1"
    local message="${2:-Command should succeed (exit 0)}"

    assert_equals 0 "$exit_code" "$message"
}

#####################################
# Assert exit code is non-zero
#
# Arguments:
#   $1 - Exit code to check
#   $2 - Optional failure message
#
# Returns:
#   0 - Assertion passed
#   1 - Assertion failed
#####################################
assert_failure() {
    local exit_code="$1"
    local message="${2:-Command should fail (exit non-zero)}"

    ((TESTS_RUN++))
    if [ "$exit_code" -ne 0 ]; then
        echo -e "${GREEN}  ✓${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗${NC} $message"
        echo -e "${RED}    Exit code: $exit_code (expected non-zero)${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

#####################################
# Test helper: Provision test VM
#
# Arguments:
#   $1 - VM name
#   $2 - Username
#   $3 - Memory (MB)
#   $4 - vCPUs
#
# Returns:
#   0 - Provision succeeded
#   1 - Provision failed
#####################################
provision_test_vm() {
    local vm_name="$1"
    local username="$2"
    local memory="${3:-2048}"
    local vcpus="${4:-1}"

    echo -e "${YELLOW}[TEST] Provisioning VM: $vm_name (user: $username)${NC}"

    # Use --test-dotfiles to use local dotfiles and bypass GitHub deploy key prompt
    # This makes tests fully automated and faster
    # TEMPORARY: Show output for debugging
    if SKIP_WHITELIST_CHECK=1 "$PROJECT_ROOT/provision-vm.sh" \
       "$vm_name" "$username" "$memory" "$vcpus" --test-dotfiles /home/mqx/workspace/dotfiles; then
        echo -e "${GREEN}[TEST] VM provisioned successfully${NC}"
        return 0
    else
        echo -e "${RED}[TEST] VM provisioning failed${NC}"
        return 1
    fi
}

#####################################
# Test helper: Destroy test VM
#
# Arguments:
#   $1 - VM name
#
# Returns:
#   0 - Destroy succeeded
#   1 - Destroy failed
#####################################
destroy_test_vm() {
    local vm_name="$1"

    echo -e "${YELLOW}[TEST] Destroying VM: $vm_name${NC}"

    if echo "y" | "$PROJECT_ROOT/destroy-vm.sh" "$vm_name" > /dev/null 2>&1; then
        echo -e "${GREEN}[TEST] VM destroyed successfully${NC}"
        return 0
    else
        echo -e "${RED}[TEST] VM destruction failed${NC}"
        return 1
    fi
}

#####################################
# Print test summary
#
# Returns:
#   0 - All tests passed
#   1 - Some tests failed
#####################################
print_test_summary() {
    echo ""
    echo "========================================="
    echo "Test Summary"
    echo "========================================="
    echo "Total:  $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo "========================================="

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ $TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

# Export functions for use in test scripts
export -f assert_equals
export -f assert_not_equals
export -f assert_empty
export -f assert_not_empty
export -f assert_success
export -f assert_failure
export -f provision_test_vm
export -f destroy_test_vm
export -f print_test_summary
