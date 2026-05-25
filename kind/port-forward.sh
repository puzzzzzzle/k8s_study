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
  "3000:svc/prometheus-grafana:80:monitoring"
  "9090:svc/prometheus-kube-prometheus-stack-prometheus:9090:monitoring"
  "9093:svc/prometheus-kube-prometheus-stack-alertmanager:9093:monitoring"
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
echo "  🔍 Grafana:       http://localhost:3000  (admin / prom-operator)"
echo "  📊 Prometheus:    http://localhost:9090"
echo "  🔔 AlertManager:  http://localhost:9093"
echo ""
echo "  🚪 Gateway 入口 (宿主机端口 10080/10443):"
echo "     curl -H 'Host: <your-app>.demo.local' http://localhost:10080"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "按 Ctrl+C 停止所有转发"
echo ""

# 等待所有后台进程
wait
