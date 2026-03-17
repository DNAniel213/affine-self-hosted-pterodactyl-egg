# =============================================================================
# AFFiNE Pterodactyl Egg - Custom Docker Image
# Based on the official AFFiNE image with Redis bundled for Pterodactyl hosting.
#
# Build args:
#   AFFINE_TAG  - one of: stable | beta | canary  (default: stable)
#
# This image is built and published automatically via GitHub Actions.
# Three tags are produced: stable, beta, canary
#
# Source: https://github.com/DNAniel213/affine-self-hosted-pterodactyl-egg
# =============================================================================

ARG AFFINE_TAG=stable
FROM ghcr.io/toeverything/affine:${AFFINE_TAG}

# Switch to root to install system packages
USER root

# Install Redis and openssl.
# The AFFiNE upstream image is Debian-based (Node.js official image lineage),
# so apt-get is available. If this ever breaks on an Alpine rebuild, swap to:
#   apk add --no-cache redis openssl
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        redis-server \
        openssl \
    && rm -rf /var/lib/apt/lists/*

# Copy the bundled Redis configuration for Pterodactyl mode.
# This config binds Redis to 127.0.0.1 only (safe for single-container use).
COPY conf/redis.conf /etc/redis/redis-ptero.conf

# Labels for GitHub Container Registry
LABEL org.opencontainers.image.source="https://github.com/DNAniel213/affine-self-hosted-pterodactyl-egg"
LABEL org.opencontainers.image.description="AFFiNE with bundled Redis — for Pterodactyl panel self-hosting"
LABEL org.opencontainers.image.licenses="MIT"

# Do NOT set ENTRYPOINT or CMD here.
# Pterodactyl Wings executes the egg's startup command directly inside the
# container. The start.sh script (installed to /home/container/start.sh by the
# egg's install script) handles all bootstrapping logic.
