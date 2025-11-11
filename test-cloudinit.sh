#!/bin/bash
# ABOUTME: Regression test for cloud-init functionality
# Tests: VM creation, cloud-init completion, SSH access, user creation
# Usage: ./test-cloudinit.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_VM_NAME="test-cloudinit-regression-$$"
TIMEOUT_SECONDS=180
PASSED=0
FAILED=0

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

cleanup() {
    echo ""
    log_test "Cleaning up test VM..."
    cd "$SCRIPT_DIR/terraform"
    terraform destroy -auto-approve -var="vm_name=$TEST_VM_NAME" &> /dev/null || true
    cd "$SCRIPT_DIR"

    echo ""
    echo "═══════════════════════════════════════"
    echo "Test Results:"
    echo "  Passed: $PASSED"
    echo "  Failed: $FAILED"
    echo "═══════════════════════════════════════"

    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

trap cleanup EXIT

echo "═══════════════════════════════════════"
echo "  Cloud-Init Regression Test"
echo "═══════════════════════════════════════"
echo "VM Name: $TEST_VM_NAME"
echo ""

# Test 1: Terraform can create VM
log_test "Creating VM with Terraform..."
cd "$SCRIPT_DIR/terraform"
if terraform apply -auto-approve -var="vm_name=$TEST_VM_NAME" &> /dev/null; then
    log_pass "VM created successfully"
else
    log_fail "Terraform failed to create VM"
    exit 1
fi
cd "$SCRIPT_DIR"

# Test 2: Get VM IP address
log_test "Retrieving VM IP address..."
VM_IP=$(cd "$SCRIPT_DIR/terraform" && terraform output -raw vm_ip)
if [ -n "$VM_IP" ] && [ "$VM_IP" != "pending" ]; then
    log_pass "VM IP retrieved: $VM_IP"
else
    log_fail "Failed to get VM IP"
fi

# Test 3: Cloud-init completes within timeout
log_test "Waiting for cloud-init to complete (timeout: ${TIMEOUT_SECONDS}s)..."
START_TIME=$(date +%s)
CLOUD_INIT_SUCCESS=false

for _ in $(seq 1 $((TIMEOUT_SECONDS / 2))); do
    if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
        mr@"$VM_IP" 'cloud-init status --wait' &> /dev/null; then
        CLOUD_INIT_SUCCESS=true
        break
    fi
    sleep 2
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

if [ "$CLOUD_INIT_SUCCESS" = true ]; then
    log_pass "Cloud-init completed in ${ELAPSED}s"
else
    log_fail "Cloud-init failed to complete within ${TIMEOUT_SECONDS}s"
fi

# Test 4: SSH connectivity
log_test "Testing SSH connectivity..."
if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    mr@"$VM_IP" 'echo "SSH OK"' &> /dev/null; then
    log_pass "SSH connectivity verified"
else
    log_fail "SSH connection failed"
fi

# Test 5: User 'mr' exists
log_test "Verifying user 'mr' created..."
USER_CHECK=$(ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no \
    mr@"$VM_IP" 'whoami' 2> /dev/null || echo "")
if [ "$USER_CHECK" = "mr" ]; then
    log_pass "User 'mr' verified"
else
    log_fail "User 'mr' not found"
fi

# Test 6: User has sudo privileges
log_test "Verifying sudo privileges..."
if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no \
    mr@"$VM_IP" 'sudo -n true' &> /dev/null; then
    log_pass "Sudo privileges verified (passwordless)"
else
    log_fail "Sudo privileges not configured"
fi

# Test 7: Cloud-init status shows 'done'
log_test "Checking cloud-init final status..."
CLOUD_INIT_STATUS=$(ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no \
    mr@"$VM_IP" 'cloud-init status' 2> /dev/null || echo "")
if echo "$CLOUD_INIT_STATUS" | grep -q "status: done"; then
    log_pass "Cloud-init status: done"
else
    log_fail "Cloud-init status not 'done': $CLOUD_INIT_STATUS"
fi

# Test 8: SSH key properly authorized
log_test "Verifying SSH key authorization..."
if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no \
    mr@"$VM_IP" 'test -f ~/.ssh/authorized_keys && grep -q "vm-access" ~/.ssh/authorized_keys' &> /dev/null; then
    log_pass "SSH key properly authorized"
else
    log_fail "SSH key not in authorized_keys"
fi

# Test 9: Cloud-init ISO attached correctly
log_test "Verifying cloud-init ISO was accessible..."
if ssh -i ~/.ssh/vm_key -o StrictHostKeyChecking=no \
    mr@"$VM_IP" 'test -d /var/lib/cloud/seed/nocloud' &> /dev/null; then
    log_pass "Cloud-init NoCloud datasource detected"
else
    log_fail "Cloud-init NoCloud datasource not found"
fi

# Cleanup will run via trap
