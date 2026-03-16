#!/usr/bin/env bash
# Errors in individual commands are handled explicitly; we never want the
# whole guard to abort because of a transient Docker / network hiccup.
set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration (all overridable via environment variables)
# ---------------------------------------------------------------------------
EXPORTER_URL="${EXPORTER_URL:-http://dcgm-exporter:9400/metrics}"
THRESHOLD_C="${THRESHOLD_C:-80}"         # stop LLM if GPU temp >= this (°C)
POLL_SECONDS="${POLL_SECONDS:-5}"         # polling interval
CONTAINER_NAME="${CONTAINER_NAME:-vllm}" # LLM container to stop on overtemp
DOCKER_STOP_TIMEOUT="${DOCKER_STOP_TIMEOUT:-30}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
  echo "[$(date -Iseconds)] $*"
}

# Return the highest GPU temperature reported by DCGM exporter.
# Exits non-zero when the endpoint is unreachable or returns no temp lines.
get_max_temp() {
  curl -fsS --max-time 5 "$EXPORTER_URL" \
    | awk '
      $1 ~ /^DCGM_FI_DEV_GPU_TEMP\{/ {
        v = $NF + 0
        if (v > max) max = v
      }
      END { if (max == "") exit 2; else print max }
    '
}

# Stop the LLM container only if it is currently running.
# Safe to call even when the container does not exist yet.
stop_llm_container() {
  local state
  state=$(docker container inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)

  if [ -z "$state" ]; then
    log "WARN: Container '${CONTAINER_NAME}' not found on the Docker host — nothing to stop."
  elif [ "$state" = "running" ]; then
    log "CRITICAL: Stopping container '${CONTAINER_NAME}' (current state: ${state})."
    docker container stop --time "$DOCKER_STOP_TIMEOUT" "$CONTAINER_NAME" || true
    log "INFO: Stop signal sent to '${CONTAINER_NAME}'."
  else
    log "INFO: Container '${CONTAINER_NAME}' is already '${state}' — no action needed."
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "Thermal guard started."
log "  DCGM exporter : ${EXPORTER_URL}"
log "  Threshold     : ${THRESHOLD_C}°C"
log "  Poll interval : ${POLL_SECONDS}s"
log "  LLM container : '${CONTAINER_NAME}' (stopped via Docker socket on overtemp)"
log "Waiting for DCGM exporter to become available..."

while true; do
  if ! max_temp="$(get_max_temp 2>/dev/null)"; then
    log "WARN: Could not read GPU temp from ${EXPORTER_URL} — DCGM exporter may not be ready yet. Retrying in ${POLL_SECONDS}s..."
    sleep "$POLL_SECONDS"
    continue
  fi

  # Truncate to integer for comparison (temps are reported as whole °C)
  if [ "${max_temp%.*}" -ge "$THRESHOLD_C" ]; then
    log "CRITICAL: Max GPU temp is ${max_temp}°C (threshold: ${THRESHOLD_C}°C)."
    stop_llm_container
    # Keep polling after the stop — do NOT auto-restart the LLM here.
    # Restart decisions belong to the operator to prevent thermal oscillation.
  else
    log "OK: Max GPU temp is ${max_temp}°C (< ${THRESHOLD_C}°C)."
  fi

  sleep "$POLL_SECONDS"
done
