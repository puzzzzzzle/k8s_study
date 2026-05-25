#!/usr/bin/env bash
#
# 获取集群各服务的登录凭据
#
# 用法: ./get-credentials.sh [服务名]
#   ./get-credentials.sh           # 显示所有凭据
#   ./get-credentials.sh grafana   # 只显示 Grafana 凭据
#   ./get-credentials.sh headlamp  # 只显示 Headlamp Token
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色
BOLD="\033[1m"
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RESET="\033[0m"

show_grafana() {
  echo -e "${BOLD}🔍 Grafana${RESET}"
  echo -e "   URL:      http://localhost:3000"
  local user pass
  user=$(kubectl get secret prometheus-grafana -n monitoring -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d)
  pass=$(kubectl get secret prometheus-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d)
  if [[ -n "$user" && -n "$pass" ]]; then
    echo -e "   用户名:   ${GREEN}${user}${RESET}"
    echo -e "   密码:     ${GREEN}${pass}${RESET}"
  else
    echo -e "   ${YELLOW}⚠️  未找到 Grafana secret（监控栈未安装？）${RESET}"
  fi
  echo ""
}

show_headlamp() {
  echo -e "${BOLD}🖥️  Headlamp${RESET}"
  echo -e "   URL:      http://localhost:3100"
  echo -e "   Gateway:  curl -H 'Host: headlamp.demo.local' http://localhost:10080"
  local token
  token=$(kubectl get secret headlamp-admin-token -n kube-system -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)
  if [[ -n "$token" ]]; then
    echo -e "   Token:    ${GREEN}${token}${RESET}"
    # 同步保存到文件
    echo "${token}" > "${SCRIPT_DIR}/headlamp-token.txt"
    echo -e "   ${CYAN}(已保存到 headlamp-token.txt)${RESET}"
  else
    echo -e "   ${YELLOW}⚠️  未找到 Headlamp token（Headlamp 未安装？）${RESET}"
  fi
  echo ""
}

show_prometheus() {
  echo -e "${BOLD}📊 Prometheus${RESET}"
  echo -e "   URL:      http://localhost:9090"
  echo -e "   认证:     无需登录"
  echo ""
}

show_alertmanager() {
  echo -e "${BOLD}🔔 AlertManager${RESET}"
  echo -e "   URL:      http://localhost:9093"
  echo -e "   认证:     无需登录"
  echo ""
}

show_helm_dashboard() {
  echo -e "${BOLD}⎈  Helm Dashboard${RESET}"
  echo -e "   URL:      http://localhost:3200"
  echo -e "   认证:     无需登录（使用当前 kubeconfig）"
  echo ""
}

# 主逻辑
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  📋 集群服务凭据 (kind-dev)${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

case "${1:-all}" in
  grafana)       show_grafana ;;
  headlamp)      show_headlamp ;;
  prometheus)    show_prometheus ;;
  alertmanager)  show_alertmanager ;;
  helm)          show_helm_dashboard ;;
  all)
    show_headlamp
    show_grafana
    show_prometheus
    show_alertmanager
    show_helm_dashboard
    ;;
  *)
    echo "用法: $0 [grafana|headlamp|prometheus|alertmanager|helm|all]"
    exit 1
    ;;
esac

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
