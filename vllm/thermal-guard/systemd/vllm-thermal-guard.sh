#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
EXPORTER_URL="${EXPORTER_URL:-http://127.0.0.1:9400/metrics}"
THRESHOLD_C="${THRESHOLD_C:-80}"      # stop if >= this temp
POLL_SECONDS="${POLL_SECONDS:-5}"     # how often to check
CONTAINER_NAME="${CONTAINER_NAME:-vllm}"
DOCKER_STOP_TIMEOUT="${DOCKER_STOP_TIMEOUT:-30}" # seconds

# --- Helper: get max GPU temp from dcgm-exporter metrics ---
get_max_temp() {
  # Parse Prometheus exposition lines like:
  # DCGM_FI_DEV_GPU_TEMP{...} 42
  curl -fsS "$EXPORTER_URL" \
    | awk '
      $1 ~ /^DCGM_FI_DEV_GPU_TEMP\{/ {
        v=$NF+0;
        if (v > max) max=v;
      }
      END { if (max == "") exit 2; else print max; }
    '
}

log() {
  echo "[$(date -Is)] $*"
}

while true; do
  if ! max_temp="$(get_max_temp)"; then
    log "WARN: Could not read DCGM_FI_DEV_GPU_TEMP from $EXPORTER_URL. Retrying..."
    sleep "$POLL_SECONDS"
    continue
  fi

  # Compare as integers (temps are whole °C)
  if [ "${max_temp%.*}" -ge "$THRESHOLD_C" ]; then
    log "CRITICAL: Max GPU temp is ${max_temp}°C (>= ${THRESHOLD_C}°C). Stopping container '${CONTAINER_NAME}'."
    # Graceful stop first; Docker will send the container’s StopSignal then wait up to timeout.
    docker container stop --time "$DOCKER_STOP_TIMEOUT" "$CONTAINER_NAME" || true
    # After stopping, keep checking; do not auto-restart here (avoid oscillation).
    sleep "$POLL_SECONDS"
  else
    log "OK: Max GPU temp is ${max_temp}°C (< ${THRESHOLD_C}°C)."
    sleep "$POLL_SECONDS"
  fi
done
