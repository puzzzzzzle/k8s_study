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

# --- 等待 Gateway 资源创建后自动 patch Envoy Service ---
# Envoy Gateway 会为每个 Gateway 创建一个 data-plane Service（名称含 hash），
# 需要 patch 为 NodePort 30080 + externalTrafficPolicy=Cluster 才能在 kind 中通过宿主机访问。
patch_envoy_service() {
  local GATEWAY_NAME="${1:-demo-gateway}"
  local NODE_PORT="${2:-30080}"
  local MAX_WAIT=120
  local INTERVAL=5

  log "等待 Gateway '${GATEWAY_NAME}' 对应的 Envoy Service 创建..."
  local elapsed=0
  local SVC_NAME=""

  while [ $elapsed -lt $MAX_WAIT ]; do
    # Envoy Gateway 为 data-plane Service 打上这个 label
    SVC_NAME=$(kubectl get svc -n "${NAMESPACE}" \
      -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [ -n "${SVC_NAME}" ]; then
      break
    fi
    sleep "${INTERVAL}"
    elapsed=$((elapsed + INTERVAL))
  done

  if [ -z "${SVC_NAME}" ]; then
    info "⚠️  未找到 Gateway '${GATEWAY_NAME}' 的 Envoy Service（可能 Gateway 还未部署）"
    info "   部署应用创建 Gateway 后，手动执行："
    info "   kubectl patch svc <envoy-svc> -n ${NAMESPACE} --type=merge \\"
    info "     -p '{\"spec\":{\"externalTrafficPolicy\":\"Cluster\",\"ports\":[{\"name\":\"http-80\",\"port\":80,\"targetPort\":10080,\"nodePort\":${NODE_PORT},\"protocol\":\"TCP\"}]}}'"
    return 0
  fi

  log "找到 Envoy Service: ${SVC_NAME}，正在 patch..."
  kubectl patch svc "${SVC_NAME}" -n "${NAMESPACE}" --type=merge -p "{
    \"spec\": {
      \"externalTrafficPolicy\": \"Cluster\",
      \"ports\": [{
        \"name\": \"http-80\",
        \"port\": 80,
        \"targetPort\": 10080,
        \"nodePort\": ${NODE_PORT},
        \"protocol\": \"TCP\"
      }]
    }
  }"

  log "✅ Envoy Service 已 patch: NodePort=${NODE_PORT}, externalTrafficPolicy=Cluster"
  info "访问方式: curl http://localhost:${NODE_PORT}/"
}

# 尝试自动 patch（如果 Gateway 已存在）
patch_envoy_service "demo-gateway" "30080"
