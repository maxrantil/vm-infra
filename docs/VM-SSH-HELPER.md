# VM SSH Helper Script

**File:** `vm-ssh.sh`
**Purpose:** One-command VM startup and SSH connection
**Created:** 2025-11-12

---

## Overview

The `vm-ssh.sh` helper script simplifies VM access by handling startup and SSH connection in a single command. It automatically:
- ✅ Checks if VM exists
- ✅ Starts VM if shut off
- ✅ Waits for network initialization
- ✅ Verifies SSH connectivity
- ✅ Connects via SSH

---

## Usage

### Basic Usage

```bash
# Connect to VM (starts if needed)
./vm-ssh.sh work-vm-1
```

### List Available VMs

```bash
# Show all VMs without connecting
./vm-ssh.sh
```

**Output:**
```
Available VMs:
  ● work-vm-1 (running)
  ○ work-vm-2 (shut off)
  ○ work-vm-3 (shut off)
```

**Legend:**
- **Green ●** = Running VM
- **Yellow ○** = Shut off VM

---

## Features

### 1. Automatic VM Startup

```bash
# VM is shut off
$ sudo virsh list --all
 -    work-vm-1   shut off

# Script automatically starts it
$ ./vm-ssh.sh work-vm-1
VM 'work-vm-1' is shut off, starting...
[OK] VM started successfully
Waiting for network initialization...
Getting IP address...
[OK] IP address: 192.168.122.110
Testing SSH connectivity...
[OK] SSH connectivity verified
========================================
Connecting to work-vm-1 at 192.168.122.110
========================================
```

### 2. Smart IP Discovery

The script automatically finds the VM's IP address with retry logic:
- Queries libvirt for IP (10 attempts, 2-second intervals)
- Handles "pending" state during boot
- Reports IP clearly before connecting

### 3. Cloud-init Wait

If SSH isn't immediately available, the script:
- Waits for cloud-init to complete (up to 60 seconds)
- Shows progress messages
- Verifies SSH works before connecting

### 4. Error Handling

**VM Not Found:**
```bash
$ ./vm-ssh.sh nonexistent-vm
[ERROR] VM 'nonexistent-vm' not found

Available VMs:
  ● work-vm-1 (running)
```

**IP Address Failed:**
```bash
[ERROR] Could not get IP address for 'work-vm-1'

The VM may still be booting. Troubleshooting:
  1. Wait longer and retry: ./vm-ssh.sh work-vm-1
  2. Check VM console: sudo virsh console work-vm-1
  3. Check VM status: sudo virsh list --all
```

**SSH Connection Failed:**
```bash
[ERROR] SSH connection failed

The VM is running but SSH is not responding. Troubleshooting:
  1. Wait longer: cloud-init may still be running
  2. Check VM console: sudo virsh console work-vm-1
  3. Try manual SSH: ssh -i ~/.ssh/vm_key mr@192.168.122.110
```

---

## Workflow Examples

### Example 1: Morning Routine

```bash
# Start work VM and connect (one command)
./vm-ssh.sh work-vm-1

# Inside VM: do your work
cd ~/project
git pull
# ... work on code ...
git push
exit

# Back on host: VM still running for next session
```

### Example 2: Switch Projects

```bash
# Morning: work on django project
./vm-ssh.sh work-vm-1
# ... work ...
exit

# Afternoon: switch to ansible project
./vm-ssh.sh work-vm-2
# ... work ...
exit

# VMs stay running until you shut them down
```

### Example 3: Fresh Start

```bash
# Shut down VM to free resources
sudo virsh shutdown work-vm-1

# Later: script automatically restarts it
./vm-ssh.sh work-vm-1
# VM starts → waits for network → connects ✅
```

---

## Advanced Usage

### Create Shell Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Quick VM access
alias vm1='~/workspace/vm-infra/vm-ssh.sh work-vm-1'
alias vm2='~/workspace/vm-infra/vm-ssh.sh work-vm-2'
alias vm3='~/workspace/vm-infra/vm-ssh.sh work-vm-3'

# VM management
alias vms='sudo virsh list --all'
alias vmstop='sudo virsh shutdown'
```

**After reloading shell:**
```bash
vm1    # Connect to work-vm-1 (starts if needed)
vm2    # Connect to work-vm-2 (starts if needed)
vms    # List all VMs
```

### Script in PATH

```bash
# Option 1: Add vm-infra to PATH
echo 'export PATH="$HOME/workspace/vm-infra:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Now use from anywhere
vm-ssh.sh work-vm-1

# Option 2: Symlink to ~/bin
mkdir -p ~/bin
ln -s ~/workspace/vm-infra/vm-ssh.sh ~/bin/vm-ssh
export PATH="$HOME/bin:$PATH"

# Use shorter command
vm-ssh work-vm-1
```

---

## Comparison with Manual Workflow

### Manual Approach (6 commands)
```bash
sudo virsh list --all               # Check status
sudo virsh start work-vm-1          # Start if needed
sleep 5                             # Wait for network
sudo virsh domifaddr work-vm-1      # Get IP
# Copy IP from output
ssh -i ~/.ssh/vm_key mr@192.168.122.110  # Connect
```

### With vm-ssh.sh (1 command)
```bash
./vm-ssh.sh work-vm-1
```

**Time saved:** ~30-60 seconds per connection
**Mental overhead:** Eliminated (no IP copying, no status checking)

---

## Troubleshooting

### Script Hangs on "Getting IP address..."

**Cause:** VM is booting slowly or network not initialized

**Solution:**
```bash
# Wait up to 20 seconds (script retries automatically)
# If still hanging, press Ctrl+C and check VM manually:
sudo virsh console work-vm-1
# Check cloud-init status inside VM
```

### Script Shows "SSH not ready yet" for Long Time

**Cause:** Cloud-init is still configuring the VM

**Solution:**
- Script waits automatically (up to 60 seconds)
- If it times out, wait a bit longer and retry:
  ```bash
  ./vm-ssh.sh work-vm-1
  ```

### "Permission Denied" Error

**Cause:** Missing sudo privileges for `virsh start`

**Solution:**
- Script uses `sudo` automatically
- Enter your password when prompted
- For passwordless sudo (optional):
  ```bash
  # Add to /etc/sudoers.d/libvirt
  your-username ALL=(ALL) NOPASSWD: /usr/bin/virsh
  ```

---

## Technical Details

### Script Flow

```
1. Validate VM name provided
   ├─ No → Show usage + list VMs → Exit
   └─ Yes → Continue

2. Check VM exists
   ├─ No → Show error + list VMs → Exit
   └─ Yes → Continue

3. Get VM state (running/shut off)
   ├─ Shut off → sudo virsh start
   │             Wait 5 seconds for network
   └─ Running → Continue

4. Get IP address (retry 10x with 2s interval)
   ├─ Success → Continue
   └─ Timeout → Show error + troubleshooting → Exit

5. Test SSH connectivity
   ├─ Success → Continue
   └─ Fail → Wait for cloud-init (30x with 2s interval)
               ├─ Success → Continue
               └─ Timeout → Show error → Exit

6. SSH connect
   └─ ssh -i ~/.ssh/vm_key mr@<IP>
```

### Color Coding

- **Red:** Errors and failures
- **Green:** Success messages and running VMs
- **Yellow:** Warnings and shut-off VMs
- **Blue:** Informational headers

### Timeouts

- **Network initialization:** 5 seconds (after VM start)
- **IP address discovery:** 20 seconds (10 retries × 2s)
- **Cloud-init wait:** 60 seconds (30 retries × 2s)
- **SSH connection test:** 5 seconds per attempt

---

## Integration with Multi-VM Workflow

### Recommended Setup (5 Work VMs)

```bash
# Provision VMs once
for i in {1..5}; do
    SKIP_WHITELIST_CHECK=1 ./provision-vm.sh work-vm-$i 4096 2 \
        --test-dotfiles /home/mqx/workspace/dotfiles
done

# Create aliases for quick access
cat >> ~/.bashrc << 'EOF'
# VM quick access
alias vm1='~/workspace/vm-infra/vm-ssh.sh work-vm-1'
alias vm2='~/workspace/vm-infra/vm-ssh.sh work-vm-2'
alias vm3='~/workspace/vm-infra/vm-ssh.sh work-vm-3'
alias vm4='~/workspace/vm-infra/vm-ssh.sh work-vm-4'
alias vm5='~/workspace/vm-infra/vm-ssh.sh work-vm-5'
EOF

source ~/.bashrc

# Daily usage
vm1  # Work on project 1 (django)
vm2  # Work on project 2 (ansible)
vm3  # Work on project 3 (pytest)
```

---

## Maintenance

### Update Script

```bash
# Script is version-controlled
cd ~/workspace/vm-infra
git pull

# Verify script is executable
ls -la vm-ssh.sh
# Should show: -rwxr-xr-x

# If not executable:
chmod +x vm-ssh.sh
```

### Customize Behavior

Edit `vm-ssh.sh` to adjust:
- **Line 73:** Network wait time (default: 5 seconds)
- **Line 79:** IP retry attempts (default: 10)
- **Line 92:** Cloud-init timeout (default: 30 attempts)
- **Line 148:** SSH command (default: `ssh -i ~/.ssh/vm_key mr@<IP>`)

---

## Security Considerations

### SSH Key Handling

- Script uses `~/.ssh/vm_key` (hard-coded)
- SSH options: `StrictHostKeyChecking=no` (convenience for local VMs)
- Key permissions verified by provision-vm.sh at VM creation

### Sudo Usage

- Script requires `sudo` for `virsh start` and `virsh domifaddr`
- No privilege escalation vulnerabilities (no user input to sudo commands)
- VM names validated against `virsh list` output before use

### Network Exposure

- VMs accessible only from host machine (192.168.122.0/24 NAT network)
- No external network exposure
- SSH keys provide authentication, no password auth

---

## Summary

**vm-ssh.sh provides:**
- ✅ One-command VM access (start + connect)
- ✅ Automatic VM startup handling
- ✅ Smart IP discovery with retry
- ✅ SSH readiness verification
- ✅ Clear error messages and troubleshooting
- ✅ Color-coded output for quick status parsing
- ✅ Integration with multi-VM workflows

**Time savings:** ~30-60 seconds per VM connection
**Complexity reduction:** 6 manual commands → 1 script command
**User experience:** Seamless VM access, no mental overhead

---

**Related Documentation:**
- `README.md` - Main project documentation
- `docs/MULTI-VM-WORKFLOW.md` - Multi-VM setup guide
- `provision-vm.sh` - VM provisioning script
- `destroy-vm.sh` - VM removal script
