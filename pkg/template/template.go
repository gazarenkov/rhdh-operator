package template

import (
	"bytes"
	"fmt"
	"strconv"
	"strings"
	texttemplate "text/template"
)

type backstageData interface {
	GetName() string
	GetNamespace() string
}

type platformData interface {
	GetExtension() string
}

type externalConfigData interface {
	GetIngressDomain() string
	GetIngressCABundle() string
	GetPluginDependencyConfigs() map[string]map[string]string
}

type TemplateData struct {
	Rhdh RhdhData
}

type RhdhData struct {
	Name               string
	Namespace          string
	Runtime            RuntimeData
	PluginDependencies map[string]map[string]string
}

type RuntimeData struct {
	Platform        string
	IngressDomain   string
	IngressCABundle string
}

var templateData *TemplateData

func SetTemplateData(backstage backstageData, platform platformData, externalConfig externalConfigData) {
	templateData = &TemplateData{
		Rhdh: RhdhData{
			Name:      backstage.GetName(),
			Namespace: backstage.GetNamespace(),
			Runtime: RuntimeData{
				Platform:        platform.GetExtension(),
				IngressDomain:   externalConfig.GetIngressDomain(),
				IngressCABundle: externalConfig.GetIngressCABundle(),
			},
			PluginDependencies: copyPluginDependencies(externalConfig.GetPluginDependencyConfigs()),
		},
	}
}

func ApplyTemplate(content []byte) ([]byte, error) {
	if !containsSupportedTemplateAction(string(content)) {
		return content, nil
	}
	if templateData == nil {
		return nil, fmt.Errorf("template data is not initialized")
	}

	tmpl, err := texttemplate.New("config").Option("missingkey=error").Funcs(texttemplate.FuncMap{
		"pluginDependencyEnabled": func(ref string) bool {
			_, exists := templateData.Rhdh.PluginDependencies[ref]
			return exists
		},
		"pluginDependencyValue": func(ref, key string) string {
			return templateData.Rhdh.PluginDependencies[ref][key]
		},
		"required": func(message, value string) (string, error) {
			if strings.TrimSpace(value) == "" {
				return "", fmt.Errorf("%s", message)
			}
			return value, nil
		},
		"quote": strconv.Quote,
		"isTrue": func(value string) bool {
			parsed, err := strconv.ParseBool(strings.TrimSpace(value))
			return err == nil && parsed
		},
		"indent": func(spaces int, value string) string {
			padding := strings.Repeat(" ", spaces)
			return padding + strings.ReplaceAll(strings.TrimSuffix(value, "\n"), "\n", "\n"+padding)
		},
	}).Parse(string(content))
	if err != nil {
		return nil, fmt.Errorf("failed to parse template: %w", err)
	}

	var rendered bytes.Buffer
	if err := tmpl.Execute(&rendered, templateData); err != nil {
		return nil, fmt.Errorf("failed to execute template: %w", err)
	}
	return rendered.Bytes(), nil
}

func containsSupportedTemplateAction(content string) bool {
	for {
		start := strings.Index(content, "{{")
		if start < 0 {
			return false
		}
		content = content[start+2:]
		end := strings.Index(content, "}}")
		if end < 0 {
			return false
		}
		action := content[:end]
		if strings.Contains(action, ".Rhdh.") || strings.Contains(action, "pluginDependency") {
			return true
		}
		content = content[end+2:]
	}
}

func copyPluginDependencies(source map[string]map[string]string) map[string]map[string]string {
	result := make(map[string]map[string]string, len(source))
	for ref, values := range source {
		result[ref] = make(map[string]string, len(values))
		for key, value := range values {
			result[ref][key] = value
		}
	}
	return result
}
