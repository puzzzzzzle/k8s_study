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
│       ├── gateway.yaml       # HTTPRoute（GatewayClass/Gateway 由开关控制）
│       └── service-monitor.yaml
├── go-pingpong/               # Go ping/pong API 服务源码
│   ├── main.go                # GET /ping → pong，GET /metrics → prometheus
│   ├── go.mod
│   └── Dockerfile
├── gateway.yaml               # 🔑 公共基础设施（GatewayClass + Gateway）
├── nginx-values.yaml          # nginx 静态站点配置（HTTPRoute: /）
├── go-values.yaml             # Go ping/pong API 配置（HTTPRoute: /ping）
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

# 1. 部署公共基础设施（GatewayClass + Gateway）
kubectl apply -f gateway.yaml

# 2. 部署业务服务（各自只创建 HTTPRoute）
helm upgrade --install nginx-demo ./web-demo -f nginx-values.yaml
helm upgrade --install go-pingpong ./web-demo -f go-values.yaml

# 3. Patch Envoy Service（首次部署 Gateway 后执行一次）
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
| `gateway.enabled` | 是否启用 HTTPRoute 路由 | `false` |
| `gateway.name` | 引用的 Gateway 名称 | `<fullname>-gateway` |
| `gateway.hostname` | HTTPRoute 域名匹配（留空 = 纯 path 路由） | 空 |
| `gateway.routes` | 自定义路由规则（path + pathType） | 空（默认 `/` 全转发） |

#### 多服务共享 Gateway 的部署模式

```
公共基础设施（gateway.yaml，kubectl apply 管理）：
  - GatewayClass: eg
  - Gateway: demo-gateway

各业务服务（helm release，只创建 HTTPRoute）：
  gateway.enabled: true
  gateway.name: demo-gateway          # 引用公共 Gateway
  gateway.routes:                     # 各自的路由规则
  - path: /xxx
```

#### gRPC Stream 支持

Envoy Gateway 原生支持 gRPC 的所有四种 RPC 模式：

| 模式 | 说明 | 支持 |
|------|------|------|
| Unary | 单请求 / 单响应 | ✅ |
| Server Streaming | 单请求 / 多响应（服务端推送） | ✅ |
| Client Streaming | 多请求 / 单响应 | ✅ |
| Bidirectional Streaming | 多请求 / 多响应（双向流） | ✅ |

**关键字**：protobuf 中使用 `stream` 关键字声明流式接口：

```protobuf
service MyService {
  rpc SimpleCall(Request) returns (Response);                       // 普通
  rpc ServerPush(Request) returns (stream Response);               // 服务端流
  rpc ClientPush(stream Request) returns (Response);               // 客户端流
  rpc BiStream(stream Request) returns (stream Response);          // 双向流
}
```

##### 多实例下 Stream 推送的路由保证

**结论：同一个 stream 内的所有推送始终路由到同一个后端实例，无需额外配置。**

原理：gRPC stream 基于 HTTP/2，一个 stream 调用 = 一个 HTTP/2 stream，从建立到关闭始终绑定在同一条 TCP 连接上。

```
时间线（Server Streaming 为例）：

t0: 客户端 → Envoy → [负载均衡选择] → 实例A    (stream 建立，此时选定后端)
t1: 实例A → Envoy → 客户端                      (第1次推送)
t2: 实例A → Envoy → 客户端                      (第2次推送)
...
tN: 实例A → Envoy → 客户端                      (stream 关闭)
```

要点：
- **负载均衡只发生一次**：在 stream 建立时（t0），后续推送不会重新路由
- **HTTP/2 协议保证**：stream 是连接内的逻辑通道，天然绑定同一后端
- **无需 sticky session**：不同于 HTTP/1.1 多次请求，gRPC stream 本身就是有状态连接

##### 注意事项

| 场景 | 处理方式 |
|------|---------|
| 断线重连 | stream 断开后重新建立，可能路由到不同实例；需应用层设计断点续传（如 cursor） |
| 多个独立请求需要亲和性 | 使用 `BackendTrafficPolicy` + ConsistentHash 实现会话粘性 |
| 超时配置 | 流式长连接需调大超时，避免被网关提前关闭 |

##### gRPC 路由配置示例

使用 `GRPCRoute`（Gateway API 原生支持）：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: my-grpc-route
spec:
  parentRefs:
    - name: demo-gateway
  rules:
    - matches:
        - method:
            service: mypackage.MyService
      backendRefs:
        - name: my-grpc-service
          port: 50051
```

流式长连接超时配置：

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: grpc-stream-timeout
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: GRPCRoute
      name: my-grpc-route
  timeout:
    http:
      requestTimeout: "0s"     # 不超时（流式场景）
      idleTimeout: "3600s"     # 空闲 1 小时后断开
```

会话亲和性（多个独立请求路由到同一实例）：

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: grpc-affinity
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: GRPCRoute
      name: my-grpc-route
  loadBalancer:
    type: ConsistentHash
    consistentHash:
      type: Header
      header:
        name: x-session-id
```

#### 预览渲染结果

```bash
# 查看 nginx-demo 的 Gateway 资源
helm template nginx-demo ./web-demo -f nginx-values.yaml -s templates/gateway.yaml

# 查看 go-pingpong 的 HTTPRoute
helm template go-pingpong ./web-demo -f go-values.yaml -s templates/gateway.yaml
```
