.PHONY: help backend-build backend-run backend-test web-dev web-build web-lint web-test mobile-check mobile-export docker-build docker-up

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

BACKEND_DIR = backend

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
