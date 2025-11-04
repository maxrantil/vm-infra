#!/usr/bin/env bash
# ABOUTME: Test runner for Test 3 only (always block creates log on success)

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Clean up provisioning.log before test
rm -f "$PROJECT_ROOT/ansible/provisioning.log"

# Source the main test file but only run Test 3
source "$SCRIPT_DIR/test_rollback_integration.sh"

# Override main execution - only run Test 3
test_always_logs_success

# Print summary
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}Test 3 Summary${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "Tests run:    $TESTS_RUN"
echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
    exit 1
else
    echo -e "Tests failed: $TESTS_FAILED"
    exit 0
fi
