# Thermal Guard - Docker-Based GPU Temperature Monitoring

This implementation provides GPU temperature monitoring and automatic container shutdown using Docker Compose, NVIDIA DCGM Exporter, and a custom thermal guard service.

## Architecture

The system is split into two independent Docker Compose files for flexibility:

1. **`docker-compose.yml`** - Main services (vllm + caddy)
2. **`docker-compose.thermal.yml`** - Thermal monitoring (dcgm-exporter + thermal-guard)

Both share a common network (`llm_server_internal`) allowing thermal-guard to monitor and control the vllm container.

## Overview

The thermal guard system consists of services split across two compose files:

**Main Services** (`docker-compose.yml`):
- **vllm-server** - The LLM server that will be protected from thermal issues
- **caddy** - Reverse proxy/load balancer

**Thermal Monitoring** (`docker-compose.thermal.yml`):
- **dcgm-exporter** - Official NVIDIA DCGM Exporter that exposes GPU metrics on port 9400
- **thermal-guard** - Custom monitoring service that polls GPU temperatures and stops vllm when thresholds are exceeded

## Architecture

```
┌─────────────────┐
│  DCGM Exporter  │ ──► Exposes GPU metrics at http://dcgm-exporter:9400/metrics
└─────────────────┘
        ▲
        │ (polls every 5s)
        │
┌─────────────────┐
│  Thermal Guard  │ ──► Monitors DCGM_FI_DEV_GPU_TEMP metric
└─────────────────┘     └─► Stops vllm container if temp >= threshold
        │
        │ (docker stop via socket)
        ▼
┌─────────────────┐
│   vLLM Server   │
└─────────────────┘
```

## Features

- **Containerized Monitoring** - All components run in Docker containers
- **Official DCGM Exporter** - Uses `nvidia/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04` (ARM64 compatible)
- **Automatic Protection** - Gracefully stops vllm container when GPU temperatures exceed threshold
- **Configurable** - Temperature thresholds and polling intervals can be adjusted via environment variables
- **Lightweight** - Thermal guard container is based on Alpine Linux (~15MB)
- **Health Checks** - Built-in health checks ensure DCGM exporter is ready before thermal monitoring starts

## Configuration

### Environment Variables

Set these in the root `.env` file (repo root) or directly in docker-compose.yml:

| Variable | Default | Description |
|----------|---------|-------------|
| `THERMAL_THRESHOLD_C` | 80 | Temperature threshold in Celsius. vllm stops if GPU temp >= this value |
| `THERMAL_POLL_SECONDS` | 5 | How often to poll GPU temperatures (in seconds) |

### Advanced Configuration

The thermal-guard service accepts additional environment variables:

- `EXPORTER_URL` - DCGM exporter metrics endpoint (default: `http://dcgm-exporter:9400/metrics`)
- `CONTAINER_NAME` - Name of container to stop (default: `vllm`)
- `DOCKER_STOP_TIMEOUT` - Graceful shutdown timeout in seconds (default: `30`)

## Usage

All commands are run from the **repo root**:

```bash
make thermal-up             # start dcgm-exporter + thermal-guard
make thermal-down           # stop thermal monitoring
make thermal-logs-guard     # follow thermal-guard logs
make thermal-logs-dcgm      # follow DCGM exporter logs
make thermal-status         # show service status
make thermal-health         # show health check status
make thermal-metrics        # verify GPU temp metrics are flowing
make thermal-rebuild        # rebuild image and restart
```

### Customizing Temperature Threshold

Set values in the root `.env` file (repo root):

```bash
# Set custom thermal threshold to 75°C
THERMAL_THRESHOLD_C=75

# Poll every 3 seconds instead of 5
THERMAL_POLL_SECONDS=3
```

Or pass it directly:

```bash
THERMAL_THRESHOLD_C=75 docker compose -f docker-compose.thermal.yml up -d
```

### Monitoring

The thermal guard emits a log line every poll cycle:

```
[2026-02-19T10:30:15+00:00] Starting thermal monitoring (threshold: 80°C, poll interval: 5s)
[2026-02-19T10:30:20+00:00] OK: Max GPU temp is 65°C (< 80°C).
[2026-02-19T10:30:25+00:00] OK: Max GPU temp is 67°C (< 80°C).
[2026-02-19T10:30:30+00:00] CRITICAL: Max GPU temp is 82°C (>= 80°C). Stopping container 'vllm'.
```

### Exposing DCGM Metrics Externally

To access DCGM metrics from outside the Docker network (e.g., for Prometheus), uncomment the ports section in `docker-compose.thermal.yml`:

```yaml
dcgm-exporter:
  # ...
  ports:
    - "9400:9400"  # Expose metrics externally
```

Then restart:

```bash
make thermal-rebuild
```

## How It Works

1. **DCGM Exporter** starts and exposes GPU metrics including `DCGM_FI_DEV_GPU_TEMP`
2. **Thermal Guard** waits for DCGM exporter to be healthy
3. **Thermal Guard** polls the metrics endpoint every `POLL_SECONDS`
4. If any GPU temperature >= `THRESHOLD_C`:
   - Logs a CRITICAL message
   - Executes `docker stop --time 30 vllm`
   - Continues monitoring (does not auto-restart to prevent oscillation)
5. If temperatures are below threshold:
   - Logs OK message
   - Continues monitoring

## Troubleshooting

### DCGM Exporter Not Starting

Check GPU and toolkit access:

```bash
make gpu-check
docker info | grep -i nvidia
```

### Thermal Guard Can't Access Docker Socket

Ensure the docker socket is mounted and readable:

```bash
docker compose -f docker-compose.thermal.yml exec thermal-guard ls -l /var/run/docker.sock
```

### Wrong Architecture

Make sure you're using the ARM64 image for ARM systems:

```bash
docker compose -f docker-compose.thermal.yml exec dcgm-exporter uname -m
# Should output: aarch64
```

### DCGM Metrics Not Available

Check if DCGM exporter is exposing metrics:

```bash
docker compose -f docker-compose.thermal.yml exec thermal-guard curl http://dcgm-exporter:9400/metrics | grep DCGM_FI_DEV_GPU_TEMP
```

### Network Errors

Ensure the thermal stack is started from the repo root so the `env_file` path resolves correctly:

```bash
make thermal-up
```

## Integration with Monitoring

The DCGM exporter exposes Prometheus-compatible metrics. You can integrate with:

- **Prometheus** - Scrape metrics from `http://dcgm-exporter:9400/metrics`
- **Grafana** - Use official NVIDIA DCGM dashboard
- **Alertmanager** - Set up custom alerts for temperature thresholds

Example Prometheus configuration:

```yaml
scrape_configs:
  - job_name: 'dcgm-exporter'
    static_configs:
      - targets: ['dcgm-exporter:9400']
```

## Security Considerations

- The thermal-guard container needs access to `/var/run/docker.sock` to stop containers
- Docker socket is mounted as read-only (`:ro`) but the container still has control capabilities
- Consider using Docker socket proxy (e.g., tecnativa/docker-socket-proxy) for production environments
- The thermal guard runs as root inside the container (required for docker CLI operations)

## License

This thermal guard implementation is provided as-is for use with the LLM server project.

## References

- [NVIDIA DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
- [DCGM Metrics Documentation](https://docs.nvidia.com/datacenter/dcgm/latest/user-guide/feature-overview.html)
- [Docker Compose Networking](https://docs.docker.com/compose/networking/)
