#!/bin/bash
# ABOUTME: Quick test runner for Test 2 only (git clone failure rescue)
# Integration test runner - Test 2 only for fast iteration

set -euo pipefail

# Source the main test file to get all functions and Test 2
source "$(dirname "$0")/test_rollback_integration.sh"

# Override main function to run only Test 2
main() {
	echo "===================================="
	echo "Integration Tests - Test 2 Only"
	echo "===================================="
	echo ""

	setup_test_suite

	# Run only Test 2
	test_rescue_cleans_dotfiles_on_failure

	# Print summary
	echo ""
	echo "===================================="
	print_test_summary
	echo "===================================="

	# Exit with appropriate code
	[[ $TESTS_FAILED -eq 0 ]]
}

# Run main
main "$@"
