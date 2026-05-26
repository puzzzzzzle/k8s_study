#!/bin/bash
# 一键部署/更新所有资源（K8s 基础设施 + Helm 业务服务）
# 幂等：不存在则创建，存在则更新
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 颜色输出
log()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

# ============================================================
# 1. NFS 共享存储基础设施（NFS Server + PV/PVC + config-writer）
# ============================================================
log "部署 NFS 共享存储基础设施..."
kubectl apply -f manifests/nfs-server.yaml
log "✅ NFS Server + PV/PVC + config-writer 已就绪"

# 等待 NFS Server Pod 就绪（业务 Pod 挂载 PVC 前必须可用）
log "等待 NFS Server Pod 就绪..."
kubectl wait --for=condition=ready pod -l app=nfs-server --timeout=120s 2>/dev/null || {
  warn "NFS Server Pod 未在 120s 内就绪，继续部署（业务 Pod 可能 pending）"
}

# ============================================================
# 2. Gateway 公共基础设施（GatewayClass + Gateway）
# ============================================================
log "部署 Gateway 公共基础设施..."
kubectl apply -f manifests/gateway.yaml
log "✅ GatewayClass + Gateway 已就绪"

# ============================================================
# 3. Helm 业务服务
# ============================================================
CHART_DIR="./web-demo"

# 服务列表：release名称 + values文件
declare -A SERVICES=(
  ["nginx-demo"]="values/nginx-values.yaml"
  ["go-pingpong"]="values/go-values.yaml"
)

for RELEASE in "${!SERVICES[@]}"; do
  VALUES_FILE="${SERVICES[$RELEASE]}"

  if [ ! -f "${VALUES_FILE}" ]; then
    warn "跳过 ${RELEASE}：values 文件 ${VALUES_FILE} 不存在"
    continue
  fi

  log "部署 ${RELEASE}（${VALUES_FILE}）..."
  helm upgrade --install "${RELEASE}" "${CHART_DIR}" -f "${VALUES_FILE}"
  log "✅ ${RELEASE} 部署完成"
done

# ============================================================
# 4. Patch Envoy Service（等待 Gateway data-plane 就绪）
# ============================================================
GATEWAY_NAME="demo-gateway"
NODE_PORT="30080"
MAX_WAIT=120
INTERVAL=5

log "等待 Envoy Service 创建（Gateway: ${GATEWAY_NAME}）..."
elapsed=0
SVC_NAME=""
SVC_NS=""

while [ $elapsed -lt $MAX_WAIT ]; do
  # 在所有 namespace 中查找
  SVC_NAME=$(kubectl get svc -A \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  SVC_NS=$(kubectl get svc -A \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)

  if [ -n "${SVC_NAME}" ]; then
    break
  fi
  log "  等待中... (${elapsed}s/${MAX_WAIT}s)"
  sleep "${INTERVAL}"
  elapsed=$((elapsed + INTERVAL))
done

if [ -n "${SVC_NAME}" ]; then
  log "Patch Envoy Service: ${SVC_NAME} (ns: ${SVC_NS})"
  kubectl patch svc "${SVC_NAME}" -n "${SVC_NS}" --type=merge -p "{
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
  log "✅ Envoy Service 已 patch: NodePort=${NODE_PORT}"

  # 等待 Envoy Pod 就绪
  log "等待 Envoy Pod 就绪..."
  kubectl wait --for=condition=ready pod \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -n "${SVC_NS}" --timeout=60s 2>/dev/null || true
  log "✅ Envoy Pod 已就绪"
else
  err "等待 ${MAX_WAIT}s 仍未找到 Envoy Service"
  err "请检查 Envoy Gateway 控制器是否正常运行："
  err "  kubectl get pods -n envoy-gateway-system"
  exit 1
fi

# ============================================================
# 完成
# ============================================================
echo ""
log "🎉 全部部署完成！"
echo ""
log "访问方式:"
log "  curl http://localhost:${NODE_PORT}/        → nginx-demo"
log "  curl http://localhost:${NODE_PORT}/ping    → go-pingpong"
echo ""
log "共享配置写入:"
log "  kubectl cp ./my-config.json \$(kubectl get pod -l app=config-writer -o jsonpath='{.items[0].metadata.name}'):/shared-config/"
log "  业务 Pod 可在 /shared-config/ 下读取配置文件"
