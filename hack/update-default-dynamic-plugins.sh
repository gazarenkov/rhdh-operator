#!/bin/bash
# Extract dynamic-plugins.default.yaml from catalog-index image
# and update it in config/profile/rhdh/default-config/
#
# Usage: Run from project root:
#   ./hack/update-default-dynamic-plugins.sh
#   IMAGE=quay.io/rhdh/plugin-catalog-index:1.10 ./hack/update-default-dynamic-plugins.sh

set -euo pipefail

# Save current directory (project root)
PROJECT_ROOT="$(pwd)"

IMAGE="${IMAGE:-quay.io/rhdh/plugin-catalog-index:latest}"
OUTPUT_FILE="config/profile/rhdh/default-config/default-dynamic-plugins.yaml"

# Verify we're in project root
if [ ! -f "go.mod" ] || [ ! -d "config/profile/rhdh" ]; then
  echo "Error: This script must be run from the project root directory"
  echo "Usage: ./hack/update-default-dynamic-plugins.sh"
  exit 1
fi

# Convert OUTPUT_FILE to absolute path
OUTPUT_FILE="${PROJECT_ROOT}/${OUTPUT_FILE}"

echo "=== Updating dynamic-plugins.default.yaml from catalog-index ==="
echo "Source image: ${IMAGE}"
echo "Output file: ${OUTPUT_FILE}"
echo ""

# Pull the image for AMD64 platform
echo "Pulling image..."
docker pull --platform linux/amd64 "${IMAGE}"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo "Extracting dynamic-plugins.default.yaml from image..."
cd "${TEMP_DIR}"

# Save and extract the image
docker save "${IMAGE}" -o image.tar
tar -xf image.tar
rm image.tar

# Find the layer with the data
# Parse manifest.json to get layer paths
LAYERS=$(grep -o '"blobs/sha256/[^"]*"' manifest.json | sed 's/"//g' | grep -v "^blobs/sha256/[a-f0-9]*$" || true)

# If that didn't work, get all blob files
if [ -z "$LAYERS" ]; then
  LAYERS=$(find blobs/sha256 -type f)
fi

echo "Found layers:"
echo "$LAYERS"

# Extract the layer
mkdir -p rootfs

# Try each layer until we find the one with dynamic-plugins.default.yaml
FOUND=false
for layer in $LAYERS; do
  echo "Trying layer: $layer"
  if tar -tzf "$layer" 2>/dev/null | grep -q "dynamic-plugins.default.yaml"; then
    echo "Found dynamic-plugins.default.yaml in layer: $layer"
    tar -xzf "$layer" -C rootfs
    FOUND=true
    break
  fi
done

if [ "$FOUND" = false ]; then
  echo "Error: Could not find dynamic-plugins.default.yaml in any layer"
  echo "Available layers:"
  ls -lh blobs/sha256/
  exit 1
fi

# Check if dynamic-plugins.default.yaml exists
if [ ! -f "rootfs/dynamic-plugins.default.yaml" ]; then
  echo "Error: dynamic-plugins.default.yaml not found in image"
  echo "Contents of rootfs:"
  ls -la rootfs
  exit 1
fi

# Create ConfigMap with the extracted content
echo "Creating ConfigMap at ${OUTPUT_FILE}..."

# Create ConfigMap header
cat > "${OUTPUT_FILE}" <<'EOF'
# WARNING: This file is auto-generated!
#
# This file is automatically extracted from the catalog-index image
# by ./hack/update-default-dynamic-plugins.sh
# Do not edit manually - your changes will be overwritten.
#
apiVersion: v1
kind: ConfigMap
metadata:
  name: default-dynamic-plugins
data:
  dynamic-plugins.yaml: |
EOF

# Append the extracted content with proper indentation (4 spaces)
sed 's/^/    /' rootfs/dynamic-plugins.default.yaml >> "${OUTPUT_FILE}"

echo ""
echo "=== Update complete ==="
echo "File updated: ${OUTPUT_FILE}"
echo "File size: $(du -h "${OUTPUT_FILE}" | cut -f1)"
echo "Total lines: $(wc -l < "${OUTPUT_FILE}")"