#!/usr/bin/env bash
# ABOUTME: Test suite for Ansible playbook rollback and error handling

set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAYBOOK_PATH="$PROJECT_ROOT/ansible/playbook.yml"

# Test helper functions
pass() {
	echo -e "${GREEN}✓${NC} $1"
	((++TESTS_PASSED))
}

fail() {
	echo -e "${RED}✗${NC} $1"
	echo -e "  ${RED}Expected:${NC} $2"
	echo -e "  ${RED}Got:${NC} $3"
	((++TESTS_FAILED))
}

test_start() {
	((++TESTS_RUN))
	echo -e "\n${YELLOW}Test $TESTS_RUN:${NC} $1"
}

# Test 1: Playbook has block structure for error handling
test_playbook_has_block_structure() {
	test_start "Playbook has block/rescue/always structure for error handling"

	# Check for block keyword (Ansible YAML format: "    - block:")
	if grep -q "^    - block:" "$PLAYBOOK_PATH"; then
		: # block found
	else
		fail "Playbook should have block structure" "block: section present" "block: section missing"
		return
	fi

	pass "Playbook has block structure"
}

# Test 2: Playbook has rescue block with cleanup tasks
test_playbook_has_rescue_block() {
	test_start "Playbook has rescue block with cleanup tasks"

	# Check for rescue keyword (Ansible YAML format: "      rescue:")
	if grep -q "^      rescue:" "$PLAYBOOK_PATH"; then
		: # rescue found
	else
		fail "Playbook should have rescue block" "rescue: section present" "rescue: section missing"
		return
	fi

	pass "Playbook has rescue block"
}

# Test 3: Rescue block includes package cleanup task
test_rescue_has_package_cleanup() {
	test_start "Rescue block includes task to remove partially installed packages"

	# Extract rescue section (Ansible YAML format with proper indentation)
	local rescue_section
	rescue_section=$(sed -n '/^      rescue:/,/^      [a-z]/p' "$PLAYBOOK_PATH" | head -n -1)

	# Check for package removal task
	if echo "$rescue_section" | grep -q "Remove partially installed packages" ||
		echo "$rescue_section" | grep -q "Rollback - Remove"; then
		: # cleanup task found
	else
		fail "Rescue should have package cleanup task" \
			"Task to remove packages present" \
			"Package cleanup task missing"
		return
	fi

	pass "Rescue block includes package cleanup"
}

# Test 4: Rescue block includes dotfiles cleanup task
test_rescue_has_dotfiles_cleanup() {
	test_start "Rescue block includes task to remove dotfiles directory"

	# Extract rescue section (Ansible YAML format with proper indentation)
	local rescue_section
	rescue_section=$(sed -n '/^      rescue:/,/^      [a-z]/p' "$PLAYBOOK_PATH" | head -n -1)

	# Check for dotfiles removal task
	if echo "$rescue_section" | grep -q "Remove dotfiles" ||
		echo "$rescue_section" | grep -q "dotfiles_dir"; then
		: # dotfiles cleanup task found
	else
		fail "Rescue should have dotfiles cleanup task" \
			"Task to remove dotfiles present" \
			"Dotfiles cleanup task missing"
		return
	fi

	pass "Rescue block includes dotfiles cleanup"
}

# Test 5: Rescue block provides recovery guidance
test_rescue_has_recovery_guidance() {
	test_start "Rescue block provides clear recovery guidance"

	# Extract rescue section (Ansible YAML format with proper indentation)
	local rescue_section
	rescue_section=$(sed -n '/^      rescue:/,/^      [a-z]/p' "$PLAYBOOK_PATH" | head -n -1)

	# Check for debug message or recovery instructions
	if echo "$rescue_section" | grep -q "debug:" &&
		echo "$rescue_section" | grep -q "destroy\|re-run\|fix"; then
		: # recovery guidance found
	else
		fail "Rescue should provide recovery guidance" \
			"Debug message with destroy/fix/re-run instructions" \
			"Recovery guidance missing"
		return
	fi

	pass "Rescue block provides recovery guidance"
}

# Test 6: Playbook has always block for logging
test_playbook_has_always_block() {
	test_start "Playbook has always block for result logging"

	# Check for always keyword (Ansible YAML format: "      always:")
	if grep -q "^      always:" "$PLAYBOOK_PATH"; then
		: # always found
	else
		fail "Playbook should have always block" "always: section present" "always: section missing"
		return
	fi

	pass "Playbook has always block"
}

# Test 7: Always block logs provisioning result
test_always_logs_result() {
	test_start "Always block logs provisioning result"

	# Extract always section (Ansible YAML format with proper indentation)
	local always_section
	always_section=$(sed -n '/^      always:/,/^  [a-z]/p' "$PLAYBOOK_PATH" | head -n -1)

	# Check for logging task
	if echo "$always_section" | grep -q "Log provisioning" ||
		echo "$always_section" | grep -q "provisioning.log"; then
		: # logging task found
	else
		fail "Always block should log provisioning result" \
			"Task that creates provisioning.log" \
			"Logging task missing"
		return
	fi

	pass "Always block logs provisioning result"
}

# Test 8: README documents rollback behavior
test_readme_documents_rollback() {
	test_start "README documents rollback behavior and recovery steps"

	local readme_path="$PROJECT_ROOT/README.md"

	# Check for rollback documentation
	if grep -q -i "rollback\|error handling\|failure recovery" "$readme_path"; then
		pass "README documents rollback behavior"
	else
		fail "README should document rollback behavior" \
			"Documentation about rollback and error handling" \
			"Rollback documentation not found"
	fi
}

# Run all tests
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Ansible Rollback Handler Tests${NC}"
echo -e "${YELLOW}========================================${NC}"

test_playbook_has_block_structure
test_playbook_has_rescue_block
test_rescue_has_package_cleanup
test_rescue_has_dotfiles_cleanup
test_rescue_has_recovery_guidance
test_playbook_has_always_block
test_always_logs_result
test_readme_documents_rollback

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

# Exit with appropriate code
if [ $TESTS_FAILED -gt 0 ]; then
	exit 1
else
	exit 0
fi
