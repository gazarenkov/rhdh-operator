#!/bin/bash
# Helper script to find the controller process

echo "Looking for controller processes..."
echo ""

# Look for Go processes related to the operator
echo "=== Go processes that might be the controller ==="
ps aux | grep -E "go run|cmd/main.go|bin/manager|rhdh-operator" | grep -v grep

echo ""
echo "=== All Go processes ==="
ps aux | grep go | grep -v grep

echo ""
echo "Recommended: Use the PID from 'go run' or 'bin/manager' process above"
echo ""
echo "To use with measure-memory.sh, either:"
echo "  1. Set PROCESS_NAME to match the pattern (e.g., 'cmd/main.go')"
echo "  2. Or just run: ps aux | grep 'cmd/main.go' | grep -v grep"
echo "     Then use the PID directly if needed"
