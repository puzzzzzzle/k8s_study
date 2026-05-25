## Helm Demo - web-demo Chart

通用 HTTP 服务 Helm Chart，支持两种部署模式：

- **nginx 模式**（`nginx.enabled: true`）：挂载 HTML ConfigMap + nginx-exporter sidecar 暴露 metrics
- **通用模式**（`nginx.enabled: false`）：纯容器部署，适用于 Go 等自带 HTTP 服务，metrics 由应用原生暴露

### 目录结构

```
helm-test/
├── web-demo/                  # 通用 Helm Chart
│   ├── Chart.yaml
│   ├── values.yaml            # 默认值（nginx.enabled: false）
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml    # 支持 nginx / 通用两种模式
│       ├── service.yaml
│       ├── configmap.yaml     # 仅 nginx.enabled 时渲染
│       └── service-monitor.yaml
├── go-pingpong/               # Go ping/pong API 服务源码
│   ├── main.go                # GET /ping → pong，GET /metrics → prometheus
│   ├── go.mod
│   └── Dockerfile
├── nginx-values.yaml          # nginx 静态站点配置
├── go-values.yaml             # Go ping/pong API 配置
└── output/                    # helm template 渲染产物（预览用）
    ├── nginx-helm.yaml
    └── go-helm.yaml
```

### Values 设计

`values.yaml` 提供默认值，各 values 文件只需覆盖差异部分（深度合并）。  
`name` 字段直接控制 K8s 资源名称，与 helm release name 解耦：

| 字段 | 说明 |
|------|------|
| `name` | K8s 资源名，留空则使用 release name |
| `nginx.enabled` | `true` → nginx 模式；`false` → 通用容器模式 |
| `metrics.port` | nginx 模式填 exporter 端口（9113）；通用模式填应用自身端口 |
| `serviceMonitor.enabled` | 是否生成 Prometheus ServiceMonitor |

### 预览渲染结果（不发布）

```bash
cd /data/srcs/k8s/helm-test

# 预览 nginx 静态站点渲染结果
helm template nginx-demo ./web-demo -f nginx-values.yaml

# 预览 Go ping/pong 渲染结果
helm template go-pingpong ./web-demo -f go-values.yaml

# 只看某个模板文件
helm template nginx-demo ./web-demo -f nginx-values.yaml -s templates/deployment.yaml

# 输出到文件
helm template nginx-demo ./web-demo -f nginx-values.yaml > output/nginx-helm.yaml
helm template go-pingpong ./web-demo -f go-values.yaml > output/go-helm.yaml
```

> `helm template` 纯本地渲染，无需连接集群；`helm install --dry-run` 需连接集群，可进行服务端校验。

### 构建 Go 镜像（minikube 本地）

```bash
cd /data/srcs/k8s/helm-test/go-pingpong

# 在宿主机构建镜像
docker build -t go-pingpong:latest .

# 推送到所有 minikube 节点（多节点集群必须）
minikube image load go-pingpong:latest --overwrite
```

> 单节点集群可用 `eval $(minikube docker-env) && docker build ...` 替代；多节点集群必须用 `minikube image load` 分发到所有节点，否则 Pod 调度到非主节点时报 `ErrImageNeverPull`。

go-values.yaml 中 `imagePullPolicy: Never` 确保使用本地镜像，不尝试从远端拉取。

### 部署

```bash
cd /data/srcs/k8s/helm-test

# 部署 nginx 静态站点
helm install nginx-demo ./web-demo -f nginx-values.yaml

# 部署 Go ping/pong API
helm install go-pingpong ./web-demo -f go-values.yaml

# 更新（幂等，不存在时自动创建）
helm upgrade --install nginx-demo ./web-demo -f nginx-values.yaml
helm upgrade --install go-pingpong ./web-demo -f go-values.yaml
```

### 查看状态

```bash
helm list
kubectl get pods
kubectl get svc
```

### 访问服务

```bash
# nginx 静态站点
kubectl port-forward svc/nginx-demo 8081:80
# 浏览器打开 http://localhost:8081

# Go ping/pong API
kubectl port-forward svc/go-pingpong 8083:8080
# curl http://localhost:8083/ping
# curl http://localhost:8083/metrics
```

> 远端机器记得在 VS Code PORTS 面板添加对应端口转发。

### 监控链路

```
nginx 模式：
  nginx(:80) → stub_status(:8080) → nginx-exporter(:9113/metrics)
                                          ↑ ServiceMonitor → Prometheus → Grafana

Go 模式：
  go-pingpong(:8080/metrics) ← ServiceMonitor → Prometheus → Grafana
```

### 清理

```bash
helm uninstall nginx-demo
helm uninstall go-pingpong
```

### Envoy Gateway（Gateway API 入口网关）

本 Chart 支持通过 [Envoy Gateway](https://gateway.envoyproxy.io/) 暴露服务，基于 Kubernetes Gateway API 标准。

#### 前置条件：安装 Envoy Gateway

```bash
# 一键安装（安装 CRDs + 控制器 + 自动 patch Service）
cd /data/srcs/k8s/kind
./install-gateway.sh
```

#### 部署带 Gateway 的服务

```bash
cd /data/srcs/k8s/helm-test

# 部署 nginx-demo（同时创建 GatewayClass + Gateway + HTTPRoute）
helm upgrade --install nginx-demo ./web-demo -f nginx-values.yaml

# 部署 go-pingpong（复用已有 Gateway，只创建 HTTPRoute）
helm upgrade --install go-pingpong ./web-demo -f go-values.yaml

# 首次部署后需要再运行一次 install-gateway.sh 来 patch Envoy Service
# （因为 Gateway 资源是由 helm 创建的，Envoy Service 在 helm install 之后才出现）
cd /data/srcs/k8s/kind && ./install-gateway.sh
```

#### 架构说明

```
                       ┌────────────────────────────────────────────┐
                       │            demo-gateway                     │
                       │   (Envoy Gateway 自动创建 Envoy Proxy Pod)  │
  curl localhost:30080 │                                            │
  ─────────────────────┤  /ping  → go-pingpong Service (:8080)     │
                       │  /      → nginx-demo Service (:80)  兜底   │
                       └────────────────────────────────────────────┘
```

采用**纯 path 路由**（不区分 hostname），多个服务共享一个 Gateway（`demo-gateway`），通过路径区分：

| 路径 | 后端服务 | 匹配方式 |
|------|---------|---------|
| `/ping` | go-pingpong:8080 | PathPrefix（优先匹配） |
| `/` | nginx-demo:80 | PathPrefix（兜底） |

> 路由优先级：`Exact` > 更长的 `PathPrefix` > 更短的 `PathPrefix`

#### 访问方式（kind 环境）

```bash
curl http://localhost:30080/        # → nginx-demo
curl http://localhost:30080/ping    # → go-pingpong {"message":"pong",...}
```

无需 `-H 'Host: ...'`，直接 `localhost` + path 即可。

#### Kind 环境 NodePort Patch 原理

在 kind 中，宿主机通过 Docker 端口映射访问集群节点端口：

```
宿主机 localhost:30080 → Docker → control-plane 节点 :30080 → kube-proxy → Envoy Pod
```

但 Envoy Gateway **自动创建的 Service** 有两个问题导致默认无法访问：

| 问题 | 默认值 | 后果 |
|------|--------|------|
| NodePort 随机 | `31xxx`（随机分配） | kind 只映射了 30080，随机端口到不了 |
| `externalTrafficPolicy: Local` | 只有 Pod 所在节点可转发 | Envoy Pod 在 worker，但端口映射在 control-plane → 流量不通 |

**`install-gateway.sh` 自动修复**：通过 label `gateway.envoyproxy.io/owning-gateway-name=demo-gateway` 找到 Envoy Service，patch 为：

```yaml
spec:
  externalTrafficPolicy: Cluster   # 所有节点都可转发（跨节点 SNAT）
  ports:
  - name: http-80
    port: 80
    targetPort: 10080              # Envoy proxy 容器实际监听端口
    nodePort: 30080                # 固定为 kind 映射的端口
```

#### Values 配置说明

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `gateway.enabled` | 是否启用 Gateway API 路由 | `false` |
| `gateway.className` | GatewayClass 名称 | `eg` |
| `gateway.createGatewayClass` | 是否创建 GatewayClass（集群只需一个） | `true` |
| `gateway.createGateway` | 是否创建 Gateway 资源 | `true` |
| `gateway.name` | Gateway 名称（多服务可共享） | `<fullname>-gateway` |
| `gateway.hostname` | HTTPRoute 域名匹配（留空 = 纯 path 路由） | 空 |
| `gateway.tls.enabled` | 是否启用 HTTPS listener | `false` |
| `gateway.routes` | 自定义路由规则（path + pathType） | 空（默认 `/` 全转发） |

#### 多服务共享 Gateway 的部署模式

```
第一个服务（创建基础设施）：
  gateway.createGatewayClass: true
  gateway.createGateway: true
  gateway.name: demo-gateway

后续服务（仅创建 HTTPRoute）：
  gateway.createGatewayClass: false
  gateway.createGateway: false
  gateway.name: demo-gateway          # 引用同一个 Gateway
```

#### 预览渲染结果

```bash
# 查看 nginx-demo 的 Gateway 资源
helm template nginx-demo ./web-demo -f nginx-values.yaml -s templates/gateway.yaml

# 查看 go-pingpong 的 HTTPRoute
helm template go-pingpong ./web-demo -f go-values.yaml -s templates/gateway.yaml
```
