#!/bin/bash
set -euo pipefail

# vLLM Thermal Guard - Systemd Service Installation Script
# This script installs the thermal monitoring service that uses DCGM exporter
# to monitor GPU temperatures and gracefully stop vLLM container when overheating.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="vllm-thermal-guard"
SCRIPT_PATH="/usr/local/sbin/vllm-thermal-guard.sh"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DCGM_SERVICE_FILE="/etc/systemd/system/dcgm-exporter.service"

echo "=== vLLM Thermal Guard Installation ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Step 1: Copy the monitoring script
echo "Step 1: Installing thermal guard script..."
if [ ! -f "${SCRIPT_DIR}/vllm-thermal-guard.sh" ]; then
    echo "ERROR: vllm-thermal-guard.sh not found in ${SCRIPT_DIR}"
    echo "Please ensure vllm-thermal-guard.sh exists in the same directory as this script."
    exit 1
fi

cp "${SCRIPT_DIR}/vllm-thermal-guard.sh" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
echo "✓ Installed: $SCRIPT_PATH"
echo ""

# Step 2: Install systemd service
echo "Step 2: Installing systemd service..."
if [ ! -f "${SCRIPT_DIR}/vllm-thermal-guard.service" ]; then
    echo "ERROR: vllm-thermal-guard.service not found in ${SCRIPT_DIR}"
    echo "Please ensure vllm-thermal-guard.service exists in the same directory as this script."
    exit 1
fi

cp "${SCRIPT_DIR}/vllm-thermal-guard.service" "$SERVICE_FILE"
echo "✓ Installed: $SERVICE_FILE"
echo ""

# Step 3: Install DCGM exporter service
echo "Step 3: Installing DCGM exporter service..."
if [ ! -f "${SCRIPT_DIR}/dcgm-exporter.service" ]; then
    echo "⚠ WARNING: dcgm-exporter.service not found in ${SCRIPT_DIR}"
    echo "  Skipping DCGM exporter service installation"
else
    # Check if dcgm-exporter service already exists
    if systemctl list-unit-files | grep -q "^dcgm-exporter.service"; then
        echo "  dcgm-exporter.service already exists, skipping installation"
    else
        cp "${SCRIPT_DIR}/dcgm-exporter.service" "$DCGM_SERVICE_FILE"
        echo "✓ Installed: $DCGM_SERVICE_FILE"
    fi
fi
echo ""

# Step 4: Verify DCGM exporter binary exists
echo "Step 4: Checking DCGM exporter binary..."
if command -v dcgm-exporter >/dev/null 2>&1; then
    echo "✓ dcgm-exporter binary found at $(command -v dcgm-exporter)"
else
    echo "⚠ WARNING: dcgm-exporter binary not found!"
    echo "  Install DCGM for ARM64:"
    echo "    sudo apt-get update"
    echo "    sudo apt-get install -y datacenter-gpu-manager"
    echo "  Or download from: https://developer.nvidia.com/dcgm"
fi
echo ""

# Step 5: Check if default counters file exists
echo "Step 5: Checking DCGM counters configuration..."
if [ -f "/etc/dcgm-exporter/default-counters.csv" ]; then
    echo "✓ Found: /etc/dcgm-exporter/default-counters.csv"
else
    echo "⚠ WARNING: /etc/dcgm-exporter/default-counters.csv not found!"
    echo "  The DCGM exporter may not start without this file"
fi
echo ""

# Step 6: Verify DCGM exporter service status
echo "Step 6: Checking DCGM exporter service status..."
if systemctl is-active --quiet dcgm-exporter.service 2>/dev/null; then
    echo "✓ dcgm-exporter.service is running"
elif systemctl list-unit-files | grep -q "^dcgm-exporter.service"; then
    echo "  dcgm-exporter.service exists but is not running"
    echo "  You can start it with: sudo systemctl start dcgm-exporter"
else
    echo "  dcgm-exporter.service not found"
fi
echo ""

# Step 7: Test DCGM metrics endpoint
echo "Step 7: Testing DCGM metrics endpoint..."
if curl -sf http://127.0.0.1:9400/metrics >/dev/null 2>&1; then
    temp_count=$(curl -sf http://127.0.0.1:9400/metrics | grep -c "^DCGM_FI_DEV_GPU_TEMP" || echo "0")
    if [ "$temp_count" -gt 0 ]; then
        echo "✓ DCGM exporter is responding ($temp_count GPU temperature metrics found)"
    else
        echo "⚠ WARNING: DCGM exporter responding but no temperature metrics found"
    fi
else
    echo "⚠ WARNING: Cannot reach DCGM exporter at http://127.0.0.1:9400/metrics"
    echo "  The thermal guard service will not work until DCGM exporter is available"
fi
echo ""

# Step 8: Reload systemd daemon
echo "Step 8: Reloading systemd daemon..."
systemctl daemon-reload
echo "✓ Systemd daemon reloaded"
echo ""

echo "=== Installation Complete ==="
echo ""
echo "Configuration:"
echo "  Service file: $SERVICE_FILE"
echo "  DCGM service: $DCGM_SERVICE_FILE"
echo "  Monitor script: $SCRIPT_PATH"
echo "  Temperature threshold: 80°C (default)"
echo "  Poll interval: 5 seconds (default)"
echo "  Container name: vllm (default)"
echo ""
echo "To customize settings, edit the Environment variables in:"
echo "  $SERVICE_FILE"
echo ""
echo "Next steps - Run these commands in order:"
echo ""
echo "  # 1. Start DCGM exporter (if not already running)"
echo "  sudo systemctl enable dcgm-exporter.service"
echo "  sudo systemctl start dcgm-exporter.service"
echo "  sudo systemctl status dcgm-exporter.service"
echo ""
echo "  # 2. Verify DCGM metrics are available"
echo "  curl http://127.0.0.1:9400/metrics | grep DCGM_FI_DEV_GPU_TEMP"
echo ""
echo "  # 3. Enable and start thermal guard service"
echo "  sudo systemctl enable ${SERVICE_NAME}.service"
echo ""
echo "  # Start the service now"
echo "  sudo systemctl start ${SERVICE_NAME}.service"
echo ""
echo "  # Check service status"
echo "  sudo systemctl status ${SERVICE_NAME}.service"
echo ""
echo "  # View live logs"
echo "  sudo journalctl -u ${SERVICE_NAME}.service -f"
echo ""
echo "Quick start (all commands):"
echo "  sudo systemctl enable --now dcgm-exporter.service && \\"
echo "  sudo systemctl enable --now ${SERVICE_NAME}.service && \\"
echo "  sudo systemctl status ${SERVICE_NAME}.service"
echo ""
