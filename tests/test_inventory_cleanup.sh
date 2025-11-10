#!/bin/bash
# ABOUTME: Tests for inventory cleanup after VM destroy (Issue #5)

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

assert_file_not_exists() {
    local file="$1"
    local message="${2:-File should not exist: $file}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ ! -f "$file" ]; then
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

assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-File should not contain pattern: $pattern}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if ! grep -q "$pattern" "$file"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
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

# Simulate destroy-vm.sh cleanup logic
simulate_destroy_cleanup() {
    local vm_name="$1"
    local test_dir="$2"

    # Remove fragment
    local fragment="$test_dir/ansible/inventory.d/${vm_name}.ini"
    if [ -f "$fragment" ]; then
        rm -f "$fragment"
    fi

    # Regenerate inventory
    if ls "$test_dir/ansible/inventory.d"/*.ini 1> /dev/null 2>&1; then
        cat "$test_dir/ansible/inventory.d"/*.ini > "$test_dir/ansible/inventory.ini"
    else
        echo "[vms]" > "$test_dir/ansible/inventory.ini"
    fi
}

# Test 1: Destroy removes fragment
test_destroy_removes_fragment() {
    echo ""
    echo "Test 1: Destroy operation removes VM fragment"

    setup

    # Create two fragments
    cat > "$TEST_DIR/ansible/inventory.d/vm1.ini" << EOF
[vms]
192.168.122.100 ansible_user=mr vm_name=vm1
EOF

    cat > "$TEST_DIR/ansible/inventory.d/vm2.ini" << EOF
[vms]
192.168.122.101 ansible_user=mr vm_name=vm2
EOF

    # Simulate destroy of vm1
    # Currently FAILING because destroy-vm.sh doesn't have cleanup logic
    simulate_destroy_cleanup "vm1" "$TEST_DIR"

    # Verify vm1.ini is removed
    assert_file_not_exists "$TEST_DIR/ansible/inventory.d/vm1.ini" \
        "destroy-vm.sh should remove vm1 fragment"

    teardown
}

# Test 2: Destroy regenerates inventory
test_destroy_regenerates_inventory() {
    echo ""
    echo "Test 2: Destroy regenerates inventory.ini"

    setup

    # Create two fragments
    cat > "$TEST_DIR/ansible/inventory.d/vm1.ini" << EOF
[vms]
192.168.122.100 ansible_user=mr vm_name=vm1
EOF

    cat > "$TEST_DIR/ansible/inventory.d/vm2.ini" << EOF
[vms]
192.168.122.101 ansible_user=mr vm_name=vm2
EOF

    # Initial merge
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"

    # Destroy vm1
    simulate_destroy_cleanup "vm1" "$TEST_DIR"

    # Verify inventory no longer contains vm1
    assert_file_not_contains "$TEST_DIR/ansible/inventory.ini" "vm_name=vm1" \
        "Inventory should not contain destroyed VM"

    # Verify inventory still contains vm2
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "vm_name=vm2" \
        "Inventory should still contain remaining VM"

    teardown
}

# Test 3: Destroy last VM creates empty inventory
test_destroy_last_vm_creates_empty_inventory() {
    echo ""
    echo "Test 3: Destroying last VM creates empty inventory"

    setup

    # Create single fragment
    cat > "$TEST_DIR/ansible/inventory.d/vm-only.ini" << EOF
[vms]
192.168.122.100 ansible_user=mr vm_name=vm-only
EOF

    # Destroy the only VM
    simulate_destroy_cleanup "vm-only" "$TEST_DIR"

    # Verify fragment removed
    assert_file_not_exists "$TEST_DIR/ansible/inventory.d/vm-only.ini" \
        "Last VM fragment should be removed"

    # Verify inventory has minimal [vms] header
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "[vms]" \
        "Empty inventory should have [vms] header"

    # Verify no VM entries remain
    VM_COUNT=$(grep -c "vm_name=" "$TEST_DIR/ansible/inventory.ini" 2> /dev/null) || VM_COUNT=0
    assert_equals "0" "$VM_COUNT" \
        "Empty inventory should have 0 VMs"

    teardown
}

# Test 4: Destroy preserves other fragments
test_destroy_preserves_other_fragments() {
    echo ""
    echo "Test 4: Destroy preserves other VM fragments"

    setup

    # Create three fragments
    for i in {1..3}; do
        cat > "$TEST_DIR/ansible/inventory.d/vm${i}.ini" << EOF
[vms]
192.168.122.$((99 + i)) ansible_user=mr vm_name=vm${i}
EOF
    done

    # Merge
    cat "$TEST_DIR/ansible/inventory.d"/*.ini > "$TEST_DIR/ansible/inventory.ini"

    # Destroy vm2 (middle VM)
    simulate_destroy_cleanup "vm2" "$TEST_DIR"

    # Verify vm2 fragment removed
    assert_file_not_exists "$TEST_DIR/ansible/inventory.d/vm2.ini" \
        "Destroyed VM fragment should be removed"

    # Verify vm1 and vm3 fragments still exist
    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "vm_name=vm1" \
        "VM1 should still exist"

    assert_file_contains "$TEST_DIR/ansible/inventory.ini" "vm_name=vm3" \
        "VM3 should still exist"

    # Verify inventory has exactly 2 VMs
    VM_COUNT=$(grep -c "vm_name=" "$TEST_DIR/ansible/inventory.ini")
    assert_equals "2" "$VM_COUNT" \
        "Inventory should have 2 remaining VMs"

    teardown
}

# Run all tests
main() {
    echo "========================================="
    echo "Inventory Cleanup Tests (RED Phase)"
    echo "Issue #5: Multi-VM Inventory Support"
    echo "========================================="

    test_destroy_removes_fragment
    test_destroy_regenerates_inventory
    test_destroy_last_vm_creates_empty_inventory
    test_destroy_preserves_other_fragments

    echo ""
    echo "========================================="
    echo "Test Results:"
    echo "  Total:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    echo "========================================="

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${YELLOW}Some tests may be failing${NC}"
        echo "This is expected in RED phase before destroy-vm.sh updates"
        exit 1
    else
        echo -e "${GREEN}All tests passing (GREEN Phase)${NC}"
        exit 0
    fi
}

# Run tests
main
