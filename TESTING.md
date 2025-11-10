# Testing Documentation

## Test-Driven Development (TDD) Approach

This project follows **strict Test-Driven Development (TDD)** for all development work. All code changes must be accompanied by tests that validate the behavior.

### TDD Workflow (Required for All New Work)

1. **RED** - Write failing test first that defines desired behavior
2. **GREEN** - Write minimal code to make the test pass
3. **REFACTOR** - Improve code while keeping tests green
4. **COMMIT** - Separate commits showing RED→GREEN→REFACTOR progression

### Test Types

Every feature must have:
- **Unit Tests**: Individual functions in isolation
- **Integration Tests**: Component interactions
- **End-to-End Tests**: Complete user workflows

## Retrospective TDD Documentation

**Context**: Some early features in this project were implemented using "retrospective TDD" where tests and implementation were committed together, before strict TDD enforcement was established.

### What is Retrospective TDD?

**Retrospective TDD** means:
- ✅ Tests follow full TDD structure (tests define behavior, minimal implementation to pass)
- ✅ Test quality remains high with comprehensive edge case coverage
- ❌ Tests and implementation committed together (no RED→GREEN→REFACTOR git evidence)
- ❌ Cannot verify tests actually catch failures via git history

### Features Implemented with Retrospective TDD

The following features were implemented retrospectively before strict TDD enforcement:

1. **`--test-dotfiles` flag** (PR #22, Issue #19)
   - 33 automated tests (unit + integration + security)
   - Test quality: Excellent (comprehensive coverage)
   - Reason: Initial feature establishing testing patterns

2. **Security hardening (SEC-001 to SEC-008)** (PR #45, PR #39)
   - Security validation tests for TOCTOU, pattern evasion, shell injection
   - Test quality: High (addresses critical CVEs)
   - Reason: Security fixes required rapid implementation

3. **VM-specific deploy keys** (PR #57, Issue #49)
   - SSH key generation and validation tests
   - Test quality: High (prevents CVE-2024-ANSIBLE-001)
   - Reason: Critical security vulnerability fix

4. **Infrastructure security scanning** (PR #59, Issue #51)
   - Security scanner integration tests
   - Test quality: High (4 scanners, 34s runtime)
   - Reason: Security compliance requirement

5. **`--dry-run` flag** (PR #52, Issue #33)
   - E2E testing mode validation
   - Test quality: High (automated E2E tests)
   - Reason: Test infrastructure feature

### Why Retrospective TDD Was Used

**Pragmatic decisions for early features**:
- Establishing initial test infrastructure
- Addressing critical security vulnerabilities rapidly
- Building foundation for strict TDD workflow
- Learning project testing patterns

### Test Quality Assurance

Despite the retrospective approach, all tests meet high quality standards:
- ✅ **Comprehensive coverage**: Unit, integration, E2E tests
- ✅ **Edge case testing**: Symlinks, spaces in paths, permissions
- ✅ **Security validation**: CVE mitigation verification
- ✅ **Behavior-focused**: Tests validate contracts, not implementation
- ✅ **100% pass rate**: All automated tests passing

### Limitation

**Impact of retrospective TDD**: While test quality is high, we cannot verify through git history that tests actually caught failures before fixes were implemented. This prevents us from demonstrating true TDD practice for these features.

**Mitigation**: All tests have been reviewed for quality and comprehensiveness. Future work must follow strict TDD to ensure full validation.

## Running Tests

### All Tests

```bash
# Run all test suites
./tests/test_local_dotfiles.sh
./tests/test_ssh_key_validation.sh
./tests/test_dry_run.sh

# Check test results
echo "Expected: All tests passing (100% pass rate)"
```

### Individual Test Suites

```bash
# Test local dotfiles feature
./tests/test_local_dotfiles.sh
# Expected: 33 tests, all passing

# Test SSH key validation
./tests/test_ssh_key_validation.sh
# Expected: 7 tests, all passing

# Test dry-run mode
./tests/test_dry_run.sh
# Expected: All E2E tests passing
```

## Pre-commit Hooks

The test suite runs automatically on every commit via pre-commit hooks to prevent regressions.

### Setup

```bash
# Install pre-commit hooks (first time only)
pre-commit install
pre-commit install --hook-type commit-msg
```

### Automated Tests on Commit

When you commit changes, the following tests run automatically:
- **Local dotfiles test suite** (66 tests) - Validates `--test-dotfiles` feature
- **Security checks** - Detects secrets, validates file permissions
- **Code quality** - Shellcheck, yamllint, markdownlint
- **Terraform validation** - Ensures infrastructure code is valid

### Manual Pre-commit Run

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run specific hook
pre-commit run dotfiles-tests --all-files
pre-commit run shellcheck --all-files
```

### Hook Behavior

- **Blocking**: If any test fails, the commit is blocked
- **No bypass**: `--no-verify` is forbidden per project policy
- **Fast feedback**: Tests run before commit to catch issues early

## Contributing Tests

When adding new features, follow strict TDD:

1. **Create failing test first** (commit as "test: add test for X feature")
2. **Implement minimal code to pass** (commit as "feat: implement X feature")
3. **Refactor while tests pass** (commit as "refactor: improve X implementation")
4. **Document TDD approach in PR** (show commits demonstrating RED→GREEN→REFACTOR)

### Good PR Documentation Example

```markdown
**TDD Approach**: ✅ Full RED→GREEN→REFACTOR workflow with separate commits
- RED: commit a1b2c3 - Added failing tests for feature X
- GREEN: commit d4e5f6 - Implemented minimal code to pass tests
- REFACTOR: commit g7h8i9 - Improved implementation while keeping tests green
```

### Test Coverage Goals

- **Unit tests**: 80%+ coverage of functions
- **Integration tests**: All component interactions
- **E2E tests**: All user-facing workflows
- **Security tests**: All CVE mitigations validated

## References

- **Issue #31**: TEST-002: TDD Violation - Document Retrospective Approach
- **AGENT_REVIEW.md**: Lines 508-521 (TEST-002 analysis)
- **PR #22**: First example of retrospective TDD documentation
- **Test Files**: `tests/test_*.sh` (all test suites)

---

**Last Updated**: 2025-10-13 (Issue #31 resolution)
**Project**: VM Infrastructure
**Motto**: "TDD is not optional" - All future work requires strict TDD workflow
