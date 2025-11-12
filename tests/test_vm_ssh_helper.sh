#!/bin/bash
# ABOUTME: Tests for vm-ssh.sh helper script
# Tests VM state detection, startup, IP discovery, and error handling

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test VM name (use test-vm-ssh-test to avoid conflicts)
TEST_VM="test-vm-ssh-test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_SSH_SCRIPT="$SCRIPT_DIR/vm-ssh.sh"

# Test helper functions
test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}[TEST $TESTS_RUN] $1${NC}"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}  ✓ PASS${NC}"
    echo ""
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}  ✗ FAIL: $1${NC}"
    echo ""
}

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up test VM..."
    if sudo virsh list --all | grep -q "$TEST_VM"; then
        sudo virsh destroy "$TEST_VM" 2> /dev/null || true
        sudo virsh undefine "$TEST_VM" 2> /dev/null || true
        sudo virsh vol-delete "${TEST_VM}.qcow2" default 2> /dev/null || true
        sudo virsh vol-delete "${TEST_VM}-cloudinit.iso" default 2> /dev/null || true
        rm -f "$SCRIPT_DIR/ansible/inventory.d/${TEST_VM}.ini" 2> /dev/null || true
    fi
    echo "Cleanup complete"
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Verify script exists
if [ ! -f "$VM_SSH_SCRIPT" ]; then
    echo -e "${RED}[ERROR] vm-ssh.sh not found at: $VM_SSH_SCRIPT${NC}"
    exit 1
fi

# Verify script is executable
if [ ! -x "$VM_SSH_SCRIPT" ]; then
    echo -e "${RED}[ERROR] vm-ssh.sh is not executable${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  vm-ssh.sh Test Suite${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ===================================================================
# TEST 1: Script shows usage when called without arguments
# ===================================================================
test_start "Script shows usage when called without arguments"

OUTPUT=$("$VM_SSH_SCRIPT" 2>&1 || true)

if echo "$OUTPUT" | grep -q "Usage:"; then
    if echo "$OUTPUT" | grep -q "Available VMs:"; then
        test_pass
    else
        test_fail "Usage shown but 'Available VMs' missing"
    fi
else
    test_fail "Usage message not shown"
fi

# ===================================================================
# TEST 2: Script exits with error for non-existent VM
# ===================================================================
test_start "Script exits with error for non-existent VM"

OUTPUT=$("$VM_SSH_SCRIPT" nonexistent-vm-12345 2>&1 || true)

if echo "$OUTPUT" | grep -q "not found"; then
    if echo "$OUTPUT" | grep -q "Available VMs:"; then
        test_pass
    else
        test_fail "Error shown but available VMs list missing"
    fi
else
    test_fail "Error message not shown for non-existent VM"
fi

# ===================================================================
# TEST 3: Script detects running VM correctly
# ===================================================================
test_start "Script detects running VM state correctly"

# Use existing work-vm-1 for this test (already running)
if sudo virsh list --all | grep -q "work-vm-1.*running"; then
    OUTPUT=$(
        "$VM_SSH_SCRIPT" work-vm-1 << EOF 2>&1 || true
exit
EOF
    )

    if echo "$OUTPUT" | grep -q "already running"; then
        test_pass
    else
        test_fail "Running VM not detected as running"
    fi
else
    echo -e "${YELLOW}  ⊘ SKIP: work-vm-1 not running, cannot test${NC}"
    echo ""
fi

# ===================================================================
# TEST 4: Script detects shut-off VM correctly
# ===================================================================
test_start "Script detects shut-off VM state correctly"

# Shut down work-vm-1 temporarily for this test
if sudo virsh list --all | grep -q "work-vm-1"; then
    ORIGINAL_STATE=$(sudo virsh list --all | grep "work-vm-1" | awk '{print $3}')

    # Ensure VM is shut off for test
    if [ "$ORIGINAL_STATE" = "running" ]; then
        sudo virsh shutdown work-vm-1 > /dev/null 2>&1
        sleep 5
    fi

    OUTPUT=$(
        "$VM_SSH_SCRIPT" work-vm-1 << EOF 2>&1 || true
exit
EOF
    )

    if echo "$OUTPUT" | grep -q "shut off.*starting"; then
        test_pass
    else
        test_fail "Shut-off VM not detected or startup message missing"
    fi

    # Restore original state
    if [ "$ORIGINAL_STATE" = "running" ]; then
        sudo virsh start work-vm-1 > /dev/null 2>&1 || true
    fi
else
    echo -e "${YELLOW}  ⊘ SKIP: work-vm-1 not available, cannot test${NC}"
    echo ""
fi

# ===================================================================
# TEST 5: Script gets IP address correctly
# ===================================================================
test_start "Script retrieves IP address correctly"

if sudo virsh list --all | grep -q "work-vm-1"; then
    # Ensure VM is running
    STATE=$(sudo virsh list --all | grep "work-vm-1" | awk '{print $3}')
    if [ "$STATE" != "running" ]; then
        sudo virsh start work-vm-1 > /dev/null 2>&1
        sleep 5
    fi

    OUTPUT=$(
        "$VM_SSH_SCRIPT" work-vm-1 << EOF 2>&1 || true
exit
EOF
    )

    # Check for IP address in output (192.168.122.x format)
    if echo "$OUTPUT" | grep -qE "IP address: 192\.168\.122\.[0-9]+"; then
        test_pass
    else
        test_fail "IP address not retrieved or incorrect format"
    fi
else
    echo -e "${YELLOW}  ⊘ SKIP: work-vm-1 not available, cannot test${NC}"
    echo ""
fi

# ===================================================================
# TEST 6: Script verifies SSH connectivity before connecting
# ===================================================================
test_start "Script verifies SSH connectivity before connecting"

if sudo virsh list --all | grep -q "work-vm-1.*running"; then
    OUTPUT=$(
        "$VM_SSH_SCRIPT" work-vm-1 << EOF 2>&1 || true
exit
EOF
    )

    if echo "$OUTPUT" | grep -q "SSH connectivity verified"; then
        test_pass
    else
        test_fail "SSH connectivity verification not shown"
    fi
else
    echo -e "${YELLOW}  ⊘ SKIP: work-vm-1 not running, cannot test${NC}"
    echo ""
fi

# ===================================================================
# TEST 7: Script executable permissions are correct
# ===================================================================
test_start "Script has correct executable permissions"

PERMS=$(stat -c %a "$VM_SSH_SCRIPT")

if [ "$PERMS" = "755" ] || [ "$PERMS" = "775" ] || [ "$PERMS" = "777" ]; then
    test_pass
else
    test_fail "Script permissions are $PERMS (expected 755)"
fi

# ===================================================================
# TEST 8: Script contains proper ABOUTME comment
# ===================================================================
test_start "Script contains proper ABOUTME comment"

if head -3 "$VM_SSH_SCRIPT" | grep -q "# ABOUTME:"; then
    test_pass
else
    test_fail "ABOUTME comment missing from script header"
fi

# ===================================================================
# TEST 9: Documentation files exist
# ===================================================================
test_start "Required documentation files exist"

DOCS_EXIST=true

if [ ! -f "$SCRIPT_DIR/docs/VM-SSH-HELPER.md" ]; then
    echo -e "${RED}    Missing: docs/VM-SSH-HELPER.md${NC}"
    DOCS_EXIST=false
fi

if [ ! -f "$SCRIPT_DIR/VM-QUICK-REFERENCE.md" ]; then
    echo -e "${RED}    Missing: VM-QUICK-REFERENCE.md${NC}"
    DOCS_EXIST=false
fi

if [ "$DOCS_EXIST" = true ]; then
    test_pass
else
    test_fail "Documentation files missing"
fi

# ===================================================================
# TEST 10: Script handles color output correctly
# ===================================================================
test_start "Script uses color codes for output"

if grep -q "RED=" "$VM_SSH_SCRIPT" &&
    grep -q "GREEN=" "$VM_SSH_SCRIPT" &&
    grep -q "YELLOW=" "$VM_SSH_SCRIPT"; then
    test_pass
else
    test_fail "Color codes not defined in script"
fi

# ===================================================================
# TEST SUMMARY
# ===================================================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Test Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    echo -e "${RED}FAIL: Some tests failed${NC}"
    exit 1
else
    echo -e "Tests failed: $TESTS_FAILED"
    echo ""
    echo -e "${GREEN}SUCCESS: All tests passed!${NC}"
    exit 0
fi
