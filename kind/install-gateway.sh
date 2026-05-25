#!/usr/bin/env bash
#
# 安装 Envoy Gateway
# 先安装 Gateway API CRDs，再安装 Envoy Gateway 控制器
#
# 用法: ./install-gateway.sh
#

set -euo pipefail

NAMESPACE="envoy-gateway-system"
RELEASE_NAME="envoy-gateway"
GATEWAY_API_VERSION="v1.2.1"
# Envoy Gateway 已迁移到 OCI registry (不再提供传统 Helm repo)
EG_CHART="oci://docker.io/envoyproxy/gateway-helm"
EG_VERSION="v1.8.0"

log() { echo -e "\033[1;34m[Gateway]\033[0m $*"; }
info() { echo -e "  \033[0;36m→\033[0m $*"; }

# 安装 Gateway API CRDs
log "安装 Gateway API CRDs (${GATEWAY_API_VERSION})..."
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" 2>/dev/null || {
  # 如果在线安装失败，尝试实验性版本（包含更多功能）
  log "尝试安装实验性 CRDs..."
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"
}

# 等待 CRDs 就绪
log "等待 CRDs 就绪..."
kubectl wait --for condition=Established crd/gatewayclasses.gateway.networking.k8s.io --timeout=60s
kubectl wait --for condition=Established crd/gateways.gateway.networking.k8s.io --timeout=60s
kubectl wait --for condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=60s

# 安装 Envoy Gateway 控制器 (OCI registry)
log "安装 Envoy Gateway 控制器 (${EG_VERSION})..."
helm upgrade --install "${RELEASE_NAME}" "${EG_CHART}" \
  --version "${EG_VERSION}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout 3m

# 等待控制器就绪
log "等待 Envoy Gateway 控制器就绪..."
kubectl wait --namespace "${NAMESPACE}" \
  --for=condition=Available \
  --timeout=120s \
  deployment/envoy-gateway

log "✅ Envoy Gateway 安装完成！"
echo ""
info "Gateway API CRDs: ${GATEWAY_API_VERSION}"
info "控制器命名空间: ${NAMESPACE}"
info "部署应用时将自动创建 GatewayClass 和 Gateway 资源"
