# =============================================================================
# Variables
# =============================================================================
DEPLOY_DIR      := vllm/deployment-templates
THERMAL_COMPOSE := vllm/thermal-guard/docker/docker-compose.thermal.yml
TESTING_SCRIPT  := vllm/testing/test_llm_api.py

# Default model — override with: make deploy MODEL=Qwen3.6-27B
MODEL ?= Ministral-3-3B-Instruct-2512

.DEFAULT_GOAL := help

# =============================================================================
# Help
# =============================================================================
.PHONY: help
help: ## Show this help message
	@echo "Self-Host AI — management commands"
	@echo ""
	@echo "Usage: make [target] [MODEL=<name>]"
	@echo ""
	@echo "Setup:"
	@awk 'BEGIN {FS = ":.*?## "} /^## @setup/ {p=1; next} /^## @/ {p=0} p && /^[a-zA-Z_-]+:.*?## / {printf "  %-28s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Model deployment:"
	@awk 'BEGIN {FS = ":.*?## "} /^## @deploy/ {p=1; next} /^## @/ {p=0} p && /^[a-zA-Z_-]+:.*?## / {printf "  %-28s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Testing:"
	@awk 'BEGIN {FS = ":.*?## "} /^## @test/ {p=1; next} /^## @/ {p=0} p && /^[a-zA-Z_-]+:.*?## / {printf "  %-28s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Thermal guard:"
	@awk 'BEGIN {FS = ":.*?## "} /^## @thermal/ {p=1; next} /^## @/ {p=0} p && /^[a-zA-Z_-]+:.*?## / {printf "  %-28s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# =============================================================================
## @setup
# =============================================================================
.PHONY: env venv gpu-check

env: ## Copy .env.example to .env (no-op if .env already exists)
	@[ -f .env ] && echo ".env already exists — skipping" || (cp .env.example .env && echo "Created .env — edit it and set VLLM_API_KEY")

venv: ## Create root .venv and install Python dependencies
	python3 -m venv .venv
	.venv/bin/pip install --upgrade pip -q
	.venv/bin/pip install -r requirements.txt
	@echo "Done — activate with: source .venv/bin/activate"

gpu-check: ## Verify GPU access (nvidia-smi + Docker runtime)
	nvidia-smi
	docker run --rm --gpus all ubuntu:22.04 nvidia-smi

# =============================================================================
## @deploy
# =============================================================================
.PHONY: deploy undeploy deploy-logs deploy-status \
        deploy-ministral-3b deploy-ministral-8b deploy-ministral-14b \
        deploy-devstral-123b deploy-gpt-20b deploy-gpt-120b deploy-qwen-27b

deploy: ## Start vLLM + Caddy for MODEL (default: Ministral-3-8B-Instruct-2512)
	docker compose -f $(DEPLOY_DIR)/docker-compose.$(MODEL).yml up -d

undeploy: ## Stop the running vLLM stack for MODEL
	docker compose -f $(DEPLOY_DIR)/docker-compose.$(MODEL).yml down

deploy-logs: ## Follow vLLM server logs for MODEL
	docker compose -f $(DEPLOY_DIR)/docker-compose.$(MODEL).yml logs -f vllm-server

deploy-status: ## Show running status for MODEL
	docker compose -f $(DEPLOY_DIR)/docker-compose.$(MODEL).yml ps

# --- per-model shortcuts ---
deploy-ministral-3b: ## Deploy Ministral-3-3B-Instruct-2512
	$(MAKE) deploy MODEL=Ministral-3-3B-Instruct-2512

deploy-ministral-8b: ## Deploy Ministral-3-8B-Instruct-2512
	$(MAKE) deploy MODEL=Ministral-3-8B-Instruct-2512

deploy-ministral-14b: ## Deploy Ministral-3-14B-Instruct-2512
	$(MAKE) deploy MODEL=Ministral-3-14B-Instruct-2512

deploy-devstral-123b: ## Deploy Devstral-2-123B-Instruct-2512
	$(MAKE) deploy MODEL=Devstral-2-123B-Instruct-2512

deploy-gpt-20b: ## Deploy gpt-oss-20B
	$(MAKE) deploy MODEL=gpt-oss-20B

deploy-gpt-120b: ## Deploy gpt-oss-120B
	$(MAKE) deploy MODEL=gpt-oss-120B

deploy-qwen-27b: ## Deploy Qwen3.6-27B
	$(MAKE) deploy MODEL=Qwen3.6-27B

# =============================================================================
## @test
# =============================================================================
.PHONY: test

# Default message — override with: make test MSG="your question here"
MESSAGE ?= Was ist die Hauptstadt von Frankreich?

test: ## Run the API smoke test (optional: make test MSG="your question")
	.venv/bin/python $(TESTING_SCRIPT) $(if $(MESSAGE),"$(MESSAGE)")

# =============================================================================
## @thermal
# =============================================================================
.PHONY: thermal-build thermal-up thermal-down thermal-logs thermal-logs-guard \
        thermal-logs-dcgm thermal-restart thermal-status thermal-health \
        thermal-metrics thermal-rebuild

thermal-build: ## Build the thermal-guard Docker image
	docker compose -f $(THERMAL_COMPOSE) build thermal-guard

thermal-up: ## Start thermal monitoring (dcgm-exporter + thermal-guard)
	docker compose -f $(THERMAL_COMPOSE) up -d

thermal-down: ## Stop thermal monitoring
	docker compose -f $(THERMAL_COMPOSE) down

thermal-logs: ## Follow logs for all thermal services
	docker compose -f $(THERMAL_COMPOSE) logs -f

thermal-logs-guard: ## Follow thermal-guard logs only
	docker compose -f $(THERMAL_COMPOSE) logs -f thermal-guard

thermal-logs-dcgm: ## Follow DCGM exporter logs only
	docker compose -f $(THERMAL_COMPOSE) logs -f dcgm-exporter

thermal-restart: ## Restart the thermal-guard service
	docker compose -f $(THERMAL_COMPOSE) restart thermal-guard

thermal-status: ## Show running status of thermal services
	docker compose -f $(THERMAL_COMPOSE) ps

thermal-health: ## Show health check status of thermal services
	@docker compose -f $(THERMAL_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"

thermal-metrics: ## Verify DCGM exporter is returning GPU temperature data
	@echo "Checking DCGM GPU temperature metrics..."
	@curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_TEMP \
	  || echo "No metrics yet — DCGM exporter may still be starting up"

thermal-rebuild: thermal-down thermal-build thermal-up ## Rebuild and restart all thermal services
