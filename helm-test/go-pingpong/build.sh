#!/usr/bin/env bash
#
# 构建 go-pingpong 镜像并加载到所有 minikube 节点
# 多节点集群不支持 docker-env，需用 minikube image load 分发到所有节点
#
set -e

cd $(dirname "$0")

IMAGE="go-pingpong"
TAG="${1:-`date "+%Y-%m-%d-%H-%M-%S"`}"

echo "构建镜像 ${IMAGE}:${TAG}..."
docker build -t "${IMAGE}:${TAG}" .

bash ../../push_img.sh "${IMAGE}" "${TAG}"

echo "完成：${IMAGE}:${TAG}"
