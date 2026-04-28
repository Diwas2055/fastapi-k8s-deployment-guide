# FastAPI Kubernetes Deployment Guide

A production-grade reference project for deploying FastAPI applications on Kubernetes.
Covers everything from local setup through advanced topics — autoscaling, secret management,
network policies, observability, and GitOps — with a dedicated section on mistakes senior
developers have seen (and fixed) in real production clusters.

---

## Project Structure

```
fastapi-k8s-deployment-guide/
├── app/                          # FastAPI application
│   ├── main.py                   # App factory, lifespan, middleware wiring
│   ├── config.py                 # Settings via pydantic-settings + Downward API
│   ├── middleware/
│   │   └── logging.py            # Structured JSON request logging (structlog)
│   ├── models/
│   │   └── item.py               # Pydantic v2 models
│   ├── routers/
│   │   ├── health.py             # /healthz/startup, /live, /ready  (3 probes)
│   │   ├── items.py              # CRUD API
│   │   └── metrics.py            # Prometheus /metrics endpoint
│   └── utils/
│       ├── db.py                 # DB client + init/close helpers
│       └── logger.py             # structlog configuration
│
├── k8s/
│   ├── base/                     # Base Kustomize manifests (shared across all envs)
│   │   ├── deployment.yaml       # Zero-downtime rolling update, probes, security ctx
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml           # Placeholder — replace with Sealed Secrets in prod
│   │   ├── serviceaccount.yaml
│   │   └── kustomization.yaml
│   ├── overlays/
│   │   ├── development/          # 1 replica, debug=true, reduced resources
│   │   ├── staging/              # 2 replicas, production-like config
│   │   └── production/           # 3 replicas, HPA, PDB, pinned image tag
│   ├── advanced/
│   │   ├── ingress.yaml          # nginx + cert-manager TLS + rate limiting
│   │   ├── rbac.yaml             # Least-privilege Role + RoleBinding
│   │   ├── network-policy.yaml   # Default-deny + explicit ingress/egress allows
│   │   ├── resource-quota.yaml   # Namespace-level resource caps
│   │   ├── limit-range.yaml      # Per-container/pod default limits
│   │   ├── sealed-secret.yaml    # Sealed Secrets example (safe to commit)
│   │   ├── external-secret.yaml  # External Secrets Operator (AWS/GCP/Vault)
│   │   ├── argocd-app.yaml       # GitOps Application manifest for ArgoCD
│   │   └── monitoring/
│   │       └── servicemonitor.yaml
│   └── helm/fastapi-app/         # Full Helm chart (alternative to Kustomize)
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/            # deployment, service, ingress, hpa, pdb,
│                                 # networkpolicy, servicemonitor, secret, sa
│
├── .github/
│   └── workflows/
│       ├── ci.yml                # lint → test → build → scan → validate
│       └── deploy.yml            # staging auto-deploy → manual gate → production
│
├── docs/
│   ├── 01-getting-started.md     # All 5 local cluster tools
│   ├── 02-docker-basics.md
│   ├── 03-k8s-core-concepts.md
│   ├── 04-deploying-fastapi.md
│   ├── 05-advanced-k8s.md
│   ├── 06-common-mistakes.md     ← Read this first if you're debugging
│   ├── 07-production-checklist.md
│   ├── 08-minikube-guide.md      # Full minikube reference
│   └── 09-cicd-pipeline.md       # GitHub Actions CI/CD walkthrough
│
├── scripts/
│   ├── setup-local.sh            # First-time local cluster bootstrap (kind|k3d|minikube)
│   ├── build.sh                  # Multi-arch image build + push
│   ├── deploy.sh                 # kustomize apply + dry-run gate + rollout wait
│   ├── rollback.sh               # kubectl rollout undo (with optional revision)
│   ├── smoke-test.sh             # Post-deploy smoke tests against any BASE_URL
│   ├── port-forward.sh           # Forward API + Prometheus + Grafana ports
│   └── prometheus.yml            # Local Prometheus scrape config
│
├── tests/
│   ├── conftest.py               # Shared fixtures (DB init, async client)
│   ├── test_health.py            # Probe endpoint tests
│   ├── test_items.py             # CRUD lifecycle + validation tests
│   └── test_metrics.py           # Prometheus endpoint test
│
├── Makefile                      # All common commands (make help)
├── Dockerfile                    # Multi-stage, non-root, read-only FS
├── docker-compose.yml            # Local dev + Prometheus sidecar
├── pyproject.toml                # pytest, ruff, mypy config
├── requirements.txt              # Runtime dependencies
└── requirements-dev.txt          # Runtime + test + lint dependencies
```

---

## Tutorial Path

Follow the docs in order for a complete walkthrough:

| Step | Doc | Topics |
|------|-----|--------|
| 1 | [Getting Started](docs/01-getting-started.md) | Local run, all 5 cluster tools, env vars |
| 2 | [Docker Basics](docs/02-docker-basics.md) | Multi-stage builds, security, tagging, scanning |
| 3 | [K8s Core Concepts](docs/03-k8s-core-concepts.md) | Pods, Deployments, Services, probes, rolling updates, StatefulSets, Jobs |
| 4 | [Deploying FastAPI](docs/04-deploying-fastapi.md) | Health probes, graceful shutdown, canary, Downward API, ResourceQuota |
| 5 | [Advanced K8s](docs/05-advanced-k8s.md) | HPA, PDB, Network Policy, RBAC, Secrets, GitOps, Helm |
| 6 | [Common Mistakes](docs/06-common-mistakes.md) | 12 real-world mistakes + senior-level fixes |
| 7 | [Production Checklist](docs/07-production-checklist.md) | Ship-readiness gates |
| 8 | [Minikube Guide](docs/08-minikube-guide.md) | Full minikube reference — drivers, addons, networking, profiles, debug |
| 9 | [CI/CD Pipeline](docs/09-cicd-pipeline.md) | GitHub Actions, image registry, auto-rollback, release process |

---

## Quick Start

```bash
# Local (Docker Compose — no K8s needed)
cp .env.example .env
docker compose up --build
curl http://localhost:8000/healthz/ready

# Local Kubernetes — pick one:
#   kind   (CI-friendly, loads images directly)
kind create cluster --name fastapi-demo
kind load docker-image fastapi-k8s-demo:local --name fastapi-demo

#   k3d    (fastest startup, built-in LoadBalancer + local registry)
k3d cluster create fastapi-demo --registry-create fastapi-registry:5000

#   minikube  (built-in dashboard, best for learning)
minikube start --driver=docker
eval $(minikube docker-env) && docker build -t fastapi-k8s-demo:local .

#   Docker Desktop — enable Kubernetes in Settings, then:
kubectl config use-context docker-desktop

# Deploy dev overlay (same for all cluster tools)
kubectl apply -k k8s/overlays/development
kubectl port-forward svc/dev-fastapi-svc 8080:80 -n fastapi-app
curl http://localhost:8080/healthz/ready

# Or deploy via Helm
helm install fastapi-app k8s/helm/fastapi-app \
  --namespace fastapi-app --create-namespace \
  --set image.tag=local --set env.DEBUG=true

# Run tests
pip install -r requirements.txt pytest pytest-asyncio httpx
pytest tests/ -v
```

---

## Key Design Decisions

### Health Probes — 3 separate endpoints

`/healthz/startup` → buys time for slow init (DB migrations, cache warm-up)
`/healthz/live`    → lightweight process check; failure = restart
`/healthz/ready`   → full dependency check; failure = no traffic, pod stays alive

This prevents crash-loop restarts caused by transient DB unavailability.

### Zero-Downtime Rolling Updates

```yaml
replicas: 2
strategy:
  rollingUpdate:
    maxUnavailable: 0   # never kill until replacement is ready
    maxSurge: 1
```

### Secret Management

Plain K8s Secrets are base64 (not encrypted). This repo uses placeholder Secrets
with a comment pointing to Sealed Secrets / External Secrets Operator for production.
See [Advanced K8s](docs/05-advanced-k8s.md#secret-management-production).

### Observability

Every request logs a structured JSON line with method, path, status, duration, and host.
Prometheus metrics are scraped automatically via the ServiceMonitor.

---

## Deployment Commands

```bash
# First-time setup (picks kind, k3d, or minikube)
make setup-local TOOL=k3d

# Build image
make build TAG=1.2.0

# Deploy to environment
make deploy ENV=staging
make deploy ENV=production

# Preview changes before applying
make diff ENV=production

# Emergency rollback
make rollback

# Run smoke tests
make smoke BASE_URL=https://api.yourdomain.com

# See all available commands
make help
```

---

## Common Mistakes Summary

Full details in [docs/06-common-mistakes.md](docs/06-common-mistakes.md).

| # | Mistake | One-Line Fix |
|---|---------|-------------|
| 1 | `:latest` image tag | Use semver or git SHA |
| 2 | No resource requests/limits | Set both on every container |
| 3 | Liveness probe hitting DB | Separate live vs ready probe paths |
| 4 | Secrets in ConfigMaps | Use Sealed Secrets / ESO |
| 5 | `maxUnavailable: 1` with 1 replica | Set to 0, use 2+ replicas |
| 6 | No PodDisruptionBudget | Add `minAvailable: 1` |
| 7 | Default ServiceAccount | Dedicated SA + `automountServiceAccountToken: false` |
| 8 | Ignoring terminationGracePeriod | Tune to actual drain time |
| 9 | Unpinned Helm chart versions | Always `--version` in Helm install |
| 10 | No NetworkPolicy | Default-deny + explicit allows |
| 11 | Running as root | `runAsNonRoot: true` + `USER` in Dockerfile |
| 12 | Blind `kubectl apply` | Always `kubectl diff` first |
