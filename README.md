# local-llms

A self-hosted local LLM environment that supports both **Ollama** and **vLLM** deployments. The primary focus is on running a vLLM inference server that exposes an **OpenAI-compatible Chat Completions API**, backed by a Caddy reverse proxy and protected by GPU thermal monitoring.

All services are deployed via **Docker Compose**.

---

## Repository Structure

```
local-llms/
├── models/                          # Local model weights (mounted read-only into containers)
│   ├── Devstral-2-123B-Instruct-2512/
│   ├── Ministral-3-3B-Instruct-2512/
│   ├── Ministral-3-8B-Instruct-2512/
│   ├── Ministral-3-14B-Instruct-2512/
│   ├── gpt-oss-20b/
│   ├── gpt-oss-120b/
│   └── gemma-3n-E2B-it/
│
├── ollama/                          # Ollama + Open WebUI deployment
│   └── docker-compose.yml
│
└── vllm/
    ├── llm-deployment/              # Per-model vLLM + Caddy Docker Compose stacks
    │   ├── .env
    │   ├── Caddyfile
    │   ├── docker-compose.Ministral-3-3B-Instruct-2512.yml
    │   ├── docker-compose.Ministral-3-8B-Instruct-2512.yml
    │   ├── docker-compose.Ministral-3-14B-Instruct-2512.yml
    │   ├── docker-compose.Devstral-2-123B-Instruct-2512.yml
    │   ├── docker-compose.gpt-oss-20B.yml
    │   └── docker-compose.gpt-oss-120B.yml
    │
    ├── llm-testing/                 # API smoke-test script
    │   ├── .env
    │   └── test_llm_api.py
    │
    ├── thermal-guard/               # GPU temperature monitoring & auto-shutdown
    │   ├── docker/                  # Docker Compose-based deployment (recommended)
    │   │   ├── Dockerfile
    │   │   ├── docker-compose.thermal.yml
    │   │   ├── thermal-guard-docker.sh
    │   │   ├── Makefile
    │   │   ├── .env
    │   │   ├── QUICKSTART.md
    │   │   └── README-docker.md
    │   └── systemd/                 # Alternative systemd-based deployment
    │       ├── vllm-thermal-guard.sh
    │       ├── vllm-thermal-guard.service
    │       ├── dcgm-exporter.service
    │       ├── install_dcgm_systemd.sh
    │       ├── uninstall_dcgm_systemd.sh
    │       └── Makefile
    │
    └── backup-files/                # Archived / reference compose files
```

---

## Prerequisites

- Docker and Docker Compose v2
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) installed and configured
- NVIDIA GPU(s) with CUDA support
- Model weights downloaded into `models/`

---

## vLLM Deployment (OpenAI-Compatible API)

### Overview

Each model has its own Docker Compose file under `vllm/llm-deployment/`. Every stack starts two services:

| Service | Image | Description |
|---------|-------|-------------|
| `vllm-server` | `nvcr.io/nvidia/vllm:26.01-py3` | Inference engine, listens on port 8000 (internal) |
| `caddy` | `caddy:latest` | Reverse proxy, exposes HTTP (80) / HTTPS (443) |

Caddy forwards all traffic to vLLM with response streaming enabled (`flush_interval -1`) and a generous read timeout to accommodate large model generation.

### Configuration

Copy the example file and fill in your secret key:

```bash
cd vllm/llm-deployment
cp .env.example .env
```

The only required variable is the API key:

```env
# Generate a strong key, e.g.: openssl rand -hex 32
VLLM_API_KEY="your-secret-key-here"
```

> `.env` is git-ignored. Only `.env.example` (no secrets) is tracked in the repository.

### Starting a Model

```bash
cd vllm/llm-deployment

# Example: Ministral 8B
docker compose -f docker-compose.Ministral-3-8B-Instruct-2512.yml up -d

# Example: Devstral 123B
docker compose -f docker-compose.Devstral-2-123B-Instruct-2512.yml up -d
```

vLLM performs a health check at `GET /health` every 15 seconds. Caddy will not start accepting traffic until vLLM reports healthy. Allow up to **10 minutes** for large models to load.

### Stopping a Stack

```bash
docker compose -f docker-compose.<model>.yml down
```

### API Usage

The API is OpenAI-compatible and reachable at `http://<host>/v1/` (or `https://` if TLS is configured in the Caddyfile).

```bash
curl http://localhost/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d '{
    "model": "Ministral-3-8B-Instruct-2512",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

> **Note for Mistral-family models:** The compose files use `--tokenizer_mode mistral`, `--config_format mistral`, and `--load_format mistral` to load weights in Mistral's native format. Omitting these flags causes vLLM to fall back to the HuggingFace loader, which misidentifies these models and crashes at startup.

### Available Models

| Model | Compose File | Notes |
|-------|-------------|-------|
| Ministral-3-3B-Instruct-2512 | `docker-compose.Ministral-3-3B-Instruct-2512.yml` | Mistral native format |
| Ministral-3-8B-Instruct-2512 | `docker-compose.Ministral-3-8B-Instruct-2512.yml` | Mistral native format, tool calling |
| Ministral-3-14B-Instruct-2512 | `docker-compose.Ministral-3-14B-Instruct-2512.yml` | Mistral native format |
| Devstral-2-123B-Instruct-2512 | `docker-compose.Devstral-2-123B-Instruct-2512.yml` | 123B, async scheduling |
| gpt-oss-20B | `docker-compose.gpt-oss-20B.yml` | |
| gpt-oss-120B | `docker-compose.gpt-oss-120B.yml` | |

---

## Ollama Deployment

Ollama is deployed together with **Open WebUI** for a browser-based chat interface.

```bash
cd ollama
docker compose up -d
```

Open WebUI is accessible at `http://localhost:8080`.

Model management is handled entirely through the Open WebUI interface or the Ollama CLI using the running container.

---

## Thermal Guard — GPU Temperature Monitoring

The thermal guard system protects the GPU(s) from overheating by automatically stopping the vLLM container when a configurable temperature threshold is exceeded.

### Architecture

```
┌──────────────────┐
│  DCGM Exporter   │  ──►  GPU metrics at http://dcgm-exporter:9400/metrics
└──────────────────┘
         ▲
         │  polls every N seconds
         │
┌──────────────────┐
│  Thermal Guard   │  ──►  Reads DCGM_FI_DEV_GPU_TEMP
└──────────────────┘        └─► docker stop vllm  (if temp >= threshold)
         │
         ▼
┌──────────────────┐
│   vLLM Server    │
└──────────────────┘
```

Two deployment options are provided:

### Option A: Docker (Recommended)

See [`vllm/thermal-guard/docker/README-docker.md`](vllm/thermal-guard/docker/README-docker.md) and [`vllm/thermal-guard/docker/QUICKSTART.md`](vllm/thermal-guard/docker/QUICKSTART.md) for full details.

```bash
cd vllm/thermal-guard/docker

# Configure thresholds (optional — defaults: 80°C, 5s polling)
cp .env.example .env
# Edit .env:
# THERMAL_THRESHOLD_C=75
# THERMAL_POLL_SECONDS=5

# Start thermal monitoring alongside a running vLLM stack
docker compose -f docker-compose.thermal.yml up -d

# Stop thermal monitoring
docker compose -f docker-compose.thermal.yml down
```

The Makefile provides convenience targets:

```bash
make up-thermal      # start thermal monitoring only
make up-all          # start vllm stack + thermal monitoring
make down            # stop everything
```

### Option B: systemd

For bare-metal / non-Docker deployments, systemd units are provided under `vllm/thermal-guard/systemd/`.

```bash
cd vllm/thermal-guard/systemd
sudo ./install_dcgm_systemd.sh   # installs dcgm-exporter.service
sudo make install                 # installs vllm-thermal-guard.service
```

### Thermal Guard Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `THERMAL_THRESHOLD_C` | `80` | Stop vLLM when any GPU reaches this temperature (°C) |
| `THERMAL_POLL_SECONDS` | `5` | Polling interval in seconds |
| `EXPORTER_URL` | `http://dcgm-exporter:9400/metrics` | DCGM exporter endpoint |
| `CONTAINER_NAME` | `vllm` | Name of the container to stop on overtemp |
| `DOCKER_STOP_TIMEOUT` | `30` | Graceful stop timeout in seconds |

---

## Testing the API

A simple smoke-test script is provided under `vllm/llm-testing/`:

```bash
cd vllm/llm-testing
pip install -r requirements.txt   # or use the provided .venv
cp .env.example .env
# Edit .env: set VLLM_API_KEY and choose a MODEL

python test_llm_api.py
```

The script reads `API_BASE_URL`, `VLLM_API_KEY`, and `MODEL` from `.env` and sends a chat completion request to `$API_BASE_URL/v1/chat/completions`, printing the status code and response body.

---

## Environment Files

All `.env` files containing secrets are git-ignored. Each location ships a committed `.env.example` that is safe to track.

| `.env.example` location | Sensitive variables |
|-------------------------|--------------------|
| `vllm/llm-deployment/.env.example` | `VLLM_API_KEY` |
| `vllm/llm-testing/.env.example` | `VLLM_API_KEY`, `API_BASE_URL` |
| `vllm/thermal-guard/docker/.env.example` | _(none — thresholds only)_ |

Workflow for a fresh clone:

```bash
cp vllm/llm-deployment/.env.example   vllm/llm-deployment/.env
cp vllm/llm-testing/.env.example      vllm/llm-testing/.env
cp vllm/thermal-guard/docker/.env.example  vllm/thermal-guard/docker/.env
# Then edit each .env and set real values
```

---

## Security Notes

- **Never commit `.env` files.** They are git-ignored; only the `.env.example` templates are tracked.
- Generate a strong API key with `openssl rand -hex 32` and set it as `VLLM_API_KEY` in both `llm-deployment/.env` and `llm-testing/.env`.
- vLLM binds on an internal Docker network only; Caddy is the sole public-facing ingress point.
- The thermal guard container mounts the Docker socket (`/var/run/docker.sock`) — restrict access to this Docker network accordingly.
