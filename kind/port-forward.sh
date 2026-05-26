#!/usr/bin/env bash
#
# 统一端口转发脚本 (kind 环境)
# 后台并行转发所有服务端口，Ctrl+C 一键全部停止
#
# 用法: ./port-forward.sh
#

set -e

# 定义要转发的服务列表：本地端口:资源:目标端口[:namespace]
FORWARDS=(
  "3100:svc/headlamp:80:kube-system"
  "3000:svc/prometheus-grafana:80:monitoring"
  "9090:svc/prometheus-kube-prometheus-stack-prometheus:9090:monitoring"
  "9093:svc/prometheus-kube-prometheus-stack-alertmanager:9093:monitoring"
  "50051:svc/go-grpc-svc:50051:default"
)

PIDS=()

cleanup() {
  echo ""
  echo "🛑 正在停止所有端口转发..."
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null
  echo "✅ 全部已停止"
  exit 0
}

trap cleanup SIGINT SIGTERM

# 启动 Helm Dashboard (集群资源可视化 + Helm release 管理)
HELM_DASH_PORT=3200
if command -v helm-dashboard >/dev/null 2>&1 || helm plugin list 2>/dev/null | grep -q dashboard; then
  echo "⎈  启动 Helm Dashboard (port ${HELM_DASH_PORT})..."
  helm dashboard --no-browser --port "${HELM_DASH_PORT}" > /tmp/helm-dashboard-kind.log 2>&1 &
  PIDS+=($!)
else
  echo "⚠️  helm-dashboard 插件未安装，跳过 (安装: helm plugin install https://github.com/komodorio/helm-dashboard.git)"
fi

echo ""
echo "🚀 启动端口转发 (kind 集群)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for entry in "${FORWARDS[@]}"; do
  IFS=':' read -r local_port resource target_port namespace <<< "$entry"

  ns_flag=""
  ns_display="default"
  if [[ -n "$namespace" ]]; then
    ns_flag="--namespace $namespace"
    ns_display="$namespace"
  fi

  echo "  📡 localhost:${local_port} → ${resource}:${target_port} [${ns_display}]"

  kubectl port-forward $ns_flag "$resource" "${local_port}:${target_port}" >/dev/null 2>&1 &
  PIDS+=($!)
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 服务访问地址:"
echo ""
echo "  🖥️  Headlamp:      http://localhost:3100  (K8s Dashboard)"
echo "  ⎈  Helm Dashboard: http://localhost:${HELM_DASH_PORT}  (集群资源 + Helm 管理)"
echo "  🔍 Grafana:        http://localhost:3000  (admin / prom-operator)"
echo "  📊 Prometheus:     http://localhost:9090"
echo "  🔔 AlertManager:   http://localhost:9093"
echo ""
echo "  🚪 Gateway 入口 (宿主机端口 30080):"
echo "     curl http://localhost:30080/       (nginx-demo)"
echo "     curl http://localhost:30080/ping   (go-pingpong)"
echo "     grpcurl -plaintext localhost:30080 list  (go-grpc-svc via Gateway)"
echo ""
echo "  🔌 gRPC 直连 (port-forward):"
echo "     grpcurl -plaintext localhost:50051 list"
echo "     grpcurl -plaintext localhost:50051 configsvc.ConfigService/Ping"
echo "     grpcurl -plaintext -d '{\"filename\":\"app.json\"}' localhost:50051 configsvc.ConfigService/GetConfig"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "按 Ctrl+C 停止所有转发"
echo ""

# 等待所有后台进程
wait
