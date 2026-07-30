.PHONY: help backend-build backend-run backend-test frontend-build frontend-run frontend-test docker-build docker-up

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

BACKEND_DIR = backend
FRONTEND_DIR = frontend

backend-build: ## Build backend binary
	cd $(BACKEND_DIR) && CGO_ENABLED=1 go build -o flux-server ./cmd/server

backend-run: ## Run backend server
	cd $(BACKEND_DIR) && go run ./cmd/server -config configs/config.yaml

backend-test: ## Run backend tests
	cd $(BACKEND_DIR) && go test ./internal/... -race

frontend-build: ## Build frontend web
	cd $(FRONTEND_DIR) && flutter build web

frontend-run: ## Run frontend in dev mode
	cd $(FRONTEND_DIR) && flutter run

frontend-test: ## Run frontend tests
	cd $(FRONTEND_DIR) && flutter test

docker-build: ## Build Docker image
	cd $(BACKEND_DIR) && docker-compose build

docker-up: ## Start Docker services
	cd $(BACKEND_DIR) && docker-compose up -d
