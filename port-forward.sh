#!/usr/bin/env bash
#
# 统一 port-forward 脚本
# 后台并行转发所有服务端口，Ctrl+C 一键全部停止
#

set -e

# 定义要转发的服务列表：本地端口 -> svc名称:目标端口 [namespace]
FORWARDS=(
  "8081:svc/demo1:80"
  "8082:svc/demo2:80"
  "8083:svc/nginx-demo:80"
  "3000:svc/prometheus-grafana:80:monitoring"
  "8084:svc/go-pingpong:8080"
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

# 启动 minikube dashboard（后台运行，自动分配端口）
echo "🖥️  启动 Minikube Dashboard..."
minikube dashboard --url > /tmp/minikube-dashboard.log 2>&1 &
PIDS+=($!)

# 启动 helm dashboard
echo "⎈  启动 Helm Dashboard..."
helm dashboard --no-browser --port 3200 > /tmp/helm-dashboard.log 2>&1 &
PIDS+=($!)

echo "🚀 启动端口转发..."
echo "-------------------------------------------"

for entry in "${FORWARDS[@]}"; do
  IFS=':' read -r local_port resource target_port namespace <<< "$entry"

  ns_flag=""
  ns_display="default"
  if [[ -n "$namespace" ]]; then
    ns_flag="--namespace $namespace"
    ns_display="$namespace"
  fi

  echo "  📡 localhost:${local_port} -> ${resource}:${target_port} [ns: ${ns_display}]"

  kubectl port-forward $ns_flag "$resource" "${local_port}:${target_port}" >/dev/null 2>&1 &
  PIDS+=($!)
done
sleep 1
# 等待 dashboard URL 就绪
DASHBOARD_URL=$(grep -oP 'http://[^\s]+' /tmp/minikube-dashboard.log 2>/dev/null || echo "启动中...")

echo "dashboard URL: ${DASHBOARD_URL}"

echo "helm dashboard URL: http://localhost:3200"

# 等待所有后台进程，任一退出则提示
wait
