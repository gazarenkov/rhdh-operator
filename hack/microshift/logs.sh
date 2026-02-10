#!/bin/bash
# Collect MicroShift and cluster logs for debugging

set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-/tmp/microshift-kubeconfig}"
export KUBECONFIG="${KUBECONFIG_PATH}"

echo "=== MicroShift Diagnostics ==="

echo ""
echo "--- MicroShift Service Logs (last 100 lines) ---"
tail -100 /tmp/microshift.log 2>/dev/null || echo "No MicroShift logs found"

echo ""
echo "--- Cluster Nodes ---"
kubectl get nodes -o wide 2>/dev/null || echo "Could not get nodes"

echo ""
echo "--- All Pods ---"
kubectl get pods -A -o wide 2>/dev/null || echo "Could not get pods"

echo ""
echo "--- Failed/Pending Pods ---"
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null || echo "No failed pods or could not query"

echo ""
echo "--- Backstage Resources ---"
kubectl get backstage -A 2>/dev/null || echo "No Backstage resources found"

echo ""
echo "--- Recent Events ---"
kubectl get events -A --sort-by='.lastTimestamp' | tail -20 2>/dev/null || echo "Could not get events"

echo ""
echo "=== End of Diagnostics ==="
