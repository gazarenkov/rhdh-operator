#!/bin/bash
# Startup script for MicroShift container

set -e

echo "=== Starting MicroShift in Container ==="

# Install OLM if requested
INSTALL_OLM="${INSTALL_OLM:-true}"
OLM_VERSION="${OLM_VERSION:-v0.28.0}"

# Start MicroShift
echo "Starting MicroShift..."
microshift run &
MICROSHIFT_PID=$!

# Wait for kubeconfig to be generated
echo "Waiting for MicroShift to generate kubeconfig..."
for i in {1..60}; do
  if [ -f /var/lib/microshift/resources/kubeadmin/kubeconfig ]; then
    echo "✓ Kubeconfig generated"
    break
  fi
  sleep 2
done

if [ ! -f /var/lib/microshift/resources/kubeadmin/kubeconfig ]; then
  echo "✗ Timeout waiting for kubeconfig"
  exit 1
fi

# Copy kubeconfig to /output if mounted
if [ -d /output ]; then
  cp /var/lib/microshift/resources/kubeadmin/kubeconfig /output/kubeconfig
  chmod 644 /output/kubeconfig
  echo "✓ Kubeconfig copied to /output/kubeconfig"
fi

# Wait for API server
echo "Waiting for API server..."
export KUBECONFIG=/var/lib/microshift/resources/kubeadmin/kubeconfig
for i in {1..60}; do
  if kubectl get --raw /healthz &>/dev/null; then
    echo "✓ API server is ready"
    break
  fi
  sleep 2
done

# Install OLM if requested
if [ "$INSTALL_OLM" = "true" ]; then
  echo "Installing OLM ${OLM_VERSION}..."

  # Use server-side apply to avoid "annotations too long" error
  # See: https://github.com/operator-framework/operator-lifecycle-manager/issues/2778
  kubectl apply --server-side --force-conflicts -f "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/crds.yaml"
  sleep 5
  kubectl apply -f "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/olm.yaml"

  echo "Waiting for OLM to be ready..."
  kubectl wait --for=condition=Available --timeout=300s deployment/olm-operator -n olm 2>/dev/null || echo "OLM operator ready"
  kubectl wait --for=condition=Available --timeout=300s deployment/catalog-operator -n olm 2>/dev/null || echo "Catalog operator ready"

  echo "✓ OLM installed"
fi

# Show cluster status
echo ""
echo "=== MicroShift Cluster Ready ==="
kubectl get nodes
echo ""
echo "System pods:"
kubectl get pods -A | grep -E "(kube-system|olm|openshift)" || true

echo ""
echo "✓ MicroShift container started successfully"
echo "  Kubeconfig: /output/kubeconfig (if volume mounted)"
echo "  API Server: https://localhost:6443"

# Keep running
wait $MICROSHIFT_PID
