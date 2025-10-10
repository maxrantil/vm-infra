## Security Vulnerability

**CVE-2024-ANSIBLE-001: SSH Private Keys Copied to VMs**

**CVSS Score**: 9.3 (CRITICAL)
**Location**: `ansible/playbook.yml` lines 147-161

## Problem

GitHub SSH private keys (`~/.ssh/id_ed25519`) are copied from host to VMs, creating credential proliferation security risk.

**Current Implementation**:
```yaml
- name: Copy GitHub SSH private key to VM
  copy:
    src: ~/.ssh/id_ed25519
    dest: "{{ ssh_key_path }}"
    mode: "0600"
  become_user: "{{ ansible_user }}"

- name: Copy GitHub SSH public key to VM
  copy:
    src: ~/.ssh/id_ed25519.pub
    dest: "{{ ssh_pub_key_path }}"
    mode: "0644"
  become_user: "{{ ansible_user }}"
```

**Security Risks**:
1. VM compromise = GitHub account compromise
2. Keys persist on VM disk images
3. Multiple copies of same private key
4. No key rotation strategy
5. Violates principle of least privilege

## Solution

Generate VM-specific deploy keys instead of copying host keys.

### Secure Implementation

**Replace lines 147-161 with**:

```yaml
- name: Generate VM-specific deploy key
  command: ssh-keygen -t ed25519 -f {{ ssh_key_path }} -N "" -C "vm-deploy-{{ ansible_hostname }}"
  args:
    creates: "{{ ssh_key_path }}"
  become_user: "{{ ansible_user }}"

- name: Set deploy key permissions
  file:
    path: "{{ ssh_key_path }}"
    mode: "0600"
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"

- name: Display public deploy key
  shell: cat {{ ssh_pub_key_path }}
  register: deploy_key_output
  become_user: "{{ ansible_user }}"

- name: Deploy key setup instructions
  debug:
    msg: |
      ═══════════════════════════════════════════════════════════════
      ⚠️  MANUAL STEP REQUIRED: Add Deploy Key to GitHub ⚠️
      ═══════════════════════════════════════════════════════════════

      Copy the key below and add it to your GitHub repository:

      {{ deploy_key_output.stdout }}

      Steps:
      1. Go to: https://github.com/maxrantil/dotfiles/settings/keys
      2. Click "Add deploy key"
      3. Title: vm-{{ ansible_hostname }}-deploy-key
      4. Paste the key above
      5. ✓ Check "Allow write access" if needed for push operations
      6. Click "Add key"

      After adding the deploy key, dotfiles will be accessible from this VM.
      ═══════════════════════════════════════════════════════════════
```

## Benefits of Deploy Keys

1. **Isolation**: Each VM has unique key
2. **Revocation**: Can revoke single VM key without affecting others
3. **Audit**: Can track which VM accessed repository
4. **Least Privilege**: Deploy keys are repository-specific
5. **Security**: Host SSH key never leaves host machine

## Implementation Checklist

- [ ] Remove SSH key copy tasks (lines 147-161)
- [ ] Add deploy key generation task
- [ ] Add permission setting task
- [ ] Add public key display task
- [ ] Add manual setup instructions
- [ ] Test with new VM provision
- [ ] Verify dotfiles clone works with deploy key
- [ ] Update README with deploy key setup
- [ ] Document key rotation strategy

## Testing Plan

1. Provision test VM with new Ansible playbook
2. Verify deploy key is generated (not copied)
3. Note public key from playbook output
4. Add deploy key to GitHub (dotfiles repository)
5. Test dotfiles clone with deploy key
6. Verify install.sh works
7. Destroy test VM
8. Verify deploy key can be revoked independently

## Documentation Updates

### README.md

Add section:

```markdown
## Deploy Key Setup

VMs use repository-specific deploy keys instead of copying your personal SSH keys.

**After provisioning**:
1. Ansible displays public deploy key
2. Add key to GitHub: Settings → Deploy keys → Add deploy key
3. Title: `vm-<hostname>-deploy-key`
4. ✓ Allow write access (if pushing from VM)

**Key Rotation**:
- Delete deploy key from GitHub
- Re-run Ansible playbook to generate new key
- Add new key to GitHub

**Security**: Each VM has unique key. Compromising one VM doesn't compromise GitHub account.
```

## Alternative: Automation Consideration

**Future Enhancement**: Could automate deploy key addition via GitHub API

```yaml
- name: Add deploy key via GitHub API (optional future enhancement)
  uri:
    url: "https://api.github.com/repos/maxrantil/dotfiles/keys"
    method: POST
    headers:
      Authorization: "token {{ github_token }}"
    body:
      title: "vm-{{ ansible_hostname }}-deploy-key"
      key: "{{ deploy_key_output.stdout }}"
      read_only: false
    body_format: json
```

**Requires**: GitHub token with `admin:public_key` scope

**Decision**: Keep manual for now (no secrets in code)

## Files to Update

- `ansible/playbook.yml` (lines 147-161)
- `README.md` (add deploy key documentation)

## Acceptance Criteria

- [ ] SSH key copy tasks removed
- [ ] Deploy key generation implemented
- [ ] Public key displayed with instructions
- [ ] Tested with new VM
- [ ] Dotfiles clone works with deploy key
- [ ] README documented
- [ ] Security vulnerability eliminated

## Priority

**CRITICAL** - Complete in Week 1 (active security vulnerability)
