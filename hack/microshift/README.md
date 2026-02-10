# MicroShift Testing Scripts

Scripts to set up and test the RHDH Operator on MicroShift (lightweight OpenShift).

## Overview

MicroShift is a small-footprint OpenShift distribution designed for edge computing and CI/CD environments. These scripts enable testing OpenShift-specific features (Routes, SCCs, etc.) in GitHub Actions or locally.

**Two ways to run MicroShift locally:**

| Method | Platforms | Best For | Command |
|--------|-----------|----------|---------|
| **Containerized** | Mac, Windows, Linux | Local development on Mac/Windows | `hack/microshift/run-local.sh -d` |
| **Native** | Linux only | CI/CD, Linux development | `hack/microshift/start.sh` |

**Quick start on Mac:**
```bash
# Start MicroShift in container
hack/microshift/run-local.sh -d

# Use the cluster
export KUBECONFIG=$(pwd)/hack/microshift/output/kubeconfig
kubectl get nodes

# Stop when done
hack/microshift/run-local.sh --stop
```

## Scripts

### Native Linux Scripts

- **`install.sh`** - Install MicroShift binary and dependencies (Linux only)
- **`start.sh`** - Start MicroShift and wait for it to be ready (Linux only)
- **`stop.sh`** - Stop MicroShift gracefully (Linux only)
- **`logs.sh`** - Collect diagnostic logs for debugging (Linux only)

### Containerized Scripts (Mac/Windows/Linux)

- **`run-local.sh`** - Run MicroShift in a container (works on any platform)
- **`docker-compose.yaml`** - Docker Compose configuration
- **`Dockerfile`** - Container image definition
- **`start-container.sh`** - Container startup script (internal)

## Usage in GitHub Actions

See `.github/workflows/microshift-tests.yaml` for the full workflow.

```yaml
- name: Install MicroShift
  run: hack/microshift/install.sh

- name: Start MicroShift
  run: hack/microshift/start.sh

# Or start without OLM if not needed:
- name: Start MicroShift without OLM
  run: hack/microshift/start.sh --no-olm

- name: Run tests
  run: make integration-test USE_EXISTING_CLUSTER=true

- name: Stop MicroShift
  run: hack/microshift/stop.sh
```

## Local Usage

### Option 1: Native Linux (Direct Installation)

#### Prerequisites

- Ubuntu 20.04+ or Fedora/RHEL 8+
- At least 2GB RAM
- `sudo` access
- `kubectl` installed

#### Quick Start

```bash
# 1. Install MicroShift
hack/microshift/install.sh

# 2. Start MicroShift (with OLM by default)
hack/microshift/start.sh           # With OLM (default)
# OR
hack/microshift/start.sh --no-olm  # Without OLM

# 3. Export kubeconfig
export KUBECONFIG=/tmp/microshift-kubeconfig

# 4. Verify cluster is ready
kubectl get nodes
kubectl get pods -A

# OLM pods (installed by default):
kubectl get pods -n olm

# 5. Run operator tests
make install
make run &  # Start operator in background

# In another terminal:
make integration-test USE_EXISTING_CLUSTER=true USE_EXISTING_CONTROLLER=true

# Or test with OLM deployment:
make deploy-olm
make test-e2e BACKSTAGE_OPERATOR_TEST_MODE=olm

# 6. Stop MicroShift when done
hack/microshift/stop.sh
```

### Option 2: Containerized (Mac/Windows/Any Platform)

Use Docker or Podman to run MicroShift in a container. This works on Mac, Windows, or any system with Docker/Podman installed.

#### Prerequisites

- Docker Desktop OR Podman Desktop
- At least 4GB RAM allocated to Docker/Podman
- `kubectl` installed locally

#### Quick Start - Using Helper Script

```bash
# 1. Start MicroShift (with OLM by default)
hack/microshift/run-local.sh -d

# 2. Export kubeconfig
export KUBECONFIG=$(pwd)/hack/microshift/output/kubeconfig

# 3. Verify cluster is ready
kubectl get nodes
kubectl get pods -A

# OLM pods (installed by default):
kubectl get pods -n olm

# 4. Run operator tests
make install
make run &  # Start operator in background

# In another terminal:
make integration-test USE_EXISTING_CLUSTER=true USE_EXISTING_CONTROLLER=true

# 5. Stop MicroShift when done
hack/microshift/run-local.sh --stop
```

#### Quick Start - Using Docker Compose

```bash
# 1. Start MicroShift
cd hack/microshift
docker-compose up -d

# 2. Wait for kubeconfig to be generated
sleep 30

# 3. Export kubeconfig
export KUBECONFIG=$(pwd)/output/kubeconfig

# 4. Verify cluster
kubectl get nodes

# 5. Stop when done
docker-compose down
```

#### Helper Script Options

```bash
hack/microshift/run-local.sh [OPTIONS]

Options:
  --no-olm      Skip OLM installation
  --clean       Remove existing container and volumes before starting
  -d, --detach  Run container in background (recommended)
  --stop        Stop and remove MicroShift container
  -h, --help    Show help message

Examples:
  # Start in background (recommended)
  hack/microshift/run-local.sh -d

  # Start without OLM
  hack/microshift/run-local.sh -d --no-olm

  # Clean start (removes all data)
  hack/microshift/run-local.sh -d --clean

  # Stop
  hack/microshift/run-local.sh --stop
```

#### Accessing the Cluster

The kubeconfig is automatically exported to `hack/microshift/output/kubeconfig`:

```bash
# Set KUBECONFIG
export KUBECONFIG=$(pwd)/hack/microshift/output/kubeconfig

# Verify connection
kubectl get nodes

# Check all pods
kubectl get pods -A

# View MicroShift logs
docker logs -f microshift
# or with podman:
podman logs -f microshift
```

#### Testing the Operator

```bash
# Make sure KUBECONFIG is set
export KUBECONFIG=$(pwd)/hack/microshift/output/kubeconfig

# Install CRDs
make install

# Run operator locally (outside container)
make run &

# Deploy a Backstage instance
kubectl apply -f examples/bs1.yaml

# Check if route was created (OpenShift-specific)
kubectl get routes -n default

# Run tests
make integration-test USE_EXISTING_CLUSTER=true USE_EXISTING_CONTROLLER=true
```

#### Troubleshooting Containerized Setup

**Container won't start:**
```bash
# Check Docker/Podman is running
docker ps
# or
podman ps

# Check logs
docker logs microshift
# or
podman logs microshift

# Try clean start
hack/microshift/run-local.sh --stop
hack/microshift/run-local.sh -d --clean
```

**Kubeconfig not generated:**
```bash
# Wait longer (can take 2-3 minutes)
sleep 60

# Check if file exists
ls -la hack/microshift/output/kubeconfig

# Check container logs
docker logs microshift | tail -50
```

**API server not responding:**
```bash
# Make sure ports aren't in use
lsof -i :6443

# Restart container
hack/microshift/run-local.sh --stop
hack/microshift/run-local.sh -d
```

### Environment Variables

- `KUBECONFIG` - Path to kubeconfig file (default: `/tmp/microshift-kubeconfig`)
- `WAIT_TIMEOUT` - Timeout in seconds for startup (default: `300`)
- `MICROSHIFT_VERSION` - MicroShift version to install (default: `4.17.0`)
- `OLM_VERSION` - OLM version to install (default: `v0.28.0`, skipped with `--no-olm`)

### Command-Line Flags

**`start.sh`:**
- `--no-olm` - Skip installing Operator Lifecycle Manager (OLM is installed by default)

## Testing OpenShift-Specific Features

MicroShift provides these OpenShift APIs:

- **Routes** - OpenShift's native ingress mechanism
- **Security Context Constraints (SCCs)** - Pod security policies
- **Projects** - Namespace wrapper with additional metadata
- **Image Streams** - Container image management
- **DeploymentConfigs** - OpenShift deployment resources

### Example: Test Routes

```bash
# Create a test route
kubectl create route edge test-route \
  --service=my-service \
  --port=8080

# Verify route was created
kubectl get routes
```

### Example: Verify Operator on MicroShift

```bash
# Start MicroShift
hack/microshift/start.sh

# Deploy operator
make install deploy IMG=localhost/operator:test

# Create a Backstage CR
kubectl apply -f examples/bs1.yaml

# Check if route was created (OpenShift-specific)
kubectl get routes -n default

# Cleanup
make undeploy
hack/microshift/stop.sh
```

## Troubleshooting

### MicroShift won't start

```bash
# Check logs
tail -f /tmp/microshift.log

# Verify dependencies
which conntrack iptables socat

# Check if ports are in use
sudo ss -tulpn | grep -E ':(6443|10250|10251|10252|10259|10257|2379|2380)'
```

### Kubeconfig not generated

```bash
# Check if MicroShift is running
ps aux | grep microshift

# Check logs
tail -100 /tmp/microshift.log

# Verify directories exist
ls -la /var/lib/microshift/resources/kubeadmin/
```

### API server not responding

```bash
# Wait longer (can take 2-3 minutes on first start)
export WAIT_TIMEOUT=600
hack/microshift/start.sh

# Check if etcd is ready
sudo journalctl -u microshift | grep etcd
```

### Cleanup stuck resources

```bash
# Stop MicroShift
hack/microshift/stop.sh

# Clean up data (WARNING: deletes all cluster data)
sudo rm -rf /var/lib/microshift/*

# Restart
hack/microshift/start.sh
```

## OLM (Operator Lifecycle Manager) Support

MicroShift **does NOT include OLM by default**, but our `start.sh` script **installs it automatically**.

To skip OLM installation, use the `--no-olm` flag:

```bash
hack/microshift/start.sh --no-olm  # Skip OLM installation
```

OLM v0.28.0 (configurable via `OLM_VERSION` env var) is installed by default and enables:
- Installing operators from catalogs
- Managing operator subscriptions
- Testing OLM deployment mode for RHDH operator

**Note:** OLM installation uses server-side apply to avoid annotation size limits. See [OLM Issue #2778](https://github.com/operator-framework/operator-lifecycle-manager/issues/2778) for details.

### Testing RHDH Operator with OLM

```bash
# 1. Start MicroShift (OLM installed by default)
hack/microshift/start.sh
export KUBECONFIG=/tmp/microshift-kubeconfig

# 2. Build and push operator catalog
make catalog-build catalog-push IMAGE_TAG_BASE=quay.io/yourorg/operator

# 3. Deploy via OLM
make deploy-olm IMAGE_TAG_BASE=quay.io/yourorg/operator

# 4. Run OLM-specific E2E tests
make test-e2e BACKSTAGE_OPERATOR_TEST_MODE=olm
```

## Differences from Full OpenShift

MicroShift is not identical to full OpenShift. Key differences:

- **Single node only** - No multi-node clusters
- **No web console** - CLI only
- **No OLM by default** - Our scripts install it automatically (skip with `--no-olm`)
- **Limited operators** - Only essential operators included
- **Simplified networking** - Uses basic CNI
- **Resource limits** - Designed for <2GB RAM

For production OpenShift testing, consider:
- OpenShift Local (CRC) for local development
- Remote OpenShift cluster for full integration tests
- OpenShift Sandbox for temporary testing

## CI/CD Integration

### GitHub Actions

Already configured in `.github/workflows/microshift-tests.yaml`.

Runs nightly and can be triggered manually:
- Go to Actions tab → "MicroShift Integration Tests" → "Run workflow"

### GitLab CI

```yaml
test-microshift:
  image: ubuntu:22.04
  script:
    - hack/microshift/install.sh
    - hack/microshift/start.sh
    - make integration-test USE_EXISTING_CLUSTER=true
  after_script:
    - hack/microshift/stop.sh
```

### Jenkins

```groovy
stage('MicroShift Tests') {
  steps {
    sh 'hack/microshift/install.sh'
    sh 'hack/microshift/start.sh'
    sh 'make integration-test USE_EXISTING_CLUSTER=true'
  }
  post {
    always {
      sh 'hack/microshift/stop.sh'
    }
  }
}
```

## Resources

- [MicroShift Documentation](https://microshift.io/)
- [MicroShift GitHub Repository](https://github.com/openshift/microshift)
- [OpenShift Documentation](https://docs.openshift.com/)
