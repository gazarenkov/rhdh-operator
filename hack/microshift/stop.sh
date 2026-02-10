#!/bin/bash
# Stop MicroShift and cleanup

set -euo pipefail

echo "=== Stopping MicroShift ==="

# Kill MicroShift process
if [ -f /tmp/microshift.pid ]; then
  MICROSHIFT_PID=$(cat /tmp/microshift.pid)
  echo "Stopping MicroShift (PID: $MICROSHIFT_PID)..."
  sudo kill "$MICROSHIFT_PID" 2>/dev/null || true
  rm -f /tmp/microshift.pid
else
  echo "Stopping any running MicroShift processes..."
  sudo pkill -f "microshift run" || true
fi

# Wait for process to stop
sleep 5

# Optional: Clean up data (uncomment if needed)
# echo "Cleaning up MicroShift data..."
# sudo rm -rf /var/lib/microshift/*

echo "✓ MicroShift stopped"
