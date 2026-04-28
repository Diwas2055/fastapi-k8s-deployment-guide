# Production Readiness Checklist

## Pre-Deployment

### Image
- [ ] Built from a specific, pinned base image digest
- [ ] Multi-stage build (builder ≠ production stage)
- [ ] Non-root user set in Dockerfile
- [ ] Trivy / Grype scan passes with no HIGH/CRITICAL CVEs
- [ ] Image tagged with git SHA or semver (no `:latest`)
- [ ] Image pushed to a private registry with access controls

### Manifests
- [ ] `kubectl diff -k` reviewed and approved in PR
- [ ] `kubectl apply --dry-run=server -k` passes in CI
- [ ] Resource `requests` and `limits` on every container
- [ ] All three health probes configured correctly
- [ ] `maxUnavailable: 0` and at least 2 `replicas`
- [ ] PodDisruptionBudget present
- [ ] Secrets not committed in plain text
- [ ] `automountServiceAccountToken: false` unless needed

### Security
- [ ] `runAsNonRoot: true` and `readOnlyRootFilesystem: true`
- [ ] `capabilities: drop: [ALL]`
- [ ] NetworkPolicy: default-deny + explicit whitelists
- [ ] RBAC: dedicated ServiceAccount with least-privilege Role
- [ ] No hostPath volumes, no `privileged: true`

## Post-Deployment

### Observability
- [ ] Prometheus scraping `/metrics` (ServiceMonitor applied)
- [ ] Alerts configured: error rate, latency p99, OOM, CrashLoopBackOff
- [ ] Grafana dashboard imported
- [ ] Log aggregation set up (Loki, Datadog, CloudWatch)
- [ ] Distributed tracing instrumented (OpenTelemetry)

### Scaling
- [ ] HPA configured with appropriate thresholds
- [ ] `topologySpreadConstraints` across nodes and zones
- [ ] Load test run to validate autoscaling behavior

### Disaster Recovery
- [ ] Rollback procedure documented and tested
- [ ] `kubectl rollout undo` verified to work
- [ ] Deployment history retained (`revisionHistoryLimit: 5`)

## Ongoing Operations

```bash
# Weekly: check for images with new CVEs
trivy image --exit-code 1 --severity HIGH,CRITICAL myapp:1.0.0

# Check cluster health
kubectl get nodes
kubectl top nodes
kubectl get events --sort-by=.lastTimestamp -n fastapi-app

# Review HPA status
kubectl get hpa -n fastapi-app

# Check certificate expiry
kubectl get certificate -n fastapi-app

# Audit RBAC drift
kubectl auth can-i --list --as=system:serviceaccount:fastapi-app:fastapi-app-sa
```
