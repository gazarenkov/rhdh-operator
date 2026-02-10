#!/bin/bash
# Script to take a memory snapshot using pprof
# This shows exactly what's using memory

set -e

CONTROLLER_URL="${CONTROLLER_URL:-http://localhost:8080}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-memory-profile}"

echo "=== Memory Profile Snapshot ==="
echo "Controller URL: ${CONTROLLER_URL}"
echo ""

# Check if pprof endpoint is accessible
if ! curl -s "${CONTROLLER_URL}/debug/pprof/" > /dev/null 2>&1; then
    echo "ERROR: Cannot reach pprof endpoint at ${CONTROLLER_URL}/debug/pprof/"
    echo ""
    echo "The controller needs to have pprof enabled."
    echo "By default, controller-runtime exposes pprof at :8080/debug/pprof/"
    echo ""
    echo "Try accessing: ${CONTROLLER_URL}/debug/pprof/"
    exit 1
fi

echo "✓ Pprof endpoint is accessible"
echo ""

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
HEAP_FILE="${OUTPUT_PREFIX}-${TIMESTAMP}.heap"
ALLOCS_FILE="${OUTPUT_PREFIX}-${TIMESTAMP}.allocs"

# Download heap profile
echo "Downloading heap profile..."
curl -s "${CONTROLLER_URL}/debug/pprof/heap" > "${HEAP_FILE}"
echo "✓ Saved to: ${HEAP_FILE}"

# Download allocs profile
echo "Downloading allocs profile..."
curl -s "${CONTROLLER_URL}/debug/pprof/allocs" > "${ALLOCS_FILE}"
echo "✓ Saved to: ${ALLOCS_FILE}"

echo ""
echo "=== Quick Analysis ==="
echo ""

# Check if go tool pprof is available
if ! command -v go &> /dev/null; then
    echo "Go toolchain not found. Cannot analyze profiles."
    echo "You can analyze the profiles later with:"
    echo "  go tool pprof -top ${HEAP_FILE}"
    echo "  go tool pprof -http=:8081 ${HEAP_FILE}"
    exit 0
fi

echo "Top memory consumers (heap):"
go tool pprof -top -nodefraction=0.01 "${HEAP_FILE}" 2>/dev/null | head -20

echo ""
echo "To view interactive analysis, run:"
echo "  go tool pprof -http=:8081 ${HEAP_FILE}"
echo ""
echo "To compare two profiles (before/after):"
echo "  go tool pprof -http=:8081 -base ${OUTPUT_PREFIX}-before.heap ${OUTPUT_PREFIX}-after.heap"
