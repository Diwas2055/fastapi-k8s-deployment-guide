# Minikube — Complete Guide

Minikube runs a single-node Kubernetes cluster on your local machine.
It is the most beginner-friendly local K8s tool and ships with a rich addon ecosystem
including a built-in dashboard, Ingress controller, and metrics-server.

---

## Installation

### Linux
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

# Verify
minikube version
```

### macOS
```bash
brew install minikube
# or
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-amd64
sudo install minikube-darwin-amd64 /usr/local/bin/minikube
```

### Windows (PowerShell as Admin)
```powershell
winget install Kubernetes.minikube
# or download the .exe installer from https://minikube.sigs.k8s.io/docs/start/
```

---

## Drivers

Minikube supports multiple drivers. Pick based on your OS:

| Driver | OS | Requirement | Notes |
|--------|----|-------------|-------|
| `docker` | Linux / Mac / Win | Docker installed | Recommended — no VM, fastest |
| `virtualbox` | All | VirtualBox installed | Good fallback, cross-platform |
| `kvm2` | Linux | KVM + libvirt | Best performance on Linux |
| `hyperkit` | Mac | macOS only | Legacy — prefer docker |
| `hyper-v` | Windows | Windows Pro/Enterprise | Built into Windows |
| `podman` | Linux | Podman installed | Rootless alternative to docker |
| `none` | Linux (CI) | Bare metal only | Runs K8s directly on host |

```bash
# Check which drivers are available on your machine
minikube start --driver=none --dry-run=true 2>&1 | head -5

# Start with a specific driver
minikube start --driver=docker
minikube start --driver=virtualbox
minikube start --driver=kvm2
```

---

## Starting a Cluster

### Basic start
```bash
minikube start
```

### Recommended start for this project
```bash
minikube start \
  --driver=docker \
  --cpus=2 \
  --memory=4096 \
  --disk-size=20g \
  --kubernetes-version=v1.30.0
```

### With a specific Kubernetes version (useful for testing upgrades)
```bash
minikube start --kubernetes-version=v1.28.0 -p k8s-128
minikube start --kubernetes-version=v1.30.0 -p k8s-130
```

---

## Loading Images into Minikube

### Method 1 — Docker daemon (recommended for dev)
Point your shell at minikube's Docker daemon so images are built directly inside the cluster:
```bash
eval $(minikube docker-env)
docker build -t fastapi-k8s-demo:local .

# To restore your shell's Docker to the host daemon
eval $(minikube docker-env --unset)
```

Set `imagePullPolicy: Never` in your pod spec when using this method — the image already
exists inside the cluster and does not need to be pulled.

### Method 2 — minikube image load
```bash
# Build locally first, then load
docker build -t fastapi-k8s-demo:local .
minikube image load fastapi-k8s-demo:local

# Verify it's inside minikube
minikube image ls | grep fastapi
```

### Method 3 — minikube image build (builds inside the cluster directly)
```bash
minikube image build -t fastapi-k8s-demo:local .
```

### Method 4 — Local registry addon
```bash
minikube addons enable registry

# Push to the in-cluster registry
docker tag fastapi-k8s-demo:local localhost:5000/fastapi-k8s-demo:local
# Forward the registry port first
kubectl port-forward -n kube-system svc/registry 5000:80 &
docker push localhost:5000/fastapi-k8s-demo:local
```

---

## Addons

Addons extend minikube with pre-configured cluster components.

```bash
# List all available addons and their status
minikube addons list

# Enable addons used in this project
minikube addons enable ingress          # nginx Ingress controller
minikube addons enable metrics-server   # required for HPA
minikube addons enable dashboard        # Kubernetes web UI
minikube addons enable registry         # local image registry
minikube addons enable storage-provisioner  # dynamic PVC provisioning

# Disable an addon
minikube addons disable dashboard
```

### Key addons explained

| Addon | What It Does | When to Enable |
|-------|-------------|----------------|
| `ingress` | Deploys nginx Ingress controller | Whenever you test Ingress resources |
| `metrics-server` | Exposes CPU/memory metrics | Required for HPA to work |
| `dashboard` | Web UI for the cluster | Learning / visual inspection |
| `registry` | In-cluster Docker registry on port 5000 | When you want a real push/pull workflow locally |
| `storage-provisioner` | Auto-provisions `hostPath` PVs for PVCs | When your app uses PersistentVolumeClaims |
| `ingress-dns` | Local DNS resolution for `*.test` domains | For Ingress without editing `/etc/hosts` |

---

## Dashboard

```bash
# Opens the dashboard in your default browser automatically
minikube dashboard

# Just get the URL without opening the browser
minikube dashboard --url
```

The dashboard shows all resources, events, logs, and resource usage.
It is read/write — you can scale, edit, and delete resources from it.

---

## Networking

### Port-forward (simplest)
```bash
kubectl port-forward svc/dev-fastapi-svc 8080:80 -n fastapi-app
curl http://localhost:8080/healthz/ready
```

### minikube service (opens browser or prints URL)
```bash
minikube service dev-fastapi-svc -n fastapi-app --url
# prints http://192.168.49.2:31234
```

### minikube tunnel (full LoadBalancer + Ingress support)
Run in a separate terminal. Requires sudo on Linux:
```bash
minikube tunnel
```
After running tunnel, `EXTERNAL-IP` on LoadBalancer services is populated with `127.0.0.1`.

### Ingress with minikube
```bash
# Enable Ingress
minikube addons enable ingress

# Apply the Ingress resource
kubectl apply -f k8s/advanced/ingress.yaml

# Get the minikube IP
minikube ip     # e.g. 192.168.49.2

# Add to /etc/hosts for local DNS
echo "$(minikube ip) api.yourdomain.com" | sudo tee -a /etc/hosts

curl http://api.yourdomain.com/healthz/ready
```

---

## Deploying the FastAPI App

```bash
# 1. Point Docker at minikube and build
eval $(minikube docker-env)
docker build -t fastapi-k8s-demo:local .

# 2. Deploy the development overlay
kubectl apply -k k8s/overlays/development

# 3. Watch rollout
kubectl rollout status deployment/dev-fastapi-app -n fastapi-app

# 4. Access via port-forward
kubectl port-forward svc/dev-fastapi-svc 8080:80 -n fastapi-app

# 5. Or use minikube service shortcut
minikube service dev-fastapi-svc -n fastapi-app --url
```

---

## Profiles — Multiple Clusters

Minikube profiles let you run multiple isolated clusters simultaneously:

```bash
# Create two profiles
minikube start -p dev   --cpus=2 --memory=2048
minikube start -p staging --cpus=4 --memory=4096

# List profiles
minikube profile list

# Switch active profile (also switches kubectl context)
minikube profile dev
kubectl config current-context   # minikube-dev

# Stop a specific profile
minikube stop -p staging

# Delete a profile
minikube delete -p staging

# Delete all profiles
minikube delete --all
```

---

## SSH into the Node

```bash
# Open an SSH session into the minikube VM/container
minikube ssh

# Run a command directly
minikube ssh "docker ps"
minikube ssh "cat /etc/hosts"
```

---

## Useful Debug Commands

```bash
# Show cluster status
minikube status

# Inspect minikube logs (useful when cluster fails to start)
minikube logs
minikube logs --problems   # only show detected problems

# Check resource usage
minikube kubectl -- top pods -n fastapi-app

# Describe a node (see capacity, allocatable resources, conditions)
kubectl describe node minikube

# View all events sorted by time
kubectl get events --sort-by=.lastTimestamp -n fastapi-app

# Follow logs from all app pods
kubectl logs -l app.kubernetes.io/name=fastapi-app -n fastapi-app -f

# Open a shell in a running pod
kubectl exec -it <pod-name> -n fastapi-app -- /bin/sh
```

---

## Pausing and Resuming

Pause freezes the cluster without deleting it — useful to free RAM when not developing:

```bash
minikube pause    # freeze all K8s components, Docker keeps running
minikube unpause  # resume
```

---

## Common Minikube Issues and Fixes

### Issue: `ImagePullBackOff` after building with `eval $(minikube docker-env)`
**Cause**: `imagePullPolicy` is not set to `Never` or `IfNotPresent`.
**Fix**: set `imagePullPolicy: IfNotPresent` in your Deployment and rebuild.

### Issue: Cluster stuck in `NotReady`
```bash
minikube delete && minikube start --driver=docker
# If persists, clear the minikube cache
rm -rf ~/.minikube
```

### Issue: Not enough memory / CPU
```bash
minikube delete
minikube start --cpus=4 --memory=6144
```

### Issue: `minikube tunnel` requires password every time
```bash
# Add to sudoers (Linux) — allows passwordless tunnel
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/ip" | sudo tee /etc/sudoers.d/minikube-tunnel
```

### Issue: Ingress returns 404
```bash
# Verify Ingress controller is running
kubectl get pods -n ingress-nginx

# Verify Ingress resource is admitted
kubectl describe ingress -n fastapi-app

# Check the host in /etc/hosts matches the Ingress host field
cat /etc/hosts | grep yourdomain
```

### Issue: HPA shows `<unknown>` for CPU metrics
**Cause**: metrics-server addon not enabled.
```bash
minikube addons enable metrics-server
kubectl rollout restart deployment/metrics-server -n kube-system
# Wait ~60s then:
kubectl top pods -n fastapi-app
```

---

## Stopping vs Deleting

| Command | Effect | Data Preserved |
|---------|--------|---------------|
| `minikube stop` | Stops the cluster VM/container | Yes — resume with `minikube start` |
| `minikube pause` | Freezes K8s processes | Yes — resume with `minikube unpause` |
| `minikube delete` | Destroys the cluster entirely | No |
| `minikube delete --all` | Destroys all profiles | No |
