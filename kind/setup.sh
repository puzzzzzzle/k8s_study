#!/usr/bin/env bash
#
# kind 集群一键创建脚本
# 按顺序执行：检查依赖 → 启动 registry → 创建 kind 集群 → 连接网络 → 安装组件 → 验证
#
# 用法: ./setup.sh [--skip-monitoring] [--skip-gateway]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="dev"
KIND_CONFIG="${SCRIPT_DIR}/kind-config.yaml"

log() { echo -e "\n\033[1;32m══════════════════════════════════════════\033[0m"; echo -e "\033[1;32m  $*\033[0m"; echo -e "\033[1;32m══════════════════════════════════════════\033[0m\n"; }
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# 解析参数
SKIP_MONITORING=false
SKIP_GATEWAY=false

for arg in "$@"; do
  case "$arg" in
    --skip-monitoring) SKIP_MONITORING=true ;;
    --skip-gateway)    SKIP_GATEWAY=true ;;
    --help|-h)
      echo "用法: $0 [选项]"
      echo ""
      echo "选项:"
      echo "  --skip-monitoring  跳过 Prometheus/Grafana 安装"
      echo "  --skip-gateway     跳过 Envoy Gateway 安装"
      echo "  --help, -h         显示帮助"
      exit 0
      ;;
  esac
done

# ═══════════════════════════════════════
# 1. 检查依赖
# ═══════════════════════════════════════
log "1/5 检查依赖工具"

check_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "未找到 $1，请先安装: $2"
  fi
  info "✅ $1 $(command $1 --version 2>/dev/null | head -1 || echo '')"
}

check_cmd docker "https://docs.docker.com/get-docker/"
check_cmd kind "https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
check_cmd kubectl "https://kubernetes.io/docs/tasks/tools/"
check_cmd helm "https://helm.sh/docs/intro/install/"

# 检查 Docker daemon 是否运行
if ! docker info >/dev/null 2>&1; then
  err "Docker daemon 未运行，请先启动 Docker"
fi

# ═══════════════════════════════════════
# 2. 启动本地 Registry
# ═══════════════════════════════════════
log "2/5 启动本地 Registry"

bash "${SCRIPT_DIR}/registry.sh" start

# ═══════════════════════════════════════
# 3. 创建 kind 集群
# ═══════════════════════════════════════
log "3/5 创建 kind 集群"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  warn "集群 '${CLUSTER_NAME}' 已存在，跳过创建"
else
  info "创建集群 '${CLUSTER_NAME}' (1 control-plane + 3 worker)..."
  kind create cluster --config "${KIND_CONFIG}" --name "${CLUSTER_NAME}" --wait 60s
  info "✅ 集群创建成功"
fi

# 确认 kubectl 上下文
kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1
info "kubectl 上下文已切换到 kind-${CLUSTER_NAME}"

# ═══════════════════════════════════════
# 4. 配置 Registry 网络
# ═══════════════════════════════════════
log "4/5 配置 Registry 网络连接"

bash "${SCRIPT_DIR}/registry.sh" setup

# ═══════════════════════════════════════
# 5. 安装平台组件
# ═══════════════════════════════════════
log "5/5 安装平台组件"

if [[ "$SKIP_MONITORING" == "false" ]]; then
  info "安装 Prometheus 监控栈..."
  bash "${SCRIPT_DIR}/install-monitoring.sh"
else
  warn "跳过监控组件安装 (--skip-monitoring)"
fi

if [[ "$SKIP_GATEWAY" == "false" ]]; then
  info "安装 Envoy Gateway..."
  bash "${SCRIPT_DIR}/install-gateway.sh"
else
  warn "跳过 Envoy Gateway 安装 (--skip-gateway)"
fi

# ═══════════════════════════════════════
# 完成 — 验证集群状态
# ═══════════════════════════════════════
log "🎉 集群搭建完成！"

echo ""
echo "┌─────────────────────────────────────────────────┐"
echo "│ 集群信息                                         │"
echo "├─────────────────────────────────────────────────┤"
echo "│ 集群名称: ${CLUSTER_NAME}                       │"
echo "│ Registry: localhost:5001                         │"
echo "│ 上下文:   kind-${CLUSTER_NAME}                  │"
echo "├─────────────────────────────────────────────────┤"
echo "│ 快速命令                                         │"
echo "├─────────────────────────────────────────────────┤"
echo "│ 端口转发:  ./port-forward.sh                    │"
echo "│ 构建镜像:  ./build-and-push.sh <name> <dir>     │"
echo "│ 销毁集群:  ./teardown.sh                        │"
echo "└─────────────────────────────────────────────────┘"
echo ""
kubectl get nodes
