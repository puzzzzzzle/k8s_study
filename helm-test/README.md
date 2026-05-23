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
