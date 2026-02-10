#!/bin/bash
# Script to measure operator memory consumption
# Supports both local controller and cluster-deployed controller

set -e

MODE="${MODE:-local}"  # local or cluster
DURATION="${DURATION:-300}"  # Measure for 5 minutes by default
INTERVAL="${INTERVAL:-5}"    # Sample every 5 seconds
OUTPUT_FILE="${OUTPUT_FILE:-memory-measurements-${MODE}.csv}"

# Cluster mode variables
NAMESPACE="${NAMESPACE:-rhdh-operator}"
LABEL_SELECTOR="${LABEL_SELECTOR:-control-plane=controller-manager}"

# Local mode variables
PROCESS_NAME="${PROCESS_NAME:-}"  # Empty means auto-detect
PROCESS_PID="${PROCESS_PID:-}"    # Can specify PID directly

case "$MODE" in
    local)
        echo "=== Local Controller Memory Measurement ==="
        if [ -n "$PROCESS_PID" ]; then
            echo "Using specified PID: ${PROCESS_PID}"
        elif [ -n "$PROCESS_NAME" ]; then
            echo "Process name pattern: ${PROCESS_NAME}"
        else
            echo "Auto-detecting controller process..."
        fi
        ;;
    cluster)
        echo "=== Cluster Controller Memory Measurement ==="
        echo "Namespace: ${NAMESPACE}"
        echo "Label selector: ${LABEL_SELECTOR}"
        ;;
    *)
        echo "ERROR: MODE must be 'local' or 'cluster'"
        exit 1
        ;;
esac

echo "Duration: ${DURATION} seconds"
echo "Sampling interval: ${INTERVAL} seconds"
echo "Output file: ${OUTPUT_FILE}"
echo ""

# Function to get PID of local controller
get_local_pid() {
    local pid=""

    # If PID specified directly, use it
    if [ -n "$PROCESS_PID" ]; then
        if kill -0 "$PROCESS_PID" 2>/dev/null; then
            echo "$PROCESS_PID"
            return
        else
            echo "ERROR: Process with PID ${PROCESS_PID} not found or not accessible"
            exit 1
        fi
    fi

    # If PROCESS_NAME specified, use it
    if [ -n "$PROCESS_NAME" ]; then
        pid=$(pgrep -f "$PROCESS_NAME" | head -1)
        if [ -n "$pid" ]; then
            echo "$pid"
            return
        fi
        echo "ERROR: No process found matching '${PROCESS_NAME}'"
        echo ""
        echo "Available processes:"
        ps aux | grep -E "go|manager|controller|cmd/main" | grep -v grep
        exit 1
    fi

    # Auto-detect: try common patterns
    # 1. Try go run with cmd/main.go
    pid=$(pgrep -f "go run.*cmd/main.go" | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return
    fi

    # 2. Try bin/manager
    pid=$(pgrep -f "bin/manager" | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return
    fi

    # 3. Try any process with "backstage" and "operator" or "controller"
    pid=$(pgrep -f "backstage.*operator\|backstage.*controller" | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return
    fi

    # 4. Try rhdh-operator
    pid=$(pgrep -f "rhdh-operator" | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return
    fi

    echo "ERROR: Could not auto-detect controller process"
    echo ""
    echo "Please specify PROCESS_PID or PROCESS_NAME environment variable"
    echo ""
    echo "Available Go processes:"
    ps aux | grep -E "go|manager|controller|cmd/main" | grep -v grep
    echo ""
    echo "Example usage:"
    echo "  PROCESS_PID=12345 MODE=local ./tests/measure-memory.sh"
    echo "  PROCESS_NAME='cmd/main.go' MODE=local ./tests/measure-memory.sh"
    exit 1
}

# Function to measure local process memory
measure_local_memory() {
    local pid=$1

    # On macOS, use ps; on Linux, can use /proc
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: RSS is in KB
        local rss_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -z "$rss_kb" ]; then
            echo "0,0"
            return
        fi
        local memory_bytes=$((rss_kb * 1024))
        local memory_mi=$(echo "scale=2; $rss_kb / 1024" | bc)
    else
        # Linux: use /proc
        if [ ! -f "/proc/$pid/status" ]; then
            echo "0,0"
            return
        fi
        local rss_kb=$(grep VmRSS /proc/$pid/status | awk '{print $2}')
        local memory_bytes=$((rss_kb * 1024))
        local memory_mi=$(echo "scale=2; $rss_kb / 1024" | bc)
    fi

    echo "${memory_mi},${memory_bytes}"
}

# Function to measure cluster pod memory
measure_cluster_memory() {
    local pod_name=$1

    MEMORY=$(kubectl top pod -n "${NAMESPACE}" "${pod_name}" --no-headers 2>/dev/null | awk '{print $3}')

    if [ -z "$MEMORY" ]; then
        echo "0,0"
        return
    fi

    # Convert to bytes (handle Mi suffix)
    MEMORY_BYTES=$(echo "$MEMORY" | sed 's/Mi//' | awk '{printf "%.0f", $1 * 1024 * 1024}')
    MEMORY_MI=$(echo "$MEMORY" | sed 's/Mi//')

    echo "${MEMORY_MI},${MEMORY_BYTES}"
}

# Initialize based on mode
if [ "$MODE" = "local" ]; then
    PID=$(get_local_pid)
    echo "Found controller process with PID: ${PID}"
    echo "Process info:"
    ps -p "$PID" -o pid,ppid,user,%cpu,%mem,rss,command
    echo ""
else
    # Check if metrics-server is available
    if ! kubectl top nodes &>/dev/null; then
        echo "ERROR: kubectl top is not working. Make sure metrics-server is installed."
        exit 1
    fi

    # Find the operator pod
    POD_NAME=$(kubectl get pods -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$POD_NAME" ]; then
        echo "ERROR: No pod found with label ${LABEL_SELECTOR} in namespace ${NAMESPACE}"
        exit 1
    fi
    echo "Found operator pod: ${POD_NAME}"
    echo ""
fi

# Initialize CSV file
echo "timestamp,memory_mi,memory_bytes" > "${OUTPUT_FILE}"

# Calculate number of samples
NUM_SAMPLES=$((DURATION / INTERVAL))

echo "Starting measurement (${NUM_SAMPLES} samples)..."
echo ""

# Store measurements
declare -a memory_values=()

for i in $(seq 1 $NUM_SAMPLES); do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Get memory based on mode
    if [ "$MODE" = "local" ]; then
        MEMORY_DATA=$(measure_local_memory "$PID")

        # Check if process still exists
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "ERROR: Controller process (PID: $PID) is no longer running"
            exit 1
        fi
    else
        MEMORY_DATA=$(measure_cluster_memory "$POD_NAME")
    fi

    MEMORY_MI=$(echo "$MEMORY_DATA" | cut -d, -f1)
    MEMORY_BYTES=$(echo "$MEMORY_DATA" | cut -d, -f2)

    memory_values+=($MEMORY_MI)

    # Write to CSV
    echo "${TIMESTAMP},${MEMORY_MI},${MEMORY_BYTES}" >> "${OUTPUT_FILE}"

    # Display current reading
    printf "[%3d/%3d] %s - Memory: %.2f MiB\n" "$i" "$NUM_SAMPLES" "$TIMESTAMP" "$MEMORY_MI"

    # Sleep until next sample (skip on last iteration)
    if [ $i -lt $NUM_SAMPLES ]; then
        sleep $INTERVAL
    fi
done

echo ""
echo "Measurement complete!"
echo ""

# Calculate statistics
sum=0
count=${#memory_values[@]}
min=${memory_values[0]}
max=${memory_values[0]}

for val in "${memory_values[@]}"; do
    sum=$(echo "$sum + $val" | bc 2>/dev/null || echo "$sum")
    if (( $(echo "$val < $min" | bc -l 2>/dev/null || echo 0) )); then
        min=$val
    fi
    if (( $(echo "$val > $max" | bc -l 2>/dev/null || echo 0) )); then
        max=$val
    fi
done

avg=$(echo "scale=2; $sum / $count" | bc 2>/dev/null || echo "0")

echo "Statistics (MiB):"
echo "  Minimum:  ${min}"
echo "  Maximum:  ${max}"
echo "  Average:  ${avg}"
echo "  Samples:  ${count}"
echo ""
echo "Data saved to: ${OUTPUT_FILE}"
