#!/usr/bin/env bash
#
# 安装 Headlamp (轻量级 Kubernetes Dashboard)
# CNCF 项目，单容器部署，支持插件扩展
#
# 用法: ./install-headlamp.sh
#

set -euo pipefail

NAMESPACE="kube-system"
MANIFEST_URL="https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/kubernetes-headlamp.yaml"
SA_NAME="headlamp-admin"

log() { echo -e "\033[1;34m[Headlamp]\033[0m $*"; }
info() { echo -e "  \033[0;36m→\033[0m $*"; }

# 安装 Headlamp
log "安装 Headlamp..."
kubectl apply -f "${MANIFEST_URL}"

# 等待 Deployment 就绪
log "等待 Headlamp Pod 就绪..."
kubectl wait --namespace "${NAMESPACE}" \
  --for=condition=Available \
  --timeout=120s \
  deployment/headlamp

# 创建 admin ServiceAccount + ClusterRoleBinding + Token
log "创建管理员 ServiceAccount (${SA_NAME})..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SA_NAME}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
---
apiVersion: v1
kind: Secret
metadata:
  name: ${SA_NAME}-token
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

# 等待 token 生成
sleep 2

# 创建 Gateway 路由 (如果 Gateway API CRDs 存在)
if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  log "创建 Headlamp Gateway 路由..."
  kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: infra-gateway
  namespace: ${NAMESPACE}
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: headlamp
  namespace: ${NAMESPACE}
spec:
  parentRefs:
  - name: infra-gateway
    namespace: ${NAMESPACE}
  hostnames:
  - "headlamp.demo.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: headlamp
      port: 80
EOF
  info "路由: Host: headlamp.demo.local → headlamp:80"
else
  info "未检测到 Gateway API CRDs，跳过路由创建"
fi

# 获取 Token
TOKEN=$(kubectl get secret ${SA_NAME}-token -n ${NAMESPACE} -o jsonpath='{.data.token}' | base64 -d)

# 保存 token 到文件
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "${TOKEN}" > "${SCRIPT_DIR}/headlamp-token.txt"

log "✅ Headlamp 安装完成！"
echo ""
info "Port-forward:  kubectl port-forward -n ${NAMESPACE} svc/headlamp 3100:80"
info "Gateway 路由:  curl -H 'Host: headlamp.demo.local' http://localhost:10080"
info "登录 Token 已保存到: ${SCRIPT_DIR}/headlamp-token.txt"
echo ""
info "打开浏览器访问 http://localhost:3100，使用 Token 登录"
