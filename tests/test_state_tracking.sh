#!/usr/bin/env bash
# ABOUTME: Integration test for playbook state tracking and rollback functionality

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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAYBOOK_PATH="$PROJECT_ROOT/ansible/playbook.yml"

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

# Test 1: Playbook registers package installation result
test_playbook_registers_package_result() {
    test_start "Playbook registers package installation result"

    # Check if "Install core packages" task has register directive
    if grep -A 50 "name: Install core packages" "$PLAYBOOK_PATH" | grep -q "register:.*package"; then
        pass "Package installation task has register directive"
    else
        fail "Package installation should register result" "register: package_install_result or similar" "no register directive found"
    fi
}

# Test 2: Playbook registers dotfiles clone result
test_playbook_registers_dotfiles_result() {
    test_start "Playbook registers dotfiles clone result"

    # Check if "Clone dotfiles repository" task has register directive
    if grep -A 10 "name: Clone dotfiles repository" "$PLAYBOOK_PATH" | grep -q "register:.*dotfiles"; then
        pass "Dotfiles clone task has register directive"
    else
        fail "Dotfiles clone should register result" "register: dotfiles_clone_result or similar" "no register directive found"
    fi
}

# Test 3: Rescue block uses registered package result
test_rescue_uses_package_result() {
    test_start "Rescue block checks package installation result"

    # Check if rescue block conditionals use registered result
    # Look for when: package_install_result or similar in rescue block
    if sed -n '/rescue:/,/always:/p' "$PLAYBOOK_PATH" | grep -q "when:.*package.*result"; then
        pass "Rescue block uses package installation result"
    else
        fail "Rescue should check package result" "when: package_install_result is failed" "uses undefined variable or no check"
    fi
}

# Test 4: Rescue block uses registered dotfiles result
test_rescue_uses_dotfiles_result() {
    test_start "Rescue block checks dotfiles clone result"

    # Check if rescue block conditionals use registered result
    if sed -n '/rescue:/,/always:/p' "$PLAYBOOK_PATH" | grep -q "when:.*dotfiles.*result"; then
        pass "Rescue block uses dotfiles clone result"
    else
        fail "Rescue should check dotfiles result" "when: dotfiles_clone_result is defined" "uses undefined variable or no check"
    fi
}

# Test 5: Rescue cleanup conditional is functional
test_rescue_conditional_is_functional() {
    test_start "Rescue block conditionals reference defined variables"

    local rescue_section
    rescue_section=$(sed -n '/rescue:/,/always:/p' "$PLAYBOOK_PATH")

    # Check for common anti-patterns that make conditionals non-functional
    local issues_found=0

    # Anti-pattern 1: Using undefined variables like failed_packages
    if echo "$rescue_section" | grep -q "failed_packages.*default"; then
        echo -e "  ${RED}Issue: Uses undefined 'failed_packages' variable${NC}"
        ((++issues_found))
    fi

    # Anti-pattern 2: Using undefined dotfiles_cloned
    if echo "$rescue_section" | grep -q "dotfiles_cloned.*default.*false"; then
        echo -e "  ${RED}Issue: Uses undefined 'dotfiles_cloned' variable${NC}"
        ((++issues_found))
    fi

    # Anti-pattern 3: when: condition on undefined variable
    if echo "$rescue_section" | grep "when:" | grep -qE "(failed_packages|dotfiles_cloned)"; then
        if ! echo "$rescue_section" | grep -q "register:"; then
            echo -e "  ${RED}Issue: Conditionals use variables never registered${NC}"
            ((++issues_found))
        fi
    fi

    if [[ $issues_found -eq 0 ]]; then
        pass "Rescue conditionals reference defined/registered variables"
    else
        fail "Rescue conditionals should use registered variables" "variables from register: directives" "$issues_found undefined variable(s) used"
    fi
}

# Test 6: State tracking enables actual cleanup
test_state_tracking_enables_cleanup() {
    test_start "State tracking enables functional rollback cleanup"

    # For cleanup to work, we need:
    # 1. register: directives on main tasks
    # 2. when: conditionals in rescue that reference registered results
    # 3. No reliance on undefined variables

    local has_package_register=false
    local has_dotfiles_register=false
    local rescue_uses_results=false

    # Check main tasks have register
    if grep -A 50 "name: Install core packages" "$PLAYBOOK_PATH" | grep -q "register:"; then
        has_package_register=true
    fi

    if grep -A 10 "name: Clone dotfiles repository" "$PLAYBOOK_PATH" | grep -q "register:"; then
        has_dotfiles_register=true
    fi

    # Check rescue uses registered results
    local rescue_section
    rescue_section=$(sed -n '/rescue:/,/always:/p' "$PLAYBOOK_PATH")

    if echo "$rescue_section" | grep "when:" | grep -qE "(.*_result|.*_install|.*_clone)"; then
        rescue_uses_results=true
    fi

    if [[ "$has_package_register" == "true" && "$has_dotfiles_register" == "true" && "$rescue_uses_results" == "true" ]]; then
        pass "State tracking complete: register + conditional rescue"
    else
        fail "State tracking incomplete" "register directives + rescue conditionals using results" \
            "package_register=$has_package_register, dotfiles_register=$has_dotfiles_register, rescue_uses=$rescue_uses_results"
    fi
}

# Run all tests
main() {
    echo "=========================================="
    echo "State Tracking Integration Tests"
    echo "=========================================="
    echo ""
    echo "Testing playbook: $PLAYBOOK_PATH"

    test_playbook_registers_package_result
    test_playbook_registers_dotfiles_result
    test_rescue_uses_package_result
    test_rescue_uses_dotfiles_result
    test_rescue_conditional_is_functional
    test_state_tracking_enables_cleanup

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
        echo -e "${GREEN}Playbook state tracking is functional.${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        echo -e "${YELLOW}Playbook needs register: directives for state tracking.${NC}"
        exit 1
    fi
}

main "$@"
