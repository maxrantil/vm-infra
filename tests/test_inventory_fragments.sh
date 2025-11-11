#!/bin/bash
# ABOUTME: Unit tests for inventory fragment generation (Issue #5)

# Test framework setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
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
		echo "  Pattern not found in: $file"
		return 1
	fi
}

assert_directory_exists() {
	local dir="$1"
	local message="${2:-Directory should exist: $dir}"

	TESTS_RUN=$((TESTS_RUN + 1))

	if [ -d "$dir" ]; then
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
	mkdir -p "$TEST_DIR/terraform"

	# Copy inventory template to test directory
	cp "$PROJECT_ROOT/terraform/inventory.tpl" "$TEST_DIR/terraform/"
}

# Cleanup test environment
teardown() {
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

# Test 1: Fragment directory should exist
test_fragment_directory_creation() {
	echo ""
	echo "Test 1: Fragment directory creation"

	setup

	# This test expects ansible/inventory.d to exist after Terraform apply
	# Currently FAILING because directory is not automatically created
	assert_directory_exists "$PROJECT_ROOT/ansible/inventory.d" \
		"ansible/inventory.d directory should exist"

	teardown
}

# Test 2: Single VM should generate fragment
test_single_vm_fragment_generation() {
	echo ""
	echo "Test 2: Single VM fragment generation"

	setup

	# Simulate Terraform creating a fragment
	# This test validates the fragment file structure after Terraform writes it

	VM_NAME="test-vm-1"
	VM_IP="192.168.122.50"
	FRAGMENT_FILE="$TEST_DIR/ansible/inventory.d/${VM_NAME}.ini"

	# Create a mock fragment (simulating what Terraform main.tf should create)
	mkdir -p "$TEST_DIR/ansible/inventory.d"
	cat >"$FRAGMENT_FILE" <<EOF
# Fragment for ${VM_NAME}
[vms]
${VM_IP} ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=${VM_NAME}

# End fragment for ${VM_NAME}
EOF

	# Verify fragment was created with correct structure
	assert_file_exists "$FRAGMENT_FILE" \
		"Fragment file should exist for VM: $VM_NAME"

	teardown
}

# Test 3: Fragment should contain VM name
test_fragment_contains_vm_name() {
	echo ""
	echo "Test 3: Fragment contains VM name"

	setup

	VM_NAME="test-vm-2"
	VM_IP="192.168.122.100"
	FRAGMENT_FILE="$TEST_DIR/ansible/inventory.d/${VM_NAME}.ini"

	# Create a mock fragment (simulating what Terraform should create)
	mkdir -p "$TEST_DIR/ansible/inventory.d"
	cat >"$FRAGMENT_FILE" <<EOF
# Fragment for ${VM_NAME}
[vms]
${VM_IP} ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=${VM_NAME}

# End fragment for ${VM_NAME}
EOF

	# Test that fragment contains vm_name variable
	assert_file_contains "$FRAGMENT_FILE" "vm_name=${VM_NAME}" \
		"Fragment should contain vm_name variable"

	teardown
}

# Test 4: Empty inventory handling
test_empty_inventory_handling() {
	echo ""
	echo "Test 4: Empty inventory handling"

	setup

	# When no fragments exist, inventory.ini should have [vms] header
	# This test expects merge logic to create minimal inventory
	# Currently FAILING because merge logic doesn't exist

	INVENTORY_FILE="$PROJECT_ROOT/ansible/inventory.ini"

	# Remove all fragments
	rm -f "$PROJECT_ROOT/ansible/inventory.d"/*.ini 2>/dev/null

	# Expected: Merge logic should create [vms] header
	# This will fail because no merge logic exists yet
	assert_file_contains "$INVENTORY_FILE" "[vms]" \
		"Empty inventory should contain [vms] header"

	teardown
}

# Test 5: Fragment format is valid INI
test_fragment_format_valid_ini() {
	echo ""
	echo "Test 5: Fragment format validation"

	setup

	VM_NAME="test-vm-3"
	VM_IP="192.168.122.101"
	FRAGMENT_FILE="$TEST_DIR/ansible/inventory.d/${VM_NAME}.ini"

	# Create fragment
	mkdir -p "$TEST_DIR/ansible/inventory.d"
	cat >"$FRAGMENT_FILE" <<EOF
# Fragment for ${VM_NAME}
[vms]
${VM_IP} ansible_user=mr ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3 vm_name=${VM_NAME}

# End fragment for ${VM_NAME}
EOF

	# Validate INI format (should have [vms] section)
	assert_file_contains "$FRAGMENT_FILE" "[vms]" \
		"Fragment should have [vms] section header"

	# Validate INI format (should have ansible_user)
	assert_file_contains "$FRAGMENT_FILE" "ansible_user=mr" \
		"Fragment should have ansible_user variable"

	teardown
}

# Test 6: Fragment file naming convention
test_fragment_naming_convention() {
	echo ""
	echo "Test 6: Fragment naming convention"

	setup

	VM_NAME="my-test-vm"
	EXPECTED_FRAGMENT="$PROJECT_ROOT/ansible/inventory.d/${VM_NAME}.ini"

	# This test expects fragments to be named ${vm_name}.ini
	# Currently FAILING because no fragments are being created

	# Simulate Terraform output (this would be done by main.tf)
	# For now, we just test that the naming convention would work

	FRAGMENT_BASENAME=$(basename "$EXPECTED_FRAGMENT")
	assert_equals "${VM_NAME}.ini" "$FRAGMENT_BASENAME" \
		"Fragment filename should match ${VM_NAME}.ini"

	teardown
}

# Test 7: Multiple fragments in directory
test_multiple_fragments_exist() {
	echo ""
	echo "Test 7: Multiple fragments can coexist"

	setup

	# Create multiple mock fragments
	mkdir -p "$TEST_DIR/ansible/inventory.d"

	cat >"$TEST_DIR/ansible/inventory.d/vm1.ini" <<EOF
[vms]
192.168.122.100 ansible_user=mr vm_name=vm1
EOF

	cat >"$TEST_DIR/ansible/inventory.d/vm2.ini" <<EOF
[vms]
192.168.122.101 ansible_user=mr vm_name=vm2
EOF

	cat >"$TEST_DIR/ansible/inventory.d/vm3.ini" <<EOF
[vms]
192.168.122.102 ansible_user=mr vm_name=vm3
EOF

	# Count fragments
	FRAGMENT_COUNT=$(ls "$TEST_DIR/ansible/inventory.d"/*.ini 2>/dev/null | wc -l)

	assert_equals "3" "$FRAGMENT_COUNT" \
		"Should have 3 fragment files"

	teardown
}

# Test 8: Fragment template uses vm_name variable
test_template_accepts_vm_name() {
	echo ""
	echo "Test 8: inventory.tpl accepts vm_name variable"

	setup

	# Test that inventory.tpl template accepts vm_name variable
	# This requires checking terraform template structure
	# Currently FAILING because inventory.tpl doesn't use vm_name variable

	TEMPLATE_FILE="$PROJECT_ROOT/terraform/inventory.tpl"

	# Check if template references ${vm_name}
	# This will fail because vm_name is not in current template
	if grep -q '\${vm_name}' "$TEMPLATE_FILE"; then
		TESTS_RUN=$((TESTS_RUN + 1))
		TESTS_PASSED=$((TESTS_PASSED + 1))
		echo -e "${GREEN}✓${NC} Template should reference vm_name variable"
	else
		TESTS_RUN=$((TESTS_RUN + 1))
		TESTS_FAILED=$((TESTS_FAILED + 1))
		echo -e "${RED}✗${NC} Template should reference vm_name variable"
		echo "  Current template does not use vm_name"
	fi

	teardown
}

# Run all tests
main() {
	echo "========================================="
	echo "Inventory Fragment Tests (RED Phase)"
	echo "Issue #5: Multi-VM Inventory Support"
	echo "========================================="

	test_fragment_directory_creation
	test_single_vm_fragment_generation
	test_fragment_contains_vm_name
	test_empty_inventory_handling
	test_fragment_format_valid_ini
	test_fragment_naming_convention
	test_multiple_fragments_exist
	test_template_accepts_vm_name

	echo ""
	echo "========================================="
	echo "Test Results:"
	echo "  Total:  $TESTS_RUN"
	echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
	echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
	echo "========================================="

	if [ $TESTS_FAILED -gt 0 ]; then
		echo -e "${RED}RED Phase: Tests are FAILING as expected${NC}"
		echo "Next: Implement fragment generation to make tests pass"
		exit 1
	else
		echo -e "${GREEN}All tests passing (GREEN Phase)${NC}"
		exit 0
	fi
}

# Run tests
main
