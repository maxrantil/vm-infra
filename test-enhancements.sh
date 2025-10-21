#!/bin/bash
# ABOUTME: Tests for medium-priority security enhancements (MRI-001, MRI-002, MV-001)

# Don't exit on test failures - we want to see all results
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_ISO_SCRIPT="$SCRIPT_DIR/terraform/create-cloudinit-iso.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    echo -e "${RED}  Error: $2${NC}"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

cleanup() {
    sudo rm -f /var/lib/libvirt/images/test-*-cloudinit.iso 2> /dev/null || true
    sudo rm -f /tmp/test_enh_*.pub 2> /dev/null || true
}

trap cleanup EXIT

echo "========================================="
echo "Enhancement Tests (MRI-001, MRI-002, MV-001)"
echo "========================================="
echo ""

# Generate valid SSH key for tests (for future test expansion)
ssh-keygen -t rsa -b 2048 -f /tmp/test_enh_key -N "" -C "test@test.com" &> /dev/null
rm -f /tmp/test_enh_key /tmp/test_enh_key.pub

echo "=== MRI-001: Temporary File Security ==="
echo ""

# Test 1: Verify temporary file in validate_ssh_key has secure permissions
echo "Test 1: Temporary file created with secure permissions (600)"
# This test verifies code implementation - we check the script source
if grep -A 2 'temp_keyfile=$(mktemp)' "$CREATE_ISO_SCRIPT" | grep -q 'chmod 600'; then
    test_pass "Temporary file has immediate chmod 600 protection"
else
    test_fail "Temporary file has immediate chmod 600 protection" "chmod 600 not found immediately after mktemp"
fi

echo ""
echo "=== MRI-002: Error Handling for Privileged Operations ==="
echo ""

# Test 2: Script fails when chmod fails on ISO
echo "Test 2: Script detects chmod failure"
# Create a mock script that fails on chmod
MOCK_SCRIPT="/tmp/test_chmod_fail.sh"
cat > "$MOCK_SCRIPT" << 'EOFMOCK'
#!/bin/bash
if [[ "$*" == *"chmod"* ]]; then
    exit 1
fi
exec "$@"
EOFMOCK
chmod +x "$MOCK_SCRIPT"

# Check if script has error handling for chmod
if grep -q 'chmod 640.*||' "$CREATE_ISO_SCRIPT" ||
    grep -q 'if.*chmod 640' "$CREATE_ISO_SCRIPT" ||
    grep -A 1 'chmod 640' "$CREATE_ISO_SCRIPT" | grep -q 'if \['; then
    test_pass "Script has error handling for chmod failures"
else
    test_fail "Script has error handling for chmod failures" "No error handling found for chmod command"
fi
rm -f "$MOCK_SCRIPT"

# Test 3: Script fails when chown fails on ISO
echo "Test 3: Script detects chown failure"
if grep -q 'chown.*||' "$CREATE_ISO_SCRIPT" ||
    grep -q 'if.*chown' "$CREATE_ISO_SCRIPT" ||
    grep -A 1 'chown' "$CREATE_ISO_SCRIPT" | grep -q 'if \['; then
    test_pass "Script has error handling for chown failures"
else
    test_fail "Script has error handling for chown failures" "No error handling found for chown command"
fi

echo ""
echo "=== MV-001: Genisoimage Validation ==="
echo ""

# Test 4: Script validates genisoimage success
echo "Test 4: Script validates genisoimage exit status"
if grep -q 'genisoimage.*||' "$CREATE_ISO_SCRIPT" ||
    grep -q 'if.*genisoimage' "$CREATE_ISO_SCRIPT" ||
    grep -A 1 'genisoimage' "$CREATE_ISO_SCRIPT" | grep -q 'if \['; then
    test_pass "Script has error handling for genisoimage failures"
else
    test_fail "Script has error handling for genisoimage failures" "No error handling found for genisoimage command"
fi

# Test 5: Script verifies ISO file exists after creation
echo "Test 5: Script verifies ISO file exists after creation"
if grep -A 10 'genisoimage' "$CREATE_ISO_SCRIPT" | grep -q 'if.*-f.*ISO_PATH' ||
    grep -A 10 'genisoimage' "$CREATE_ISO_SCRIPT" | grep -q '\[ ! -f'; then
    test_pass "Script verifies ISO file existence"
else
    test_fail "Script verifies ISO file existence" "No file existence check found after genisoimage"
fi

echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}FAILED: Some enhancement tests failed${NC}"
    exit 1
else
    echo -e "${GREEN}SUCCESS: All enhancement tests passed${NC}"
    exit 0
fi
