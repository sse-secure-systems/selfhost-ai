# Quick Start - Docker-Based Thermal Guard

This guide helps you quickly set up GPU temperature monitoring with automatic vLLM container shutdown.

## Prerequisites

- Docker and Docker Compose installed
- NVIDIA Container Toolkit installed
- NVIDIA GPU with CUDA support

## Step 1: Verify GPU Access

```bash
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

You should see your GPU(s) listed.

## Step 2: Configure (Optional)

Set your preferred temperature threshold:

```bash
# Create .env file with custom settings
cat > .env << EOF
THERMAL_THRESHOLD_C=75
THERMAL_POLL_SECONDS=5
EOF
```

Or use defaults (80°C threshold, 5s polling).

## Step 3: Start Services

**Option A: Start everything together**

```bash
# From the project root directory
make up-all

# Or manually:
docker compose up -d
docker compose -f docker-compose.thermal.yml up -d
```

**Option B: Start main services only (no thermal protection)**

```bash
make up
# or
docker compose up -d
```

**Option C: Start thermal monitoring (if main services already running)**

```bash
make up-thermal
# or
docker compose -f docker-compose.thermal.yml up -d
```

## Step 4: Verify Services

```bash
# Check all services are running
docker compose ps

# Should show:
# - dcgm-exporter (healthy)
# - thermal-guard (running)
# - vllm (running)
```

## Step 5: Monitor Logs

```bash
# Watch thermal guard logs
docker compose logs -f thermal-guard

# You should see output like:
# [2026-02-19T10:30:15+00:00] Starting thermal monitoring (threshold: 80°C, poll interval: 5s)
# [2026-02-19T10:30:20+00:00] OK: Max GPU temp is 65°C (< 80°C).
```

## Test the Setup

### View GPU Metrics

```bash
# Check DCGM metrics are available
curl http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_TEMP

# Or use the Makefile
cd thermal-guard
make -f Makefile-docker test-metrics
```

### Simulate High Temperature (Optional)

**WARNING**: Only do this if you understand the risks!

```bash
# Temporarily lower the threshold to test shutdown behavior
docker compose exec thermal-guard sh -c 'export THRESHOLD_C=50 && /usr/local/bin/thermal-guard.sh'

# This will stop vllm if current temp > 50°C
```

## Common Commands

**From project root:**

```bash
# Start everything
make up-all

# Start main services only
make up

# Start thermal monitoring only
make up-thermal

# Stop everything
make down-all

# View thermal logs
make logs-thermal

# Check status
make status
```

**Manual commands:**

```bash
# Start main services
docker compose up -d

# Start thermal monitoring
docker compose -f docker-compose.thermal.yml up -d

# View thermal logs
docker compose -f docker-compose.thermal.yml logs -f thermal-guard

# Stop thermal monitoring
docker compose -f docker-compose.thermal.yml down

# Stop main services
docker compose down
```

## Using the Makefile

The root `Makefile` provides convenient shortcuts:

```bash
# From project root:

# Show all available commands
make help

# Start everything
make up-all

# Start main services only
make up

# Start thermal monitoring only (requires main services running)
make up-thermal

# View thermal guard logs
make logs-thermal

# Check status of all services
make status

# Stop everything
make down-all
```

The `thermal-guard/Makefile-docker` also has thermal-specific commands:

```bash
cd thermal-guard

# Show thermal-specific commands
make -f Makefile-docker help

# Test metrics endpoint
make -f Makefile-docker test-metrics

# Check health
make -f Makefile-docker health
```

## Troubleshooting

### DCGM Exporter Won't Start

```bash
# Check GPU access
docker compose logs dcgm-exporter

# Verify NVIDIA runtime
docker info | grep -i nvidia
```

### Thermal Guard Shows Warnings

```bash
# Check DCGM exporter is healthy
docker compose ps dcgm-exporter

# Test metrics endpoint
docker compose exec thermal-guard curl http://dcgm-exporter:9400/metrics
```

### vLLM Keeps Stopping

Your GPU is running hot! Check:

```bash
# Current temperature
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader

# Thermal guard logs
docker compose logs thermal-guard | grep CRITICAL

# Consider:
# - Improving cooling
# - Reducing GPU load
# - Raising threshold (if safe)
```

## Next Steps

- **Monitor with Prometheus**: Expose port 9400 and scrape DCGM metrics
- **Set up Grafana**: Use NVIDIA's DCGM dashboard
- **Alerting**: Configure Alertmanager for thermal alerts
- **Production**: Use Docker socket proxy for security

See [README-docker.md](README-docker.md) for detailed documentation.

## Architecture

```
┌────────────────────────────────────────────────┐
│                Docker Compose                  │
│                                                │
│  ┌──────────────┐      ┌──────────────┐      │
│  │    DCGM      │◄─────│   Thermal    │      │
│  │  Exporter    │      │    Guard     │      │
│  │              │      │              │      │
│  │  - Exposes   │      │  - Monitors  │      │
│  │    GPU       │      │    temps     │      │
│  │    metrics   │      │  - Stops     │      │
│  │  - Port 9400 │      │    vllm      │      │
│  └──────────────┘      └──────┬───────┘      │
│         ▲                      │              │
│         │                      │ (docker stop)│
│         │ (GPU access)         ▼              │
│  ┌──────┴────────────────────────────┐       │
│  │        vLLM Server                 │       │
│  │  - Serves LLM                      │       │
│  │  - Protected by thermal guard      │       │
│  └────────────────────────────────────┘       │
└────────────────────────────────────────────────┘
```

## Files Created

**Docker Compose:**
- `docker-compose.yml` - Main services (vllm + caddy)
- `docker-compose.thermal.yml` - Thermal monitoring (dcgm-exporter + thermal-guard)

**Configuration:**
- `thermal-guard/Dockerfile` - Thermal guard container definition
- `thermal-guard/thermal-guard-docker.sh` - Monitoring script
- `.env.example` - Configuration template

**Documentation:**
- `thermal-guard/README-docker.md` - Detailed documentation
- `thermal-guard/QUICKSTART.md` - This file
- `DOCKER-COMPOSE-SPLIT.md` - Split compose usage guide

**Utilities:**
- `Makefile` - Root-level management commands
- `thermal-guard/Makefile-docker` - Thermal-specific commands

## Architecture Note

The services are split into two independent compose files that share the `llm_server_internal` network:

```
docker-compose.yml (Main)          docker-compose.thermal.yml (Monitoring)
┌────────────────────┐            ┌────────────────────┐
│  vLLM Server       │◄───────────│  Thermal Guard     │
│  Caddy             │   monitors │  DCGM Exporter     │
└────────────────────┘   controls └────────────────────┘
         │                                │
         └────────── llm_server_internal ─┘
                  (shared network)
```

This allows you to:
- Run main services without thermal protection
- Start/stop thermal monitoring independently
- Develop and test each component separately

## Support

For issues or questions, refer to:
- [Detailed README](README-docker.md)
- [NVIDIA DCGM Documentation](https://docs.nvidia.com/datacenter/dcgm/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
