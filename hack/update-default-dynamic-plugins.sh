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

# Find the layers from manifest.json
# Docker images are built from multiple layers stacked together
# We need to extract ALL layers in order to build the complete filesystem
LAYERS=$(python3 -c "
import json
with open('manifest.json') as f:
    manifest = json.load(f)
    for layer in manifest[0]['Layers']:
        print(layer)
" 2>/dev/null || grep -o '"Layers":\s*\[[^]]*\]' manifest.json | grep -o '"blobs/[^"]*"' | sed 's/"//g')

if [ -z "$LAYERS" ]; then
  echo "Error: Could not parse layers from manifest.json"
  echo "manifest.json content:"
  cat manifest.json
  exit 1
fi

echo "Found layers (will extract all in order):"
echo "$LAYERS"
echo ""

# Extract all layers
mkdir -p rootfs

for layer in $LAYERS; do
  echo "Extracting layer: $layer ($(du -h "$layer" 2>/dev/null | cut -f1 || echo 'unknown size'))"

  # Check if it's a gzipped file
  if ! gunzip -t "$layer" 2>/dev/null; then
    echo "  Skipping (not a gzipped tar file)"
    continue
  fi

  # Extract the layer (later layers overwrite earlier ones)
  tar -xzf "$layer" -C rootfs 2>/dev/null || echo "  Warning: Failed to extract layer"
done

echo ""
echo "Extraction complete. Filesystem contents:"
ls -lh rootfs/ | head -20

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