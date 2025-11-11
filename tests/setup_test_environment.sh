#!/usr/bin/env bash
# ABOUTME: Automated test environment setup and validation for integration tests

set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MIN_DISK_SPACE_GB=10
REQUIRED_PACKAGES=(
	"genisoimage"
	"terraform"
	"ansible"
)

# Flags
CHECK_ONLY=0

# Parse arguments
parse_args() {
	while [[ $# -gt 0 ]]; do
		case $1 in
		--check)
			CHECK_ONLY=1
			shift
			;;
		-h | --help)
			show_help
			exit 0
			;;
		*)
			echo -e "${RED}Unknown option: $1${NC}"
			show_help
			exit 1
			;;
		esac
	done
}

show_help() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Automated test environment setup and validation for integration tests.

Options:
    --check         Check environment without making changes (dry-run)
    -h, --help      Show this help message

Functions:
    check_libvirt              Verify libvirt/KVM installed and running
    check_disk_space           Ensure sufficient disk space for test VMs
    install_test_dependencies  Install required test packages
    validate_ssh_keys          Ensure ~/.ssh/vm_key exists

Example:
    # Check environment status
    ./setup_test_environment.sh --check

    # Setup environment (install missing dependencies)
    ./setup_test_environment.sh
EOF
}

# Check if libvirt/KVM is available
check_libvirt() {
	echo -e "\n${BLUE}==> Checking libvirt/KVM...${NC}"

	# Check if virsh command exists
	if ! command -v virsh &>/dev/null; then
		echo -e "${RED}✗ virsh not found${NC}"
		echo -e "  Install with: sudo apt-get install libvirt-clients libvirt-daemon-system"
		return 1
	fi

	echo -e "${GREEN}✓ virsh found${NC}"

	# Check if libvirtd service is running
	if ! systemctl is-active --quiet libvirtd; then
		echo -e "${YELLOW}⚠ libvirtd service not running${NC}"
		if [[ $CHECK_ONLY -eq 0 ]]; then
			echo -e "  Attempting to start libvirtd..."
			if sudo systemctl start libvirtd; then
				echo -e "${GREEN}✓ libvirtd started${NC}"
			else
				echo -e "${RED}✗ Failed to start libvirtd${NC}"
				return 1
			fi
		else
			echo -e "  Run: sudo systemctl start libvirtd"
			return 1
		fi
	else
		echo -e "${GREEN}✓ libvirtd is running${NC}"
	fi

	# Check if user can access libvirt
	if ! virsh list --all &>/dev/null; then
		echo -e "${YELLOW}⚠ Cannot access libvirt (permission issue)${NC}"
		echo -e "  Add user to libvirt group: sudo usermod -aG libvirt \$USER"
		echo -e "  Then log out and back in"
		return 1
	fi

	echo -e "${GREEN}✓ libvirt/KVM accessible${NC}"
	return 0
}

# Check available disk space
check_disk_space() {
	echo -e "\n${BLUE}==> Checking disk space...${NC}"

	local available_gb
	available_gb=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')

	echo -e "  Available: ${available_gb}GB"
	echo -e "  Required:  ${MIN_DISK_SPACE_GB}GB"

	if [[ $available_gb -lt $MIN_DISK_SPACE_GB ]]; then
		echo -e "${RED}✗ Insufficient disk space${NC}"
		echo -e "  Need at least ${MIN_DISK_SPACE_GB}GB for test VMs"
		return 1
	fi

	echo -e "${GREEN}✓ Sufficient disk space available${NC}"
	return 0
}

# Install test dependencies
install_test_dependencies() {
	echo -e "\n${BLUE}==> Checking test dependencies...${NC}"

	local missing_packages=()

	for package in "${REQUIRED_PACKAGES[@]}"; do
		if ! command -v "$package" &>/dev/null; then
			missing_packages+=("$package")
			echo -e "${YELLOW}⚠ $package not found${NC}"
		else
			echo -e "${GREEN}✓ $package found${NC}"
		fi
	done

	if [[ ${#missing_packages[@]} -eq 0 ]]; then
		echo -e "${GREEN}✓ All test dependencies installed${NC}"
		return 0
	fi

	if [[ $CHECK_ONLY -eq 1 ]]; then
		echo -e "${YELLOW}Missing packages: ${missing_packages[*]}${NC}"
		echo -e "  Install with: sudo apt-get install ${missing_packages[*]}"
		return 1
	fi

	echo -e "${BLUE}Installing missing packages: ${missing_packages[*]}${NC}"
	if sudo apt-get update && sudo apt-get install -y "${missing_packages[@]}"; then
		echo -e "${GREEN}✓ Test dependencies installed${NC}"
		return 0
	else
		echo -e "${RED}✗ Failed to install dependencies${NC}"
		return 1
	fi
}

# Validate SSH keys exist
validate_ssh_keys() {
	echo -e "\n${BLUE}==> Checking SSH keys...${NC}"

	local ssh_key="$HOME/.ssh/vm_key"

	if [[ ! -f "$ssh_key" ]]; then
		echo -e "${YELLOW}⚠ SSH key not found: $ssh_key${NC}"

		if [[ $CHECK_ONLY -eq 1 ]]; then
			echo -e "  Generate with: ssh-keygen -t ed25519 -f $ssh_key -N ''"
			return 1
		fi

		echo -e "${BLUE}Generating SSH key...${NC}"
		mkdir -p "$HOME/.ssh"
		if ssh-keygen -t ed25519 -f "$ssh_key" -N '' -C "vm-test-key"; then
			echo -e "${GREEN}✓ SSH key generated${NC}"
		else
			echo -e "${RED}✗ Failed to generate SSH key${NC}"
			return 1
		fi
	else
		echo -e "${GREEN}✓ SSH key exists${NC}"
	fi

	# Check key permissions
	local perms
	perms=$(stat -c "%a" "$ssh_key")
	if [[ "$perms" != "600" ]]; then
		echo -e "${YELLOW}⚠ Incorrect SSH key permissions: $perms (should be 600)${NC}"
		if [[ $CHECK_ONLY -eq 0 ]]; then
			chmod 600 "$ssh_key"
			echo -e "${GREEN}✓ SSH key permissions fixed${NC}"
		else
			echo -e "  Fix with: chmod 600 $ssh_key"
			return 1
		fi
	else
		echo -e "${GREEN}✓ SSH key permissions correct${NC}"
	fi

	return 0
}

# Main execution
main() {
	parse_args "$@"

	echo "=========================================="
	echo "Test Environment Setup"
	echo "=========================================="

	if [[ $CHECK_ONLY -eq 1 ]]; then
		echo -e "${BLUE}Running in check-only mode (no changes will be made)${NC}"
	fi

	local failures=0

	check_libvirt || ((++failures))
	check_disk_space || ((++failures))
	install_test_dependencies || ((++failures))
	validate_ssh_keys || ((++failures))

	echo ""
	echo "=========================================="
	echo "Summary"
	echo "=========================================="

	if [[ $failures -eq 0 ]]; then
		echo -e "${GREEN}✓ Test environment ready!${NC}"
		echo ""
		echo "You can now run integration tests:"
		echo "  ./tests/test_rollback_integration.sh"
		echo "  ./tests/test_rollback_e2e.sh"
		exit 0
	else
		echo -e "${RED}✗ Test environment not ready ($failures checks failed)${NC}"
		echo ""
		if [[ $CHECK_ONLY -eq 1 ]]; then
			echo "Re-run without --check to automatically fix issues:"
			echo "  ./tests/setup_test_environment.sh"
		else
			echo "Please resolve the issues above before running integration tests."
		fi
		exit 1
	fi
}

main "$@"
