#!/usr/bin/env bash
# ABOUTME: Test suite for Ansible playbook configurable paths

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
	((TESTS_PASSED++))
}

fail() {
	echo -e "${RED}✗${NC} $1"
	echo -e "  ${RED}Expected:${NC} $2"
	echo -e "  ${RED}Got:${NC} $3"
	((TESTS_FAILED++))
}

test_start() {
	((TESTS_RUN++))
	echo -e "\n${YELLOW}Test $TESTS_RUN:${NC} $1"
}

# Test 1: Playbook has vars section with required variables
test_playbook_has_vars_section() {
	test_start "Playbook has vars section with required variables"

	# Check for vars section
	if grep -q "^  vars:" "$PLAYBOOK_PATH"; then
		: # vars section found
	else
		fail "Playbook should have vars section" "vars: section present" "vars: section missing"
		return
	fi

	# Required variables
	local required_vars=(
		"user_home"
		"ssh_key_path"
		"ssh_pub_key_path"
		"dotfiles_dir"
		"dotfiles_repo"
		"nvim_undo_dir"
		"nvim_autoload_dir"
		"tmux_plugins_dir"
	)

	local missing_vars=()
	for var in "${required_vars[@]}"; do
		if grep -q "^    ${var}:" "$PLAYBOOK_PATH"; then
			: # variable found
		else
			missing_vars+=("$var")
		fi
	done

	if [ ${#missing_vars[@]} -gt 0 ]; then
		fail "All required variables should be defined" \
			"All vars: ${required_vars[*]}" \
			"Missing: ${missing_vars[*]}"
		return
	fi

	pass "All required variables defined in vars section"
}

# Test 2: No hardcoded /home/mr paths in tasks (except copy src)
test_no_hardcoded_home_paths() {
	test_start "No hardcoded /home/mr paths in tasks (except copy src)"

	# Extract tasks section (everything after "tasks:")
	local tasks_section
	tasks_section=$(sed -n '/^  tasks:/,$p' "$PLAYBOOK_PATH")

	# Exclude copy task 'src:' lines (those reference host paths)
	local hardcoded_paths
	hardcoded_paths=$(echo "$tasks_section" | grep -n "/home/mr" | grep -v "src: ~/.ssh" || true)

	if [ -n "$hardcoded_paths" ]; then
		fail "No hardcoded /home/mr paths in tasks" \
			"All paths use variables" \
			"Found hardcoded paths: $hardcoded_paths"
		return
	fi

	pass "No hardcoded /home/mr paths in tasks"
}

# Test 3: Variables use Jinja2 templating
test_variables_use_jinja2() {
	test_start "Variables use Jinja2 templating syntax"

	# Check that user_home uses ansible_user
	if grep -q 'user_home:.*ansible_user' "$PLAYBOOK_PATH"; then
		: # pattern found
	else
		fail "user_home should use ansible_user variable" \
			'user_home: "/home/{{ ansible_user }}"' \
			"Pattern not found"
		return
	fi

	# Check that ssh_key_path uses user_home variable
	if grep -q 'ssh_key_path:.*user_home' "$PLAYBOOK_PATH"; then
		: # pattern found
	else
		fail "ssh_key_path should use user_home variable" \
			'ssh_key_path: "{{ user_home }}/.ssh/id_ed25519"' \
			"Pattern not found"
		return
	fi

	pass "Variables use proper Jinja2 templating"
}

# Test 4: Copy tasks use variable for dest
test_copy_tasks_use_variables() {
	test_start "Copy SSH key tasks use variables for dest"

	# Check private key copy task
	local priv_key_line
	priv_key_line=$(grep -A5 "Copy GitHub SSH private key" "$PLAYBOOK_PATH" | grep "dest:")

	if echo "$priv_key_line" | grep -q "ssh_key_path"; then
		: # variable found
	else
		fail "Private key copy should use ssh_key_path variable" \
			'dest: "{{ ssh_key_path }}"' \
			"$priv_key_line"
		return
	fi

	# Check public key copy task
	local pub_key_line
	pub_key_line=$(grep -A5 "Copy GitHub SSH public key" "$PLAYBOOK_PATH" | grep "dest:")

	if echo "$pub_key_line" | grep -q "ssh_pub_key_path"; then
		: # variable found
	else
		fail "Public key copy should use ssh_pub_key_path variable" \
			'dest: "{{ ssh_pub_key_path }}"' \
			"$pub_key_line"
		return
	fi

	pass "Copy tasks use variables for destinations"
}

# Test 5: Git clone task uses variable for dotfiles repo and dest
test_git_clone_uses_variables() {
	test_start "Git clone task uses variables for repo and dest"

	local clone_section
	clone_section=$(grep -A5 "Clone dotfiles repository" "$PLAYBOOK_PATH")

	# Check repo uses variable
	if echo "$clone_section" | grep "repo:" | grep -q "dotfiles_repo"; then
		: # variable found
	else
		fail "Git clone should use dotfiles_repo variable" \
			'repo: "{{ dotfiles_repo }}"' \
			"$(echo "$clone_section" | grep "repo:")"
		return
	fi

	# Check dest uses variable
	if echo "$clone_section" | grep "dest:" | grep -q "dotfiles_dir"; then
		: # variable found
	else
		fail "Git clone should use dotfiles_dir variable" \
			'dest: "{{ dotfiles_dir }}"' \
			"$(echo "$clone_section" | grep "dest:")"
		return
	fi

	pass "Git clone uses variables for repo and dest"
}

# Test 6: group_vars/all.yml exists with variable documentation
test_group_vars_documentation() {
	test_start "group_vars/all.yml exists with variable documentation"

	local group_vars_path="$PROJECT_ROOT/ansible/group_vars/all.yml"

	if [ -f "$group_vars_path" ]; then
		: # file exists
	else
		fail "group_vars/all.yml should exist" \
			"File exists with documented variables" \
			"File not found"
		return
	fi

	# Check for documentation comments
	if grep -q "# Override these variables" "$group_vars_path"; then
		: # documentation found
	else
		fail "group_vars/all.yml should have override documentation" \
			"Documentation comments present" \
			"Documentation missing"
		return
	fi

	pass "group_vars/all.yml exists with documentation"
}

# Test 7: README documents variable override process
test_readme_documents_variables() {
	test_start "README documents how to override variables"

	local readme_path="$PROJECT_ROOT/README.md"

	# Check for any of the key documentation indicators
	if grep -q "Ansible variables" "$readme_path" ||
		grep -q "group_vars" "$readme_path" ||
		grep -q "dotfiles_repo" "$readme_path"; then
		pass "README documents variable override process"
	else
		fail "README should document variable overrides" \
			"Documentation about ansible variables and group_vars" \
			"Documentation not found"
	fi
}

# Run all tests
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Ansible Variable Configuration Tests${NC}"
echo -e "${YELLOW}========================================${NC}"

test_playbook_has_vars_section
test_no_hardcoded_home_paths
test_variables_use_jinja2
test_copy_tasks_use_variables
test_git_clone_uses_variables
test_group_vars_documentation
test_readme_documents_variables

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
