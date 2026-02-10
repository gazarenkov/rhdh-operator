#!/bin/bash
# Script to measure Go heap memory using pprof
# This is more accurate than measuring RSS

set -e

CONTROLLER_URL="${CONTROLLER_URL:-http://localhost:8080}"
DURATION="${DURATION:-60}"
INTERVAL="${INTERVAL:-5}"
OUTPUT_FILE="${OUTPUT_FILE:-heap-measurements.csv}"

echo "=== Go Heap Memory Measurement ==="
echo "Controller metrics URL: ${CONTROLLER_URL}"
echo "Duration: ${DURATION} seconds"
echo "Sampling interval: ${INTERVAL} seconds"
echo "Output file: ${OUTPUT_FILE}"
echo ""

# Check if controller is accessible
if ! curl -s "${CONTROLLER_URL}/metrics" > /dev/null 2>&1; then
    echo "ERROR: Cannot reach controller metrics endpoint at ${CONTROLLER_URL}/metrics"
    echo ""
    echo "Make sure the controller is running and metrics are exposed."
    echo "If running locally with 'make run', metrics should be at http://localhost:8080/metrics"
    echo ""
    echo "You can check with:"
    echo "  curl ${CONTROLLER_URL}/metrics | grep process_resident_memory"
    exit 1
fi

echo "✓ Controller is accessible"
echo ""

# Initialize CSV file
echo "timestamp,heap_alloc_mb,heap_inuse_mb,heap_sys_mb,total_alloc_mb" > "${OUTPUT_FILE}"

# Calculate number of samples
NUM_SAMPLES=$((DURATION / INTERVAL))

echo "Starting measurement (${NUM_SAMPLES} samples)..."
echo ""

# Store measurements
declare -a heap_inuse_values=()

for i in $(seq 1 $NUM_SAMPLES); do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Fetch metrics from controller
    METRICS=$(curl -s "${CONTROLLER_URL}/metrics")

    # Extract Go memory metrics and convert from scientific notation to MB using awk
    # go_memstats_alloc_bytes - currently allocated heap objects
    # go_memstats_heap_inuse_bytes - bytes in in-use spans
    # go_memstats_heap_sys_bytes - bytes of heap memory obtained from the OS

    HEAP_ALLOC_MB=$(echo "$METRICS" | grep "^go_memstats_alloc_bytes " | awk '{printf "%.2f", $2/1024/1024}')
    HEAP_INUSE_MB=$(echo "$METRICS" | grep "^go_memstats_heap_inuse_bytes " | awk '{printf "%.2f", $2/1024/1024}')
    HEAP_SYS_MB=$(echo "$METRICS" | grep "^go_memstats_heap_sys_bytes " | awk '{printf "%.2f", $2/1024/1024}')

    # Also get cumulative allocation (shows memory churn)
    TOTAL_ALLOC_MB=$(echo "$METRICS" | grep "^go_memstats_alloc_bytes_total " | awk '{printf "%.2f", $2/1024/1024}')

    heap_inuse_values+=($HEAP_INUSE_MB)

    # Write to CSV
    echo "${TIMESTAMP},${HEAP_ALLOC_MB},${HEAP_INUSE_MB},${HEAP_SYS_MB},${TOTAL_ALLOC_MB}" >> "${OUTPUT_FILE}"

    # Display current reading
    printf "[%3d/%3d] %s - Heap Alloc: %8.2f MB, Heap InUse: %8.2f MB, Heap Sys: %8.2f MB\n" \
        "$i" "$NUM_SAMPLES" "$TIMESTAMP" "$HEAP_ALLOC_MB" "$HEAP_INUSE_MB" "$HEAP_SYS_MB"

    # Sleep until next sample (skip on last iteration)
    if [ $i -lt $NUM_SAMPLES ]; then
        sleep $INTERVAL
    fi
done

echo ""
echo "Measurement complete!"
echo ""

# Calculate statistics for heap_inuse (most relevant metric)
sum=0
count=${#heap_inuse_values[@]}
min=${heap_inuse_values[0]}
max=${heap_inuse_values[0]}

for val in "${heap_inuse_values[@]}"; do
    sum=$(echo "$sum + $val" | bc 2>/dev/null || echo "$sum")
    if (( $(echo "$val < $min" | bc -l 2>/dev/null || echo 0) )); then
        min=$val
    fi
    if (( $(echo "$val > $max" | bc -l 2>/dev/null || echo 0) )); then
        max=$val
    fi
done

avg=$(echo "scale=2; $sum / $count" | bc 2>/dev/null || echo "0")

echo "Statistics for Heap InUse (MB):"
echo "  Minimum:  ${min}"
echo "  Maximum:  ${max}"
echo "  Average:  ${avg}"
echo "  Samples:  ${count}"
echo ""
echo "Data saved to: ${OUTPUT_FILE}"
echo ""
echo "Metric explanations:"
echo "  Heap Alloc:  Currently allocated heap objects (active memory)"
echo "  Heap InUse:  Memory in in-use spans (includes some overhead)"
echo "  Heap Sys:    Total heap memory obtained from OS (includes free space)"
echo ""
echo "For cache impact analysis, focus on 'Heap InUse' changes."
