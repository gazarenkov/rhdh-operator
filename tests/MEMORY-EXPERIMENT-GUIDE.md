# Memory Consumption Experiment Guide

This guide explains how to measure and compare operator memory consumption with and without cache label filtering.

## Overview

The operator watches Secrets and ConfigMaps for external configuration. By default, the controller-runtime cache loads **all** Secrets/ConfigMaps from the cluster, even though predicates filter which ones trigger reconciliation. This causes significant memory consumption on clusters with many Secrets/ConfigMaps.

The experiment compares memory usage between:
1. **Baseline**: Default behavior (caches all Secrets/ConfigMaps)
2. **Optimized**: Cache label filtering enabled (only caches labeled resources)

## Prerequisites

- OpenShift or Kubernetes cluster
- kubectl/oc configured
- Make tools installed
- bc (basic calculator) for statistics

## Phase 1: Baseline Measurement (Without Label Filtering)

### Step 1: Generate Test Data

Create many Secrets and ConfigMaps on your cluster:

```bash
# Make script executable
chmod +x tests/memory-test-setup.sh
chmod +x tests/measure-memory.sh

# Create 2000 Secrets and 2000 ConfigMaps
# 10% will have the label 'rhdh.redhat.com/external-config=true'
NAMESPACE=default NUM_SECRETS=2000 NUM_CONFIGMAPS=2000 LABELED_PERCENT=10 \
  ./tests/memory-test-setup.sh create
```

Adjust the numbers based on your cluster capacity:
- For smaller clusters: Use 500-1000 each
- For larger clusters: Use 5000+ each

### Step 2: Run Operator Locally (Option A - Recommended for Testing)

```bash
# Install CRDs
make install

# Run operator locally without cache filtering
make run
```

The operator will run in your terminal. Keep it running.

### Step 2 Alternative: Deploy to Cluster (Option B)

```bash
# Build and deploy without cache filtering
make docker-build docker-push deploy IMG=<your-registry>/rhdh-operator:baseline

# Verify deployment
kubectl get pods -n rhdh-operator
```

### Step 3: Create a Backstage CR

In another terminal:

```bash
# Create a test Backstage instance
kubectl apply -f - <<EOF
apiVersion: rhdh.redhat.com/v1alpha5
kind: Backstage
metadata:
  name: test-backstage
  namespace: default
spec:
  database:
    enableLocalDb: true
  application:
    replicas: 1
EOF

# Wait for deployment
kubectl wait --for=condition=Deployed backstage/test-backstage -n default --timeout=600s
```

### Step 4: Measure Memory

**For local controller:**

```bash
# Measure for 5 minutes, sampling every 5 seconds
MODE=local DURATION=300 INTERVAL=5 OUTPUT_FILE=baseline-local.csv \
  ./tests/measure-memory.sh
```

**For cluster-deployed controller:**

```bash
# Ensure metrics-server is running
kubectl top nodes

# Measure
MODE=cluster NAMESPACE=rhdh-operator DURATION=300 INTERVAL=5 \
  OUTPUT_FILE=baseline-cluster.csv \
  ./tests/measure-memory.sh
```

### Step 5: Record Results

```bash
# View statistics (printed at the end of measurement script)
cat baseline-local.csv  # or baseline-cluster.csv

# Calculate average manually if needed
tail -n +2 baseline-local.csv | awk -F, '{sum+=$2; count++} END {print "Average: " sum/count " MiB"}'
```

Save the results:
- Minimum memory
- Maximum memory
- Average memory
- Number of Secrets/ConfigMaps on cluster

## Phase 2: Optimized Measurement (With Label Filtering)

### Step 1: Stop Previous Operator

**For local controller:** Press Ctrl+C in the terminal running `make run`

**For cluster deployment:**
```bash
make undeploy
```

### Step 2: Run Operator with Cache Filtering

**For local controller (Option A - Recommended):**

```bash
# Run with cache label filter enabled
make run ARGS="--enable-cache-label-filter"
```

**For cluster deployment (Option B):**

You need to modify the deployment to add the flag:

```bash
# Build with your changes
make docker-build docker-push deploy IMG=<your-registry>/rhdh-operator:filtered

# Edit the deployment to add the flag
kubectl edit deployment backstage-operator-controller-manager -n rhdh-operator

# Add to container args:
#   - --enable-cache-label-filter
```

Or use kustomize:

```bash
# Edit config/manager/manager.yaml and add to args:
#   - --enable-cache-label-filter

# Redeploy
make deploy IMG=<your-registry>/rhdh-operator:filtered
```

### Step 3: Verify Backstage CR Still Works

```bash
# The Backstage instance should still be running
kubectl get backstage test-backstage -n default

# If needed, recreate it
kubectl delete backstage test-backstage -n default
kubectl apply -f - <<EOF
apiVersion: rhdh.redhat.com/v1alpha5
kind: Backstage
metadata:
  name: test-backstage
  namespace: default
spec:
  database:
    enableLocalDb: true
  application:
    replicas: 1
EOF
```

### Step 4: Measure Memory Again

**For local controller:**

```bash
MODE=local DURATION=300 INTERVAL=5 OUTPUT_FILE=filtered-local.csv \
  ./tests/measure-memory.sh
```

**For cluster-deployed controller:**

```bash
MODE=cluster NAMESPACE=rhdh-operator DURATION=300 INTERVAL=5 \
  OUTPUT_FILE=filtered-cluster.csv \
  ./tests/measure-memory.sh
```

### Step 5: Record Results

```bash
# View statistics
cat filtered-local.csv  # or filtered-cluster.csv
```

## Phase 3: Compare Results

### Create Comparison Report

```bash
cat > comparison-report.txt <<EOF
# Memory Consumption Comparison

## Test Environment
- Cluster Type: <OpenShift/Kubernetes>
- Number of Secrets: <count>
- Number of ConfigMaps: <count>
- Labeled Secrets: <count>
- Labeled ConfigMaps: <count>

## Baseline (No Cache Filtering)
- Average Memory: <value> MiB
- Minimum Memory: <value> MiB
- Maximum Memory: <value> MiB

## Optimized (Cache Label Filtering Enabled)
- Average Memory: <value> MiB
- Minimum Memory: <value> MiB
- Maximum Memory: <value> MiB

## Savings
- Memory Reduction: <value> MiB (<percentage>%)
- Cache Efficiency: Only caching <labeled_count> vs <total_count> resources

## Conclusion
<your observations>
EOF
```

### Calculate Reduction

```bash
# Extract averages from CSV files
BASELINE_AVG=$(tail -n +2 baseline-local.csv | awk -F, '{sum+=$2; count++} END {print sum/count}')
FILTERED_AVG=$(tail -n +2 filtered-local.csv | awk -F, '{sum+=$2; count++} END {print sum/count}')

# Calculate reduction
REDUCTION=$(echo "$BASELINE_AVG - $FILTERED_AVG" | bc)
PERCENT=$(echo "scale=2; ($REDUCTION / $BASELINE_AVG) * 100" | bc)

echo "Memory reduction: ${REDUCTION} MiB (${PERCENT}%)"
```

## Understanding the Results

### What to Expect

- **Baseline**: Memory should scale with total number of Secrets/ConfigMaps on cluster
- **Filtered**: Memory should only scale with number of **labeled** Secrets/ConfigMaps
- **Reduction**: Should be proportional to `(total - labeled) / total`

Example: If you have 2000 Secrets total and only 200 labeled:
- Expected reduction: ~90% of the Secret cache memory

### Important Notes

1. **The label used**: `rhdh.redhat.com/external-config=true`
   - This is different from the existing `rhdh.redhat.com/ext-config-sync` label
   - You can change this in `cmd/main.go` line 140

2. **Watch behavior**:
   - Predicates still filter events (no change)
   - Cache filtering reduces memory (new behavior)

3. **Functionality**:
   - Only Secrets/ConfigMaps with the label will be cached
   - Unlabeled resources won't trigger reconciliation (expected)
   - Backstage CRs referencing unlabeled configs **will fail**

## Cleanup

```bash
# Remove test Backstage instance
kubectl delete backstage test-backstage -n default

# Remove test Secrets and ConfigMaps
NAMESPACE=default ./tests/memory-test-setup.sh cleanup

# Uninstall operator
make undeploy
make uninstall
```

## Troubleshooting

### "kubectl top not working"

Install metrics-server:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### "Process not found" (local mode)

The script looks for a process matching "manager". If your binary has a different name:
```bash
PROCESS_NAME="your-binary-name" MODE=local ./tests/measure-memory.sh
```

### High memory even with filtering

1. Check other resources cached by the operator (Deployments, Routes, etc.)
2. Verify the label selector is correct
3. Ensure you're running the modified code with `--enable-cache-label-filter`

## Advanced: Testing with Different Label Percentages

```bash
# Test with different ratios
for percent in 5 10 25 50; do
  echo "Testing with ${percent}% labeled resources"

  # Cleanup previous
  NAMESPACE=default ./tests/memory-test-setup.sh cleanup

  # Create new set
  NAMESPACE=default NUM_SECRETS=1000 NUM_CONFIGMAPS=1000 \
    LABELED_PERCENT=$percent ./tests/memory-test-setup.sh create

  # Measure
  MODE=local DURATION=120 OUTPUT_FILE="filtered-${percent}pct.csv" \
    ./tests/measure-memory.sh
done
```

## Next Steps

If the memory reduction is significant:
1. Consider making cache filtering configurable (add env var or operator config)
2. Update documentation about labeling requirements
3. Add validation webhooks to ensure external configs have required labels
4. Consider making this the default behavior with opt-out
