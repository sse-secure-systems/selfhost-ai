# local-llms

A self-hosted LLM environment supporting both **Ollama** and **vLLM** deployments. The primary focus is running a vLLM inference server that exposes an **OpenAI-compatible Chat Completions API**, fronted by a Caddy reverse proxy and protected by GPU thermal monitoring.

The repository ships ready-to-use compose templates for a selection of models, but is not limited to them — any model supported by vLLM can be added by following the same pattern.

All services are deployed via **Docker Compose**.

---

## Project Structure

```text
selfhost-ai/
├── models/                          # Model weights — one subdirectory per model,
│                                    # mounted read-only into the vLLM container
│
├── ollama/                          # Ollama + Open WebUI deployment
│   └── docker-compose.yml
│
└── vllm/
    ├── llm-deployment/              # Per-model vLLM + Caddy Docker Compose stacks
    │   ├── Caddyfile
    │   └── docker-compose.<model-name>.yml   # one file per model
    │
    ├── llm-testing/                 # API smoke-test script
    │   └── test_llm_api.py
    │
    ├── thermal-guard/               # GPU temperature monitoring & auto-shutdown
    │   ├── docker/                  # Docker Compose-based deployment (recommended)
    │   │   ├── Dockerfile
    │   │   ├── docker-compose.thermal.yml
    │   │   ├── thermal-guard-docker.sh
    │   │   ├── Makefile
    │   │   ├── QUICKSTART.md
    │   │   └── README-docker.md
    │   └── systemd/                 # Alternative bare-metal deployment
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

## Tech Stack

| Component | Image / Tool |
|-----------|-------------|
| Inference engine | `nvcr.io/nvidia/vllm:26.01-py3` |
| Reverse proxy | `caddy:latest` |
| GPU metrics | `nvidia/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04` |
| Thermal guard | `alpine:latest` (custom script) |
| Ollama + WebUI | `ghcr.io/open-webui/open-webui:ollama` |
| Orchestration | Docker Compose v2 |

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

Caddy forwards all traffic to vLLM with response streaming enabled (`flush_interval -1`) and a 20-minute read timeout to accommodate slow generation on large models.

### Configuration

Create the `.env` file from the example and set your API key:

```bash
cd vllm/llm-deployment
cp .env.example .env
# Edit .env and set VLLM_API_KEY
```

The only required variable is:

```env
# Generate a strong key: openssl rand -hex 32
VLLM_API_KEY="your-secret-key-here"
```

> `.env` is git-ignored and must never be committed.

### Starting a Model

```bash
cd vllm/llm-deployment

# Example: Ministral 8B
docker compose -f docker-compose.Ministral-3-8B-Instruct-2512.yml up -d

# Example: Devstral 123B
docker compose -f docker-compose.Devstral-2-123B-Instruct-2512.yml up -d
```

vLLM performs a health check at `GET /health` every 15 seconds with a 10-minute startup grace period. Caddy will not accept traffic until vLLM reports healthy. Allow up to **10 minutes** for large models to load.

### Stopping a Stack

```bash
docker compose -f docker-compose.<model>.yml down
```

### API Usage

The API is OpenAI-compatible and reachable at `http://<host>/v1/`.

```bash
curl http://localhost/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d '{
    "model": "Ministral-3-8B-Instruct-2512",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

> **Note for Mistral-family models:** The compose files pass `--tokenizer_mode mistral`, `--config_format mistral`, and `--load_format mistral` to use Mistral's native weight format. Without these flags vLLM falls back to the HuggingFace loader, which misidentifies these models as a Pixtral vision model and crashes at startup.

> **Note for structured output (xgrammar):** Ministral models with structured output enabled can generate indefinitely without hitting a natural stop token. Always pass `max_tokens` in client API calls when using structured output.

### Included Model Templates

The following models have ready-to-use compose files. These serve as templates — the repo is not limited to these models.

| Model | Compose File | Notes |
|-------|-------------|-------|
| Ministral-3-3B-Instruct-2512 | `docker-compose.Ministral-3-3B-Instruct-2512.yml` | Mistral native format, tool calling |
| Ministral-3-8B-Instruct-2512 | `docker-compose.Ministral-3-8B-Instruct-2512.yml` | Mistral native format, tool calling |
| Ministral-3-14B-Instruct-2512 | `docker-compose.Ministral-3-14B-Instruct-2512.yml` | Mistral native format, tool calling |
| Devstral-2-123B-Instruct-2512 | `docker-compose.Devstral-2-123B-Instruct-2512.yml` | 123B, async scheduling |
| gpt-oss-20B | `docker-compose.gpt-oss-20B.yml` | async scheduling |
| gpt-oss-120B | `docker-compose.gpt-oss-120B.yml` | async scheduling |

Model weights must be present in the corresponding `models/<model-name>/` directory before starting the stack.

### Adding a Model

#### Step 1 — Download the model weights

Use the Hugging Face CLI to download weights into `models/`:

```bash
pip install huggingface-hub
huggingface-cli download <org>/<model-name> --local-dir models/<model-name>
```

The directory name under `models/` is what gets mounted into the container and passed to `vllm serve`.

#### Step 2 — Create a compose file

Copy the closest existing template and rename it:

```bash
cp vllm/llm-deployment/docker-compose.Ministral-3-8B-Instruct-2512.yml \
   vllm/llm-deployment/docker-compose.<model-name>.yml
```

Edit the new file and update:

- `volumes` — change the host path to `../../models/<model-name>`
- `command` — update the model path and any model-specific vLLM flags
  - Mistral-family models require `--tokenizer_mode mistral --config_format mistral --load_format mistral`
  - Standard HuggingFace models do not need these flags
- `mem_limit` / `memswap_limit` — adjust to the model's size
- `container_name` — keep as `vllm` unless running multiple stacks simultaneously

#### Step 3 — Start the stack

```bash
cd vllm/llm-deployment
docker compose -f docker-compose.<model-name>.yml up -d
```

---

## Ollama Deployment

Ollama is bundled inside the **Open WebUI** image and deployed as a single container.

```bash
cd ollama
docker compose up -d
```

Open WebUI is accessible at `http://localhost:8080`. Manage models through the Open WebUI interface.

> **Note:** Port 11434 (Ollama API) is not exposed externally in the current compose file. To use the Ollama CLI from the host, exec into the container: `docker exec -it open-webui-compose ollama ...`

---

## Thermal Guard — GPU Temperature Monitoring

The thermal guard protects GPU(s) from overheating by stopping the vLLM container when a temperature threshold is exceeded. It does **not** auto-restart the container after cooling — that decision is left to the operator to prevent thermal oscillation.

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

See [vllm/thermal-guard/docker/README-docker.md](vllm/thermal-guard/docker/README-docker.md) and [vllm/thermal-guard/docker/QUICKSTART.md](vllm/thermal-guard/docker/QUICKSTART.md) for full details.

```bash
cd vllm/thermal-guard/docker

# Optional: set a custom threshold (default: 80°C, 5s polling)
cat > .env << 'EOF'
THERMAL_THRESHOLD_C=75
THERMAL_POLL_SECONDS=5
EOF

# Start thermal monitoring (requires a vLLM stack to already be running)
docker compose -f docker-compose.thermal.yml up -d

# Stop thermal monitoring
docker compose -f docker-compose.thermal.yml down
```

The Makefile provides convenience targets:

```bash
make up              # start thermal monitoring only
make down            # stop thermal monitoring
make logs            # follow all thermal service logs
make logs-thermal    # follow thermal-guard logs only
make logs-dcgm       # follow DCGM exporter logs only
make status          # show service status
make health          # show health check status
make test-metrics    # verify DCGM exporter is returning GPU temp data
make rebuild         # rebuild the thermal-guard image and restart
```

> **Note:** The `make up-all` target references a `../docker-compose.yml` path that does not exist in this repository layout. Start the vLLM stack and thermal guard separately using the compose files in `vllm/llm-deployment/` and `vllm/thermal-guard/docker/` respectively.

### Option B: systemd

For bare-metal deployments (dcgm-exporter installed directly on the host), systemd units are provided under `vllm/thermal-guard/systemd/`.

```bash
cd vllm/thermal-guard/systemd
sudo make install    # installs dcgm-exporter.service + vllm-thermal-guard.service
sudo make start      # start both services
make logs            # follow journal output
sudo make uninstall  # remove services
```

### Thermal Guard Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `THERMAL_THRESHOLD_C` | `80` | Stop vLLM when any GPU reaches this temperature (°C) |
| `THERMAL_POLL_SECONDS` | `5` | Polling interval in seconds |
| `EXPORTER_URL` | `http://dcgm-exporter:9400/metrics` | DCGM exporter Prometheus endpoint |
| `CONTAINER_NAME` | `vllm` | Name of the container to stop on overtemp |
| `DOCKER_STOP_TIMEOUT` | `30` | Graceful stop timeout in seconds |

The DCGM exporter also exposes metrics on host port `9400`, which can be scraped by Prometheus.

---

## Testing the API

A smoke-test script is provided under `vllm/llm-testing/`. It requires `requests` and `python-dotenv`:

```bash
cd vllm/llm-testing
pip install requests python-dotenv

# Create .env with your connection details
cat > .env << 'EOF'
VLLM_API_KEY=your-secret-key-here
API_BASE_URL=http://localhost
MODEL=Ministral-3-8B-Instruct-2512
EOF

python test_llm_api.py
```

The script sends a single chat completion request to `$API_BASE_URL/v1/chat/completions` and prints the HTTP status code and response body.

---

## Environment Files

All `.env` files are git-ignored. Each location has a committed `.env.example` with safe defaults. On a fresh clone:

```bash
cp vllm/llm-deployment/.env.example        vllm/llm-deployment/.env
cp vllm/llm-testing/.env.example           vllm/llm-testing/.env
cp vllm/thermal-guard/docker/.env.example  vllm/thermal-guard/docker/.env
```

Then edit each `.env` and fill in the required values:

| Location | Variables |
|----------|-----------|
| `vllm/llm-deployment/.env` | `VLLM_API_KEY` |
| `vllm/llm-testing/.env` | `VLLM_API_KEY`, `API_BASE_URL`, `MODEL` |
| `vllm/thermal-guard/docker/.env` | `THERMAL_THRESHOLD_C`, `THERMAL_POLL_SECONDS`, `LLM_CONTAINER_NAME` |

---

## Security Notes

- **Never commit `.env` files.** They are git-ignored.
- Generate a strong API key: `openssl rand -hex 32`. Set the same value as `VLLM_API_KEY` in both `llm-deployment/.env` and `llm-testing/.env`.
- vLLM binds only on an internal Docker bridge network; Caddy is the sole public-facing ingress point.
- The thermal guard container mounts the Docker socket (`/var/run/docker.sock`) to stop containers on overtemp. Restrict access to the host socket accordingly.

---

## Known Gaps

- The `make up-all` target in `vllm/thermal-guard/docker/Makefile` references `../docker-compose.yml`, which does not exist. Start the LLM stack and thermal monitoring separately.
- TLS (HTTPS) is not configured in the provided `Caddyfile`. To enable it, update `Caddyfile` with your domain and Caddy will obtain a certificate automatically via ACME.
