#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-development}"
NAMESPACE="fastapi-app"
OVERLAY="k8s/overlays/${ENV}"

if [[ ! -d "${OVERLAY}" ]]; then
  echo "ERROR: overlay '${OVERLAY}' not found"
  exit 1
fi

echo "==> Deploying to environment: ${ENV}"

# Validate manifests before applying (dry-run)
kubectl apply --dry-run=server -k "${OVERLAY}"

echo "==> Applying manifests..."
kubectl apply -k "${OVERLAY}"

echo "==> Waiting for rollout..."
kubectl rollout status deployment/fastapi-app -n "${NAMESPACE}" --timeout=120s

echo "==> Deployment complete"
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=fastapi-app
