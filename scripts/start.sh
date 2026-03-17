#!/bin/bash
# =============================================================================
# AFFiNE Pterodactyl - Runtime Startup Script
# =============================================================================
# This script runs INSIDE the AFFiNE container on every server start.
# It is installed to /home/container/start.sh by the egg's install script.
#
# Responsibilities (in order):
#   1. Detect the AFFiNE installation directory inside the container image
#   2. Create symlinks from /root/.affine -> /home/container persistent dirs
#   3. Forward the Pterodactyl-allocated port to AFFiNE
#   4. Start bundled Redis (if REDIS_SERVER_HOST is localhost/127.0.0.1)
#   5. Run AFFiNE's idempotent pre-deploy migration script
#   6. Start the AFFiNE Node.js server in the foreground
# =============================================================================

echo "========================================="
echo "  AFFiNE - Pterodactyl"
echo "  github.com/DNAniel213/affine-self-hosted-pterodactyl-egg"
echo "========================================="

# ---------------------------------------------------------------------------
# 1. Auto-detect AFFiNE installation directory
#    The migration script is the most reliable landmark across image versions.
# ---------------------------------------------------------------------------
AFFINE_HOME=""
for candidate in /app /affine /srv/affine /home/affine; do
    if [ -f "$candidate/scripts/self-host-predeploy.js" ]; then
        AFFINE_HOME="$candidate"
        break
    fi
done

if [ -z "$AFFINE_HOME" ]; then
    echo "[ERROR] Cannot locate AFFiNE installation (scripts/self-host-predeploy.js not found)."
    echo "[ERROR] Is the Docker image set correctly in the Pterodactyl egg?"
    echo "[ERROR] Expected image: ghcr.io/dnaniel213/affine-pterodactyl:stable (or beta/canary)"
    exit 1
fi
echo "[ptero] AFFiNE found at: $AFFINE_HOME"

# ---------------------------------------------------------------------------
# 2. Persistent storage symlinks
#    Pterodactyl only guarantees /home/container is persistent across restarts.
#    AFFiNE writes user data and config to /root/.affine/{storage,config}.
#    We bridge the two with symlinks on every boot.
# ---------------------------------------------------------------------------
mkdir -p /home/container/storage
mkdir -p /home/container/config
mkdir -p /home/container/redis-data

mkdir -p /root/.affine

# Remove stale symlinks before recreating them
rm -f /root/.affine/storage /root/.affine/config
ln -sfn /home/container/storage /root/.affine/storage
ln -sfn /home/container/config  /root/.affine/config
echo "[ptero] Persistent storage symlinks configured."

# ---------------------------------------------------------------------------
# 3. Port forwarding
#    Pterodactyl automatically injects SERVER_PORT with the panel-allocated port.
#    We pass it through to AFFiNE via AFFINE_SERVER_PORT.
# ---------------------------------------------------------------------------
export AFFINE_SERVER_PORT="${SERVER_PORT:-3010}"
echo "[ptero] AFFiNE will listen on port: $AFFINE_SERVER_PORT"

# ---------------------------------------------------------------------------
# 4. Bundled Redis startup (conditional)
#    If REDIS_SERVER_HOST is localhost or 127.0.0.1 (the default), start the
#    Redis instance bundled into our custom Docker image.
#    If set to an external host, skip this step entirely.
# ---------------------------------------------------------------------------
REDIS_HOST="${REDIS_SERVER_HOST:-localhost}"

if [ "$REDIS_HOST" = "localhost" ] || [ "$REDIS_HOST" = "127.0.0.1" ]; then
    echo "[ptero] Starting bundled Redis server..."

    redis-server /etc/redis/redis-ptero.conf \
        --daemonize yes \
        --dir /home/container/redis-data \
        --logfile /home/container/redis.log \
        --loglevel notice

    echo "[ptero] Waiting for Redis to become ready..."
    REDIS_READY=0
    for i in $(seq 1 30); do
        if redis-cli ping 2>/dev/null | grep -q PONG; then
            REDIS_READY=1
            break
        fi
        echo "[ptero]   ... waiting ($i/30)"
        sleep 1
    done

    if [ "$REDIS_READY" != "1" ]; then
        echo "[ERROR] Bundled Redis failed to start after 30 seconds."
        echo "[ERROR] Check the Redis log at /home/container/redis.log"
        echo "[ERROR] Alternatively, set REDIS_SERVER_HOST to an external Redis instance."
        exit 1
    fi
    echo "[ptero] Bundled Redis is ready."
else
    echo "[ptero] Using external Redis at ${REDIS_HOST}:${REDIS_SERVER_PORT:-6379}"
fi

# ---------------------------------------------------------------------------
# 5. Database migration
#    The migration script is idempotent — safe to run on every restart.
#    It handles schema creation on first boot and schema upgrades on restarts
#    after an image update. Never skip this step.
# ---------------------------------------------------------------------------
echo "[ptero] Running AFFiNE pre-deploy migration..."
cd "$AFFINE_HOME"
if ! node scripts/self-host-predeploy.js; then
    echo "[ERROR] Database migration failed."
    echo "[ERROR] Common causes:"
    echo "[ERROR]   - DATABASE_URL is wrong or the database is unreachable"
    echo "[ERROR]   - PostgreSQL version is below 16 (required by AFFiNE 0.21+)"
    echo "[ERROR]   - The database user lacks CREATE/ALTER TABLE permissions"
    exit 1
fi
echo "[ptero] Migration complete."

# ---------------------------------------------------------------------------
# 6. Start AFFiNE server
#    Check known entry point paths across AFFiNE image versions.
#    'exec' replaces this shell process with AFFiNE — Pterodactyl's Wings
#    monitor will track it correctly.
# ---------------------------------------------------------------------------
echo "[ptero] Starting AFFiNE server..."

if [ -f "$AFFINE_HOME/packages/backend/server/dist/index.js" ]; then
    exec node "$AFFINE_HOME/packages/backend/server/dist/index.js"
elif [ -f "$AFFINE_HOME/dist/index.js" ]; then
    exec node "$AFFINE_HOME/dist/index.js"
elif [ -f "$AFFINE_HOME/packages/backend/server/dist/main.js" ]; then
    exec node "$AFFINE_HOME/packages/backend/server/dist/main.js"
else
    echo "[ERROR] Cannot find AFFiNE server entry point. Directory listing:"
    ls -la "$AFFINE_HOME/" 2>/dev/null || true
    echo ""
    echo "[ERROR] The upstream AFFiNE image may have changed its structure."
    echo "[ERROR] Please open an issue at:"
    echo "[ERROR]   https://github.com/DNAniel213/affine-self-hosted-pterodactyl-egg/issues"
    exit 1
fi
