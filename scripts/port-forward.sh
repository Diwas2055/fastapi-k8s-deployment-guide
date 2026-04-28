#!/usr/bin/env bash
# Forward all useful ports locally for development.
set -euo pipefail

NAMESPACE="${NAMESPACE:-fastapi-app}"
API_PORT="${API_PORT:-8080}"
METRICS_PORT="${METRICS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"

cleanup() {
  echo ""
  echo "==> Stopping port-forwards..."
  kill "${PIDS[@]}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PIDS=()

echo "==> Forwarding FastAPI API → localhost:${API_PORT}"
kubectl port-forward "svc/$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/component=api -o name | head -1 | cut -d/ -f2)" \
  "${API_PORT}:80" -n "$NAMESPACE" &
PIDS+=($!)

if kubectl get svc -n monitoring prometheus-operated &>/dev/null; then
  echo "==> Forwarding Prometheus → localhost:${METRICS_PORT}"
  kubectl port-forward svc/prometheus-operated "${METRICS_PORT}:9090" -n monitoring &
  PIDS+=($!)
fi

if kubectl get svc -n monitoring kube-prometheus-stack-grafana &>/dev/null; then
  echo "==> Forwarding Grafana → localhost:${GRAFANA_PORT}"
  kubectl port-forward svc/kube-prometheus-stack-grafana "${GRAFANA_PORT}:80" -n monitoring &
  PIDS+=($!)
fi

echo ""
echo "  API:      http://localhost:${API_PORT}/healthz/ready"
echo "  Docs:     http://localhost:${API_PORT}/docs"
echo "  Metrics:  http://localhost:${METRICS_PORT}"
echo "  Grafana:  http://localhost:${GRAFANA_PORT}"
echo ""
echo "  Press Ctrl+C to stop all port-forwards."

wait
