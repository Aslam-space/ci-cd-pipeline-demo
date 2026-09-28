# Local shortcuts that mirror the CI pipeline stages.
IMAGE      ?= ci-cd-demo
TAG        ?= local
PORT       ?= 8080
CONTAINER  ?= ci-cd-demo-local
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
BUILD_DATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

.DEFAULT_GOAL := help
.PHONY: help lint build run test scan deploy stop clean

help: ## Show available targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

lint: ## Lint the Dockerfile and shell scripts
	docker run --rm -i hadolint/hadolint:v2.12.0-alpine hadolint - < Dockerfile
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt koalaman/shellcheck-alpine:v0.10.0 shellcheck scripts/*.sh

build: ## Build the image with local build metadata
	docker build \
	  --build-arg BUILD_NUMBER=$(TAG) \
	  --build-arg GIT_COMMIT=$(GIT_COMMIT) \
	  --build-arg GIT_BRANCH=$(GIT_BRANCH) \
	  --build-arg BUILD_DATE=$(BUILD_DATE) \
	  -t $(IMAGE):$(TAG) .

run: build stop ## Build and run at http://localhost:8080 (override with PORT=)
	docker run -d --name $(CONTAINER) --read-only --tmpfs /tmp --cap-drop ALL -p $(PORT):8080 $(IMAGE):$(TAG)
	@echo "→ http://localhost:$(PORT)"

test: run ## Build, run and smoke-test
	scripts/smoke-test.sh http://localhost:$(PORT)

scan: build ## Scan the image for vulnerabilities with Trivy
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.62.1 \
	  image --no-progress --severity HIGH,CRITICAL $(IMAGE):$(TAG)

deploy: build ## Deploy the local image with the health gate (HOST_PORT=80 by default)
	scripts/deploy.sh $(IMAGE):$(TAG)

stop: ## Stop the local container
	-@docker rm -f $(CONTAINER) >/dev/null 2>&1

clean: stop ## Remove the local container and image
	-docker rmi $(IMAGE):$(TAG)
