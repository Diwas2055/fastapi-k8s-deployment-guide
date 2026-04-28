#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-fastapi-app}"
DEPLOYMENT="fastapi-app"
REVISION="${1:-}"

echo "==> Rolling back ${DEPLOYMENT} in ${NAMESPACE}"

if [[ -n "${REVISION}" ]]; then
  kubectl rollout undo deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --to-revision="${REVISION}"
else
  kubectl rollout undo deployment/"${DEPLOYMENT}" -n "${NAMESPACE}"
fi

kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=60s
echo "==> Rollback complete"
