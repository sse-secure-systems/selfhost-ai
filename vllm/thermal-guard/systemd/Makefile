.PHONY: install uninstall status logs start stop restart enable disable help

# Check if running with sudo
check-root:
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "Error: This target must be run with sudo"; \
		echo "Usage: sudo make install"; \
		exit 1; \
	fi

help:
	@echo "vLLM Thermal Guard - Makefile Commands"
	@echo ""
	@echo "Installation:"
	@echo "  make install       Install thermal guard and DCGM exporter services"
	@echo "  make uninstall     Remove thermal guard and optionally DCGM exporter"
	@echo ""
	@echo "Service Control (requires sudo):"
	@echo "  make start         Start thermal guard service"
	@echo "  make stop          Stop thermal guard service"
	@echo "  make restart       Restart thermal guard service"
	@echo "  make enable        Enable service to start on boot"
	@echo "  make disable       Disable service from starting on boot"
	@echo ""
	@echo "Monitoring:"
	@echo "  make status        Show service status"
	@echo "  make logs          View live logs"
	@echo "  make test-metrics  Test DCGM exporter metrics endpoint"
	@echo ""
	@echo "Example:"
	@echo "  sudo make install"
	@echo "  sudo make start"
	@echo "  make logs"

install: check-root
	@echo "Installing vLLM Thermal Guard..."
	@chmod +x install_dcgm_systemd.sh
	@./install_dcgm_systemd.sh

uninstall: check-root
	@echo "Uninstalling vLLM Thermal Guard..."
	@chmod +x uninstall_dcgm_systemd.sh
	@./uninstall_dcgm_systemd.sh

start: check-root
	@echo "Starting DCGM exporter..."
	@systemctl start dcgm-exporter.service || true
	@echo "Starting thermal guard service..."
	@systemctl start vllm-thermal-guard.service
	@echo "Done. Use 'make status' to check."

stop: check-root
	@echo "Stopping thermal guard service..."
	@systemctl stop vllm-thermal-guard.service

restart: check-root
	@echo "Restarting thermal guard service..."
	@systemctl restart vllm-thermal-guard.service
	@echo "Done. Use 'make status' to check."

enable: check-root
	@echo "Enabling services to start on boot..."
	@systemctl enable dcgm-exporter.service || true
	@systemctl enable vllm-thermal-guard.service
	@echo "Services enabled."

disable: check-root
	@echo "Disabling thermal guard from starting on boot..."
	@systemctl disable vllm-thermal-guard.service
	@echo "Service disabled."

status:
	@echo "=== DCGM Exporter Status ==="
	@systemctl status dcgm-exporter.service --no-pager || true
	@echo ""
	@echo "=== Thermal Guard Status ==="
	@systemctl status vllm-thermal-guard.service --no-pager || true

logs:
	@echo "Viewing thermal guard logs (Ctrl+C to exit)..."
	@journalctl -u vllm-thermal-guard.service -f

test-metrics:
	@echo "Testing DCGM exporter metrics endpoint..."
	@echo ""
	@if curl -sf http://127.0.0.1:9400/metrics >/dev/null 2>&1; then \
		echo "✓ DCGM exporter is responding"; \
		echo ""; \
		echo "GPU Temperature Metrics:"; \
		curl -sf http://127.0.0.1:9400/metrics | grep DCGM_FI_DEV_GPU_TEMP || echo "No temperature metrics found"; \
	else \
		echo "✗ Cannot reach DCGM exporter at http://127.0.0.1:9400/metrics"; \
		exit 1; \
	fi
