# Advanced Kubernetes

## Horizontal Pod Autoscaler (HPA)

HPA watches metrics and scales the Deployment between `minReplicas` and `maxReplicas`.

```yaml
# k8s/overlays/production/hpa.yaml
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70   # scale when avg CPU > 70%
```

**Requirements**:
- `metrics-server` must be installed in the cluster
- Pods must have `resources.requests` set (HPA can't compute utilization without a baseline)

**Scale-down stabilization** (prevent flapping):
```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300   # don't scale down for 5 min after scale-up
```

## Pod Disruption Budget (PDB)

Guarantees minimum availability during voluntary disruptions (node drains, cluster upgrades):

```yaml
spec:
  minAvailable: 1   # at least 1 pod stays running during drain
```

Without a PDB, a `kubectl drain` could evict all pods simultaneously.

## Topology Spread Constraints

Ensures pods are distributed across failure domains (nodes, zones):

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname   # spread across nodes
    whenUnsatisfiable: DoNotSchedule
```

Combine with zone-level spreading for multi-AZ HA:
```yaml
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway   # soft constraint for zones
```

## Network Policies — Zero-Trust Networking

Default Kubernetes networking allows all pod-to-pod communication.
Apply a `default-deny-all` policy, then explicitly allow what you need:

```bash
kubectl apply -f k8s/advanced/network-policy.yaml
```

This enforces:
1. Only nginx-ingress can reach the API on port 8000
2. The API can only reach postgres on port 5432
3. All other traffic is dropped

## RBAC — Least Privilege

Every pod gets the `default` ServiceAccount with broad permissions by default.
Always:
1. Create a dedicated ServiceAccount per workload
2. Set `automountServiceAccountToken: false` unless the app reads the K8s API
3. Grant only the specific verbs and resources needed

```bash
# Audit what permissions a service account has
kubectl auth can-i --list --as=system:serviceaccount:fastapi-app:fastapi-app-sa -n fastapi-app
```

## Secret Management (Production)

Never store secrets as plain K8s Secrets in Git. Options:

### Option 1: Sealed Secrets (simplest)
```bash
kubeseal --format yaml < k8s/base/secret.yaml > k8s/base/secret-sealed.yaml
# sealed file is safe to commit — only the in-cluster controller can decrypt
```

### Option 2: External Secrets Operator
Syncs secrets from AWS Secrets Manager / GCP Secret Manager / Vault:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: fastapi-secrets
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: fastapi-prod/database
        property: url
```

### Option 3: Vault Agent Sidecar
Vault injects secrets as files at `/vault/secrets/` — never stored in etcd.

## Observability Stack

```bash
# Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

# Apply ServiceMonitor to auto-scrape the FastAPI /metrics endpoint
kubectl apply -f k8s/advanced/monitoring/servicemonitor.yaml
```

Access Grafana:
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# Default credentials: admin / prom-operator
```

## GitOps with ArgoCD

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Create an Application pointing to this repo
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fastapi-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/fastapi-k8s-deployment-guide
    targetRevision: main
    path: k8s/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: fastapi-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

ArgoCD watches the Git repo and automatically applies changes — the cluster state
always mirrors Git state.

## Resource Quotas (Multi-Tenant Clusters)

Prevent one team's namespace from consuming all cluster resources:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: fastapi-app-quota
  namespace: fastapi-app
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    pods: "20"
```

## Helm — Packaging and Distribution

When you need to distribute the app to multiple teams or environments with different values:

```bash
# Package
helm package k8s/helm/fastapi-app

# Install with custom values
helm install fastapi-app k8s/helm/fastapi-app \
  --namespace fastapi-app \
  --create-namespace \
  --set image.tag=1.2.0 \
  --set replicaCount=3

# Upgrade
helm upgrade fastapi-app k8s/helm/fastapi-app --set image.tag=1.3.0

# Rollback
helm rollback fastapi-app 1
```
