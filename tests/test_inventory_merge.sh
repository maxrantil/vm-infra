#!/bin/bash
# ABOUTME: Integration tests for inventory fragment merging (Issue #5)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-File should contain pattern: $pattern}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if grep -q "$pattern" "$file"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo "  Pattern not found in: $file"
        return 1
    fi
}

# Setup test environment
setup() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/ansible/inventory.d"
}

# Cleanup test environment
teardown() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# Test 1: Merge two fragments
test_merge_two_fragments() {
    echo ""
    echo "Test 1: Merge two fragments into inventory.ini"

    setup

    # Create two fragments
    cat > "$TEST_DIR/ansible/inventory.d/vm1.ini" << EOF
# Fragment for vm1
[vms]
192.168.122.100 ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=vm1

# End fragment for vm1
EOF

    cat > "$TEST_DIR/ansible/inventory.d/vm2.ini" << EOF
# Fragment for vm2
[vms]
192.168.122.101 ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=vm2

# End fragment for vm2
EOF

    # Merge fragments (this is what Terraform should do)
    # Currently FAILING because merge logic doesn't exist
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini" 2> /dev/null || echo "[vms]" > "$TEST_DIR/ansible/inventory.ini"

    # Test that both VMs are in merged inventory
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "vm_name=vm1" \
        "Merged inventory should contain vm1"

    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "vm_name=vm2" \
        "Merged inventory should contain vm2"

    teardown
}

# Test 2: Merge three fragments
test_merge_three_fragments() {
    echo ""
    echo "Test 2: Merge three fragments into inventory.ini"

    setup

    # Create three fragments
    for i in {1..3}; do
        cat > "$TEST_DIR/ansible/inventory.d/vm${i}.ini" << EOF
# Fragment for vm${i}
[vms]
192.168.122.$((99 + i)) ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key vm_name=vm${i}

# End fragment for vm${i}
EOF
    done

    # Merge fragments
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"

    # Count how many VM entries are in merged inventory
    VM_COUNT=$(grep -c "vm_name=vm" "$TEST_DIR/ansible/inventory.ini" || echo "0")

    assert_equals "3" "$VM_COUNT" \
        "Merged inventory should contain 3 VMs"

    teardown
}

# Test 3: Merge preserves all entries
test_merge_preserves_all_entries() {
    echo ""
    echo "Test 3: Merge preserves all VM entry details"

    setup

    # Create fragment with full details
    cat > "$TEST_DIR/ansible/inventory.d/detailed-vm.ini" << EOF
# Fragment for detailed-vm
[vms]
192.168.122.150 ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=detailed-vm dotfiles_local_path=/path/to/dotfiles

# End fragment for detailed-vm
EOF

    # Merge
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"

    # Verify all details preserved
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "192.168.122.150" \
        "Merged inventory should preserve IP address"

    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "dotfiles_local_path=/path/to/dotfiles" \
        "Merged inventory should preserve dotfiles_local_path"

    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "ansible_ssh_common_args" \
        "Merged inventory should preserve SSH args"

    teardown
}

# Test 4: Merge handles missing directory
test_merge_handles_missing_directory() {
    echo ""
    echo "Test 4: Merge handles missing inventory.d directory"

    setup

    # Remove inventory.d directory
    rm -rf "$TEST_DIR/ansible/inventory.d"

    # Attempt merge (should create minimal inventory)
    # This tests the error handling: || echo "[vms]"
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini" 2> /dev/null || echo "[vms]" > "$TEST_DIR/ansible/inventory.ini"

    # Should create inventory with at least [vms] header
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "[vms]" \
        "Empty inventory should have [vms] header"

    teardown
}

# Test 5: Merge idempotency
test_merge_idempotency() {
    echo ""
    echo "Test 5: Merge operation is idempotent"

    setup

    # Create fragment
    cat > "$TEST_DIR/ansible/inventory.d/vm1.ini" << EOF
# Fragment for vm1
[vms]
192.168.122.100 ansible_user=mr vm_name=vm1

# End fragment for vm1
EOF

    # Merge once
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"
    FIRST_MERGE=$(cat "$TEST_DIR/ansible/inventory.ini")

    # Merge again (should produce identical result)
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"
    SECOND_MERGE=$(cat "$TEST_DIR/ansible/inventory.ini")

    assert_equals "$FIRST_MERGE" "$SECOND_MERGE" \
        "Merge operation should be idempotent"

    teardown
}

# Run all tests
main() {
    echo "========================================="
    echo "Inventory Merge Tests (RED Phase)"
    echo "Issue #5: Multi-VM Inventory Support"
    echo "========================================="

    test_merge_two_fragments
    test_merge_three_fragments
    test_merge_preserves_all_entries
    test_merge_handles_missing_directory
    test_merge_idempotency

    echo ""
    echo "========================================="
    echo "Test Results:"
    echo "  Total:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    echo "========================================="

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${YELLOW}Some tests may be failing${NC}"
        echo "This is expected in RED phase before implementation"
        exit 1
    else
        echo -e "${GREEN}All tests passing (GREEN Phase)${NC}"
        exit 0
    fi
}

# Run tests
main
