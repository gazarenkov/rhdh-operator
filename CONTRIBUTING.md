# Contributing to RHDH Operator

Thank you for your interest in contributing to the Red Hat Developer Hub (RHDH) Operator! This guide will help you get started.

## Table of Contents

- [Development Setup](#development-setup)
- [Development Workflow](#development-workflow)
- [Testing Your Changes](#testing-your-changes)
- [Bundle Manifests](#bundle-manifests)
- [Building Container Images](#building-container-images)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Code Standards](#code-standards)
- [Getting Help](#getting-help)

## Development Setup

### Prerequisites

- Go (see [`go.mod`](./go.mod) for required version)
- Docker or Podman
- kubectl
- Access to a Kubernetes cluster (kind, minikube, k3d, or remote cluster)

### Clone and Build

```bash
# Clone the repository
git clone https://github.com/redhat-developer/rhdh-operator.git
cd rhdh-operator

# Install dependencies and build
make build

# Run tests
make test
```

### Local Development

Run the operator locally against a cluster:

```bash
# Install CRDs
make install

# Run operator locally (logs to terminal)
make run

# In another terminal, apply a Backstage CR
kubectl apply -f examples/bs1.yaml -n <namespace>
```

## Development Workflow

### Making Changes

1. **Create a branch:**
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make your changes** to the code

3. **Format and lint:**
   ```bash
   make fmt
   make lint
   ```

4. **Run tests:**
   ```bash
   make test
   make integration-test
   ```

5. **Commit your changes:**
   ```bash
   git add .
   git commit -s -m "feat: add my feature"
   ```

   Note: We require signed commits (`-s` flag)

### Commit Message Format

Follow conventional commits:

- `feat:` - New feature
- `fix:` - Bug fix
- `chore:` - Maintenance (deps, CI, etc.)
- `docs:` - Documentation changes
- `refactor:` - Code refactoring
- `test:` - Test changes

Examples:
```
feat: add support for external PostgreSQL
fix: resolve deployment rollout issue
chore: update dependencies
docs: improve installation guide
```

## Testing Your Changes

### Unit Tests

```bash
# Run all unit tests
make test

# Run specific package tests
go test ./pkg/model -v
```

### Integration Tests

```bash
# Run integration tests (requires cluster)
make integration-test

# Run specific test
make integration-test ARGS='--focus "test name"'

# Use existing cluster and controller
USE_EXISTING_CLUSTER=true USE_EXISTING_CONTROLLER=true make integration-test
```

### End-to-End Tests

```bash
# Run e2e tests
make test-e2e

# Build local images and test
make test-e2e BACKSTAGE_OPERATOR_TESTS_BUILD_IMAGES=true
```

## Bundle Manifests

**Important:** If you modify CRDs, manifests, or RBAC configurations, you **must** regenerate the OLM bundle.

### Files that Require Bundle Regeneration

- `api/v1alpha*/` - CRD definitions
- `config/manifests/` - CSV and metadata
- `config/rbac/` - RBAC permissions
- `config/crd/` - CRD bases
- `config/webhook/` - Webhook configurations

### Regenerating the Bundle

```bash
# Regenerate bundle manifests
make bundles

# Commit the changes
git add bundle/ config/ dist/
git commit -m "chore: regenerate bundle manifests"
```

**Note:** The PR check will **fail** if bundle manifests are out of sync. Follow the error message instructions to fix.

## Building Container Images

### Building Images for Testing

Need to test container images from your PR?

**For Maintainers:**

Comment `/build-images` on the PR to trigger image builds. The workflow will:
- Build operator, bundle, and catalog images
- Push them to Quay.io with PR-specific tags
- Post the image URLs in a comment

**For Contributors:**

Ask a maintainer to comment `/build-images` on your PR.

### Images Generated

Images will be tagged as:
```
quay.io/rhdh-community/operator:VERSION-pr-NUMBER-SHA
quay.io/rhdh-community/operator-bundle:VERSION-pr-NUMBER-SHA
quay.io/rhdh-community/operator-catalog:VERSION-pr-NUMBER-SHA
```

### Building Locally

```bash
# Build operator image
make image-build IMG=quay.io/myrepo/operator:tag

# Build all images (operator, bundle, catalog)
make release-build
```

## Submitting a Pull Request

### Before Submitting

- ✅ All tests pass (`make test`)
- ✅ Code is formatted (`make fmt`)
- ✅ Code is linted (`make lint`)
- ✅ Bundle manifests are up to date (if you changed CRDs/manifests)
- ✅ Commits are signed (`git commit -s`)

### Creating the PR

1. **Push your branch:**
   ```bash
   git push origin feature/my-feature
   ```

2. **Open a Pull Request** on GitHub

3. **Fill out the PR template** with:
   - Description of changes
   - Related issue number
   - Testing instructions

4. **Wait for CI checks** to pass

5. **Address review feedback** if needed

### PR Checks

Your PR will run the following checks:
- ✅ Unit tests
- ✅ Integration tests
- ✅ Security scanning (gosec)
- ✅ Bundle manifest validation
- ✅ Linting

All checks must pass before merging.

## Code Standards

### Go Code Style

- Follow standard Go conventions
- Use `gofmt` for formatting (run via `make fmt`)
- Add comments for exported functions
- Keep functions focused and small

### Testing

- Write unit tests for new functionality
- Update integration tests if needed
- Aim for reasonable test coverage
- Use table-driven tests where appropriate

Example:
```go
func TestMyFunction(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        {"case 1", "input1", "output1"},
        {"case 2", "input2", "output2"},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := MyFunction(tt.input)
            if result != tt.expected {
                t.Errorf("got %v, want %v", result, tt.expected)
            }
        })
    }
}
```

### Documentation

- Update relevant documentation for user-facing changes
- Add code comments for complex logic
- Update examples if needed

## Getting Help

### Resources

- **Documentation:** See [docs/](./docs/) directory
- **Examples:** See [examples/](./examples/) directory
- **Issues:** Check existing [GitHub Issues](https://github.com/redhat-developer/rhdh-operator/issues)
- **Discussions:** Use GitHub Discussions for questions

### Questions?

- Open a [GitHub Discussion](https://github.com/redhat-developer/rhdh-operator/discussions)
- Ask in the PR comments
- Check the [OWNERS](./OWNERS) file for maintainers

### Reporting Bugs

Found a bug? Please open an issue with:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Operator version and Kubernetes version
- Relevant logs

### Feature Requests

Have an idea? Open an issue with:
- Use case description
- Proposed solution (if you have one)
- Alternative approaches considered

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/0/code_of_conduct/).

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

---

**Thank you for contributing to RHDH Operator!** 🎉
