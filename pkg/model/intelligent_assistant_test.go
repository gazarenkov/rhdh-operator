package model

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/redhat-developer/rhdh-operator/api"
	"github.com/redhat-developer/rhdh-operator/pkg/platform"
	"github.com/redhat-developer/rhdh-operator/pkg/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	yamlv2 "gopkg.in/yaml.v2"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/yaml"
)

func TestIntelligentAssistantPlatformConfiguration(t *testing.T) {
	tests := []struct {
		name           string
		platform       platform.Platform
		external       ExternalConfig
		wantOKP        bool
		wantServiceURL string
		wantIngressCA  string
	}{
		{
			name:           "openshift enables OKP automatically",
			platform:       platform.OpenShift,
			external:       ExternalConfig{OpenShiftIngressDomain: "apps.example.com", OpenShiftIngressCABundle: "test ingress CA\n"},
			wantOKP:        true,
			wantServiceURL: "https://developer-hub-ia-okp-rhdh-test.apps.example.com",
			wantIngressCA:  "test ingress CA\n",
		},
		{
			name:     "kubernetes keeps intelligent assistant without OKP",
			platform: platform.Kubernetes,
			wantOKP:  false,
		},
		{
			name:     "kubernetes enables OKP from the referenced dependency config",
			platform: platform.Kubernetes,
			external: ExternalConfig{PluginDependencyConfigs: map[string]map[string]string{
				"okp": {
					"OKP_INGRESS_HOST":        "okp.example.com",
					"OKP_INGRESS_TLS_ENABLED": "true",
				},
			}},
			wantOKP:        true,
			wantServiceURL: "https://okp.example.com",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			backstage := &api.Backstage{ObjectMeta: metav1.ObjectMeta{Name: "developer-hub", Namespace: "rhdh-test"}}
			template.SetTemplateData(backstage, &tt.platform, &tt.external)

			deploymentContent := renderIntelligentAssistantConfig(t, "deployment.yaml")
			var deployment appsv1.Deployment
			require.NoError(t, yaml.Unmarshal(deploymentContent, &deployment))
			container := findContainer(t, deployment.Spec.Template.Spec.Containers, "lightspeed-core")
			assert.Equal(t, "quay.io/lightspeed-core/lightspeed-stack:dev-20260824-cbd182b", container.Image)
			serviceURL := findEnvValue(container.Env, "OKP_SERVICE_URL")
			assert.Equal(t, tt.wantServiceURL, serviceURL)
			if tt.platform.IsOpenshift() {
				assert.Equal(t, []string{"/bin/sh", "-c"}, container.Command)
				require.Len(t, container.Args, 1)
				assert.Contains(t, container.Args[0], "REQUESTS_CA_BUNDLE=/tmp/combined-ca-bundle.crt")
				assert.Contains(t, container.Args[0], "/app-root/ingress-ca.crt")
			} else {
				assert.Empty(t, container.Command)
				assert.Equal(t, []string{"--synthesized-config-output", "/tmp/.generated/run.yaml"}, container.Args)
			}

			configMapContent := renderIntelligentAssistantConfig(t, "configmap-files.yaml")
			var stackConfigMap corev1.ConfigMap
			require.NoError(t, yaml.Unmarshal(configMapContent, &stackConfigMap))
			stack := stackConfigMap.Data["lightspeed-stack.yaml"]
			assert.Equal(t, tt.wantIngressCA, stackConfigMap.Data["ingress-ca.crt"])
			assert.Contains(t, stack, "baseline: byo-llm")
			assert.Equal(t, tt.wantOKP, strings.Contains(stack, "\nrag:\n"))
			assert.Equal(t, tt.wantOKP, strings.Contains(stack, "sources:") && strings.Contains(stack, "- okp"))

			dynamicPluginsContent := renderIntelligentAssistantConfig(t, "dynamic-plugins.yaml")
			var dynamicPluginsConfigMap corev1.ConfigMap
			require.NoError(t, yaml.Unmarshal(dynamicPluginsContent, &dynamicPluginsConfigMap))
			var dynamicPlugins DynaPluginsConfig
			require.NoError(t, yamlv2.Unmarshal([]byte(dynamicPluginsConfigMap.Data[DynamicPluginsFile]), &dynamicPlugins))
			backend := findDynamicPlugin(t, dynamicPlugins.Plugins, "red-hat-developer-hub-backstage-plugin-intelligent-assistant-backend")
			assert.Equal(t, tt.wantOKP, len(backend.Dependencies) == 1 && backend.Dependencies[0].Ref == "okp")
		})
	}
}

func renderIntelligentAssistantConfig(t *testing.T, name string) []byte {
	t.Helper()
	path := filepath.Join("../../config/profile/rhdh/default-config/flavours/intelligent-assistant", name)
	content, err := os.ReadFile(path)
	require.NoError(t, err)
	rendered, err := template.ApplyTemplate(content)
	require.NoError(t, err)
	return rendered
}

func findContainer(t *testing.T, containers []corev1.Container, name string) corev1.Container {
	t.Helper()
	for _, container := range containers {
		if container.Name == name {
			return container
		}
	}
	t.Fatalf("container %q not found", name)
	return corev1.Container{}
}

func findEnvValue(env []corev1.EnvVar, name string) string {
	for _, variable := range env {
		if variable.Name == name {
			return variable.Value
		}
	}
	return ""
}

func findDynamicPlugin(t *testing.T, plugins []DynaPlugin, packageSuffix string) DynaPlugin {
	t.Helper()
	for _, plugin := range plugins {
		if strings.HasSuffix(plugin.Package, packageSuffix) {
			return plugin
		}
	}
	t.Fatalf("dynamic plugin ending in %q not found", packageSuffix)
	return DynaPlugin{}
}
