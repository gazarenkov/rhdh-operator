# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the **Backstage Operator** (also known as **RHDH Operator** for Red Hat Developer Hub), a Kubernetes Operator that configures, installs, and synchronizes Backstage instances on Kubernetes/OpenShift. It follows the Kubernetes Operator pattern using the controller-runtime framework and supports dynamic plugins, multiple configuration profiles, and both local and external database configurations.

## AI-Assisted Configuration

Users can leverage AI assistants (Claude, ChatGPT, etc.) to generate Backstage CRs using natural language. See [docs/ai-configuration-guide.md](docs/ai-configuration-guide.md) for:
- Optimized prompt templates
- Complete CRD schema for AI prompts
- Common configuration scenarios
- Validation and troubleshooting tips

Extract the current CRD schema for AI prompts:
```bash
make schema
```

## Essential Commands

### Building and Testing

```bash
# Build the operator binary
make build

# Run unit tests (fast, runs locally without cluster)
make test

# Run integration tests (requires envtest or real cluster)
make integration-test

# Run unit tests for a specific package
go test ./pkg/model -v

# Format code (uses goimports)
make fmt

# Lint code
make lint

# Fix linting issues automatically
make lint-fix

# Run Go vet
make vet
```

### Running the Operator Locally

```bash
# Run controller locally (standalone, logs in terminal)
# This is convenient for debugging but RBAC doesn't work
make run

# Or with a specific profile
make PROFILE=rhdh run

# Run integration tests against existing cluster with local controller
USE_EXISTING_CLUSTER=true USE_EXISTING_CONTROLLER=true make integration-test

# Run specific integration test
make integration-test ARGS='--focus "test name here"'
```

### Deploying to a Cluster

```bash
# Install CRDs only
make install

# Deploy operator to cluster (uses current kubeconfig context)
make deploy

# Or with specific image and profile
make deploy IMG=quay.io/myrepo/operator:tag PROFILE=rhdh

# Undeploy operator
make undeploy

# Uninstall CRDs
make uninstall
```

### Building and Pushing Images

```bash
# Build operator image
make image-build IMG=quay.io/myrepo/operator:tag

# Push operator image
make image-push IMG=quay.io/myrepo/operator:tag

# Build and push (for non-default architectures, specify PLATFORM)
make PLATFORM=linux/arm64 image-build image-push IMG=quay.io/myrepo/operator:tag
```

### OLM Deployment

```bash
# Install OLM (if not already present)
make install-olm

# Generate bundle manifests (for specific profile or all profiles)
make bundle PROFILE=rhdh
make bundles  # all profiles

# Build and deploy with OLM (complete workflow)
make deploy-k8s-olm IMAGE_TAG_BASE=quay.io/myrepo/operator
make deploy-openshift IMAGE_TAG_BASE=quay.io/myrepo/operator

# Update catalog source
make catalog-update OLM_NAMESPACE=olm IMAGE_TAG_BASE=quay.io/myrepo/operator

# Deploy operator via OLM
make deploy-olm

# Undeploy from OLM
make undeploy-olm
```

### End-to-End Testing

```bash
# Run E2E tests against current cluster
make test-e2e

# Test with specific image
make test-e2e IMG=quay.io/myrepo/operator:tag

# Test building local changes on kind/k3d/minikube
make test-e2e BACKSTAGE_OPERATOR_TESTS_BUILD_IMAGES=true BACKSTAGE_OPERATOR_TESTS_PLATFORM=kind

# Test with OLM
make test-e2e BACKSTAGE_OPERATOR_TEST_MODE=olm

# Test RHDH downstream builds (OpenShift only)
make test-e2e BACKSTAGE_OPERATOR_TEST_MODE=rhdh-latest
make test-e2e BACKSTAGE_OPERATOR_TEST_MODE=rhdh-next

# Test airgap scenario (OpenShift only)
make test-e2e BACKSTAGE_OPERATOR_TEST_MODE=rhdh-airgap
```

## Architecture Overview

### Directory Structure

- **`api/v1alpha{3,4,5}/`** - CRD API definitions. v1alpha5 is the current version. The `Backstage` CR is defined in `backstage_types.go`
- **`cmd/main.go`** - Operator entry point, sets up the manager and controllers
- **`internal/controller/`** - Core reconciliation logic:
  - `backstage_controller.go` - Main `BackstageReconciler` with reconciliation loop
  - `spec_preprocessor.go` - Processes and validates Backstage CR specs
  - `watchers.go` - ConfigMap/Secret watchers to trigger pod refreshes
  - `monitor.go` - Handles deployment status monitoring
  - `platform_detector.go` - Detects OpenShift vs Kubernetes
  - `plugin-deps.go` - Manages plugin dependency resolution
- **`pkg/model/`** - Transforms Backstage CR into Kubernetes runtime objects (Deployment, Service, ConfigMap, etc.)
- **`pkg/platform/`** - Platform-specific implementations (currently OpenShift routes)
- **`pkg/utils/`** - Utility functions
- **`config/`** - Kustomize configurations:
  - `config/crd/` - CRD manifests
  - `config/profile/{rhdh,backstage.io,external}/` - Configuration profiles
  - `config/profile/*/default-config/` - Default Backstage configurations per profile
  - `config/manifests/` - OLM bundle base configurations
- **`integration_tests/`** - Integration tests (Ginkgo-based)
- **`tests/e2e/`** - End-to-end tests (Ginkgo-based)
- **`examples/`** - Sample Backstage CR YAML files
- **`bundle/`** - OLM bundle manifests per profile

### Reconciliation Flow

1. **Fetch Backstage CR** - Controller retrieves the Backstage custom resource
2. **Preprocess Spec** - `spec_preprocessor.go` validates and enriches the spec with defaults
3. **Initialize Runtime Objects** - `pkg/model/` creates Kubernetes objects (Deployment, Service, ConfigMaps, Secrets, etc.)
4. **Apply Dynamic Plugins** - Processes `dynamic-plugins.yaml` and sets up init containers for plugin installation
5. **Apply to Cluster** - Creates/updates Kubernetes resources
6. **Monitor Status** - Watches Deployment status and updates Backstage CR status conditions
7. **Watch ConfigMaps/Secrets** - Triggers pod refreshes when mounted ConfigMaps/Secrets change (if using `subPath`)

### Configuration Profiles

The operator supports different runtime configurations via **profiles** (specified with `PROFILE=<name>`):

- **`rhdh`** (default) - Red Hat Developer Hub with OOTB dynamic plugins support
- **`backstage.io`** - Vanilla Backstage image
- **`external`** - Empty profile for external configurations

Each profile has:
- **`default-config/`** - Default ConfigMaps/Secrets for Backstage configuration
- **`plugin-deps/`** - Plugin dependency manifests (optional)
- **`plugin-infra/`** - Infrastructure for plugins like ArgoCD, Tekton (optional)

### Configuration Layers

The operator uses a 3-layer configuration approach (in order of precedence):

1. **Default Configuration** - From `config/profile/<PROFILE>/default-config/`, mounted in operator namespace
2. **Raw Runtime Config** - Instance-scoped ConfigMaps specified via `spec.rawRuntimeConfig`
3. **Backstage CR Spec Fields** - Direct fields in the CR (e.g., `spec.application`, `spec.database`, `spec.deployment`)

### Dynamic Plugins

Dynamic plugins are configured via:
- **`spec.application.dynamicPluginsConfigMapName`** - Reference to ConfigMap containing `dynamic-plugins.yaml`
- Init container downloads and installs plugins before Backstage starts
- Supports plugin integrity checks and dependency management
- Plugin configs can be merged from multiple sources

### Database Configuration

- **Local Database** (`spec.database.enableLocalDb=true`, default) - Deploys PostgreSQL StatefulSet in the same namespace
- **External Database** (`spec.database.enableLocalDb=false`) - Uses external database, credentials in Secret referenced by `spec.database.authSecretName`

### Status Conditions

The Backstage CR `.status.conditions[]` includes a `Deployed` condition with these reasons:

- **`DeployInProgress`** - Deployment not yet available
- **`Deployed`** - Deployment available and ready
- **`DeployFailed`** - Deployment failed (see `.status.conditions[].message`)

## Development Patterns

### Modifying CRDs

After editing files in `api/v1alpha*/`:

```bash
# Regenerate CRD manifests and deepcopy code
make manifests generate

# Reinstall CRDs if testing on cluster
make install
```

### ConfigMap/Secret Updates

- **With `subPath`** (default behavior) - Operator watches ConfigMaps/Secrets and recreates pods on changes. File structure is "convenient" (all files in same directory).
- **Without `subPath`** (specify `mountPath` without `key`) - Kubernetes auto-updates files. Operator doesn't recreate pods. Enables Backstage's file watching mechanism.

### Testing Against Real Cluster

For integration tests:

```bash
# Deploy operator to cluster first
make install deploy

# Then run integration tests pointing to that cluster
USE_EXISTING_CLUSTER=true USE_EXISTING_CONTROLLER=true make integration-test
```

For local controller iteration:

```bash
# Install CRDs
make install

# Run controller locally in terminal
make run

# In another terminal, apply Backstage CR
kubectl apply -f examples/bs1.yaml -n <namespace>
```

### OpenShift-Specific Features

Some tests and features are OpenShift-only (Routes, etc.). Tests detect the platform:

```go
if !isOpenshiftCluster() {
    Skip("Skipped for non-Openshift cluster")
}
```

### Version Compatibility Notes

- Go version: **1.24.0+**
- Kubernetes versions: Tested with 1.28.0 (see `ENVTEST_K8S_VERSION` in Makefile)
- The project uses k8s.io v0.31.3 (see `go.mod` replace directives) due to compatibility constraints with OpenShift API dependencies

### Common Gotchas

1. **Profile awareness** - Many commands support `PROFILE=<name>`. Default is `rhdh`. Be explicit when testing other profiles.
2. **LOCALBIN requirement** - Tests need `LOCALBIN=$(LOCALBIN)` to locate default-config files correctly. This is handled by Makefile targets.
3. **Bundle regeneration** - PR workflow automatically regenerates bundle manifests. Review changes in `bundle/` directory.
4. **Image tags for RHDH profile** - The RHDH profile has special version transformation logic (0.y.z → 1.y in image tags).