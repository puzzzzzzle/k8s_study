#!/usr/bin/env bash
#
# kind 集群销毁脚本
# 删除 kind 集群、停止 registry 容器、清理网络
#
# 用法: ./teardown.sh [--keep-registry]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="dev"
KEEP_REGISTRY=false

for arg in "$@"; do
  case "$arg" in
    --keep-registry) KEEP_REGISTRY=true ;;
    --help|-h)
      echo "用法: $0 [选项]"
      echo ""
      echo "选项:"
      echo "  --keep-registry  保留本地 registry 容器（镜像缓存不丢失）"
      echo "  --help, -h       显示帮助"
      exit 0
      ;;
  esac
done

log() { echo -e "\033[1;34m[Teardown]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# ═══════════════════════════════════════
# 1. 删除 kind 集群
# ═══════════════════════════════════════
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  log "删除 kind 集群 '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
  log "✅ 集群已删除"
else
  warn "集群 '${CLUSTER_NAME}' 不存在，跳过"
fi

# ═══════════════════════════════════════
# 2. 处理 Registry
# ═══════════════════════════════════════
if [[ "$KEEP_REGISTRY" == "true" ]]; then
  log "保留 Registry 容器 (--keep-registry)"
  # 断开 kind 网络连接（网络可能已被删除）
  docker network disconnect kind kind-registry 2>/dev/null || true
else
  log "停止本地 Registry..."
  bash "${SCRIPT_DIR}/registry.sh" stop
fi

# ═══════════════════════════════════════
# 3. 清理
# ═══════════════════════════════════════
# kind 删除集群时已自动清理 Docker 网络，这里只做确认
if docker network inspect kind >/dev/null 2>&1; then
  log "清理残留 kind 网络..."
  docker network rm kind 2>/dev/null || true
fi

log "🧹 清理完成！"
echo ""
echo "重新创建集群: ./setup.sh"
