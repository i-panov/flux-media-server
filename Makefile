.PHONY: help backend-lint backend-lint-install semgrep semgrep-deep analyze codeql codeql-analyze backend-build backend-run backend-test web-dev web-build web-lint web-test mobile-check mobile-export docker-build docker-up

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

BACKEND_DIR = backend
GOLANGCI_LINT_VERSION ?= v2.14.0
GOLANGCI_LINT := $(shell go env GOPATH)/bin/golangci-lint
SEMGREP_RULES ?= $(HOME)/semgrep-rules

backend-build: ## Build backend binary
	cd $(BACKEND_DIR) && CGO_ENABLED=1 go build -o flux-server ./cmd/server

backend-run: ## Run backend server
	cd $(BACKEND_DIR) && go run ./cmd/server -config configs/config.yaml

backend-test: ## Run backend tests
	cd $(BACKEND_DIR) && go test ./internal/... -race

web-dev: ## Run web dev server
	npm run dev -w web

web-build: ## Build web production bundle
	npm run build -w web

web-lint: ## Lint web (Biome + ESLint + Knip)
	npm run lint -w web && npm run lint:deadcode -w web

web-test: ## Run web unit and e2e tests
	npm run test -w web && npm run test:e2e -w web

mobile-check: ## Typecheck and lint mobile
	npm run typecheck -w mobile && npm run lint -w mobile

mobile-export: ## Smoke-build Android JS bundle
	cd mobile && npx expo export --platform android --output-dir dist

docker-build: ## Build Docker image
	cd $(BACKEND_DIR) && docker compose build

docker-up: ## Start Docker services
	cd $(BACKEND_DIR) && docker compose up -d

codeql:
	./scripts/codeql.sh

codeql-analyze:
	./scripts/codeql.sh analyze

backend-lint-new: ## Run golangci-lint only for changes since origin/master
	@test -x "$(GOLANGCI_LINT)" || { echo "run: make backend-lint-install"; exit 1; }
	cd backend && $(GOLANGCI_LINT) run --new-from-rev=origin/master ./...

backend-lint: ## Run golangci-lint
	@test -x "$(GOLANGCI_LINT)" || { echo "run: make backend-lint-install"; exit 1; }
	cd backend && $(GOLANGCI_LINT) run ./...

backend-lint-install: ## Install golangci-lint
	go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)

semgrep: ## Semgrep security/best-practice scan
	semgrep scan --metrics=off --config .semgrep/rules \
		--config $(SEMGREP_RULES)/go/lang/security \
		--config $(SEMGREP_RULES)/go/lang/best-practice \
		--config $(SEMGREP_RULES)/typescript/react/security \
		--config $(SEMGREP_RULES)/javascript/lang \
		backend/ web/src/ mobile/src/ mobile/app/ packages/shared/src/

semgrep-deep: ## Full Semgrep rule packs
	semgrep scan --metrics=off --config .semgrep/rules \
		--config $(SEMGREP_RULES)/go \
		--config $(SEMGREP_RULES)/javascript \
		--config $(SEMGREP_RULES)/typescript \
		backend/ web/src/ mobile/src/ mobile/app/ packages/shared/src/

analyze: semgrep codeql ## Deep static analysis (Semgrep + CodeQL)
