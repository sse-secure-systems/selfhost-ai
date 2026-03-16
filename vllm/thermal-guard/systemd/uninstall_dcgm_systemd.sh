#!/bin/bash
set -euo pipefail

# vLLM Thermal Guard - Uninstall Script
# This script removes the thermal monitoring service and cleans up all files

SERVICE_NAME="vllm-thermal-guard"
DCGM_SERVICE_NAME="dcgm-exporter"
SCRIPT_PATH="/usr/local/sbin/vllm-thermal-guard.sh"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DCGM_SERVICE_FILE="/etc/systemd/system/${DCGM_SERVICE_NAME}.service"

echo "=== vLLM Thermal Guard Uninstallation ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Step 1: Stop the service if running
echo "Step 1: Stopping service (if running)..."
if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    systemctl stop "${SERVICE_NAME}.service"
    echo "✓ Service stopped"
else
    echo "  Service is not running"
fi
echo ""

# Step 2: Disable the service if enabled
echo "Step 2: Disabling service (if enabled)..."
if systemctl is-enabled --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    systemctl disable "${SERVICE_NAME}.service"
    echo "✓ Service disabled"
else
    echo "  Service is not enabled"
fi
echo ""

# Step 3: Remove systemd service file
echo "Step 3: Removing systemd service file..."
if [ -f "$SERVICE_FILE" ]; then
    rm -f "$SERVICE_FILE"
    echo "✓ Removed: $SERVICE_FILE"
else
    echo "  Service file not found: $SERVICE_FILE"
fi
echo ""

# Step 4: Handle DCGM exporter service
echo "Step 4: Checking DCGM exporter service..."
if systemctl list-unit-files | grep -q "^${DCGM_SERVICE_NAME}.service"; then
    echo "  Found DCGM exporter service"

    # Ask if user wants to stop it
    if systemctl is-active --quiet "${DCGM_SERVICE_NAME}.service" 2>/dev/null; then
        read -p "  Stop DCGM exporter service? This will stop GPU metrics collection. (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl stop "${DCGM_SERVICE_NAME}.service"
            echo "  ✓ DCGM exporter service stopped"
        else
            echo "  Keeping DCGM exporter running"
        fi
    fi

    # Ask if user wants to disable it
    if systemctl is-enabled --quiet "${DCGM_SERVICE_NAME}.service" 2>/dev/null; then
        read -p "  Disable DCGM exporter service? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl disable "${DCGM_SERVICE_NAME}.service"
            echo "  ✓ DCGM exporter service disabled"
        else
            echo "  Keeping DCGM exporter enabled"
        fi
    fi

    # Ask if user wants to remove the service file
    if [ -f "$DCGM_SERVICE_FILE" ]; then
        read -p "  Remove DCGM exporter service file? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$DCGM_SERVICE_FILE"
            echo "  ✓ Removed: $DCGM_SERVICE_FILE"
        else
            echo "  Keeping DCGM exporter service file"
        fi
    fi
else
    echo "  DCGM exporter service not found (nothing to do)"
fi
echo ""

# Step 5: Remove monitoring script
echo "Step 5: Removing monitoring script..."
if [ -f "$SCRIPT_PATH" ]; then
    rm -f "$SCRIPT_PATH"
    echo "✓ Removed: $SCRIPT_PATH"
else
    echo "  Script not found: $SCRIPT_PATH"
fi
echo ""

# Step 6: Reload systemd daemon
echo "Step 6: Reloading systemd daemon..."
systemctl daemon-reload
echo "✓ Systemd daemon reloaded"
echo ""

# Step 7: Reset failed state (if any)
echo "Step 7: Resetting failed service states..."
systemctl reset-failed 2>/dev/null || true
echo "✓ Failed states reset"
echo ""

echo "=== Uninstallation Complete ==="
echo ""
echo "Thermal Guard components removed:"
echo "  • Service: ${SERVICE_NAME}.service"
echo "  • Service file: $SERVICE_FILE"
echo "  • Monitor script: $SCRIPT_PATH"
echo ""
if [ ! -f "$DCGM_SERVICE_FILE" ]; then
    echo "DCGM Exporter service also removed:"
    echo "  • Service file: $DCGM_SERVICE_FILE"
    echo ""
fi
echo "The vLLM container can now run without thermal monitoring."
echo ""
echo "To verify thermal guard removal:"
echo "  systemctl status ${SERVICE_NAME}.service"
echo ""
echo "To check if DCGM exporter is still running:"
echo "  systemctl status ${DCGM_SERVICE_NAME}.service"
echo ""
