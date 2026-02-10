#!/bin/bash
# Start MicroShift and wait for it to be ready

set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-/tmp/microshift-kubeconfig}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"
INSTALL_OLM=true
OLM_VERSION="${OLM_VERSION:-v0.27.0}"  # v0.28.0 has annotation size issues

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-olm)
      INSTALL_OLM=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--no-olm]"
      exit 1
      ;;
  esac
done

echo "=== Starting MicroShift ==="

# Create required directories
echo "Creating MicroShift directories..."
sudo mkdir -p /var/lib/microshift/manifests
sudo mkdir -p /var/lib/microshift/resources/kubeadmin
sudo mkdir -p /etc/microshift

# Create MicroShift config
echo "Creating MicroShift configuration..."
sudo tee /etc/microshift/config.yaml > /dev/null <<EOF
apiServer:
  subjectAltNames:
    - microshift.local
    - localhost
  auditLog:
    profile: Default
network:
  clusterNetwork:
    - 10.42.0.0/16
  serviceNetwork:
    - 10.43.0.0/16
EOF

# Start MicroShift in background
echo "Starting MicroShift service..."
sudo microshift run &> /tmp/microshift.log &
MICROSHIFT_PID=$!
echo "MicroShift started with PID: $MICROSHIFT_PID"
echo "$MICROSHIFT_PID" > /tmp/microshift.pid

# Wait for kubeconfig to be generated
echo "Waiting for MicroShift to generate kubeconfig..."
SECONDS=0
while [ $SECONDS -lt $WAIT_TIMEOUT ]; do
  if sudo test -f /var/lib/microshift/resources/kubeadmin/kubeconfig; then
    echo "✓ Kubeconfig generated after ${SECONDS}s"
    break
  fi

  if [ $((SECONDS % 10)) -eq 0 ]; then
    echo "  Still waiting for kubeconfig... (${SECONDS}s/${WAIT_TIMEOUT}s)"
  fi
  sleep 2
done

if ! sudo test -f /var/lib/microshift/resources/kubeadmin/kubeconfig; then
  echo "✗ Timeout waiting for kubeconfig"
  echo "=== MicroShift logs ==="
  tail -50 /tmp/microshift.log || true
  exit 1
fi

# Copy kubeconfig to accessible location
echo "Copying kubeconfig to ${KUBECONFIG_PATH}..."
sudo cp /var/lib/microshift/resources/kubeadmin/kubeconfig "${KUBECONFIG_PATH}"
sudo chmod 644 "${KUBECONFIG_PATH}"

export KUBECONFIG="${KUBECONFIG_PATH}"

# Wait for API server to be ready
echo "Waiting for API server to respond..."
SECONDS=0
while [ $SECONDS -lt $WAIT_TIMEOUT ]; do
  if kubectl get --raw /healthz &>/dev/null; then
    echo "✓ API server is ready after ${SECONDS}s"
    break
  fi

  if [ $((SECONDS % 10)) -eq 0 ]; then
    echo "  Still waiting for API server... (${SECONDS}s/${WAIT_TIMEOUT}s)"
  fi
  sleep 2
done

if ! kubectl get --raw /healthz &>/dev/null; then
  echo "✗ Timeout waiting for API server"
  echo "=== MicroShift logs ==="
  tail -50 /tmp/microshift.log || true
  exit 1
fi

# Wait for node to be ready
echo "Waiting for node to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=${WAIT_TIMEOUT}s

# Display cluster info
echo ""
echo "=== MicroShift cluster is ready ==="
echo "Nodes:"
kubectl get nodes -o wide

echo ""
echo "System pods:"
kubectl get pods -A

echo ""
echo "OpenShift APIs available:"
kubectl api-resources | grep -E "(route|security|image|project)" || echo "  (checking...)"

echo ""
echo "✓ MicroShift setup completed successfully"
echo "  KUBECONFIG=${KUBECONFIG_PATH}"

# Install OLM if requested
if [ "$INSTALL_OLM" = true ]; then
  echo ""
  echo "=== Installing OLM ${OLM_VERSION} ==="

  # Check if OLM is already installed
  if kubectl get deployment olm-operator -n olm &>/dev/null; then
    echo "⚠️  OLM is already installed"
  else
    echo "Installing OLM CRDs..."
    kubectl apply -f "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/crds.yaml"

    echo "Waiting for CRDs to be established..."
    sleep 5

    echo "Installing OLM operators..."
    kubectl apply -f "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/olm.yaml"

    echo "Waiting for OLM to be ready..."
    kubectl wait --for=condition=Available --timeout=300s deployment/olm-operator -n olm
    kubectl wait --for=condition=Available --timeout=300s deployment/catalog-operator -n olm
    kubectl wait --for=condition=Available --timeout=300s deployment/packageserver -n olm || echo "Packageserver check completed"

    echo ""
    echo "OLM Pods:"
    kubectl get pods -n olm

    echo ""
    echo "✓ OLM installation completed"
  fi

  echo ""
  echo "Next steps for OLM deployment:"
  echo "  1. Build and push catalog: make catalog-build catalog-push"
  echo "  2. Deploy operator via OLM: make deploy-olm"
  echo "  3. Run OLM tests: make test-e2e BACKSTAGE_OPERATOR_TEST_MODE=olm"
fi
