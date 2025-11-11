#!/bin/bash
# ABOUTME: Unit tests for create-cloudinit-iso.sh script validation logic

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_ISO_SCRIPT="$SCRIPT_DIR/terraform/create-cloudinit-iso.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1: $2"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

cleanup() {
    sudo rm -f /var/lib/libvirt/images/test-*-cloudinit.iso 2> /dev/null || true
}

trap cleanup EXIT

echo "========================================"
echo "Unit Tests for create-cloudinit-iso.sh"
echo "========================================"
echo ""

# Generate valid SSH key for tests
ssh-keygen -t rsa -b 2048 -f /tmp/test_unit_key -N "" -C "test@test.com" &> /dev/null
VALID_KEY=$(cat /tmp/test_unit_key.pub)

echo "=== Input Validation Tests ==="
echo ""

# Test 1: Script rejects empty VM name
if sudo bash "$CREATE_ISO_SCRIPT" "" "$VALID_KEY" 2>&1 | grep -q "Usage:"; then
    test_pass "Rejects empty VM name"
else
    test_fail "Rejects empty VM name" "Should show usage message"
fi

# Test 2: Script rejects empty SSH key
if sudo bash "$CREATE_ISO_SCRIPT" "test-vm" "" 2>&1 | grep -q "Usage:"; then
    test_pass "Rejects empty SSH key"
else
    test_fail "Rejects empty SSH key" "Should show usage message"
fi

# Test 3: Script rejects invalid SSH key
if sudo bash "$CREATE_ISO_SCRIPT" "test-invalid" "not-a-valid-key" 2>&1 | grep -q "Invalid SSH public key"; then
    test_pass "Rejects invalid SSH key format"
else
    test_fail "Rejects invalid SSH key format" "Should show validation error"
fi

# Test 4: Script rejects VM name with special characters
if sudo bash "$CREATE_ISO_SCRIPT" 'test-$(whoami)' "$VALID_KEY" 2>&1 | grep -q "invalid characters"; then
    test_pass "Rejects VM name with command substitution"
else
    test_fail "Rejects VM name with command substitution" "Should show validation error"
fi

# Test 5: Script rejects VM name with path traversal
if sudo bash "$CREATE_ISO_SCRIPT" 'test/../../../etc/passwd' "$VALID_KEY" 2>&1 | grep -q "invalid characters"; then
    test_pass "Rejects VM name with path traversal"
else
    test_fail "Rejects VM name with path traversal" "Should show validation error"
fi

echo ""
echo "=== ISO Creation Tests ==="
echo ""

# Test 6: Script creates ISO with valid inputs
if sudo bash "$CREATE_ISO_SCRIPT" "test-unit-valid" "$VALID_KEY" 2>&1 | grep -q "cloudinit.iso"; then
    test_pass "Creates ISO with valid inputs"
else
    test_fail "Creates ISO with valid inputs" "Should output ISO path"
fi

# Test 7: ISO file exists
if [ -f /var/lib/libvirt/images/test-unit-valid-cloudinit.iso ]; then
    test_pass "ISO file created"
else
    test_fail "ISO file created" "ISO not found"
fi

# Test 8: ISO has correct permissions (640)
PERMS=$(sudo stat -c %a /var/lib/libvirt/images/test-unit-valid-cloudinit.iso 2> /dev/null || echo "000")
if [ "$PERMS" = "640" ]; then
    test_pass "ISO has 640 permissions"
else
    test_fail "ISO has 640 permissions" "Got $PERMS"
fi

# Test 9: ISO has correct ownership (root:libvirt)
OWNER=$(sudo stat -c %U /var/lib/libvirt/images/test-unit-valid-cloudinit.iso 2> /dev/null || echo "unknown")
GROUP=$(sudo stat -c %G /var/lib/libvirt/images/test-unit-valid-cloudinit.iso 2> /dev/null || echo "unknown")
if [ "$OWNER" = "root" ] && [ "$GROUP" = "libvirt" ]; then
    test_pass "ISO ownership is root:libvirt"
else
    test_fail "ISO ownership is root:libvirt" "Got $OWNER:$GROUP"
fi

# Test 10: ISO contains user-data
if sudo isoinfo -l -i /var/lib/libvirt/images/test-unit-valid-cloudinit.iso 2> /dev/null | grep -q "user-data"; then
    test_pass "ISO contains user-data"
else
    test_fail "ISO contains user-data" "user-data not found in ISO"
fi

# Test 11: ISO contains meta-data
if sudo isoinfo -l -i /var/lib/libvirt/images/test-unit-valid-cloudinit.iso 2> /dev/null | grep -q "meta-data"; then
    test_pass "ISO contains meta-data"
else
    test_fail "ISO contains meta-data" "meta-data not found in ISO"
fi

# Cleanup
rm -f /tmp/test_unit_key /tmp/test_unit_key.pub

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Tests run: $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: All unit tests passed${NC}"
    exit 0
else
    echo -e "${RED}FAILURE: Some tests failed${NC}"
    exit 1
fi
