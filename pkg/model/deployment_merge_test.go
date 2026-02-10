package model

import (
	"fmt"
	"testing"

	kyaml "sigs.k8s.io/kustomize/kyaml/yaml"
	"sigs.k8s.io/kustomize/kyaml/yaml/merge2"
)

func TestStrategyMerge(t *testing.T) {
	base := `
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      containers:
      - name: test
        image: test:1.0
`

	patch := `
spec:
  strategy:
    type: Recreate
    rollingUpdate: null
`

	// Test current approach
	merged, err := merge2.MergeStrings(patch, base, false, kyaml.MergeOptions{})
	if err != nil {
		t.Fatalf("merge failed: %v", err)
	}

	fmt.Println("=== Merged Result ===")
	fmt.Println(merged)

	// Check if rollingUpdate was removed
	if contains(merged, "rollingUpdate") {
		t.Error("rollingUpdate was NOT removed - kyaml merge didn't handle null correctly")
	} else {
		t.Log("SUCCESS: rollingUpdate was removed")
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) && (s[:len(substr)] == substr || s[len(s)-len(substr):] == substr || containsInMiddle(s, substr)))
}

func containsInMiddle(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
