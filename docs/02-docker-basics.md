# Docker Basics for K8s Deployments

## Why Multi-Stage Builds

A single-stage Dockerfile copies build tools (gcc, pip cache) into the final image,
bloating it from ~100 MB to 600+ MB and increasing the attack surface.

Multi-stage solves this:

```
Stage 1 (builder)  →  installs deps with build tools
Stage 2 (prod)     →  copies only the compiled artifacts
```

Our Dockerfile achieves a final image of ~120 MB vs ~550 MB single-stage.

## Image Tagging Strategy

```bash
# BAD: :latest is ambiguous — K8s can't tell if the image changed
docker build -t myapp:latest .
kubectl set image deployment/myapp myapp=myapp:latest   # will NOT re-pull if tag exists

# GOOD: use immutable tags (git SHA, semver)
TAG=$(git rev-parse --short HEAD)
docker build -t myapp:${TAG} .
```

## Layer Caching — Order Matters

```dockerfile
# BAD: copying source before requirements busts cache on every code change
COPY . .
RUN pip install -r requirements.txt

# GOOD: dependencies change less often than source
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app/ ./app/
```

## Security in Images

1. **Non-root user** — Add `RUN useradd` and switch with `USER`. Linux containers default
   to root inside the container, which maps to root on the host if the runtime is misconfigured.

2. **Read-only filesystem** — Set `readOnlyRootFilesystem: true` in the K8s securityContext
   and mount `emptyDir` only where writes are needed (`/tmp`).

3. **Minimal base image** — `python:3.12-slim` vs `python:3.12` saves ~700 MB.
   For production consider `gcr.io/distroless/python3` (no shell = smaller attack surface).

4. **Pin base image digest** — Tags are mutable; digests are not:
   ```dockerfile
   FROM python:3.12-slim@sha256:abc123...
   ```

## Scanning Images

```bash
# Trivy — free, fast vulnerability scanner
trivy image fastapi-k8s-demo:1.0.0

# Integrate into CI (fail on HIGH/CRITICAL)
trivy image --exit-code 1 --severity HIGH,CRITICAL fastapi-k8s-demo:1.0.0
```
