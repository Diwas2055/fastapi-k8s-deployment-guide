#!/usr/bin/env bash
# First-time local environment setup — run once after cloning.
set -euo pipefail

TOOL="${1:-kind}"   # kind | k3d | minikube
CLUSTER="fastapi-demo"
IMAGE="fastapi-k8s-demo:local"

echo "==> [1/5] Checking dependencies"
for cmd in docker kubectl; do
  command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
done

echo "==> [2/5] Copying env file"
[[ -f .env ]] || cp .env.example .env

echo "==> [3/5] Building Docker image"

case "$TOOL" in
  kind)
    command -v kind &>/dev/null || { echo "ERROR: kind not found — https://kind.sigs.k8s.io"; exit 1; }
    echo "  Using kind..."
    docker build --target production -t "$IMAGE" .
    kind get clusters | grep -q "$CLUSTER" || kind create cluster --name "$CLUSTER"
    kind load docker-image "$IMAGE" --name "$CLUSTER"
    ;;
  k3d)
    command -v k3d &>/dev/null || { echo "ERROR: k3d not found — https://k3d.io"; exit 1; }
    echo "  Using k3d..."
    k3d cluster list | grep -q "$CLUSTER" || \
      k3d cluster create "$CLUSTER" \
        --registry-create fastapi-registry:5000 \
        --port "8080:80@loadbalancer"
    docker build --target production -t "$IMAGE" .
    k3d image import "$IMAGE" -c "$CLUSTER"
    ;;
  minikube)
    command -v minikube &>/dev/null || { echo "ERROR: minikube not found — https://minikube.sigs.k8s.io"; exit 1; }
    echo "  Using minikube..."
    minikube status -p "$CLUSTER" &>/dev/null || \
      minikube start -p "$CLUSTER" --driver=docker --cpus=2 --memory=4096
    eval "$(minikube docker-env -p "$CLUSTER")"
    docker build --target production -t "$IMAGE" .
    minikube addons enable metrics-server -p "$CLUSTER"
    minikube addons enable ingress -p "$CLUSTER"
    ;;
  *)
    echo "ERROR: Unknown tool '$TOOL'. Use: kind | k3d | minikube"
    exit 1
    ;;
esac

echo "==> [4/5] Deploying dev overlay"
kubectl apply -k k8s/overlays/development
kubectl rollout status deployment -n fastapi-app --timeout=90s

echo "==> [5/5] Done!"
echo ""
echo "  Port-forward: kubectl port-forward svc/dev-fastapi-svc 8080:80 -n fastapi-app"
echo "  Health check: curl http://localhost:8080/healthz/ready"
echo "  API docs:     http://localhost:8080/docs  (DEBUG=true)"
