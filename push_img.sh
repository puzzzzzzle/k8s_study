#!/usr/bin/env bash
#
# 将镜像推送到 minikube registry
#
set -e

IMAGE=$1
TAG=$2
if [ -z "$IMAGE" ] || [ -z "$TAG" ]; then
    echo "Usage: $0 <image> <tag>"
    exit 1
fi

echo "加载镜像 ${IMAGE}:${TAG} 到所有 minikube 节点..."
minikube image load "${IMAGE}:${TAG}" --overwrite
