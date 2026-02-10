#!/bin/bash
# Run MicroShift locally using Docker/Podman (for Mac/Windows)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"

# Detect container runtime
if command -v docker &> /dev/null; then
    CONTAINER_RUNTIME="docker"
elif command -v podman &> /dev/null; then
    CONTAINER_RUNTIME="podman"
else
    echo "Error: Neither docker nor podman found. Please install one of them."
    exit 1
fi

echo "Using container runtime: ${CONTAINER_RUNTIME}"

# Parse arguments
INSTALL_OLM=true
CLEAN_START=false
DETACH=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-olm)
      INSTALL_OLM=false
      shift
      ;;
    --clean)
      CLEAN_START=true
      shift
      ;;
    -d|--detach)
      DETACH=true
      shift
      ;;
    --stop)
      echo "Stopping MicroShift container..."
      ${CONTAINER_RUNTIME} stop microshift 2>/dev/null || true
      ${CONTAINER_RUNTIME} rm microshift 2>/dev/null || true
      echo "✓ MicroShift stopped"
      exit 0
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --no-olm      Skip OLM installation"
      echo "  --clean       Remove existing container and volumes before starting"
      echo "  -d, --detach  Run container in background"
      echo "  --stop        Stop and remove MicroShift container"
      echo "  -h, --help    Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run with --help for usage information"
      exit 1
      ;;
  esac
done

# Clean start if requested
if [ "$CLEAN_START" = true ]; then
  echo "Cleaning up existing MicroShift container and data..."
  ${CONTAINER_RUNTIME} stop microshift 2>/dev/null || true
  ${CONTAINER_RUNTIME} rm microshift 2>/dev/null || true
  ${CONTAINER_RUNTIME} volume rm microshift_microshift-data 2>/dev/null || true
  rm -rf "${OUTPUT_DIR}"
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Build container image if needed
echo "Building MicroShift container image..."
cd "${SCRIPT_DIR}"
${CONTAINER_RUNTIME} build -t microshift:local .

# Run container
echo "Starting MicroShift container..."
RUN_ARGS=(
  run
  --name microshift
  --hostname microshift
  --privileged
  --cap-add SYS_ADMIN
  --cap-add NET_ADMIN
  -e "INSTALL_OLM=${INSTALL_OLM}"
  -e "OLM_VERSION=${OLM_VERSION:-v0.28.0}"
  -p 6443:6443
  -p 10250:10250
  -v "${OUTPUT_DIR}:/output"
)

if [ "$DETACH" = true ]; then
  RUN_ARGS+=(-d)
else
  RUN_ARGS+=(--rm)
fi

${CONTAINER_RUNTIME} "${RUN_ARGS[@]}" microshift:local

# If running detached, wait for kubeconfig
if [ "$DETACH" = true ]; then
  echo ""
  echo "Waiting for kubeconfig to be generated..."
  for i in {1..60}; do
    if [ -f "${OUTPUT_DIR}/kubeconfig" ]; then
      echo "✓ Kubeconfig ready at ${OUTPUT_DIR}/kubeconfig"
      break
    fi
    sleep 2
  done

  echo ""
  echo "=== MicroShift is running in background ==="
  echo ""
  echo "To use the cluster:"
  echo "  export KUBECONFIG=${OUTPUT_DIR}/kubeconfig"
  echo "  kubectl get nodes"
  echo ""
  echo "To view logs:"
  echo "  ${CONTAINER_RUNTIME} logs -f microshift"
  echo ""
  echo "To stop:"
  echo "  $0 --stop"
  echo "  # or: ${CONTAINER_RUNTIME} stop microshift"
fi
