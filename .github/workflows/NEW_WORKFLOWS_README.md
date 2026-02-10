# New Workflows (pull_request_target Removal)

This directory contains new workflow files that replace the existing `pull_request_target` workflows.

## Files

### 1. pr.yaml.new
**Replaces:** `pr.yaml`

**Changes:**
- ✅ Changed trigger from `pull_request_target` to `pull_request`
- ✅ Removed `authorize` job (no manual approval needed)
- ✅ Removed SARIF upload step (SonarCloud provides Code Scanning)
- ✅ Simplified checkout (no need to specify repo/ref)
- ✅ Gosec still runs, results in workflow logs

**Impact:** Faster PR validation, no approval gates, simpler workflow

### 2. pr-bundle-diff-checks.yaml.new
**Replaces:** `pr-bundle-diff-checks.yaml`

**Changes:**
- ✅ Changed trigger from `pull_request_target` to `pull_request`
- ✅ Removed `authorize` job
- ✅ Removed auto-commit functionality
- ✅ Blocks PR if bundle manifests are out of sync
- ✅ Clear error messages with fix instructions
- ✅ Follows standard Kubernetes operator practices

**Impact:** Enforces bundle correctness, cleaner git history, requires contributors to run `make bundles`

### 3. pr-container-build.yaml.new
**Replaces:** `pr-container-build.yaml`

**Changes:**
- ✅ Changed trigger from `pull_request_target` to `issue_comment`
- ✅ Slash command pattern: `/build-images`
- ✅ Removed changed-files check (not needed for manual trigger)
- ✅ Added user feedback (rocket emoji, success/failure comments)
- ✅ Maintainers can trigger their own PRs

**Impact:** Manual trigger instead of automatic, better UX

## Testing Before Deployment

Before replacing the old workflows, test these new ones:

### Test pr.yaml.new

1. **Create test branch:**
   ```bash
   git checkout -b test-new-pr-workflow
   ```

2. **Temporarily rename files:**
   ```bash
   mv .github/workflows/pr.yaml .github/workflows/pr.yaml.old
   mv .github/workflows/pr.yaml.new .github/workflows/pr.yaml
   git add .github/workflows/
   git commit -m "test: new pr workflow"
   git push -u origin test-new-pr-workflow
   ```

3. **Open PR and verify:**
   - ✅ Workflow runs automatically (no approval needed)
   - ✅ All tests run
   - ✅ Gosec runs and completes
   - ✅ No errors

4. **Revert if needed:**
   ```bash
   mv .github/workflows/pr.yaml.old .github/workflows/pr.yaml
   rm .github/workflows/pr.yaml.new
   ```

### Test pr-bundle-diff-checks.yaml.new

1. **Make a change that affects bundle:**
   ```bash
   # Edit a CRD file
   vi api/v1alpha5/backstage_types.go
   # Add a comment or minor change
   # Don't run make bundles
   git commit -am "test: trigger bundle drift"
   git push
   ```

2. **Verify check fails:**
   - ✅ Workflow runs
   - ✅ Detects bundle drift
   - ❌ Check fails with clear error message
   - ✅ Error message shows fix instructions

3. **Fix and verify check passes:**
   ```bash
   # Regenerate bundle as instructed
   make bundles
   git add bundle/ config/ dist/
   git commit -m "chore: regenerate bundle manifests"
   git push
   ```
   - ✅ Workflow runs again
   - ✅ Check passes (bundle is in sync)

### Test pr-container-build.yaml.new

1. **Deploy the new workflow:**
   ```bash
   mv .github/workflows/pr-container-build.yaml .github/workflows/pr-container-build.yaml.old
   mv .github/workflows/pr-container-build.yaml.new .github/workflows/pr-container-build.yaml
   git add .github/workflows/
   git commit -m "test: new container build workflow"
   git push
   ```

2. **On a PR, comment:**
   ```
   /build-images
   ```

3. **Verify:**
   - ✅ Rocket emoji reaction appears
   - ✅ Workflow triggers
   - ✅ Images build and push
   - ✅ Success comment with image links

4. **Test non-maintainer:**
   - Ask someone not in the maintainer list to comment `/build-images`
   - ✅ Nothing happens (workflow doesn't trigger)

## Deployment Plan

### Phase 1: Deploy pr.yaml (Week 1)
```bash
# Backup old file
mv .github/workflows/pr.yaml .github/workflows/pr.yaml.backup

# Deploy new file
mv .github/workflows/pr.yaml.new .github/workflows/pr.yaml

# Commit
git add .github/workflows/
git commit -m "chore: remove pull_request_target from pr.yaml"
git push
```

**Monitor for 1 week**, then delete backup if all good.

### Phase 2: Deploy pr-bundle-diff-checks.yaml (Week 2)
```bash
# Backup old file
mv .github/workflows/pr-bundle-diff-checks.yaml .github/workflows/pr-bundle-diff-checks.yaml.backup

# Deploy new file
mv .github/workflows/pr-bundle-diff-checks.yaml.new .github/workflows/pr-bundle-diff-checks.yaml

# Commit
git add .github/workflows/
git commit -m "chore: remove pull_request_target from bundle checks"
git push
```

**Update CONTRIBUTING.md** with bundle regeneration instructions.

### Phase 3: Deploy pr-container-build.yaml (Week 3)
```bash
# Backup old file
mv .github/workflows/pr-container-build.yaml .github/workflows/pr-container-build.yaml.backup

# Deploy new file
mv .github/workflows/pr-container-build.yaml.new .github/workflows/pr-container-build.yaml

# Commit
git add .github/workflows/
git commit -m "chore: convert container build to slash command pattern"
git push
```

**Update CONTRIBUTING.md** with `/build-images` usage instructions.

**Notify all maintainers** about the new slash command pattern.

### Phase 4: Cleanup (Week 4)
After confirming all workflows work correctly:

```bash
# Remove backup files
rm .github/workflows/*.backup

# Remove this README
rm .github/workflows/NEW_WORKFLOWS_README.md

# Commit
git add .github/workflows/
git commit -m "chore: cleanup workflow backups"
git push
```

## Rollback Procedure

If any workflow has issues:

```bash
# Example for pr.yaml
mv .github/workflows/pr.yaml .github/workflows/pr.yaml.broken
mv .github/workflows/pr.yaml.backup .github/workflows/pr.yaml
git add .github/workflows/
git commit -m "revert: rollback to old pr.yaml workflow"
git push
```

Then investigate the issue in the `.broken` file.

## Documentation Updates Needed

After successful deployment, update:

### CONTRIBUTING.md

Add section:

```markdown
## Building PR Images for Testing

To build container images from your PR for testing:

**For Maintainers:**
Comment `/build-images` on the PR to trigger image builds.

**For Contributors:**
Ask a maintainer to run `/build-images` to build test images.

The workflow will:
1. Build operator, bundle, and catalog images
2. Push them to Quay.io with PR-specific tags
3. Comment back with image URLs for testing

Images are available at:
- `quay.io/rhdh-community/operator:VERSION-pr-NUMBER-SHA`
- `quay.io/rhdh-community/operator-bundle:VERSION-pr-NUMBER-SHA`
- `quay.io/rhdh-community/operator-catalog:VERSION-pr-NUMBER-SHA`

## Bundle Manifests

If you modify CRDs or manifests, you **must** regenerate bundle files:

\`\`\`bash
make bundles
git add bundle/ config/ dist/
git commit -m "chore: regenerate bundle manifests"
\`\`\`

**The PR check will fail if bundle manifests are out of sync.** Follow the error message instructions to fix.
```

## Questions?

Contact the operator team maintainers for assistance.
