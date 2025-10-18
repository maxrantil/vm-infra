#!/bin/bash
# ABOUTME: Creates cloud-init ISO manually to bypass libvirt provider UUID issue

set -e

VM_NAME="$1"
SSH_KEY="$2"

if [ -z "$VM_NAME" ] || [ -z "$SSH_KEY" ]; then
    echo "Usage: $0 <vm-name> <ssh-public-key>" >&2
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
    local temp_keyfile
    temp_keyfile=$(mktemp)
    echo "$key" > "$temp_keyfile"

    # Use ssh-keygen to validate the key format
    if ! ssh-keygen -l -f "$temp_keyfile" &>/dev/null; then
        rm -f "$temp_keyfile"
        echo "ERROR: Invalid SSH public key format" >&2
        return 1
    fi

    rm -f "$temp_keyfile"
    return 0
}

# Validate SSH key before proceeding
if ! validate_ssh_key "$SSH_KEY"; then
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

hostname: ubuntu-vm
fqdn: ubuntu-vm.local

# Create user
users:
  - name: mr
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

# HRI-001 FIX: Use sed to safely substitute SSH key (prevents command injection)
sed -i "s|SSH_KEY_PLACEHOLDER|$SSH_KEY|g" "$TEMP_DIR/user-data"

# Create meta-data with quoted heredoc
cat > "$TEMP_DIR/meta-data" << 'EOF'
instance-id: VM_NAME_PLACEHOLDER
local-hostname: VM_NAME_PLACEHOLDER
EOF

# HRI-001 FIX: Use sed to safely substitute VM name
sed -i "s|VM_NAME_PLACEHOLDER|$VM_NAME|g" "$TEMP_DIR/meta-data"

# Create ISO
ISO_PATH="/var/lib/libvirt/images/${VM_NAME}-cloudinit.iso"
genisoimage -output "$ISO_PATH" -volid cidata -joliet -rock "$TEMP_DIR/user-data" "$TEMP_DIR/meta-data" 2>/dev/null

# HRI-003 FIX: Set secure permissions (640) and ownership (root:libvirt)
chmod 640 "$ISO_PATH"
chown root:libvirt "$ISO_PATH"

echo "$ISO_PATH"
