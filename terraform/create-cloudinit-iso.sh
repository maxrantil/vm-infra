#!/bin/bash
# ABOUTME: Creates cloud-init ISO manually to bypass libvirt provider UUID issue

set -e

VM_NAME="$1"
VM_USERNAME="$2"
SSH_KEY="$3"

if [ -z "$VM_NAME" ] || [ -z "$VM_USERNAME" ] || [ -z "$SSH_KEY" ]; then
    echo "Usage: $0 <vm-name> <username> <ssh-public-key>" >&2
    exit 1
fi

# HRI-002: Validate SSH public key format
validate_ssh_key() {
    local key="$1"

    # Check if key is empty
    if [ -z "$key" ]; then
        echo "ERROR: SSH key cannot be empty" >&2
        return 1
    fi

    # Create temporary file for validation
    # MRI-001 FIX: Set secure permissions immediately to prevent TOCTOU
    local temp_keyfile
    temp_keyfile=$(mktemp)
    chmod 600 "$temp_keyfile"
    echo "$key" > "$temp_keyfile"

    # Use ssh-keygen to validate the key format
    if ! ssh-keygen -l -f "$temp_keyfile" &> /dev/null; then
        rm -f "$temp_keyfile"
        echo "ERROR: Invalid SSH public key format" >&2
        return 1
    fi

    rm -f "$temp_keyfile"
    return 0
}

# Validate username
validate_username() {
    local username="$1"

    # Reserved usernames
    local reserved_names=(
        "root" "daemon" "bin" "sys" "sync" "games" "man" "lp"
        "mail" "news" "uucp" "proxy" "www-data" "backup" "list"
        "irc" "gnats" "nobody" "systemd-network" "systemd-resolve"
        "messagebus" "systemd-timesync" "syslog" "admin" "ubuntu"
    )

    # Check if username is empty
    if [ -z "$username" ]; then
        echo "ERROR: Username cannot be empty" >&2
        return 1
    fi

    # Check length (1-32 characters)
    if [ ${#username} -gt 32 ]; then
        echo "ERROR: Username too long: $username (max 32 characters)" >&2
        return 1
    fi

    # Check for valid characters (lowercase letters, digits, underscore, hyphen)
    # Must start with lowercase letter
    if ! [[ "$username" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        echo "ERROR: Invalid username: $username" >&2
        echo "Username must:" >&2
        echo "  - Start with a lowercase letter" >&2
        echo "  - Contain only lowercase letters, digits, underscores, and hyphens" >&2
        echo "  - Be 1-32 characters long" >&2
        return 1
    fi

    # Check reserved names
    for reserved in "${reserved_names[@]}"; do
        if [ "$username" = "$reserved" ]; then
            echo "ERROR: Reserved username: $username" >&2
            echo "This username is reserved by the system and cannot be used." >&2
            return 1
        fi
    done

    return 0
}

# Validate SSH key before proceeding
if ! validate_ssh_key "$SSH_KEY"; then
    exit 1
fi

# Validate username before proceeding
if ! validate_username "$VM_USERNAME"; then
    exit 1
fi

# Strip trailing whitespace/newlines from SSH key for sed substitution
SSH_KEY=$(echo "$SSH_KEY" | tr -d '\n' | sed 's/[[:space:]]*$//')

# HRI-001: Validate VM name (prevent path traversal and command injection)
if [[ "$VM_NAME" =~ [^a-zA-Z0-9._-] ]]; then
    echo "ERROR: VM name contains invalid characters. Use only alphanumeric, dots, underscores, and hyphens." >&2
    exit 1
fi

# Create temporary directory for cloud-init files
TEMP_DIR=$(mktemp -d)
# HRI-001 FIX: Quote variable in trap to prevent command injection
trap 'rm -rf "$TEMP_DIR"' EXIT

# Create user-data with template file to avoid variable expansion issues
# HRI-001 FIX: Use quoted heredoc and sed substitution instead of variable expansion
cat > "$TEMP_DIR/user-data" << 'EOF'
#cloud-config

# Explicit NoCloud datasource prevents waiting for cloud metadata (AWS/Azure/etc)
datasource_list: [ NoCloud, None ]
datasource:
  NoCloud:
    seedfrom: /dev/sr0  # Cloud-init ISO device

hostname: HOSTNAME_PLACEHOLDER
fqdn: HOSTNAME_PLACEHOLDER.local

# Create user
users:
  - name: USERNAME_PLACEHOLDER
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - SSH_KEY_PLACEHOLDER

# Set timezone
timezone: UTC

# Enable SSH
ssh_pwauth: false
disable_root: true
EOF

# HRI-001 FIX: Use sed to safely substitute values (prevents command injection)
sed -i "s|SSH_KEY_PLACEHOLDER|$SSH_KEY|g" "$TEMP_DIR/user-data"
sed -i "s|USERNAME_PLACEHOLDER|$VM_USERNAME|g" "$TEMP_DIR/user-data"
sed -i "s|HOSTNAME_PLACEHOLDER|$VM_NAME|g" "$TEMP_DIR/user-data"

# Create meta-data with quoted heredoc
cat > "$TEMP_DIR/meta-data" << 'EOF'
instance-id: VM_NAME_PLACEHOLDER
local-hostname: VM_NAME_PLACEHOLDER
EOF

# HRI-001 FIX: Use sed to safely substitute VM name
sed -i "s|VM_NAME_PLACEHOLDER|$VM_NAME|g" "$TEMP_DIR/meta-data"

# Create ISO
ISO_PATH="/var/lib/libvirt/images/${VM_NAME}-cloudinit.iso"

# MV-001 FIX: Validate genisoimage success and file creation
if ! genisoimage -output "$ISO_PATH" -volid cidata -joliet -rock "$TEMP_DIR/user-data" "$TEMP_DIR/meta-data" 2> /dev/null; then
    echo "ERROR: Failed to create ISO with genisoimage" >&2
    exit 1
fi

if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO file not created at $ISO_PATH" >&2
    exit 1
fi

# HRI-003 FIX: Set secure permissions (640) and ownership (root:libvirt)
# MRI-002 FIX: Validate privileged operations succeed (fail-secure)
if ! chmod 640 "$ISO_PATH"; then
    echo "ERROR: Failed to set ISO permissions to 640" >&2
    exit 1
fi

if ! chown root:libvirt "$ISO_PATH"; then
    echo "ERROR: Failed to set ISO ownership to root:libvirt" >&2
    exit 1
fi

echo "$ISO_PATH"
