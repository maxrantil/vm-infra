#!/usr/bin/env bash
# ABOUTME: Isolated test runner for Test 5 (rescue block idempotency)

# Determine script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the main test file to get functions and test
source "$SCRIPT_DIR/test_rollback_integration.sh"

# Run only Test 5
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Test 5 Only: Rescue Block Idempotency${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "${BLUE}Test ID: $TEST_ID${NC}"
echo ""

test_rescue_idempotent

# Print summary
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}Test Summary${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "Tests run:    $TESTS_RUN"
echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
else
    echo -e "Tests failed: $TESTS_FAILED"
fi
echo -e "Exit code:    $([ $TESTS_FAILED -gt 0 ] && echo 1 || echo 0)"

# Exit with appropriate code
if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
else
    exit 0
fi
