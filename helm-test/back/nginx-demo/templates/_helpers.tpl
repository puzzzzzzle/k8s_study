{{/*
生成完整名称，优先使用 .Values.name，否则使用 release name
*/}}
{{- define "nginx-demo.fullname" -}}
{{- if .Values.name }}
{{- .Values.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
生成通用标签
*/}}
{{- define "nginx-demo.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "nginx-demo.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
生成 selector 标签
*/}}
{{- define "nginx-demo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nginx-demo.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
