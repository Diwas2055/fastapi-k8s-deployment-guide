.PHONY: help install dev test lint build deploy rollback setup-local smoke clean

# ── Config ────────────────────────────────────────────────────────────────────
TAG        ?= local
ENV        ?= development
TOOL       ?= kind
IMAGE      := fastapi-k8s-demo
NAMESPACE  := fastapi-app

help:                  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Local development ─────────────────────────────────────────────────────────
install:               ## Install all dependencies (runtime + dev)
	pip install -r requirements-dev.txt

dev:                   ## Run the API locally with auto-reload
	uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

compose-up:            ## Start the full stack with Docker Compose
	docker compose up --build

compose-down:          ## Stop Docker Compose stack
	docker compose down

# ── Testing ───────────────────────────────────────────────────────────────────
test:                  ## Run unit + integration tests with coverage
	pytest tests/ -v

test-watch:            ## Run tests in watch mode
	pytest-watch tests/ -- -v

lint:                  ## Lint and format check (ruff + mypy)
	ruff check app/ tests/
	mypy app/

format:                ## Auto-fix lint issues
	ruff check --fix app/ tests/
	ruff format app/ tests/

# ── Docker ────────────────────────────────────────────────────────────────────
build:                 ## Build Docker image (TAG=local by default)
	./scripts/build.sh $(TAG)

scan:                  ## Scan image for vulnerabilities (requires trivy)
	trivy image --exit-code 1 --severity HIGH,CRITICAL $(IMAGE):$(TAG)

# ── Kubernetes ────────────────────────────────────────────────────────────────
setup-local:           ## Bootstrap local cluster + deploy dev overlay (TOOL=kind|k3d|minikube)
	./scripts/setup-local.sh $(TOOL)

deploy:                ## Deploy to ENV overlay (ENV=development|staging|production)
	./scripts/deploy.sh $(ENV)

diff:                  ## Preview what will change before applying (ENV=production)
	kubectl diff -k k8s/overlays/$(ENV)

rollback:              ## Roll back the last deployment
	./scripts/rollback.sh

smoke:                 ## Run smoke tests (BASE_URL=http://localhost:8080)
	./scripts/smoke-test.sh

port-forward:          ## Forward API + Prometheus + Grafana ports locally
	./scripts/port-forward.sh

logs:                  ## Stream logs from all app pods
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=fastapi-app -f --max-log-requests 10

pods:                  ## List app pods with status
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=fastapi-app -o wide

events:                ## Show recent cluster events for the namespace
	kubectl get events --sort-by=.lastTimestamp -n $(NAMESPACE)

# ── Helm ──────────────────────────────────────────────────────────────────────
helm-lint:             ## Lint the Helm chart
	helm lint k8s/helm/fastapi-app

helm-template:         ## Render Helm chart templates to stdout
	helm template fastapi-app k8s/helm/fastapi-app

helm-install:          ## Install via Helm (dev defaults)
	helm install fastapi-app k8s/helm/fastapi-app \
	  --namespace $(NAMESPACE) --create-namespace \
	  --set image.tag=$(TAG) --set env.DEBUG=true

helm-upgrade:          ## Upgrade via Helm
	helm upgrade fastapi-app k8s/helm/fastapi-app --set image.tag=$(TAG)

helm-uninstall:        ## Uninstall Helm release
	helm uninstall fastapi-app -n $(NAMESPACE)

# ── Cleanup ───────────────────────────────────────────────────────────────────
clean:                 ## Remove build artifacts and caches
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null; \
	find . -name "*.pyc" -delete; \
	rm -rf .pytest_cache .mypy_cache .ruff_cache htmlcov coverage.xml .coverage
