#!/usr/bin/env bash
# ABOUTME: Reusable validation functions for VM infrastructure security and path handling

# This library provides security-hardened validation functions for:
# - SSH key and directory permission validation
# - Dotfiles path security validation (CVE-1, CVE-3, SEC-001, SEC-003, SEC-004)
# - install.sh safety inspection (CVE-2, SEC-002, SEC-005, SEC-006)
# - Git repository validation (BUG-006)
#
# Security mitigations implemented:
# - CVE-1: Symlink attack prevention (CVSS 9.3)
# - CVE-2: install.sh content inspection (CVSS 9.0)
# - CVE-3: Shell injection prevention (CVSS 7.8)
# - SEC-001: TOCTOU race condition mitigation (CVSS 6.8)
# - SEC-002: Pattern evasion detection (CVSS 7.5)
# - SEC-003: Comprehensive metacharacter blocking (CVSS 7.0)
# - SEC-004: Recursive symlink detection (CVSS 5.5)
# - SEC-005: Permission validation (CVSS 4.0)
# - SEC-006: Whitelist validation (CVSS 5.0)
#
# Usage:
#   source "$(dirname "$0")/lib/validation.sh"
#   validate_dotfiles_path_exists "/path/to/dotfiles"
#
# Dependencies:
#   - bash >= 4.0
#   - coreutils (stat, chmod, realpath)
#   - openssh (ssh-keygen)
#   - git (optional, for git repo validation)

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	echo "Error: This library should be sourced, not executed directly" >&2
	echo "Usage: source lib/validation.sh" >&2
	exit 1
fi

# Prevent multiple sourcing
if [ -n "${VALIDATION_LIB_LOADED:-}" ]; then
	return 0
fi
readonly VALIDATION_LIB_LOADED=1

# Color codes for output (if not already defined by caller)
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"
NC="${NC:-\033[0m}"

# Permission constants
readonly PERM_SSH_DIR="700"
readonly PERM_PRIVATE_KEY_RW="600" # pragma: allowlist secret
readonly PERM_PRIVATE_KEY_RO="400" # pragma: allowlist secret
readonly PERM_WORLD_WRITABLE_BIT="8#002"
readonly PERM_GROUP_WRITABLE_BIT="8#020"

#####################################
# SECTION 1: SSH KEY VALIDATION
#####################################

validate_ssh_directory_permissions() {
	local ssh_dir="$HOME/.ssh"
	local ssh_dir_perms
	ssh_dir_perms=$(stat -c "%a" "$ssh_dir" 2>/dev/null || echo "")

	if [ -z "$ssh_dir_perms" ]; then
		echo -e "${RED}[ERROR] SSH directory not found${NC}" >&2
		exit 1
	fi

	if [ "$ssh_dir_perms" != "$PERM_SSH_DIR" ]; then
		echo -e "${YELLOW}[WARNING] Insecure SSH directory permissions: $ssh_dir_perms${NC}" >&2
		echo "Expected: $PERM_SSH_DIR, fixing automatically..." >&2
		chmod "$PERM_SSH_DIR" "$ssh_dir"
		echo -e "${GREEN}[FIXED] SSH directory permissions set to $PERM_SSH_DIR${NC}"
	fi
}

validate_private_key_permissions() {
	local key_path="$1"
	local key_name="$2"
	local key_perms
	key_perms=$(stat -c "%a" "$key_path" 2>/dev/null || echo "")

	if [ "$key_perms" != "$PERM_PRIVATE_KEY_RW" ] && [ "$key_perms" != "$PERM_PRIVATE_KEY_RO" ]; then
		echo -e "${RED}[ERROR] Insecure permissions on $key_name: $key_perms${NC}" >&2
		echo "Expected: $PERM_PRIVATE_KEY_RW (read/write for owner only) or $PERM_PRIVATE_KEY_RO (read-only for owner)" >&2
		echo "Fix with: chmod $PERM_PRIVATE_KEY_RW <key-path>" >&2
		exit 1
	fi
}

validate_key_content() {
	local key_path="$1"
	local key_name="$2"

	if ! ssh-keygen -l -f "$key_path" >/dev/null 2>&1; then
		echo -e "${RED}[ERROR] Invalid or corrupt $key_name${NC}" >&2
		echo "Regenerate with: ssh-keygen -t ed25519 -f <key-path> -C 'description'" >&2
		exit 1
	fi
}

validate_public_key_exists() {
	local key_path="$1"
	local key_name="$2"
	local pub_key_path="${key_path}.pub"

	if [ ! -f "$pub_key_path" ]; then
		echo -e "${RED}[ERROR] Public key missing for $key_name${NC}" >&2
		echo "Regenerate keypair with: ssh-keygen -t ed25519 -f <key-path> -C 'description'" >&2
		exit 1
	fi

	# Validate public key content format
	if ! ssh-keygen -l -f "$pub_key_path" >/dev/null 2>&1; then
		echo -e "${RED}[ERROR] Invalid or corrupt public key for $key_name${NC}" >&2
		echo "Regenerate keypair with: ssh-keygen -t ed25519 -f <key-path> -C 'description'" >&2
		exit 1
	fi
}

#####################################
# SECTION 2: DOTFILES PATH VALIDATION
#####################################

validate_dotfiles_path_exists() {
	local path="$1"

	if [ ! -e "$path" ]; then
		echo -e "${RED}[ERROR] Dotfiles path does not exist: $path${NC}" >&2
		exit 1
	fi

	if [ ! -d "$path" ]; then
		echo -e "${RED}[ERROR] Dotfiles path is not a directory: $path${NC}" >&2
		exit 1
	fi
}

validate_dotfiles_no_symlinks() {
	local path="$1"

	# CVE-1: Symlink detection (CVSS 9.3)
	# Check if the path itself is a symlink
	if [ -L "$path" ]; then
		echo -e "${RED}[ERROR] Dotfiles path is a symlink (security risk)${NC}" >&2
		echo "Symlink attacks could redirect to sensitive system directories." >&2
		exit 1
	fi

	# Check if any component in the path is a symlink
	local current_path=""
	IFS='/' read -ra PARTS <<<"$path"
	for part in "${PARTS[@]}"; do
		if [ -n "$part" ]; then
			current_path="${current_path}/${part}"
			if [ -L "$current_path" ]; then
				echo -e "${RED}[ERROR] Dotfiles path contains symlink component: $current_path${NC}" >&2
				echo "Symlink attacks could redirect to sensitive system directories." >&2
				exit 1
			fi
		fi
	done

	# SEC-004: Recursive symlink detection (CVSS 5.5)
	# Check for symlinked files within the directory
	if find "$path" -type l -print -quit 2>/dev/null | grep -q .; then
		echo -e "${RED}[ERROR] Symlinked files detected in dotfiles directory${NC}" >&2
		echo "The following symlinks were found:" >&2
		find "$path" -type l 2>/dev/null >&2
		echo "Symlinks within dotfiles could redirect to malicious files." >&2
		exit 1
	fi
}

validate_dotfiles_canonical_path() {
	local path="$1"

	# SEC-001: TOCTOU race condition prevention (CVSS 6.8)
	# This check is intentionally DUPLICATED after validate_dotfiles_no_symlinks
	# to catch race conditions where the directory is replaced with a symlink
	# between the initial validation and the time we use it.
	#
	# Attack scenario prevented:
	# 1. Initial check: /path/to/dotfiles is a directory (PASS)
	# 2. Attacker replaces: /path/to/dotfiles -> /etc/passwd (symlink)
	# 3. This check detects replacement: FAIL
	if [ -L "$path" ]; then
		echo -e "${RED}[ERROR] Path is a symlink (TOCTOU protection)${NC}" >&2
		echo "Path may have been replaced after initial validation." >&2
		echo "This prevents time-of-check-time-of-use race conditions." >&2
		exit 1
	fi

	# Additional canonical path check using realpath if available
	if command -v realpath >/dev/null 2>&1; then
		local canonical_path
		canonical_path=$(realpath --no-symlinks "$path" 2>/dev/null)

		if [ -z "$canonical_path" ]; then
			echo -e "${RED}[ERROR] Unable to resolve canonical path${NC}" >&2
			exit 1
		fi

		if [ "$canonical_path" != "$path" ]; then
			echo -e "${RED}[ERROR] Path contains symlink component (TOCTOU protection)${NC}" >&2
			echo "Expected: $path" >&2
			echo "Canonical: $canonical_path" >&2
			echo "This prevents time-of-check-time-of-use race conditions." >&2
			exit 1
		fi
	fi
}

validate_dotfiles_no_shell_injection() {
	local path="$1"

	# CVE-3: Shell injection prevention (CVSS 7.8)
	# SEC-003: Comprehensive metacharacter coverage (CVSS 7.0)
	# Block ALL metacharacters and control chars
	# Pattern explanation:
	# - [;\&|`$()<>{}*?#'\"[:space:][:cntrl:]] - most special chars and POSIX classes
	# - \\ - backslash (needs alternation)
	# - \[ - open bracket (needs alternation)
	local pattern='[;\&|`$()<>{}*?#'\''"[:space:][:cntrl:]]|\\|\['
	if [[ "$path" =~ $pattern ]]; then
		echo -e "${RED}[ERROR] Dotfiles path contains prohibited characters (security risk)${NC}" >&2
		echo "Path: $path" >&2
		echo "Allowed characters: alphanumeric, hyphen, underscore, slash, period" >&2
		exit 1
	fi

	# Ensure path is printable ASCII
	if ! [[ "$path" =~ ^[[:print:]]+$ ]]; then
		echo -e "${RED}[ERROR] Dotfiles path contains non-printable characters (security risk)${NC}" >&2
		echo "Path must contain only printable ASCII characters" >&2
		exit 1
	fi
}

validate_dotfiles_git_repo() {
	local path="$1"

	# BUG-006: Git repository validation
	if [ -d "$path/.git" ]; then
		if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
			echo -e "${RED}[ERROR] Invalid git repository in dotfiles path${NC}" >&2
			exit 1
		fi
	fi
}

#####################################
# SECTION 3: install.sh VALIDATION
#####################################

validate_install_sh() {
	local path="$1"
	local install_script="$path/install.sh"

	if [ ! -f "$install_script" ]; then
		echo -e "${YELLOW}[WARNING] install.sh not found in dotfiles directory${NC}"
		read -p "Continue without install.sh? [y/N] " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			exit 1
		fi
		return 0
	fi

	# SEC-005: Permission validation (CVSS 4.0)
	# Check for world-writable or group-writable permissions
	local perms
	perms=$(stat -c "%a" "$install_script" 2>/dev/null || echo "000")

	# Check world-writable bit (002)
	if [ $((8#$perms & $PERM_WORLD_WRITABLE_BIT)) -ne 0 ]; then
		echo -e "${RED}[ERROR] install.sh is world-writable (insecure permissions)${NC}" >&2
		echo "Permissions: $perms" >&2
		echo "Fix with: chmod 644 $install_script" >&2
		exit 1
	fi

	# Check group-writable bit (020)
	if [ $((8#$perms & $PERM_GROUP_WRITABLE_BIT)) -ne 0 ]; then
		echo -e "${RED}[ERROR] install.sh is group-writable (insecure permissions)${NC}" >&2
		echo "Permissions: $perms" >&2
		echo "Fix with: chmod 644 $install_script" >&2
		exit 1
	fi

	# CVE-2: install.sh content inspection (CVSS 9.0)
	# SEC-002: Expanded patterns to prevent evasion (CVSS 7.5)
	# Issue #103: Pragma-based allowlist for documentation/help text
	#
	# Pragma Format: # pragma: allowlist PATTERN-ID
	# Example: echo "Install: curl url | sh"  # pragma: allowlist RCE-001
	#
	# Use Cases:
	# - Documentation showing dangerous commands (without executing them)
	# - Help text explaining security risks
	# - Installation instructions in comments
	#
	# Security: Each pragma is logged for audit trail
	local dangerous_patterns=(
		# === DESTRUCTIVE COMMANDS ===
		"rm.*-rf.*/"
		"rm -rf /"
		"dd if="
		"mkfs\."
		"> ?/dev/sd"

		# === REMOTE CODE EXECUTION ===
		"curl.*\|.*(bash|sh)"
		"wget.*\|.*(bash|sh)"
		"eval"
		"exec"
		"source.*http"
		"\\. .*http"

		# === PRIVILEGE ESCALATION ===
		":/bin/(ba)?sh"
		"chown.*root"
		"chmod.*[67][0-9][0-9]"
		"sudo"
		"su "

		# === OBFUSCATION INDICATORS ===
		"\\\\x[0-9a-f]{2}"
		"base64.*-d.*\|"
		"xxd"
		"\\\${IFS}"
		# Issue #103: Removed overly-broad \$[A-Z_]+.*\$[A-Z_]+ pattern
		# Reason: Catches legitimate shell code (for loops, path construction)
		# Security: Direct RCE still caught by curl.*\|.*(bash|sh), eval, exec patterns
		# Note: Variable-based command construction with pipes already caught by existing patterns

		# === NETWORK ACCESS ===
		"nc "
		"netcat"
		"socat"
		"/dev/tcp/"

		# === SYSTEM MODIFICATION ===
		"iptables"
		"ufw "
		"systemctl"
		"service "

		# === CRYPTO MINING ===
		"xmrig"
		"miner"
		"stratum"
	)

	for pattern in "${dangerous_patterns[@]}"; do
		while IFS= read -r matched_line; do
			# Issue #103: Check for pragma allowlist comment
			# Format: # pragma: allowlist PATTERN-ID
			# Allows documentation/help text containing dangerous patterns
			if echo "$matched_line" | grep -qE '#[[:space:]]*pragma:[[:space:]]*allowlist[[:space:]]+[A-Za-z0-9_-]+'; then
				local pragma_id
				pragma_id=$(echo "$matched_line" | grep -oE '#[[:space:]]*pragma:[[:space:]]*allowlist[[:space:]]+[A-Za-z0-9_-]+' | awk '{print $NF}')
				echo -e "${YELLOW}[INFO] Pattern allowed by pragma: $pragma_id${NC}" >&2
				continue # Skip this match, pragma explicitly allows it
			fi

			echo -e "${RED}[ERROR] Dangerous pattern detected in install.sh${NC}" >&2
			echo "Pattern: $pattern" >&2
			echo "Matched line: ${matched_line:0:100}" >&2
			echo "For security, cannot proceed with potentially malicious install script." >&2
			exit 1
		done < <(grep -E "$pattern" "$install_script" 2>/dev/null || true)
	done

	# SEC-006: Whitelist validation (CVSS 5.0)
	# Add whitelist validation as second layer after blacklist
	# Whitelisted commands are common dotfiles operations
	local safe_pattern="^(#|$|[[:space:]]*(ln|cp|mv|mkdir|echo|cat|grep|sed|awk|printf|test|\\[|chmod|chown|git|stow))"

	local unsafe_lines=0
	while IFS= read -r line; do
		# Skip comments
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		# Skip empty lines
		[[ -z "$line" ]] && continue

		# Check if line matches safe pattern
		if ! [[ "$line" =~ $safe_pattern ]]; then
			echo -e "${YELLOW}[WARNING] Potentially unsafe command: $line${NC}" >&2
			((unsafe_lines++))
		fi
	done <"$install_script"

	# Interactive confirmation if unsafe lines detected
	if [ "$unsafe_lines" -gt 0 ]; then
		echo "" >&2
		echo -e "${YELLOW}[WARNING] install.sh contains $unsafe_lines potentially unsafe command(s)${NC}" >&2
		echo "Commands outside the whitelist may indicate security risks." >&2
		echo "Whitelisted commands: ln, cp, mv, mkdir, echo, cat, grep, sed, awk, printf, test, [, chmod, chown, git, stow" >&2
		echo "" >&2
		read -p "Continue anyway? [y/N] " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			exit 1
		fi
	fi
}

#####################################
# SECTION 4: COMPOSITE VALIDATION
#####################################

validate_and_prepare_dotfiles_path() {
	local path="$1"

	# Expand tilde
	path="${path/#\~/$HOME}"

	# Convert to absolute path (BUG-003: handles spaces correctly)
	if [[ "$path" != /* ]]; then
		path="$(cd "$path" && pwd)"
	fi

	# Security validations
	validate_dotfiles_path_exists "$path"
	validate_dotfiles_no_symlinks "$path"
	validate_dotfiles_canonical_path "$path"
	validate_dotfiles_no_shell_injection "$path"
	validate_dotfiles_git_repo "$path"
	validate_install_sh "$path"

	echo "$path"
}
