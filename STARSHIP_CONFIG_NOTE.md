# Starship Configuration for VM Username Display

## Context

**Issue:** VMs now use configurable usernames instead of hardcoded `mr`. The starship prompt should always display the username clearly to help identify which VM you're in.

**Related PR:** vm-infra username parameter implementation

---

## Required Changes to Dotfiles

The starship configuration in your dotfiles repository needs to be updated to **always show the username**, even when not SSH'd in.

### Current Behavior (Likely)

Starship probably only shows username when `$SSH_CONNECTION` is detected:

```toml
[username]
show_always = false  # Only shows when SSH'd in
ssh_only = true      # Default behavior
```

### Required Behavior

Update `~/.config/starship.toml` to always show username for VM clarity:

```toml
[username]
show_always = true
format = "[$user]($style) "
style_user = "bold yellow"
style_root = "bold red"

[hostname]
ssh_only = false
format = "[@$hostname](bold green) "
trim_at = "."
```

**Result:** Prompt will show `developer@work-vm-1` regardless of SSH vs console login.

---

## Why This Matters

**Problem:** With multiple VMs using different usernames, it's easy to lose track of which VM you're in.

**Solution:** Always-visible username in the prompt provides immediate context:
- ✅ `developer@work-vm-1` - Clear which VM and user
- ✅ `testuser@test-vm` - Testing environment obvious
- ✅ `admin@prod-vm` - Production environment highlighted

**Without this change:** You might only see the hostname (`work-vm-1`) and not realize which user you're operating as.

---

## Testing the Change

After updating your dotfiles:

1. **Provision a test VM:**
   ```bash
   ./provision-vm.sh test-vm testuser 2048 1 --test-dotfiles /path/to/dotfiles
   ```

2. **SSH into the VM:**
   ```bash
   ssh -i ~/.ssh/vm_key testuser@<VM_IP>
   ```

3. **Verify prompt shows:**
   ```
   testuser@test-vm ~/some/path
   ```

4. **If prompt doesn't show username:**
   - Check `~/.config/starship.toml` was applied
   - Run `source ~/.zshrc` to reload
   - Verify `starship config` shows your changes

---

## Recommended Starship Config Snippet

Add this to your dotfiles repository's starship configuration:

```toml
# ===================================
# USERNAME - Always show for VM clarity
# ===================================
[username]
show_always = true                    # Show even when not SSH'd in
format = "[$user]($style)"           # Format: username only
style_user = "bold yellow"           # Yellow for regular users
style_root = "bold red"              # Red for root (warning!)
disabled = false

# ===================================
# HOSTNAME - Always show for VM clarity
# ===================================
[hostname]
ssh_only = false                     # Show even when not SSH'd in
format = "[@$hostname](bold green) " # Format: @hostname with space
trim_at = "."                        # Remove domain suffix
disabled = false

# ===================================
# CHARACTER - Prompt symbol
# ===================================
[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
```

**Result:**
```
developer@work-vm-1 ~/projects
❯
```

---

## Priority

**High** - This should be included in the dotfiles repository to ensure VMs are immediately identifiable when provisioned.

---

## References

- **Starship Docs:** https://starship.rs/config/#username
- **vm-infra Issue:** Configurable VM usernames
- **Testing:** Use `--test-dotfiles` flag to test changes before pushing to GitHub

---

**Created:** 2025-11-17
**Author:** Claude
**For:** Doctor Hubert's dotfiles repository integration
