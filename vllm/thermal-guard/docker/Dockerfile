# Lightweight container for thermal monitoring
FROM alpine:latest

# Install dependencies: curl for metrics, docker CLI to stop containers
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli

# Copy the thermal guard script
COPY thermal-guard-docker.sh /usr/local/bin/thermal-guard.sh
RUN chmod +x /usr/local/bin/thermal-guard.sh

# Run as non-root user for security (but needs docker socket access)
USER root

ENTRYPOINT ["/usr/local/bin/thermal-guard.sh"]
