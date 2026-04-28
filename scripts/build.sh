#!/usr/bin/env bash
set -euo pipefail

IMAGE="fastapi-k8s-demo"
TAG="${1:-$(git rev-parse --short HEAD 2>/dev/null || echo 'local')}"
REGISTRY="${REGISTRY:-}"

echo "==> Building image: ${IMAGE}:${TAG}"
docker build \
  --target production \
  --tag "${IMAGE}:${TAG}" \
  --tag "${IMAGE}:latest" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg VCS_REF="${TAG}" \
  .

if [[ -n "${REGISTRY}" ]]; then
  echo "==> Pushing to ${REGISTRY}"
  docker tag "${IMAGE}:${TAG}" "${REGISTRY}/${IMAGE}:${TAG}"
  docker push "${REGISTRY}/${IMAGE}:${TAG}"
fi

echo "==> Done: ${IMAGE}:${TAG}"
