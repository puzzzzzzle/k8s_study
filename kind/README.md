# Kind 本地 K8s 集群管理工具

一键管理本地 Kubernetes 集群（基于 kind），包含本地 Registry、监控栈和网关。应用部署由各自项目目录自行负责。

## 架构概览

```
┌─────────────────────────────────────────────────────────┐
│ 宿主机                                                   │
│                                                         │
│  ┌──────────────┐    docker build & push                │
│  │ Local        │◄─────────────────────────             │
│  │ Registry     │    localhost:5001                      │
│  │ (容器)       │                                       │
│  └──────┬───────┘                                       │
│         │ (Docker network: kind)                        │
│  ┌──────┴───────────────────────────────────────────┐   │
│  │ kind Cluster "dev"                                │   │
│  │                                                   │   │
│  │  ┌───────────┐ ┌────────┐ ┌────────┐ ┌────────┐ │   │
│  │  │ CP Node   │ │Worker 1│ │Worker 2│ │Worker 3│ │   │
│  │  └───────────┘ └────────┘ └────────┘ └────────┘ │   │
│  │                                                   │   │
│  │  安装组件:                                        │   │
│  │  • kube-prometheus-stack (monitoring)             │   │
│  │  • Envoy Gateway (envoy-gateway-system)           │   │
│  │  • Headlamp Dashboard (kube-system)               │   │
│  └───────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## 前置依赖

| 工具 | 最低版本 | 安装 |
|------|---------|------|
| Docker | 20+ | https://docs.docker.com/get-docker/ |
| kind | 0.20+ | `go install sigs.k8s.io/kind@latest` 或 [Release](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| kubectl | 1.28+ | https://kubernetes.io/docs/tasks/tools/ |
| Helm | 3.12+ | https://helm.sh/docs/intro/install/ |

## 快速开始

```bash
# 一键创建集群（约 3-5 分钟）
./setup.sh

# 端口转发访问服务
./port-forward.sh

# 销毁集群
./teardown.sh
```

## 脚本说明

| 脚本 | 用途 |
|------|------|
| `setup.sh` | 一键创建集群 + 安装平台组件 (监控/网关/Dashboard) |
| `teardown.sh` | 销毁集群，可选保留 registry |
| `registry.sh` | 管理本地 Docker Registry |
| `build-and-push.sh` | 构建镜像并推送到本地 registry |
| `install-monitoring.sh` | 单独安装/升级 Prometheus 监控栈 |
| `install-gateway.sh` | 单独安装/升级 Envoy Gateway |
| `install-headlamp.sh` | 单独安装/升级 Headlamp Dashboard |
| `get-credentials.sh` | 获取各服务登录凭据 (Grafana/Headlamp) |
| `port-forward.sh` | 统一端口转发（Dashboard/监控服务） |

## 端口映射表

| 本地端口 | 服务 | 说明 |
|---------|------|------|
| 10080 | Envoy Gateway | HTTP 入口（通过 Host 头路由） |
| 10443 | Envoy Gateway | HTTPS 入口 |
| 30080 | Envoy Gateway (NodePort) | HTTP + gRPC 统一入口 |
| 50051 | go-grpc-svc (port-forward) | gRPC 直连（绕过 Gateway） |
| 3100 | Headlamp | K8s Dashboard（Token 登录） |
| 3200 | Helm Dashboard | 集群资源 + Helm release 管理 |
| 3000 | Grafana | 监控面板 (admin / prom-operator) |
| 9090 | Prometheus | 指标查询 |
| 9093 | AlertManager | 告警管理 |

## 镜像管理

### 构建并推送镜像

```bash
# 构建 go-pingpong（自动时间戳 tag）
./build-and-push.sh go-pingpong ../helm-test/go-pingpong

# 指定 tag
./build-and-push.sh go-pingpong ../helm-test/go-pingpong v1.0.0

# 构建任意应用
./build-and-push.sh my-app /path/to/app latest
```

### 镜像命名约定

- 宿主机推送地址: `localhost:5001/<image>:<tag>`
- 集群内拉取地址: `kind-registry:5000/<image>:<tag>`（自动映射）

### 在应用的 values.yaml 中引用本地镜像

```yaml
image:
  repository: localhost:5001/go-pingpong
  tag: latest
  pullPolicy: Always
```

## Registry 管理

```bash
./registry.sh start    # 启动
./registry.sh stop     # 停止
./registry.sh status   # 查看状态
./registry.sh setup    # 完整初始化（含连接 kind 网络）
```

## 常用操作

### 更新监控配置

```bash
# 修改 values/prometheus-values.yaml 后
./install-monitoring.sh
```

### 查看集群状态

```bash
kubectl get nodes
kubectl get pods -A
kubectl get gateway -A
```

## setup.sh 选项

```bash
./setup.sh                    # 完整安装
./setup.sh --skip-monitoring  # 跳过 Prometheus 安装
./setup.sh --skip-gateway     # 跳过 Envoy Gateway 安装
./setup.sh --skip-headlamp    # 跳过 Headlamp Dashboard 安装
```

## teardown.sh 选项

```bash
./teardown.sh                 # 完全清理（含 registry）
./teardown.sh --keep-registry # 保留 registry（镜像缓存不丢）
```

## 目录结构

```
kind/
├── README.md                 # 本文档
├── kind-config.yaml          # kind 集群配置
├── setup.sh                  # 一键创建集群
├── teardown.sh               # 销毁集群
├── registry.sh               # Registry 管理
├── build-and-push.sh         # 镜像构建推送
├── install-monitoring.sh     # 安装监控
├── install-gateway.sh        # 安装网关
├── install-headlamp.sh       # 安装 Headlamp Dashboard
├── get-credentials.sh        # 获取服务登录凭据
├── port-forward.sh           # 端口转发
├── headlamp-token.txt        # Headlamp 登录 Token (自动生成)
└── values/
    └── prometheus-values.yaml  # Prometheus 配置
```

## Headlamp Dashboard

[Headlamp](https://github.com/kubernetes-sigs/headlamp) 是 CNCF/Kubernetes SIG-UI 维护的轻量级 K8s Dashboard，单容器部署。

### 访问方式

```bash
# 方式 1: port-forward（推荐，./port-forward.sh 已包含）
kubectl port-forward -n kube-system svc/headlamp 3100:80

# 方式 2: 通过 Gateway 路由
curl -H 'Host: headlamp.demo.local' http://localhost:10080
```

### 登录

使用 Token 方式登录，token 保存在 `headlamp-token.txt`：

```bash
cat headlamp-token.txt
```

### 单独安装/升级

```bash
./install-headlamp.sh
```

## 常见问题

### Q: 镜像拉取失败 (ImagePullBackOff)

确保 registry 正在运行且已连接到 kind 网络：
```bash
./registry.sh status
./registry.sh connect
```

### Q: Gateway 没有分配 IP

检查 Envoy Gateway 控制器是否正常：
```bash
kubectl get pods -n envoy-gateway-system
kubectl get gateway -A
```

### Q: Gateway 30080 端口超时 (context deadline exceeded)

**根因**：`externalTrafficPolicy: Local` 时流量不跨节点转发。如果 Envoy Pod 不在 control-plane 节点则超时。

**现状**：已通过 `manifests/gateway.yaml` 中 EnvoyProxy CRD 的 StrategicMerge patch 声明式解决：
- `externalTrafficPolicy: Cluster`（流量可跨节点）
- `nodeSelector` 将 Envoy Pod 调度到 control-plane 节点
- `nodePort: 30080` 固定端口号

所有配置通过 `kubectl apply -f manifests/gateway.yaml` 生效，无需脚本临时修复。

### Q: 端口 10080 被占用

修改 `kind-config.yaml` 中的 `hostPort` 为其他端口，然后重建集群。

### Q: 节点资源不足

kind 节点共享宿主机资源。可以在 `kind-config.yaml` 中减少 worker 数量。
