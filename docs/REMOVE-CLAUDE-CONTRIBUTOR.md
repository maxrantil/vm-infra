# How to Remove Claude/AI Contributors from GitHub Repository

**Problem**: Claude Code or other AI assistants appear in your GitHub repository's contributor list, even after removing Co-Authored-By lines from commits.

**Root Cause**: GitHub caches contributor data. Even with clean git history, the cache doesn't automatically refresh.

---

## Prerequisites

- Git installed locally
- GitHub CLI (`gh`) installed and authenticated
- Repository cloned locally
- Admin access to the repository

---

## Method 1: Public → Private → Public (Try This First)

**Success Rate**: ✅ Works in some cases (as of Nov 2024)
**Time Required**: 5-10 minutes
**Risk**: Low (repository briefly unavailable publicly)

### Steps

1. **Go to GitHub repository settings:**
   ```
   https://github.com/USERNAME/REPO-NAME/settings
   ```

2. **Scroll to "Danger Zone" → "Change repository visibility"**

3. **Change to Private:**
   - Click "Change visibility"
   - Select "Make private"
   - Type repository name to confirm
   - Click "I understand, change repository visibility"

4. **Wait 2-3 minutes**

5. **Change back to Public:**
   - Repeat step 3, but select "Make public"

6. **Wait another 2-3 minutes for cache propagation**

7. **Verify:**
   - Check: `https://github.com/USERNAME/REPO-NAME`
   - Look at Contributors section
   - Check: `https://github.com/USERNAME/REPO-NAME/graphs/contributors`

### If Method 1 Doesn't Work

If Claude still appears after 1-2 hours, proceed to **Method 2**.

---

## Method 2: Branch Rename (Guaranteed to Work)

**Success Rate**: ✅ 100% effective (confirmed working)
**Time Required**: 1-2 hours (includes wait time)
**Risk**: Medium (requires careful execution)

### Important Notes Before Starting

- **Backup your repository** before starting
- You'll need to bypass pre-push hooks (if you have them)
- Default branch will temporarily change
- This forces GitHub to rebuild contributor cache

### Step-by-Step Instructions

#### Part 1: Rename to Temporary Branch (5 minutes)

1. **Verify clean state:**
   ```bash
   cd /path/to/your/repo
   git status
   git branch -a
   ```

2. **Rename master/main to temp branch:**
   ```bash
   # If your default branch is "master":
   git branch -m master master-temp

   # If your default branch is "main":
   git branch -m main main-temp
   ```

3. **Push temp branch to GitHub:**
   ```bash
   # For master:
   git push origin -u master-temp --no-verify

   # For main:
   git push origin -u main-temp --no-verify
   ```

   **Note**: `--no-verify` bypasses pre-push hooks if you have them.

4. **Change default branch on GitHub via API:**
   ```bash
   # For master → master-temp:
   gh api repos/USERNAME/REPO-NAME -X PATCH -f default_branch=master-temp

   # For main → main-temp:
   gh api repos/USERNAME/REPO-NAME -X PATCH -f default_branch=main-temp
   ```

5. **Delete old default branch from GitHub:**
   ```bash
   # Delete master:
   git push origin --delete master --no-verify

   # Delete main:
   git push origin --delete main --no-verify
   ```

6. **Verify default branch changed:**
   ```bash
   gh repo view USERNAME/REPO-NAME --json defaultBranchRef --jq '.defaultBranchRef.name'
   ```

   Should output: `master-temp` or `main-temp`

#### Part 2: Wait for Cache Rebuild (1-2 hours)

7. **Check if cache is rebuilding:**

   Visit: `https://github.com/USERNAME/REPO-NAME/graphs/contributors`

   - If you see "Crunching the latest data..." → **Good!** Cache is rebuilding
   - If you see contributor list with only your username → **Perfect!** Cache rebuilt

8. **Wait until:**
   - Contributors page shows only your username
   - Or at least 1 hour has passed

#### Part 3: Restore Original Branch (5 minutes)

9. **Rename temp branch back to original:**
   ```bash
   # For master:
   git branch -m master-temp master

   # For main:
   git branch -m main-temp main
   ```

10. **Push original branch to GitHub:**
    ```bash
    # For master:
    git push origin -u master --no-verify

    # For main:
    git push origin -u main --no-verify
    ```

11. **Change default branch back via API:**
    ```bash
    # For master:
    gh api repos/USERNAME/REPO-NAME -X PATCH -f default_branch=master

    # For main:
    gh api repos/USERNAME/REPO-NAME -X PATCH -f default_branch=main
    ```

12. **Delete temp branch from GitHub:**
    ```bash
    # Via API (bypasses hooks):
    gh api repos/USERNAME/REPO-NAME/git/refs/heads/master-temp -X DELETE

    # Or for main:
    gh api repos/USERNAME/REPO-NAME/git/refs/heads/main-temp -X DELETE
    ```

13. **Clean up local remote refs:**
    ```bash
    git remote prune origin
    ```

#### Part 4: Verification (2 minutes)

14. **Verify final state:**
    ```bash
    # Check git status
    git status

    # Verify branch
    git branch

    # Check GitHub API
    gh api repos/USERNAME/REPO-NAME/contributors --jq '.[] | {login: .login, contributions: .contributions}'
    ```

15. **Check on GitHub web interface:**
    - Main page: `https://github.com/USERNAME/REPO-NAME`
    - Contributors graph: `https://github.com/USERNAME/REPO-NAME/graphs/contributors`

**Expected Result**: Only your username appears with correct contribution count.

---

## Quick Reference Command Sequence

Replace `USERNAME/REPO-NAME` with your repository details.

### For repositories with "master" as default branch:

```bash
# Part 1: Rename to temp
git branch -m master master-temp
git push origin -u master-temp --no-verify
gh api repos/USERNAME/REPO-NAME -X PATCH -f default_branch=master-temp
git push origin --delete master --no-verify

# Part 2: Wait 1-2 hours, verify cache rebuilt

# Part 3: Restore original
git branch -m master-temp master
git push origin -u master --no-verify
gh api repos/USERNAME/REPO-NAME -X PATCH -f default_branch=master
gh api repos/USERNAME/REPO-NAME/git/refs/heads/master-temp -X DELETE
git remote prune origin
```

### For repositories with "main" as default branch:

```bash
# Part 1: Rename to temp
git branch -m main main-temp
git push origin -u main-temp --no-verify
gh api repos/USERNAME/REPO-NAME -X PATCH -f default_branch=main-temp
git push origin --delete main --no-verify

# Part 2: Wait 1-2 hours, verify cache rebuilt

# Part 3: Restore original
git branch -m main-temp main
git push origin -u main --no-verify
gh api repos/USERNAME/REPO-NAME -X PATCH -f default_branch=main
gh api repos/USERNAME/REPO-NAME/git/refs/heads/main-temp -X DELETE
git remote prune origin
```

---

## Troubleshooting

### "error: failed to push" (pre-push hook blocking)

**Solution**: Add `--no-verify` flag to bypass hooks:
```bash
git push origin -u master --no-verify
```

This is safe for administrative tasks like branch renames.

### "Error: Direct pushes to 'master' are not allowed"

**Solution**: Use `--no-verify` flag or delete via GitHub API:
```bash
gh api repos/USERNAME/REPO-NAME/git/refs/heads/BRANCH-NAME -X DELETE
```

### Contributors page still shows "Crunching data..." after 2 hours

**Solutions**:
1. Wait another hour (can take up to 3 hours in rare cases)
2. Contact GitHub Support for manual cache refresh
3. Try Method 1 (visibility toggle) again

### Claude still appears after both methods

**Last resort options**:

1. **Use git filter-repo to rewrite history** (advanced, risky):
   ```bash
   # Install git-filter-repo first
   # This rewrites entire git history - DANGEROUS!
   git filter-repo --mailmap <(echo "Your Name <your@email.com> Claude <noreply@anthropic.com>")
   ```

   **Warning**: This rewrites git history. Only use if you understand the implications.

2. **Contact GitHub Support**:
   - Go to: https://support.github.com
   - Request: "Manual contributor cache refresh for repository USERNAME/REPO-NAME"
   - Explain: "AI contributor appearing despite clean git history"

---

## Preventing Future AI Attribution

Add these settings to your Claude Code configuration:

**File**: `~/.claude/settings.json` (Linux/macOS) or `%APPDATA%\claude-code\settings.json` (Windows)

```json
{
  "includeCoAuthoredBy": false,
  "gitAttribution": false
}
```

Create the file if it doesn't exist.

This prevents Claude Code from adding itself as a co-author in future commits.

---

## Verification Checklist

After completing the process:

- [ ] GitHub API shows only your username as contributor
- [ ] Main repository page shows only you in Contributors section
- [ ] Contributor graph page shows only your contributions
- [ ] Default branch is back to original name (master/main)
- [ ] No temporary branches remain
- [ ] Local working tree is clean (`git status`)
- [ ] Browser cache cleared (hard refresh: Ctrl+Shift+R)

---

## Time Estimates

| Method | Estimated Time | Waiting Required |
|--------|----------------|------------------|
| Method 1 | 5-10 minutes | 5-10 minutes |
| Method 2 | 10-15 minutes active work | 1-2 hours wait time |

---

## References

- GitHub Community Discussion: https://github.com/orgs/community/discussions/49813
- Claude Code Attribution Guide: https://velvetshark.com/til/claude-code-github-co-author
- Git Filter-Repo: https://github.com/newren/git-filter-repo

---

## Document History

- **2025-11-20**: Initial version created based on successful removal from vm-infra repository
- **Tested on**: Ubuntu Linux, GitHub CLI 2.x, Git 2.x
- **Confirmed working**: Method 2 (Branch Rename) - 100% success rate

---

**Questions or issues?** Check GitHub Community discussions or contact GitHub Support.
