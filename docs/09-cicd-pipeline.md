# CI/CD Pipeline

This project uses GitHub Actions for a full CI/CD pipeline with automated testing,
image scanning, staging deploy, manual production gate, and auto-rollback on failure.

---

## Pipeline Overview

```
Pull Request
    └── CI (lint → test → build → scan → validate manifests)

Push to main
    └── CI → Deploy to Staging → Smoke Tests → [wait for approval] → Deploy to Production

Push a semver tag (v1.2.3)
    └── CI → Deploy to Staging → Smoke Tests → [manual approval] → Deploy to Production → Notify Slack
```

---

## Workflows

### `.github/workflows/ci.yml` — runs on every push and PR

| Job | What it does |
|-----|-------------|
| `lint` | ruff (linting + format check) + mypy type check |
| `test` | pytest with coverage, uploads to Codecov |
| `build` | Multi-stage Docker build, pushes to GHCR on `main` |
| `scan` | Trivy image scan — fails on HIGH/CRITICAL CVEs, uploads SARIF to Security tab |
| `validate-manifests` | kubeconform validates kustomize output against K8s 1.30 schema, helm lint |

### `.github/workflows/deploy.yml` — runs on push to `main` or semver tag

| Job | Trigger | What it does |
|-----|---------|-------------|
| `deploy-staging` | push to `main` | Apply staging overlay, wait for rollout, run smoke tests |
| `deploy-production` | semver tag or manual approval | Diff, apply prod overlay, rollout, smoke tests, auto-rollback on failure |

---

## GitHub Secrets Required

Set these in **Repository → Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `KUBE_CONFIG_STAGING` | base64-encoded kubeconfig for the staging cluster |
| `KUBE_CONFIG_PRODUCTION` | base64-encoded kubeconfig for the production cluster |
| `STAGING_URL` | Base URL for staging smoke tests (e.g. `https://staging-api.yourdomain.com`) |
| `PRODUCTION_URL` | Base URL for prod smoke tests |
| `SLACK_WEBHOOK_URL` | Incoming webhook for deploy notifications |

### Encoding a kubeconfig
```bash
cat ~/.kube/config | base64 -w 0
# Paste the output into the GitHub secret
```

---

## GitHub Environments

1. Go to **Repository → Settings → Environments**
2. Create **staging** (no protection rules — auto-deploy on every merge to `main`)
3. Create **production** with:
   - **Required reviewers**: add your team lead or yourself
   - **Wait timer**: 0 minutes (optional buffer)
   - This creates a manual approval gate between staging and production

---

## Image Registry (GHCR)

Images are pushed to GitHub Container Registry automatically on merge to `main`:

```
ghcr.io/<org>/fastapi-k8s-demo:<sha>     # e.g. ghcr.io/acme/fastapi-k8s-demo:a1b2c3d4
ghcr.io/<org>/fastapi-k8s-demo:latest
```

Pull the image:
```bash
docker pull ghcr.io/<org>/fastapi-k8s-demo:a1b2c3d4
```

---

## Release Process

```bash
# 1. Merge feature branch into main — triggers staging deploy automatically

# 2. Verify staging
curl https://staging-api.yourdomain.com/healthz/ready

# 3. Tag a release to trigger production deploy
git tag v1.2.0
git push origin v1.2.0

# 4. Approve the "Deploy → Production" job in GitHub Actions

# 5. Pipeline runs smoke tests post-deploy
#    On failure: auto-rolls back to the previous revision
```

---

## Auto-Rollback Logic

The production deploy job saves the current revision before applying:

```yaml
- name: Record current revision
  id: revision
  run: |
    REV=$(kubectl rollout history deployment/fastapi-app -n fastapi-app \
            --no-headers | tail -1 | awk '{print $1}')
    echo "REVISION=${REV}" >> $GITHUB_OUTPUT
```

If smoke tests fail after deploy, the pipeline rolls back automatically:

```yaml
- name: Auto-rollback on smoke failure
  if: failure()
  run: |
    kubectl rollout undo deployment/fastapi-app \
      --to-revision=${{ steps.revision.outputs.REVISION }} -n fastapi-app
```

---

## Running CI Locally

Use `act` to run GitHub Actions workflows on your machine before pushing:

```bash
# Install act
brew install act   # or download from https://github.com/nektos/act

# Run the CI workflow
act push

# Run only the test job
act push --job test

# Run with secrets
act push --secret-file .env.secrets
```

---

## Adding a New Secret

```bash
# Add via GitHub CLI
gh secret set MY_SECRET --body "secret-value" --repo your-org/fastapi-k8s-deployment-guide

# List existing secrets
gh secret list --repo your-org/fastapi-k8s-deployment-guide
```

---

## Caching

The CI workflow uses GitHub Actions cache for:
- **pip packages** (`actions/setup-python` built-in cache)
- **Docker layers** (`cache-from: type=gha` in `docker/build-push-action`)

This reduces build times from ~3 minutes to ~45 seconds after the first run.

---

## Common CI Failures and Fixes

### Trivy scan fails (HIGH/CRITICAL CVE)
```bash
# Check locally what Trivy found
trivy image fastapi-k8s-demo:local

# Update base image in Dockerfile to get patched packages
FROM python:3.12-slim   # bump the tag to latest patch version

# Or suppress a known false-positive
echo "CVE-2023-12345" >> .trivyignore
```

### mypy type errors
```bash
mypy app/   # run locally first
# Add type: ignore[...] only when the error is a known mypy limitation
```

### kubeconform fails on CRD (e.g. ServiceMonitor)
```bash
# Kubeconform doesn't know about CRDs by default — skip them
kubectl kustomize k8s/overlays/production \
  | kubeconform -strict -skip ServiceMonitor,SealedSecret -summary
```

### pytest flaky test in CI
```bash
# Pin asyncio mode explicitly in pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```
