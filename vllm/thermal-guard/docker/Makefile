.PHONY: help build up down logs logs-thermal logs-dcgm restart status clean test-metrics up-all down-all

help: ## Show this help message
	@echo "Docker-based Thermal Guard Management (Split Compose)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

build: ## Build the thermal-guard Docker image
	docker compose -f docker-compose.thermal.yml build thermal-guard

up: ## Start thermal monitoring only (requires main services running)
	docker compose -f docker-compose.thermal.yml up -d

down: ## Stop thermal monitoring only
	docker compose -f docker-compose.thermal.yml down

up-all: ## Start main services + thermal monitoring
	docker compose -f ../docker-compose.yml up -d
	docker compose -f docker-compose.thermal.yml up -d

down-all: ## Stop thermal monitoring + main services
	docker compose -f docker-compose.thermal.yml down
	docker compose -f ../docker-compose.yml down

logs: ## Follow logs for thermal services
	docker compose -f docker-compose.thermal.yml logs -f

logs-thermal: ## Follow thermal guard logs only
	docker compose -f docker-compose.thermal.yml logs -f thermal-guard

logs-dcgm: ## Follow DCGM exporter logs only
	docker compose -f docker-compose.thermal.yml logs -f dcgm-exporter

restart: ## Restart thermal guard service
	docker compose -f docker-compose.thermal.yml restart thermal-guard

restart-all: ## Restart all thermal services
	docker compose -f docker-compose.thermal.yml restart

status: ## Show status of thermal services
	docker compose -f docker-compose.thermal.yml ps

status-all: ## Show status of all services (main + thermal)
	@echo "=== Main Services ==="
	@docker compose -f ../docker-compose.yml ps
	@echo ""
	@echo "=== Thermal Services ==="
	@docker compose -f docker-compose.thermal.yml ps

clean: ## Stop and remove thermal containers
	docker compose -f docker-compose.thermal.yml down -v

test-metrics: ## Test DCGM metrics endpoint
	@echo "Testing DCGM exporter metrics endpoint..."
	@docker compose -f docker-compose.thermal.yml exec -T dcgm-exporter curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_TEMP || echo "DCGM metrics not available yet"

test-thermal: ## Test thermal guard connectivity
	@echo "Testing thermal guard access to DCGM exporter..."
	@docker compose -f docker-compose.thermal.yml exec -T thermal-guard curl -s http://dcgm-exporter:9400/metrics | grep DCGM_FI_DEV_GPU_TEMP || echo "Cannot reach DCGM from thermal guard"

rebuild: down build up ## Rebuild and restart thermal services

health: ## Check health status of thermal services
	@echo "=== Thermal Services Health Status ==="
	@docker compose -f docker-compose.thermal.yml ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
