# VM Quick Reference Card

**One-page cheat sheet for daily VM operations**

---

## 🚀 Quick Start (Using vm-ssh.sh)

```bash
# Connect to VM (auto-starts if needed)
./vm-ssh.sh work-vm-1

# List available VMs
./vm-ssh.sh

# That's it! Everything else is automatic.
```

---

## 📋 VM Status Commands

```bash
# Show ALL VMs (running + shut off) ⭐ MOST USEFUL
sudo virsh list --all

# Show running VMs only
virsh list

# Detailed VM info
sudo virsh dominfo work-vm-1
```

---

## 🌐 Get VM IP Address

```bash
# Method 1: Direct query ⭐ FASTEST
sudo virsh domifaddr work-vm-1

# Method 2: Clean IP only
sudo virsh domifaddr work-vm-1 | awk 'NR==3 {print $4}' | cut -d'/' -f1

# Method 3: From inventory file
cat ansible/inventory.d/work-vm-1.ini | grep "^192" | awk '{print $1}'
```

---

## ⚡ Start/Stop VMs

```bash
# Start shut-off VM
sudo virsh start work-vm-1

# Graceful shutdown (preferred)
sudo virsh shutdown work-vm-1

# Force stop (emergency only)
sudo virsh destroy work-vm-1

# Check status after operation
sudo virsh list --all
```

---

## 🔌 SSH Connection

```bash
# Manual SSH (if not using vm-ssh.sh)
ssh -i ~/.ssh/vm_key mr@192.168.122.110

# Check SSH service status
ssh -i ~/.ssh/vm_key mr@<IP> 'systemctl status sshd'

# Execute command remotely
ssh -i ~/.ssh/vm_key mr@<IP> 'hostname && uptime'
```

---

## 📦 Complete Manual Workflow

```bash
# 1. Check VM status
sudo virsh list --all

# 2. Start if shut off
sudo virsh start work-vm-1

# 3. Wait for network
sleep 5

# 4. Get IP
sudo virsh domifaddr work-vm-1

# 5. Connect
ssh -i ~/.ssh/vm_key mr@<IP>
```

---

## 🔧 Troubleshooting

### VM Not Showing Up?
```bash
sudo virsh list --all    # Use --all flag!
```

### No IP Address?
```bash
sleep 10 && sudo virsh domifaddr work-vm-1
sudo virsh console work-vm-1    # Exit: Ctrl+]
```

### SSH Refused?
```bash
# Wait for cloud-init
ssh -i ~/.ssh/vm_key mr@<IP> 'cloud-init status --wait'
```

### VM Won't Start?
```bash
# Check error details
sudo virsh start work-vm-1
sudo virsh dominfo work-vm-1
```

---

## 📊 Multiple VMs

```bash
# Start multiple VMs
for i in {1..3}; do sudo virsh start work-vm-$i; done

# Get IPs for all work VMs
for i in {1..5}; do
    echo -n "work-vm-$i: "
    sudo virsh domifaddr work-vm-$i | awk 'NR==3 {print $4}' | cut -d'/' -f1
done

# Stop all work VMs
for i in {1..5}; do sudo virsh shutdown work-vm-$i; done
```

---

## ⚙️ Bash Aliases (Recommended)

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# VM management
alias vms='sudo virsh list --all'
alias vmstart='sudo virsh start'
alias vmstop='sudo virsh shutdown'
alias vmip='sudo virsh domifaddr'

# Quick VM access (customize IPs after provisioning)
alias vm1='~/workspace/vm-infra/vm-ssh.sh work-vm-1'
alias vm2='~/workspace/vm-infra/vm-ssh.sh work-vm-2'
alias vm3='~/workspace/vm-infra/vm-ssh.sh work-vm-3'
```

**After adding:** `source ~/.bashrc`

---

## 📁 Project Structure

```
vm-infra/
├── vm-ssh.sh              ← Helper script (use this!)
├── provision-vm.sh        ← Create new VMs
├── destroy-vm.sh          ← Remove VMs
├── terraform/             ← Infrastructure config
├── ansible/               ← Provisioning playbooks
│   └── inventory.d/       ← VM inventory fragments
└── docs/                  ← Full documentation
    ├── MULTI-VM-WORKFLOW.md
    └── VM-SSH-HELPER.md
```

---

## 🎯 Daily Workflow Patterns

### Pattern 1: Work on Single Project
```bash
./vm-ssh.sh work-vm-1      # Auto-start + connect
cd ~/django-project
git pull && code .
# ... work all day ...
exit                        # VM stays running
```

### Pattern 2: Switch Between Projects
```bash
./vm-ssh.sh work-vm-1      # Morning: django
exit
./vm-ssh.sh work-vm-2      # Afternoon: ansible
exit
```

### Pattern 3: Resource Conservation
```bash
./vm-ssh.sh work-vm-1      # Start and connect
exit                        # Leave running
# ... later, free resources ...
sudo virsh shutdown work-vm-1
```

---

## 🔐 Security Notes

- **SSH Key:** `~/.ssh/vm_key` (600 permissions)
- **Network:** VMs isolated in 192.168.122.0/24 NAT
- **Access:** Only from host machine, no external exposure
- **User:** Default user is `mr` (created during provisioning)

---

## 📞 Getting Help

```bash
# Show vm-ssh.sh usage
./vm-ssh.sh

# View full documentation
cat docs/VM-SSH-HELPER.md
cat docs/MULTI-VM-WORKFLOW.md

# Virsh help
man virsh
virsh help list
virsh help domifaddr
```

---

## ⏱️ Time Comparisons

| Task | Manual | With vm-ssh.sh |
|------|--------|----------------|
| Connect to running VM | 3 commands (~20s) | 1 command (~5s) |
| Start + connect | 6 commands (~60s) | 1 command (~15s) |
| Check status + connect | 7 commands (~90s) | 1 command (~15s) |

---

## 🎓 Most Common Commands (90% of daily use)

```bash
# Connect to VM (starts if needed)
./vm-ssh.sh work-vm-1

# Check which VMs are running
sudo virsh list --all

# Shut down VM when done
sudo virsh shutdown work-vm-1
```

**That's 95% of what you'll need daily!**

---

**Last Updated:** 2025-11-12
**Project:** vm-infra (libvirt/KVM Ubuntu VMs)
