#!/bin/bash
# Script to generate many Secrets and ConfigMaps for memory consumption testing

set -e

NAMESPACE="${NAMESPACE:-default}"
NUM_SECRETS="${NUM_SECRETS:-1000}"
NUM_CONFIGMAPS="${NUM_CONFIGMAPS:-1000}"
LABELED_PERCENT="${LABELED_PERCENT:-10}"

echo "Creating ${NUM_SECRETS} Secrets and ${NUM_CONFIGMAPS} ConfigMaps in namespace ${NAMESPACE}"
echo "Approximately ${LABELED_PERCENT}% will have the label 'rhdh.redhat.com/external-config=true'"

# Create namespace if it doesn't exist
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Function to create Secrets
create_secrets() {
    local num_labeled=$((NUM_SECRETS * LABELED_PERCENT / 100))

    echo "Creating ${NUM_SECRETS} Secrets (${num_labeled} labeled)..."

    for i in $(seq 1 $NUM_SECRETS); do
        local secret_name="test-secret-${i}"

        if [ $i -le $num_labeled ]; then
            kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: ${NAMESPACE}
  labels:
    rhdh.redhat.com/external-config: "true"
    test-data: "memory-test"
type: Opaque
stringData:
  key1: "value1"
  key2: "value2"
  data: "This is test secret ${i} with some data to consume memory"
EOF
        else
            kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: ${NAMESPACE}
  labels:
    test-data: "memory-test"
type: Opaque
stringData:
  key1: "value1"
  key2: "value2"
  data: "This is test secret ${i} with some data to consume memory"
EOF
        fi

        if [ $((i % 100)) -eq 0 ]; then
            echo "  Created ${i} Secrets..."
        fi
    done

    echo "✓ Created ${NUM_SECRETS} Secrets"
}

# Function to create ConfigMaps
create_configmaps() {
    local num_labeled=$((NUM_CONFIGMAPS * LABELED_PERCENT / 100))

    echo "Creating ${NUM_CONFIGMAPS} ConfigMaps (${num_labeled} labeled)..."

    for i in $(seq 1 $NUM_CONFIGMAPS); do
        local cm_name="test-configmap-${i}"

        if [ $i -le $num_labeled ]; then
            kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${cm_name}
  namespace: ${NAMESPACE}
  labels:
    rhdh.redhat.com/external-config: "true"
    test-data: "memory-test"
data:
  key1: "value1"
  key2: "value2"
  config.yaml: |
    # Test configuration ${i}
    setting1: value1
    setting2: value2
    data: "This is test configmap ${i} with some data to consume memory"
EOF
        else
            kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${cm_name}
  namespace: ${NAMESPACE}
  labels:
    test-data: "memory-test"
data:
  key1: "value1"
  key2: "value2"
  config.yaml: |
    # Test configuration ${i}
    setting1: value1
    setting2: value2
    data: "This is test configmap ${i} with some data to consume memory"
EOF
        fi

        if [ $((i % 100)) -eq 0 ]; then
            echo "  Created ${i} ConfigMaps..."
        fi
    done

    echo "✓ Created ${NUM_CONFIGMAPS} ConfigMaps"
}

# Function to clean up
cleanup() {
    echo "Cleaning up test resources..."
    kubectl delete secrets -n "${NAMESPACE}" -l test-data=memory-test
    kubectl delete configmaps -n "${NAMESPACE}" -l test-data=memory-test
    echo "✓ Cleanup complete"
}

# Main execution
case "${1:-create}" in
    create)
        create_secrets
        create_configmaps
        echo ""
        echo "Summary:"
        echo "  Total Secrets: $(kubectl get secrets -n ${NAMESPACE} -l test-data=memory-test --no-headers | wc -l)"
        echo "  Labeled Secrets: $(kubectl get secrets -n ${NAMESPACE} -l rhdh.redhat.com/external-config=true --no-headers | wc -l)"
        echo "  Total ConfigMaps: $(kubectl get configmaps -n ${NAMESPACE} -l test-data=memory-test --no-headers | wc -l)"
        echo "  Labeled ConfigMaps: $(kubectl get configmaps -n ${NAMESPACE} -l rhdh.redhat.com/external-config=true --no-headers | wc -l)"
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "Usage: $0 {create|cleanup}"
        echo ""
        echo "Environment variables:"
        echo "  NAMESPACE        - Target namespace (default: default)"
        echo "  NUM_SECRETS      - Number of secrets to create (default: 1000)"
        echo "  NUM_CONFIGMAPS   - Number of configmaps to create (default: 1000)"
        echo "  LABELED_PERCENT  - Percentage with rhdh.redhat.com/external-config label (default: 10)"
        exit 1
        ;;
esac
