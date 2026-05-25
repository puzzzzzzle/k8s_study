#!/usr/bin/env bash
#
# 镜像构建并推送到本地 Registry
#
# 用法:
#   ./build-and-push.sh <image-name> <context-dir> [tag]
#
# 示例:
#   ./build-and-push.sh go-pingpong ../helm-test/go-pingpong
#   ./build-and-push.sh go-pingpong ../helm-test/go-pingpong v1.0.0
#   ./build-and-push.sh my-app ./app latest
#

set -euo pipefail

REGISTRY="localhost:5001"

log() { echo -e "\033[1;34m[Build]\033[0m $*"; }
err() { echo -e "\033[1;31m[Error]\033[0m $*" >&2; exit 1; }

# 参数校验
if [[ $# -lt 2 ]]; then
  echo "用法: $0 <image-name> <context-dir> [tag]"
  echo ""
  echo "参数:"
  echo "  image-name    镜像名称 (如: go-pingpong)"
  echo "  context-dir   Dockerfile 所在目录"
  echo "  tag           镜像标签 (默认: 时间戳)"
  echo ""
  echo "示例:"
  echo "  $0 go-pingpong ../helm-test/go-pingpong"
  echo "  $0 go-pingpong ../helm-test/go-pingpong v1.0.0"
  exit 1
fi

IMAGE_NAME="$1"
CONTEXT_DIR="$2"
TAG="${3:-$(date +%Y%m%d-%H%M%S)}"

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
LATEST_IMAGE="${REGISTRY}/${IMAGE_NAME}:latest"

# 检查 context 目录和 Dockerfile
if [[ ! -d "$CONTEXT_DIR" ]]; then
  err "目录不存在: $CONTEXT_DIR"
fi

if [[ ! -f "${CONTEXT_DIR}/Dockerfile" ]]; then
  err "Dockerfile 不存在: ${CONTEXT_DIR}/Dockerfile"
fi

# 检查 registry 是否运行
if ! docker inspect -f '{{.State.Running}}' kind-registry 2>/dev/null | grep -q 'true'; then
  err "本地 Registry 未运行，请先执行: ./registry.sh start"
fi

# 构建
log "构建镜像: ${FULL_IMAGE}"
log "Context: ${CONTEXT_DIR}"
docker build -t "${FULL_IMAGE}" -t "${LATEST_IMAGE}" "${CONTEXT_DIR}"

# 推送
log "推送到本地 Registry..."
docker push "${FULL_IMAGE}"
docker push "${LATEST_IMAGE}"

log "✅ 完成！"
echo ""
echo "镜像地址:"
echo "  ${FULL_IMAGE}"
echo "  ${LATEST_IMAGE}"
echo ""
echo "在 values.yaml 中使用:"
echo "  image:"
echo "    repository: ${REGISTRY}/${IMAGE_NAME}"
echo "    tag: ${TAG}"
