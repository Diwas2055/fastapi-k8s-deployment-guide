# Getting Started

## Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Docker | 24+ | Build and run containers locally |
| kubectl | 1.28+ | Interact with Kubernetes clusters |
| kustomize | 5+ | Manage K8s overlays |
| helm | 3.14+ | Install third-party charts |
| One local cluster tool | see below | Run K8s on your machine |

---

## Quick Local Run (Docker Compose — no K8s needed)

```bash
# 1. Clone and enter the project
git clone <repo>
cd fastapi-k8s-deployment-guide

# 2. Copy and populate env file
cp .env.example .env

# 3. Start with Docker Compose
docker compose up --build

# 4. Verify the API is running
curl http://localhost:8000/healthz/ready
# {"status":"ready","environment":"development","version":"1.0.0"}

# 5. Open interactive docs (DEBUG=true in .env)
open http://localhost:8000/docs
```

---

## Local Kubernetes Cluster Options

Choose **one** tool that fits your workflow. They all produce a working local cluster;
the deployment steps after cluster creation are identical.

### Option 1 — kind (Kubernetes IN Docker)

Best for: CI pipelines, lightweight, works everywhere Docker runs.

```bash
# Install
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# Create cluster
kind create cluster --name fastapi-demo

# Load your local image (no registry needed)
kind load docker-image fastapi-k8s-demo:local --name fastapi-demo

# Destroy when done
kind delete cluster --name fastapi-demo
```

Limitation: no built-in LoadBalancer; use port-forward or MetalLB.

---

### Option 2 — k3d (k3s in Docker)

Best for: fastest startup, closest to real clusters, built-in LoadBalancer via k3s.

```bash
# Install
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Create cluster with a local registry sidecar (no image loading step needed)
k3d cluster create fastapi-demo \
  --registry-create fastapi-registry:5000 \
  --port "8080:80@loadbalancer"

# Tag and push image to the local registry
docker tag fastapi-k8s-demo:local localhost:5000/fastapi-k8s-demo:local
docker push localhost:5000/fastapi-k8s-demo:local

# Destroy
k3d cluster delete fastapi-demo
```

k3d is the fastest local option — cluster up in ~10 seconds.

---

### Option 3 — minikube

Best for: learning, single-node, rich built-in dashboard, widest driver choice (Docker, VirtualBox, KVM, Hyper-V, Podman).

> Full minikube guide: [08-minikube-guide.md](08-minikube-guide.md)

```bash
# Install (Linux)
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64

# Install (Mac)
brew install minikube

# Install (Windows)
winget install Kubernetes.minikube

# Start with Docker driver (recommended — no VM overhead)
minikube start --driver=docker --cpus=2 --memory=4096 --disk-size=20g

# Point your Docker CLI at minikube's Docker daemon
# Images built here are immediately available inside the cluster — no push needed
eval $(minikube docker-env)
docker build -t fastapi-k8s-demo:local .

# Enable addons for this project
minikube addons enable ingress          # nginx Ingress controller
minikube addons enable metrics-server   # required by HPA
minikube addons enable dashboard        # Kubernetes web UI

# Open the dashboard in a browser
minikube dashboard

# Deploy and access
kubectl apply -k k8s/overlays/development
kubectl port-forward svc/dev-fastapi-svc 8080:80 -n fastapi-app
# OR use minikube tunnel for LoadBalancer/Ingress
minikube tunnel   # run in a separate terminal; needs sudo on Linux

# Get the cluster IP for Ingress
minikube ip       # e.g. 192.168.49.2

# Profile management — run multiple clusters side by side
minikube start -p staging --cpus=2 --memory=2048
minikube profile list

# Stop (keeps cluster state) vs delete (wipes everything)
minikube stop
minikube delete --all   # removes all profiles
```

---

### Option 4 — Docker Desktop (Mac / Windows)

Best for: zero-install on Mac/Windows — K8s is built into Docker Desktop.

1. Open **Docker Desktop → Settings → Kubernetes → Enable Kubernetes → Apply**
2. Wait ~2 minutes for the cluster to start
3. Switch context: `kubectl config use-context docker-desktop`
4. Build your image normally (`docker build`) — it's already inside the cluster

Limitation: single-node only; no multi-zone testing.

---

### Option 5 — Rancher Desktop (Mac / Linux / Windows)

Best for: open-source Docker Desktop alternative, supports both containerd and dockerd.

```bash
# Download from https://rancherdesktop.io
# After install, enable Kubernetes in the UI

# Switch context
kubectl config use-context rancher-desktop

# Build image (uses nerdctl under the hood)
nerdctl build -t fastapi-k8s-demo:local .
nerdctl -n k8s.io tag fastapi-k8s-demo:local fastapi-k8s-demo:local
```

---

### Comparison Table

| Tool | Startup | Multi-node | Built-in LB | Local registry | Best for |
|------|---------|-----------|-------------|---------------|---------|
| kind | ~30s | Yes | No (use MetalLB) | No (use `kind load`) | CI / pipelines |
| k3d | ~10s | Yes | Yes (k3s) | Yes (sidecar) | Day-to-day dev |
| minikube | ~60s | No | Via tunnel | No (use docker-env) | Learning |
| Docker Desktop | ~2min | No | Via host | No | Mac/Win zero-config |
| Rancher Desktop | ~2min | No | Via host | No | Open-source alternative |

**Recommendation**: use **k3d** for development, **kind** in CI.

---

## Deploy to Your Local Cluster (all tools)

After cluster creation the commands are the same regardless of which tool you used:

```bash
# Build the image
./scripts/build.sh local

# Deploy the development overlay
kubectl apply -k k8s/overlays/development

# Watch pods come up
kubectl get pods -n fastapi-app -w

# Port-forward (if no LoadBalancer)
kubectl port-forward svc/dev-fastapi-svc 8080:80 -n fastapi-app
curl http://localhost:8080/healthz/ready
```

### Via Helm (alternative to Kustomize)

```bash
helm install fastapi-app k8s/helm/fastapi-app \
  --namespace fastapi-app \
  --create-namespace \
  --set image.tag=local \
  --set env.ENVIRONMENT=development \
  --set env.DEBUG=true

# Upgrade after a code change
helm upgrade fastapi-app k8s/helm/fastapi-app --set image.tag=new-tag

# Uninstall
helm uninstall fastapi-app -n fastapi-app
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ENVIRONMENT` | development | Runtime environment tag |
| `DEBUG` | false | Enables /docs and verbose logging |
| `LOG_LEVEL` | INFO | structlog level |
| `DATABASE_URL` | sqlite:///./dev.db | Database connection string |
| `SECRET_KEY` | — | App secret (required in production) |
| `WORKERS` | 1 | uvicorn worker count |
| `ENABLE_METRICS` | true | Expose /metrics endpoint |
