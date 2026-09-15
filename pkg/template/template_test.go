package template

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type testBackstage struct {
	name      string
	namespace string
}

func (b testBackstage) GetName() string      { return b.name }
func (b testBackstage) GetNamespace() string { return b.namespace }

type testPlatform struct{ extension string }

func (p testPlatform) GetExtension() string { return p.extension }

type testExternalConfig struct {
	ingressDomain      string
	ingressCABundle    string
	pluginDependencies map[string]map[string]string
}

func (c testExternalConfig) GetIngressDomain() string   { return c.ingressDomain }
func (c testExternalConfig) GetIngressCABundle() string { return c.ingressCABundle }
func (c testExternalConfig) GetPluginDependencyConfigs() map[string]map[string]string {
	return c.pluginDependencies
}

func TestApplyTemplate(t *testing.T) {
	SetTemplateData(
		testBackstage{name: "developer-hub", namespace: "rhdh-test"},
		testPlatform{extension: "k8s"},
		testExternalConfig{
			ingressDomain: "apps.example.com",
			pluginDependencies: map[string]map[string]string{
				"okp": {
					"OKP_INGRESS_HOST":        "okp.example.com",
					"OKP_INGRESS_TLS_ENABLED": "true",
				},
			},
		},
	)

	content := []byte(`{{if pluginDependencyEnabled "okp"}}{{if isTrue (pluginDependencyValue "okp" "OKP_INGRESS_TLS_ENABLED")}}https{{else}}http{{end}}://{{required "host is required" (pluginDependencyValue "okp" "OKP_INGRESS_HOST")}}/{{.Rhdh.Name}}{{end}}`)
	rendered, err := ApplyTemplate(content)
	require.NoError(t, err)
	assert.Equal(t, "https://okp.example.com/developer-hub", string(rendered))
}

func TestApplyTemplateRequiredValue(t *testing.T) {
	SetTemplateData(
		testBackstage{},
		testPlatform{},
		testExternalConfig{pluginDependencies: map[string]map[string]string{"okp": {}}},
	)

	_, err := ApplyTemplate([]byte(`{{required "OKP host is required" (pluginDependencyValue "okp" "OKP_INGRESS_HOST")}}`))
	require.ErrorContains(t, err, "OKP host is required")
}

func TestApplyTemplateSkipsUnsupportedActions(t *testing.T) {
	content := []byte("Question: {{message}}\nPackage: {{inherit}}\n")
	rendered, err := ApplyTemplate(content)
	require.NoError(t, err)
	assert.Equal(t, content, rendered)
}

func TestApplyTemplateIndentsMultilineValue(t *testing.T) {
	SetTemplateData(
		testBackstage{},
		testPlatform{},
		testExternalConfig{ingressCABundle: "first\nsecond\n"},
	)

	rendered, err := ApplyTemplate([]byte("data: |\n{{ indent 2 .Rhdh.Runtime.IngressCABundle }}\n"))
	require.NoError(t, err)
	assert.Equal(t, "data: |\n  first\n  second\n", string(rendered))
}
