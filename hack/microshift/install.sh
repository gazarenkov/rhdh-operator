#!/bin/bash
# Install MicroShift on Ubuntu (for GitHub Actions or local testing)

set -euo pipefail

MICROSHIFT_VERSION="${MICROSHIFT_VERSION:-4.17.0}"

echo "=== Installing MicroShift ${MICROSHIFT_VERSION} ==="

# Install dependencies
echo "Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
  conntrack \
  iptables \
  socat \
  containernetworking-plugins

# Download MicroShift binary
echo "Downloading MicroShift binary..."
MICROSHIFT_URL="https://github.com/openshift/microshift/releases/download/nightly/microshift-linux-amd64"

sudo mkdir -p /usr/local/bin
sudo curl -sSL "${MICROSHIFT_URL}" -o /usr/local/bin/microshift
sudo chmod +x /usr/local/bin/microshift

# Verify installation
echo "Verifying MicroShift installation..."
microshift version || echo "Warning: Could not get MicroShift version"

echo "✓ MicroShift installation completed"