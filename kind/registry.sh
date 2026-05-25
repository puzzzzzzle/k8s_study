#!/usr/bin/env bash
#
# 本地 Docker Registry 管理脚本
# 用法: ./registry.sh [start|stop|status]
#

set -euo pipefail

REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5001"
REGISTRY_INTERNAL_PORT="5000"

log() { echo -e "\033[1;34m[Registry]\033[0m $*"; }
err() { echo -e "\033[1;31m[Error]\033[0m $*" >&2; }

start() {
  # 检查是否已经运行
  if docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null | grep -q 'true'; then
    log "Registry 已在运行中 (localhost:${REGISTRY_PORT})"
    return 0
  fi

  # 如果容器存在但停止了，先删除
  if docker inspect "${REGISTRY_NAME}" >/dev/null 2>&1; then
    log "发现停止的 registry 容器，正在移除..."
    docker rm -f "${REGISTRY_NAME}" >/dev/null
  fi

  # 启动 registry 容器
  log "启动本地 Registry (localhost:${REGISTRY_PORT})..."
  docker run -d \
    --name "${REGISTRY_NAME}" \
    --restart=always \
    -p "127.0.0.1:${REGISTRY_PORT}:${REGISTRY_INTERNAL_PORT}" \
    registry:2

  log "✅ Registry 已启动: localhost:${REGISTRY_PORT}"
}

stop() {
  if docker inspect "${REGISTRY_NAME}" >/dev/null 2>&1; then
    log "停止并删除 Registry 容器..."
    docker rm -f "${REGISTRY_NAME}" >/dev/null
    log "✅ Registry 已停止"
  else
    log "Registry 容器不存在"
  fi
}

status() {
  if docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null | grep -q 'true'; then
    local ip
    ip=$(docker inspect -f '{{.NetworkSettings.Ports}}' "${REGISTRY_NAME}" 2>/dev/null)
    log "✅ 运行中 — localhost:${REGISTRY_PORT}"
    # 检查是否连接到 kind 网络
    if docker network inspect kind >/dev/null 2>&1; then
      if docker inspect -f '{{json .NetworkSettings.Networks}}' "${REGISTRY_NAME}" 2>/dev/null | grep -q '"kind"'; then
        log "   已连接到 kind 网络"
      else
        log "   ⚠️  未连接到 kind 网络"
      fi
    fi
  else
    log "❌ 未运行"
  fi
}

# 将 registry 连接到 kind 的 Docker 网络
connect_to_kind_network() {
  if ! docker network inspect kind >/dev/null 2>&1; then
    log "kind 网络不存在，跳过连接"
    return 0
  fi

  if docker inspect -f '{{json .NetworkSettings.Networks}}' "${REGISTRY_NAME}" 2>/dev/null | grep -q '"kind"'; then
    log "Registry 已连接到 kind 网络"
    return 0
  fi

  log "连接 Registry 到 kind 网络..."
  docker network connect kind "${REGISTRY_NAME}" 2>/dev/null || true
  log "✅ 已连接到 kind 网络"
}

# 配置集群节点的 containerd 以识别本地 registry
configure_cluster_nodes() {
  log "配置集群节点信任本地 Registry..."
  for node in $(kind get nodes --name dev 2>/dev/null); do
    docker exec "${node}" mkdir -p /etc/containerd/certs.d/localhost:${REGISTRY_PORT}
    cat <<EOF | docker exec -i "${node}" tee /etc/containerd/certs.d/localhost:${REGISTRY_PORT}/hosts.toml > /dev/null
[host."http://${REGISTRY_NAME}:${REGISTRY_INTERNAL_PORT}"]
EOF
  done
  log "✅ 节点配置完成"
}

# 创建 configmap 让集群知道 registry 地址 (kind 约定)
create_registry_configmap() {
  log "创建 registry ConfigMap..."
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
  log "✅ ConfigMap 已创建"
}

# 完整的 setup：启动 registry + 连接网络 + 配置节点
setup() {
  start
  connect_to_kind_network
  configure_cluster_nodes
  create_registry_configmap
}

case "${1:-status}" in
  start)   start ;;
  stop)    stop ;;
  status)  status ;;
  setup)   setup ;;
  connect) connect_to_kind_network ;;
  *)
    echo "用法: $0 {start|stop|status|setup|connect}"
    echo ""
    echo "  start   - 启动 registry 容器"
    echo "  stop    - 停止并删除 registry 容器"
    echo "  status  - 查看 registry 状态"
    echo "  setup   - 完整初始化（启动 + 连接 kind 网络 + 配置节点）"
    echo "  connect - 仅连接到 kind 网络"
    exit 1
    ;;
esac
