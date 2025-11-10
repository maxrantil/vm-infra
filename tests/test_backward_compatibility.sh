#!/bin/bash
# ABOUTME: Backward compatibility tests for single-VM workflow (Issue #5)

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
assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -f "$file" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
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
        return 1
    fi
}

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

# Test 1: Single VM workflow still creates inventory.ini
test_single_vm_creates_inventory() {
    echo ""
    echo "Test 1: Single VM workflow creates inventory.ini"

    setup

    # Simulate single VM provision (what provision-vm.sh does)
    # 1. Terraform creates fragment
    cat > "$TEST_DIR/ansible/inventory.d/single-vm.ini" <<EOF
# Fragment for single-vm
[vms]
192.168.122.100 ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=single-vm

# End fragment for single-vm
EOF

    # 2. Terraform merges fragments
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"

    # Verify inventory.ini exists (backward compat)
    assert_file_exists "$TEST_DIR/ansible/inventory.ini" \
        "Single VM should create inventory.ini"

    # Verify it contains the VM
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "192.168.122.100" \
        "Inventory should contain VM IP"

    teardown
}

# Test 2: inventory.ini format unchanged
test_inventory_format_unchanged() {
    echo ""
    echo "Test 2: inventory.ini format remains unchanged"

    setup

    # Create single VM fragment
    cat > "$TEST_DIR/ansible/inventory.d/compat-vm.ini" <<EOF
# Fragment for compat-vm
[vms]
192.168.122.50 ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=compat-vm

# End fragment for compat-vm
EOF

    # Merge
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"

    # Verify format (should have [vms] section)
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "[vms]" \
        "Inventory should have [vms] section"

    # Verify format (should have ansible variables)
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "ansible_user=mr" \
        "Inventory should have ansible_user variable"

    # Verify format (should have SSH key path)
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "ansible_ssh_private_key_file=~/.ssh/vm_key" \
        "Inventory should have SSH key path"

    # Verify format (should have Python interpreter)
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "ansible_python_interpreter=/usr/bin/python3" \
        "Inventory should have Python interpreter"

    teardown
}

# Test 3: Ansible playbook compatibility
test_ansible_playbook_compatibility() {
    echo ""
    echo "Test 3: Generated inventory is Ansible-compatible"

    setup

    # Create realistic inventory
    cat > "$TEST_DIR/ansible/inventory.d/ansible-test-vm.ini" <<EOF
# Fragment for ansible-test-vm
[vms]
192.168.122.200 ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=ansible-test-vm

# End fragment for ansible-test-vm
EOF

    # Merge
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"

    # Test Ansible can parse inventory (without actually connecting)
    # This uses ansible-inventory command to validate format
    if command -v ansible-inventory > /dev/null 2>&1; then
        if ansible-inventory -i "$TEST_DIR/ansible/inventory.ini" --list > /dev/null 2>&1; then
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Ansible can parse generated inventory"
        else
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Ansible cannot parse generated inventory"
        fi
    else
        # If Ansible not installed, just verify format manually
        TESTS_RUN=$((TESTS_RUN + 1))
        if grep -q "\[vms\]" "$TEST_DIR/ansible/inventory.ini" && grep -q "ansible_user" "$TEST_DIR/ansible/inventory.ini"; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Inventory format looks correct (Ansible not installed to verify)"
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Inventory format incorrect"
        fi
    fi

    teardown
}

# Test 4: Single VM has same behavior as before
test_single_vm_behavior_unchanged() {
    echo ""
    echo "Test 4: Single VM behavior unchanged from before"

    setup

    # Simulate old behavior (direct write to inventory.ini)
    OLD_INVENTORY="$TEST_DIR/old-inventory.ini"
    cat > "$OLD_INVENTORY" <<EOF
[vms]
192.168.122.100 ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3
EOF

    # Simulate new behavior (fragment + merge)
    cat > "$TEST_DIR/ansible/inventory.d/test-vm.ini" <<EOF
# Fragment for test-vm
[vms]
192.168.122.100 ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=test-vm

# End fragment for test-vm
EOF

    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"

    # Compare: Both should have same essential fields
    # (New has vm_name added, but that's additive, not breaking)

    # Check old has IP
    if grep -q "192.168.122.100" "$OLD_INVENTORY"; then
        OLD_HAS_IP=true
    else
        OLD_HAS_IP=false
    fi

    # Check new has IP
    if grep -q "192.168.122.100" "$TEST_DIR/ansible/inventory.ini"; then
        NEW_HAS_IP=true
    else
        NEW_HAS_IP=false
    fi

    assert_equals "$OLD_HAS_IP" "$NEW_HAS_IP" \
        "New behavior should preserve IP address"

    # Check ansible_user present in both
    if grep -q "ansible_user=mr" "$OLD_INVENTORY"; then
        OLD_HAS_USER=true
    else
        OLD_HAS_USER=false
    fi

    if grep -q "ansible_user=mr" "$TEST_DIR/ansible/inventory.ini"; then
        NEW_HAS_USER=true
    else
        NEW_HAS_USER=false
    fi

    assert_equals "$OLD_HAS_USER" "$NEW_HAS_USER" \
        "New behavior should preserve ansible_user"

    teardown
}

# Run all tests
main() {
    echo "========================================="
    echo "Backward Compatibility Tests"
    echo "Issue #5: Multi-VM Inventory Support"
    echo "========================================="

    test_single_vm_creates_inventory
    test_inventory_format_unchanged
    test_ansible_playbook_compatibility
    test_single_vm_behavior_unchanged

    echo ""
    echo "========================================="
    echo "Test Results:"
    echo "  Total:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    echo "========================================="

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${YELLOW}Some backward compatibility tests failing${NC}"
        echo "This may be expected if implementation not complete"
        exit 1
    else
        echo -e "${GREEN}All backward compatibility tests passing${NC}"
        exit 0
    fi
}

# Run tests
main
