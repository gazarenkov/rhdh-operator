package controller

import (
	"context"
	"os"

	"testing"

	"github.com/redhat-developer/rhdh-operator/api"
	"github.com/redhat-developer/rhdh-operator/pkg/model"
	"github.com/redhat-developer/rhdh-operator/pkg/platform"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
)

func updateConfigMap(t *testing.T) BackstageReconciler {
	ctx := context.TODO()

	bs := api.Backstage{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "bs1",
			Namespace: "ns1",
		},
		Spec: api.BackstageSpec{
			Application: &api.Application{
				AppConfig: &api.AppConfig{
					ConfigMaps: []api.FileObjectRef{{Name: "cm1"}},
				},
			},
		},
	}

	cm := corev1.ConfigMap{}
	cm.Name = "cm1"

	rc := BackstageReconciler{
		Client: NewMockClient(),
	}

	assert.NoError(t, rc.Create(ctx, &cm))

	// reconcile
	extConf, err := rc.preprocessSpec(ctx, bs)
	assert.NoError(t, err)

	oldHash := extConf.WatchingHash

	// Update ConfigMap with new data
	err = rc.Get(ctx, types.NamespacedName{Namespace: "ns1", Name: "cm1"}, &cm)
	assert.NoError(t, err)
	cm.Data = map[string]string{"key": "value"}
	err = rc.Update(ctx, &cm)
	assert.NoError(t, err)

	// reconcile again
	extConf, err = rc.preprocessSpec(ctx, bs)
	assert.NoError(t, err)

	assert.NotEqual(t, oldHash, extConf.WatchingHash)

	return rc
}

func TestExtConfigChanged(t *testing.T) {

	ctx := context.TODO()
	cm := corev1.ConfigMap{}

	rc := updateConfigMap(t)
	err := rc.Get(ctx, types.NamespacedName{Namespace: "ns1", Name: "cm1"}, &cm)
	assert.NoError(t, err)
	// true : Backstage will be reconciled
	assert.Equal(t, "true", cm.Labels[model.ExtConfigSyncLabel])

	err = os.Setenv(AutoSyncEnvVar, "false")
	assert.NoError(t, err)

	rc = updateConfigMap(t)
	err = rc.Get(ctx, types.NamespacedName{Namespace: "ns1", Name: "cm1"}, &cm)
	assert.NoError(t, err)
	// false : Backstage will not be reconciled
	assert.Equal(t, "false", cm.Labels[model.ExtConfigSyncLabel])

}

// TestExtConfigChanged tests if concatData returns the same data when the order of the keys is different
func TestExtConcatData(t *testing.T) {
	cm := corev1.ConfigMap{}

	cm.Data = map[string]string{"key1": "value1", "key2": "value2", "key3": "value3", "key4": "value4"}
	original := []byte("original")
	data1 := concatData(original, &cm)

	cm.Data = map[string]string{"key4": "value4", "key2": "value2", "key3": "value3", "key1": "value1"}
	assert.Equal(t, data1, concatData(original, &cm))

}

func TestPluginDependencyConfig(t *testing.T) {
	ctx := context.TODO()
	bs := api.Backstage{
		ObjectMeta: metav1.ObjectMeta{Name: "bs1", Namespace: "ns1"},
		Spec: api.BackstageSpec{Application: &api.Application{ExtraEnvs: &api.ExtraEnvs{
			ConfigMaps: []api.EnvObjectRef{{Name: "okp-config", Containers: []string{"lightspeed-core"}}},
		}}},
	}
	cm := corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "okp-config",
			Namespace: "ns1",
			Labels:    map[string]string{model.PluginDependencyConfigLabel: "okp"},
		},
		Data: map[string]string{"OKP_INGRESS_HOST": "okp.example.com"},
	}
	rc := BackstageReconciler{Client: NewMockClient()}
	assert.NoError(t, rc.Create(ctx, &cm))

	extConf, err := rc.preprocessSpec(ctx, bs)
	assert.NoError(t, err)
	assert.Equal(t, "okp.example.com", extConf.PluginDependencyConfigs["okp"]["OKP_INGRESS_HOST"])
}

func TestOpenShiftIngressConfig(t *testing.T) {
	ctx := context.TODO()
	rc := BackstageReconciler{Client: NewMockClient(), Platform: platform.OpenShift}

	ingress := &unstructured.Unstructured{}
	ingress.SetGroupVersionKind(schema.GroupVersionKind{Group: "config.openshift.io", Version: "v1", Kind: "Ingress"})
	ingress.SetName("cluster")
	ingress.Object["spec"] = map[string]interface{}{"domain": "apps.example.com"}
	require.NoError(t, rc.Create(ctx, ingress))

	certificate := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      openShiftIngressCertificateName,
			Namespace: openShiftIngressCertificateNamespace,
		},
		Data: map[string]string{openShiftIngressCertificateKey: "test ingress CA\n"},
	}
	require.NoError(t, rc.Create(ctx, certificate))

	extConf, err := rc.preprocessSpec(ctx, api.Backstage{ObjectMeta: metav1.ObjectMeta{Name: "bs1", Namespace: "ns1"}})
	require.NoError(t, err)
	assert.Equal(t, "apps.example.com", extConf.OpenShiftIngressDomain)
	assert.Equal(t, "test ingress CA\n", extConf.OpenShiftIngressCABundle)
}
