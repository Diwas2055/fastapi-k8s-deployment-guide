# Common Mistakes & Senior-Level Fixes

This document covers the most frequent mistakes seen in production K8s deployments,
why they happen, and how to fix them permanently.

---

## 1. Using `:latest` Image Tag

**Mistake**
```yaml
image: myapp:latest
imagePullPolicy: IfNotPresent
```

**Why It Breaks**
K8s won't pull a new image if `latest` is already cached on the node.
Two pods on different nodes can run different code with the same tag name.
Rollbacks become impossible — what was "latest" yesterday?

**Fix**
```yaml
image: myapp:1.4.2              # semver or git SHA
imagePullPolicy: IfNotPresent   # safe because tags are now immutable
```

Pin to a digest for maximum immutability:
```yaml
image: myapp@sha256:abc123def456...
```

---

## 2. No Resource Requests or Limits

**Mistake**
```yaml
containers:
  - name: api
    image: myapp:1.0.0
    # no resources block
```

**Why It Breaks**
- Scheduler has no data → places pods randomly → hot nodes get OOM-killed
- One runaway pod can starve all other workloads on the node
- HPA cannot compute utilization without `requests`

**Fix**
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

Start with a guess, then use `kubectl top pods` + VPA recommendations to tune.

---

## 3. Wrong or Missing Health Probes

**Mistake A**: Single probe pointing to a DB-dependent endpoint as liveness.
```yaml
livenessProbe:
  httpGet:
    path: /health    # checks DB connection
```
If DB is temporarily unavailable, K8s enters a restart loop → crash loops → outage.

**Mistake B**: No `startupProbe` on a slow-starting app.
The `livenessProbe` fires before the app is ready → immediate restart loop.

**Fix**
```yaml
startupProbe:              # Gives app 60s to start (30 * 2s)
  httpGet: {path: /healthz/startup, port: http}
  failureThreshold: 30
  periodSeconds: 2

livenessProbe:             # Only checks: "is the process running?"
  httpGet: {path: /healthz/live, port: http}
  periodSeconds: 10

readinessProbe:            # Checks: "is the app ready for traffic?" (may include DB)
  httpGet: {path: /healthz/ready, port: http}
  periodSeconds: 5
```

---

## 4. Secrets in ConfigMaps (or Worse, in the Image)

**Mistake**
```yaml
# configmap.yaml
data:
  DATABASE_URL: "postgresql://admin:password123@db:5432/prod"
```

**Why It Breaks**
ConfigMaps are stored unencrypted in etcd and visible to anyone with `get configmap` permission.
Hardcoded secrets in images are extractable with `docker history`.

**Fix**
- Use K8s `Secret` for sensitive values (at minimum)
- Enable etcd encryption at rest in the cluster
- Use Sealed Secrets, External Secrets Operator, or HashiCorp Vault in production
- Audit access with `kubectl auth can-i --list`

---

## 5. `maxUnavailable: 1` with Only 1 Replica

**Mistake**
```yaml
replicas: 1
strategy:
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 0
```

**Why It Breaks**
During a rolling update, K8s terminates the single running pod before starting a new one.
Result: guaranteed downtime on every deploy.

**Fix**
For zero-downtime deploys:
```yaml
replicas: 2             # Minimum 2 for rolling zero-downtime
strategy:
  rollingUpdate:
    maxUnavailable: 0   # Never take a pod down before a new one is ready
    maxSurge: 1         # Allow 1 extra pod during rollout
```

---

## 6. No PodDisruptionBudget

**Mistake**
No PDB defined.

**Why It Breaks**
During node maintenance (`kubectl drain`), all pods are evicted simultaneously.
Users see a full outage even though the cluster is healthy.

**Fix**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: fastapi-app
```

---

## 7. Default ServiceAccount with Broad Permissions

**Mistake**
Not specifying a ServiceAccount. The `default` SA in many clusters has RBAC bound to it by Helm charts or operators, granting unexpected permissions.

**Fix**
```yaml
# Deployment
serviceAccountName: fastapi-app-sa

# ServiceAccount
automountServiceAccountToken: false   # Opt-in, not opt-out
```

Then grant only what the app actually uses:
```bash
kubectl auth can-i --list --as=system:serviceaccount:fastapi-app:fastapi-app-sa
```

---

## 8. Ignoring terminationGracePeriodSeconds

**Mistake**
Default `terminationGracePeriodSeconds: 30` with uvicorn handling thousands of long-polling WebSocket connections.

**Why It Breaks**
K8s sends SIGTERM → waits 30s → sends SIGKILL.
If 30s isn't enough to drain connections, clients get hard-disconnected.

**Fix**
Align the grace period with your p99 request duration + buffer:
```yaml
terminationGracePeriodSeconds: 60   # for apps with long connections
```

And ensure the framework drains properly:
```bash
# uvicorn: handles SIGTERM gracefully by default
# gunicorn: needs --graceful-timeout matching the K8s grace period
```

---

## 9. Not Pinning Kustomize/Helm Chart Versions

**Mistake**
```bash
helm install prometheus prometheus-community/kube-prometheus-stack
# No --version flag
```

**Why It Breaks**
A `helm repo update` + re-install next month pulls a new major version.
Breaking API changes in CRDs can corrupt existing CustomResources.

**Fix**
```bash
helm install prometheus prometheus-community/kube-prometheus-stack --version 65.1.1
```

Pin everything: Helm chart versions, image tags, base image digests.

---

## 10. No Network Policy (Open Pod-to-Pod Communication)

**Mistake**
Default K8s networking: any pod in any namespace can call any other pod.
A compromised pod can reach your database, internal APIs, or metadata endpoint.

**Fix**
Apply a default-deny policy and explicitly whitelist traffic.
See `k8s/advanced/network-policy.yaml` for a working example.

Test your policies:
```bash
# Confirm the DB is unreachable from a random pod
kubectl run test-pod --image=busybox --rm -it --restart=Never -- \
  wget -T3 postgres-svc.fastapi-app.svc.cluster.local:5432
# Should timeout / be refused
```

---

## 11. Running as Root Inside Containers

**Mistake**
Not setting a `USER` in the Dockerfile or `runAsNonRoot` in the pod spec.

**Why It Breaks**
If an attacker escapes the container (e.g., via a kernel vulnerability), they land as
root on the host.

**Fix**
Dockerfile:
```dockerfile
RUN useradd --uid 1001 --gid 1001 appuser
USER appuser
```

Pod spec:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: true
```

---

## 12. Not Using `kubectl diff` Before Apply

**Mistake**
```bash
kubectl apply -k k8s/overlays/production   # blindly applying
```

**Fix**
Always diff first to understand exactly what will change:
```bash
kubectl diff -k k8s/overlays/production
```

In CI, fail the pipeline if there are unexpected diffs.

---

## Senior-Level Production Checklist

- [ ] All images tagged with immutable tags (no `:latest`)
- [ ] Resources `requests` and `limits` set on every container
- [ ] All three probes configured (`startup`, `liveness`, `readiness`)
- [ ] `maxUnavailable: 0` with at least 2 replicas
- [ ] PodDisruptionBudget created
- [ ] Secrets managed via Sealed Secrets or ESO (not plain Secret in Git)
- [ ] Network policies: default-deny + explicit allows
- [ ] Non-root user, read-only root filesystem, `capabilities: drop: ALL`
- [ ] HPA with CPU/memory metrics
- [ ] `topologySpreadConstraints` for multi-node/zone HA
- [ ] Prometheus metrics exposed and ServiceMonitor applied
- [ ] Structured JSON logging with pod/node metadata
- [ ] `terminationGracePeriodSeconds` tuned to actual drain time
- [ ] GitOps (ArgoCD/Flux) — no manual `kubectl apply` in production
- [ ] Image vulnerability scanning in CI (Trivy, Grype)
- [ ] `kubectl diff` gated in CI before any apply
