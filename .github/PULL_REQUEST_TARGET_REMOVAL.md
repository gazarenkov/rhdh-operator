# Removing pull_request_target from GitHub Workflows

## Context

The `pull_request_target` event is being deprecated/restricted due to security concerns. This document provides recommendations for updating all workflows that currently use it.

## Current Workflows Using pull_request_target

1. `pr.yaml` - PR validation and gosec SARIF upload
2. `pr-bundle-diff-checks.yaml` - Auto-fix bundle manifests
3. `pr-container-build.yaml` - Build and push container images

---

## 1. pr.yaml - PR Validation

**Current:** Uses `pull_request_target` to upload gosec SARIF to Code Scanning

**Issue:** SARIF upload requires `security_events: write` permission, which `pull_request` from forks doesn't have.

**Finding:** SonarCloud already provides Code Scanning alerts. Gosec alerts are visible but SonarCloud is the primary tool.

### Recommendation: Remove SARIF Upload (Simplest)

**Changes:**
```yaml
# Change trigger
on:
  pull_request:  # Changed from pull_request_target
    types: [opened, synchronize, reopened, ready_for_review]

jobs:
  pr-validate:  # Remove authorize job
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4  # Simplified - no need to specify repo/ref

      # ... all existing steps ...

      - name: Run Gosec Security Scanner
        run: make gosec
        # Runs gosec, results in workflow logs
        # SonarCloud provides Code Scanning integration

      # REMOVE: Upload SARIF step
```

**Pros:**
- ✅ Simple change (remove ~30 lines)
- ✅ No approval gates needed
- ✅ Faster PR validation (no waiting for approval)
- ✅ Gosec still runs (validates in CI logs)
- ✅ SonarCloud provides Code Scanning alerts
- ✅ Minimal code changes required

**Cons:**
- ❌ Gosec results only in logs (not in Security tab)
- ❌ Lose direct Code Scanning integration for gosec
- ⚠️ Note: SonarCloud already provides the primary Code Scanning integration

**Decision:** Use this approach - SonarCloud provides sufficient Code Scanning coverage.

---

## 2. pr-bundle-diff-checks.yaml - Bundle Manifest Validation

**Current:** Uses `pull_request_target` to commit bundle fixes back to external fork PRs

**Issue:** Needs write access to push commits to external contributor forks

### Recommendation: Block PR on Bundle Drift

Remove auto-commit functionality, fail the check if bundle manifests are out of sync:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  check-bundle:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup Go
        uses: actions/setup-go@v6
        with:
          go-version-file: 'go.mod'

      - name: Verify bundle manifests are up to date
        run: |
          make bundles build-installers

          # Check if bundle manifests changed (ignoring createdAt timestamps)
          if git diff --quiet -I'^    createdAt: ' bundle config dist; then
            echo "✅ Bundle manifests are up to date"
            exit 0
          fi

          # Bundle is out of sync - provide helpful error message
          echo "::error::Bundle manifests are out of sync with the code"
          echo ""
          echo "❌ The bundle manifests need to be regenerated."
          echo ""
          echo "This usually happens when you modify:"
          echo "  - CRD definitions (api/)"
          echo "  - Operator manifests (config/manifests/)"
          echo "  - RBAC permissions (config/rbac/)"
          echo "  - Webhook configurations (config/webhook/)"
          echo ""
          echo "To fix this, run:"
          echo "  make bundles"
          echo "  git add bundle/ config/ dist/"
          echo "  git commit -m 'chore: regenerate bundle manifests'"
          echo "  git push"
          echo ""
          echo "Changed files:"
          git diff --name-only -I'^    createdAt: ' bundle config dist

          exit 1
```

**Pros:**
- ✅ Simple implementation
- ✅ No pull_request_target needed
- ✅ No approval gates
- ✅ Enforces correctness - bundle always in sync
- ✅ Clean git history - all changes in one PR
- ✅ Clear error messages with fix instructions
- ✅ Standard practice for Kubernetes operators
- ✅ Protects main branch integrity

**Cons:**
- ❌ Blocks PR until fixed
- ❌ Requires contributor to run `make bundles`
- ❌ Learning curve for new contributors
- ❌ Extra commit in PR workflow

**Decision:** Use blocking approach - enforces correctness and follows industry best practices.

---

## 3. pr-container-build.yaml - Build PR Images

**Current:** Uses `pull_request_target` to access secrets (QUAY_TOKEN, RHDH_BOT_TOKEN) for building and pushing container images

**Issue:**
- Needs secrets to push to Quay.io
- Container images are too large for artifact pattern
- Automatic builds on every push waste resources

### Recommendation: Slash Command Pattern (Detailed Implementation)

See separate file: `pr-container-build-slash-command.yaml` (already drafted)

**Key changes:**
```yaml
on:
  issue_comment:  # Changed from pull_request_target
    types: [created]

jobs:
  build-images:
    if: |
      github.event.issue.pull_request &&
      startsWith(github.event.comment.body, '/build-images') &&
      contains(fromJSON('[...]'), github.event.comment.user.login)
```

**Workflow:**
1. Maintainer reviews PR code
2. Maintainer comments `/build-images` on PR
3. Workflow builds and pushes images to Quay
4. Bot comments with image URLs

**Pros:**
- ✅ No pull_request_target needed
- ✅ Explicit approval per build (maintainer command)
- ✅ Clear audit trail (visible in PR)
- ✅ On-demand (saves CI resources)
- ✅ Self-service for maintainers (can build their own PRs)
- ✅ Better UX (visible command vs hidden approval gate)
- ✅ Simplified workflow (no changed-files check needed)

**Cons:**
- ❌ Not automatic (requires manual trigger)
- ❌ Only maintainers can trigger

**Decision:** **This is the recommended approach** - better than pull_request_target in every way except automation.

---

## Implementation Plan

### Phase 1: Prepare New Workflows

1. Create new workflow files:
   - `pr-tests.yaml` (replaces pr.yaml, uses pull_request)
   - `pr-bundle-check.yaml` (replaces pr-bundle-diff-checks.yaml, uses pull_request)
   - `pr-build-images.yaml` (replaces pr-container-build.yaml, uses issue_comment)

2. Test in a feature branch/fork to verify they work

### Phase 2: Migration

1. **Week 1:** Deploy pr-tests.yaml
   - Add new workflow
   - Monitor for issues
   - Keep old pr.yaml as backup

2. **Week 2:** Deploy pr-bundle-check.yaml
   - Add new workflow
   - Update CONTRIBUTING.md with "run make bundles" guidance
   - Keep old pr-bundle-diff-checks.yaml as backup

3. **Week 3:** Deploy pr-build-images.yaml
   - Add new workflow with slash command
   - Update CONTRIBUTING.md with `/build-images` documentation
   - Notify maintainers of new workflow
   - Keep old pr-container-build.yaml as backup

### Phase 3: Cleanup (After 1-2 Weeks)

1. Remove old workflows:
   - Delete pr.yaml
   - Delete pr-bundle-diff-checks.yaml
   - Delete pr-container-build.yaml

2. Update documentation

### Phase 4: Update Documentation

Update the following files:

**CONTRIBUTING.md:**
```markdown
## Pull Request Workflow

### Validating Your PR

All PRs automatically run:
- Unit tests
- Integration tests
- Go security scanning (gosec)
- Bundle manifest validation

### Bundle Manifests

If you modify CRDs or manifests, you must regenerate bundle files:

\`\`\`bash
make bundles
git add bundle/ config/ dist/
git commit -m "chore: regenerate bundle manifests"
\`\`\`

If you forget, the PR check will fail with instructions.

### Building Test Images

To get container images for testing your PR:

**For Contributors:**
Ask a maintainer to run \`/build-images\` on your PR.

**For Maintainers:**
1. Review the PR code
2. Comment \`/build-images\` on the PR
3. Images will be built and links posted automatically

Images are tagged as:
- \`quay.io/rhdh-community/operator:VERSION-pr-NUMBER-SHA\`
- \`quay.io/rhdh-community/operator-bundle:VERSION-pr-NUMBER-SHA\`
- \`quay.io/rhdh-community/operator-catalog:VERSION-pr-NUMBER-SHA\`
```

**README.workflows.adoc** (update workflow descriptions)

---

## Security Considerations

### Before (pull_request_target)

❌ All external PRs require manual approval via hidden Actions UI
❌ Approval process not visible in PR conversation
❌ Complex authorization logic with environment gates
❌ Potential for PwnRequest vulnerabilities if misconfigured

### After (pull_request + slash commands)

✅ External PRs run automatically (read-only operations)
✅ Secrets only accessed via explicit maintainer commands
✅ Clear audit trail in PR conversation
✅ Simpler authorization (list of trusted usernames)
✅ No PwnRequest risk (no automatic execution with secrets)

---

## Testing Plan

Before deploying, test each new workflow:

### pr-tests.yaml
1. Open test PR from fork
2. Verify tests run automatically
3. Verify gosec runs successfully
4. Check workflow logs for gosec results

### pr-bundle-check.yaml
1. Open PR with outdated bundles
2. Verify check fails with helpful message
3. Run `make bundles` locally
4. Push changes, verify check passes

### pr-build-images.yaml
1. Open test PR
2. Comment `/build-images` as maintainer
3. Verify workflow triggers
4. Verify images build and push to Quay
5. Verify comment posts with image links
6. Test as non-maintainer (verify it doesn't trigger)

---

## Rollback Plan

If issues arise after migration:

1. **Immediate:** Re-enable old workflow file
   ```bash
   git revert <commit-hash>
   git push
   ```

2. **Investigate:** Check workflow run logs for errors

3. **Fix:** Update new workflow as needed

4. **Redeploy:** Test in fork before deploying to main

---

## Summary

| Workflow | Current Trigger | New Trigger | Approach | Complexity | Priority |
|----------|----------------|-------------|----------|------------|----------|
| pr.yaml | pull_request_target | pull_request | Remove SARIF upload | Low | Medium |
| pr-bundle-diff-checks.yaml | pull_request_target | pull_request | Block PR on bundle drift | Low | High |
| pr-container-build.yaml | pull_request_target | issue_comment | Slash command `/build-images` | Medium | High |

**Total effort:** ~2-3 days for implementation and testing
**Risk level:** Low (can rollback easily)
**Recommended timeline:** 3-4 weeks (phased rollout)

**Key principles:**
- ✅ Simple implementations (maintainable)
- ✅ Clear user guidance (helpful error messages)
- ✅ Enforce correctness where needed (bundle validation)
- ✅ No pull_request_target needed

---

## Questions?

Contact the operator team maintainers for clarification or assistance with migration.
