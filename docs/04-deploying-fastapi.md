# Deploying FastAPI on Kubernetes

## Application Architecture

```
Internet
   │
   ▼
Ingress (nginx)           ← TLS termination, rate limiting, routing
   │
   ▼
Service (ClusterIP)       ← stable DNS: fastapi-svc.fastapi-app.svc.cluster.local
   │
   ├─ Pod (fastapi:1.0.0) ← uvicorn, non-root, read-only FS
   ├─ Pod (fastapi:1.0.0)
   └─ Pod (fastapi:1.0.0)
```

---

## Health Probe Design

FastAPI must implement three distinct endpoints for different K8s concerns:

```
GET /healthz/startup   → called until 200; then K8s hands off to liveness
GET /healthz/live      → lightweight "is the process alive?" check
GET /healthz/ready     → full "is the app ready to serve traffic?" check
```

### Why three endpoints?

**Scenario**: your app takes 30s to connect to the database on startup.

- **Bad**: single `/health` endpoint used for liveness — K8s restarts the pod before it
  finishes starting → CrashLoopBackOff.
- **Bad**: liveness checks the DB — transient DB blip restarts all your pods → outage.
- **Good**: startup probe gives the app 60s to init; liveness checks only the process;
  readiness checks DB — failure means "stop sending traffic" not "restart the pod".

```python
# app/routers/health.py

@router.get("/healthz/startup")
async def startup():
    # Called once. Return 200 as soon as the app has finished initializing.
    # Perform DB connection, cache warm-up, etc. here if needed.
    return {"status": "started"}

@router.get("/healthz/live")
async def liveness():
    # Must be fast and cheap. Never check external dependencies here.
    # If this fails, K8s restarts the container.
    return {"status": "alive"}

@router.get("/healthz/ready")
async def readiness():
    # Check that the app can serve real traffic: DB reachable, cache warm, etc.
    # If this fails, K8s removes the pod from the load balancer (no restart).
    try:
        await db.execute("SELECT 1")
    except Exception:
        raise HTTPException(503, "Database not ready")
    return {"status": "ready"}
```

Corresponding K8s configuration:
```yaml
startupProbe:
  httpGet: {path: /healthz/startup, port: http}
  failureThreshold: 30    # 30 × 2s = 60 seconds for the app to start
  periodSeconds: 2

livenessProbe:
  httpGet: {path: /healthz/live, port: http}
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3

readinessProbe:
  httpGet: {path: /healthz/ready, port: http}
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

---

## Graceful Shutdown

When K8s wants to terminate a pod it:
1. Removes the pod from the Service endpoints (no new requests)
2. Sends `SIGTERM` to the container
3. Waits `terminationGracePeriodSeconds` (30s here)
4. Sends `SIGKILL` if still running

uvicorn handles `SIGTERM` correctly — it finishes in-flight requests then exits.

```yaml
terminationGracePeriodSeconds: 30
```

Tune this to your p99 request duration plus a buffer. For a REST API serving sub-second
requests, 30s is ample. For long-polling or WebSocket connections, increase accordingly.

**Important**: there is a race condition in K8s. After `SIGTERM` is sent, it takes a few
seconds for the endpoint to be removed from all kube-proxies. Add a pre-stop sleep to handle it:

```yaml
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 5"]
```

This gives kube-proxy 5 seconds to propagate the endpoint removal before uvicorn starts
refusing connections.

---

## Downward API — Pod Self-Awareness

Inject pod metadata as environment variables without any extra permissions:

```yaml
env:
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: POD_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
  - name: NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
  - name: POD_IP
    valueFrom:
      fieldRef:
        fieldPath: status.podIP
```

Use these in your structured logs so you can filter by pod or node in Grafana/Kibana:

```python
import os
logger.info(
    "request_completed",
    pod=os.getenv("POD_NAME"),
    node=os.getenv("NODE_NAME"),
    namespace=os.getenv("POD_NAMESPACE"),
)
```

---

## ConfigMap vs Secret vs Downward API

| Source | Data Type | Encrypted | When to Use |
|--------|-----------|-----------|-------------|
| ConfigMap | Plain text | No | Feature flags, env names, non-sensitive config |
| Secret | Base64 | No (by default) | Passwords, API keys, TLS certs |
| Downward API | Pod metadata | N/A | Pod name, namespace, labels, IP |

Load a full ConfigMap as environment variables:
```yaml
envFrom:
  - configMapRef:
      name: fastapi-config
```

Load specific Secret keys individually (avoids all-or-nothing exposure):
```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: fastapi-secrets
        key: DATABASE_URL
```

---

## Rolling Deployment Step-by-Step

```bash
# 1. Build and tag the new image
TAG=1.2.0
./scripts/build.sh $TAG

# 2. Update the image tag in the production overlay
# Edit k8s/overlays/production/kustomization.yaml:
#   images:
#     - name: fastapi-k8s-demo
#       newTag: "1.2.0"

# 3. Dry-run to preview changes before touching the cluster
kubectl diff -k k8s/overlays/production

# 4. Apply — K8s starts the rolling update automatically
kubectl apply -k k8s/overlays/production

# 5. Watch the rollout in real time
kubectl rollout status deployment/fastapi-app -n fastapi-app --timeout=120s

# 6. Verify new pods are healthy
kubectl get pods -n fastapi-app -l app.kubernetes.io/name=fastapi-app

# 7. If anything is wrong — instant rollback
kubectl rollout undo deployment/fastapi-app -n fastapi-app
# Or use the rollback script
./scripts/rollback.sh
```

---

## Canary Deployments (Manual)

Run two Deployment objects side by side to send a percentage of traffic to the new version:

```bash
# 90% traffic to v1 (9 pods), 10% to v2 (1 pod)
kubectl scale deployment fastapi-app-v1 --replicas=9 -n fastapi-app
kubectl scale deployment fastapi-app-v2 --replicas=1 -n fastapi-app

# Both Deployments must share the same Service selector label:
#   app.kubernetes.io/name: fastapi-app
# Service distributes traffic proportional to pod count.

# Graduate canary — shift all traffic to v2
kubectl scale deployment fastapi-app-v1 --replicas=0 -n fastapi-app
kubectl scale deployment fastapi-app-v2 --replicas=3 -n fastapi-app
```

For sophisticated canary (by header, cookie, %, A/B) use Argo Rollouts or Flagger.

---

## Useful Debug Commands

```bash
# Stream logs from all app pods simultaneously
kubectl logs -n fastapi-app -l app.kubernetes.io/name=fastapi-app -f --max-log-requests 10

# Describe a pod — shows events, probe results, resource consumption
kubectl describe pod <pod-name> -n fastapi-app

# Open a shell in a running container
kubectl exec -it <pod-name> -n fastapi-app -- /bin/sh

# Check which pods the Service is routing to
kubectl get endpoints fastapi-svc -n fastapi-app

# View live resource usage
kubectl top pods -n fastapi-app
kubectl top nodes

# List recent events (sorted by time)
kubectl get events --sort-by=.lastTimestamp -n fastapi-app

# Check rollout history
kubectl rollout history deployment/fastapi-app -n fastapi-app

# Inspect the full Deployment spec as live in the cluster
kubectl get deployment fastapi-app -n fastapi-app -o yaml
```

---

## Namespace Resource Quota

Prevent the app from consuming more than its fair share of cluster resources:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: fastapi-app-quota
  namespace: fastapi-app
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "20"
    services: "5"
```

```bash
# Check current quota usage
kubectl describe resourcequota fastapi-app-quota -n fastapi-app
```

---

## LimitRange — Per-Pod Defaults

Automatically apply default resource requests/limits for any pod that doesn't set them:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: fastapi-app
spec:
  limits:
    - type: Container
      default:
        cpu: "250m"
        memory: "128Mi"
      defaultRequest:
        cpu: "50m"
        memory: "64Mi"
```

This is a safety net — always set explicit resources in the Deployment spec.
