# Kubernetes Core Concepts

## The Control Plane

```
┌─────────────────────── Control Plane ───────────────────────────┐
│  API Server      ← all kubectl / client requests land here      │
│  etcd            ← distributed KV store for all cluster state   │
│  Scheduler       ← assigns Pods to Nodes based on resources     │
│  Controller Mgr  ← reconciliation loops (Deployment, ReplicaSet)│
│  Cloud Controller← syncs K8s resources with cloud provider APIs │
└──────────────────────────────────────────────────────────────────┘
                   ↓ kubelet watches API server
┌─────────────── Worker Nodes ────────────────────────────────────┐
│  kubelet         ← ensures containers match desired pod spec     │
│  kube-proxy      ← maintains iptables/IPVS rules for Services   │
│  Container Runtime (containerd / CRI-O)                         │
└──────────────────────────────────────────────────────────────────┘
```

Everything in K8s is a reconciliation loop:
**Desired state** (what you write in YAML) vs **Actual state** (what's running).
Controllers continuously close the gap between the two.

---

## Core Resources

### Pod
The smallest deployable unit. Wraps one or more containers that share the same:
- Network namespace (same IP, same ports)
- Storage volumes

> Rule: You almost never create a Pod directly. Use a Deployment.
> Bare pods are not restarted on failure and cannot be rolled back.

### ReplicaSet
Ensures N copies of a Pod template are always running.
Created automatically by a Deployment — you rarely interact with it directly.

### Deployment
Declares desired state: which image, how many replicas, update strategy.
Owns a ReplicaSet. On every change it creates a new ReplicaSet and gradually migrates traffic.

```
Deployment
  └── ReplicaSet (v2, current)
        ├── Pod
        └── Pod
  └── ReplicaSet (v1, scaled to 0 — kept for rollback)
```

```bash
# Check rollout history (kept via revisionHistoryLimit)
kubectl rollout history deployment/fastapi-app -n fastapi-app

# Roll back to the previous revision
kubectl rollout undo deployment/fastapi-app -n fastapi-app

# Roll back to a specific revision
kubectl rollout undo deployment/fastapi-app --to-revision=3 -n fastapi-app
```

### Service
A stable virtual IP (ClusterIP) and DNS name that load-balances across matching Pods.
Pods come and go; the Service IP never changes.

```
Client → Service (ClusterIP: 10.96.0.10, DNS: fastapi-svc.fastapi-app.svc.cluster.local)
              ├── Pod-1  (10.244.0.5)
              ├── Pod-2  (10.244.0.6)
              └── Pod-3  (10.244.1.2)
```

#### Service Types

| Type | Description | When to Use |
|------|-------------|-------------|
| `ClusterIP` | Internal IP only (default) | Internal service-to-service calls |
| `NodePort` | Exposes a port on every node's IP | Quick local testing |
| `LoadBalancer` | Provisions a cloud LB | Production external access |
| `ExternalName` | DNS CNAME alias | Route to external service by hostname |

```yaml
# ClusterIP (default) — only reachable inside the cluster
spec:
  type: ClusterIP
  ports:
    - port: 80           # port the Service listens on
      targetPort: 8000   # port on the Pod container
```

### Ingress
HTTP/HTTPS routing rules that sit in front of Services.
Requires an Ingress Controller (nginx, Traefik, AWS ALB) to be installed.

```
Internet → LoadBalancer → IngressController (nginx)
                               ├── /api  → fastapi-svc:80
                               └── /web  → frontend-svc:80
```

### ConfigMap
Non-sensitive configuration injected as environment variables or mounted as files.

```bash
kubectl create configmap my-config --from-file=config.yaml
kubectl get configmap my-config -o yaml
```

### Secret
Base64-encoded sensitive data. **Not encrypted at rest by default** — enable etcd
encryption or use Sealed Secrets / External Secrets Operator in production.

```bash
kubectl create secret generic my-secret --from-literal=password=s3cr3t
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d
```

### Namespace
Logical isolation within a cluster. Scopes names, RBAC, and ResourceQuotas.

```bash
kubectl get pods -n fastapi-app          # scoped to namespace
kubectl get pods --all-namespaces        # across all namespaces
kubectl config set-context --current --namespace=fastapi-app  # set default ns
```

### PersistentVolume (PV) and PersistentVolumeClaim (PVC)

```
PVC (what you request)  →  StorageClass (how to provision)  →  PV (the actual disk)
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
  storageClassName: standard
```

---

## Labels & Selectors — The Glue

Everything in K8s is connected via labels. A Service finds its Pods through label selectors:

```yaml
# Pod has label
metadata:
  labels:
    app.kubernetes.io/name: fastapi-app
    version: "1.0.0"

# Service selects pods with that label
spec:
  selector:
    app.kubernetes.io/name: fastapi-app    # matches pods
```

**Recommended label schema** (`app.kubernetes.io/*`):

| Label | Example | Purpose |
|-------|---------|---------|
| `app.kubernetes.io/name` | `fastapi-app` | App name |
| `app.kubernetes.io/version` | `1.0.0` | Current version |
| `app.kubernetes.io/component` | `api` | Role within the app |
| `app.kubernetes.io/part-of` | `fastapi-k8s-demo` | Higher-level app |
| `app.kubernetes.io/managed-by` | `helm` | Tool that manages this |

---

## Health Probes

| Probe | When It Runs | Failure Action |
|-------|-------------|----------------|
| `startupProbe` | Only during startup | Restart container |
| `livenessProbe` | Continuously after startup | Restart container |
| `readinessProbe` | Continuously | Remove from Service endpoints (no restart) |

**The most important distinction**:
- `livenessProbe` failure = **restart the pod** (destructive)
- `readinessProbe` failure = **stop sending traffic** (the pod stays alive to recover)

```yaml
startupProbe:               # 30 × 2s = up to 60s to start
  httpGet: {path: /healthz/startup, port: http}
  failureThreshold: 30
  periodSeconds: 2

livenessProbe:              # is the process alive?
  httpGet: {path: /healthz/live, port: http}
  periodSeconds: 10
  failureThreshold: 3       # 3 failures = restart

readinessProbe:             # is the app ready for traffic?
  httpGet: {path: /healthz/ready, port: http}
  periodSeconds: 5
  failureThreshold: 3       # 3 failures = removed from LB
```

Probe types:
- `httpGet` — most common; checks HTTP status code (2xx/3xx = success)
- `tcpSocket` — checks if a port is open (good for non-HTTP services)
- `exec` — runs a command inside the container; exit 0 = success
- `grpc` — for gRPC services implementing the health protocol

---

## Rolling Update Mechanics

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0   # never reduce below desired replica count
    maxSurge: 1         # allow 1 extra pod during rollout
```

With `replicas: 2`, `maxUnavailable: 0`, `maxSurge: 1`:

```
Step 1: [old-1] [old-2]               ← start
Step 2: [old-1] [old-2] [new-1]       ← surge pod starts
Step 3: [old-2] [new-1]               ← old-1 terminated after new-1 is ready
Step 4: [new-1] [new-2]               ← done
```

Rollout waits for `readinessProbe` to pass before terminating old pods.

---

## Resource Requests and Limits

```yaml
resources:
  requests:            # Scheduler uses this to find a node with enough capacity
    cpu: "100m"        # 100 millicores = 0.1 CPU
    memory: "128Mi"
  limits:              # Container is throttled (CPU) or killed (memory) if exceeded
    cpu: "500m"
    memory: "256Mi"
```

| Behaviour | CPU | Memory |
|-----------|-----|--------|
| Exceeds limit | Throttled (slowed down) | OOMKilled (restarted) |
| No request set | Scheduler blind | Scheduler blind |
| No limit set | Can starve neighbors | Can crash the node |

**Always set both.** Start conservative, then tune with `kubectl top pods`.

---

## kustomize Basics

Kustomize lets you manage multiple environments from a single base without templating:

```
k8s/
├── base/          ← shared manifests (Deployment, Service, ConfigMap)
└── overlays/
    ├── development/   ← 1 replica, debug=true, smaller resources
    └── production/    ← 3 replicas, HPA, PDB, pinned image tag
```

```bash
# Preview rendered output (no apply)
kubectl kustomize k8s/overlays/production

# Diff against what's live (see what will change)
kubectl diff -k k8s/overlays/production

# Apply an overlay
kubectl apply -k k8s/overlays/production
```

---

## StatefulSets vs Deployments

| Feature | Deployment | StatefulSet |
|---------|-----------|-------------|
| Pod identity | Random names (fastapi-abc12) | Stable names (db-0, db-1) |
| Storage | Shared or ephemeral | Dedicated PVC per pod |
| Startup order | Parallel | Sequential (db-0 before db-1) |
| Use case | Stateless APIs | Databases, queues, distributed systems |

Use **Deployment** for FastAPI. Use **StatefulSet** for PostgreSQL, Redis, Kafka.

---

## DaemonSet

Runs one pod on every node. Used for cluster-wide agents:
- Log shippers (Fluentd, Filebeat)
- Node monitoring (Prometheus Node Exporter)
- Security agents (Falco)

---

## Jobs and CronJobs

```yaml
# Job — runs once to completion (DB migration, batch processing)
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: fastapi-k8s-demo:1.0.0
          command: ["python", "-m", "alembic", "upgrade", "head"]
      restartPolicy: OnFailure
---
# CronJob — runs on a schedule
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup-job
spec:
  schedule: "0 2 * * *"   # 2am daily (standard cron syntax)
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: cleanup
              image: fastapi-k8s-demo:1.0.0
              command: ["python", "scripts/cleanup.py"]
          restartPolicy: OnFailure
```
