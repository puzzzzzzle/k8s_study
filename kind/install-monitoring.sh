#!/usr/bin/env bash
#
# 安装 kube-prometheus-stack (Prometheus + Grafana + AlertManager)
#
# 用法: ./install-monitoring.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
VALUES_FILE="${SCRIPT_DIR}/values/prometheus-values.yaml"

log() { echo -e "\033[1;34m[Monitoring]\033[0m $*"; }
info() { echo -e "  \033[0;36m→\033[0m $*"; }

# 添加 Helm repo
log "添加 prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

# 创建命名空间
log "创建命名空间 '${NAMESPACE}'..."
kubectl create namespace "${NAMESPACE}" 2>/dev/null || true

# 安装/升级 kube-prometheus-stack
log "安装 kube-prometheus-stack..."
helm upgrade --install "${RELEASE_NAME}" prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 5m

log "✅ 监控栈安装完成！"
echo ""
info "Grafana:      kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-grafana 3000:80"
info "Prometheus:   kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-kube-prometheus-stack-prometheus 9090:9090"
info "AlertManager: kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-kube-prometheus-stack-alertmanager 9093:9093"
echo ""
info "Grafana 默认账号: admin / prom-operator"
