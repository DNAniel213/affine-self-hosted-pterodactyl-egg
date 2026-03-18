#!/bin/bash
# =============================================================================
# AFFiNE Pterodactyl — Runtime Entrypoint (baked into Docker image at build time)
#
# AFFiNE image internals (verified from upstream Dockerfile):
#   Base image : node:22-bookworm-slim
#   WORKDIR    : /app
#   CMD        : ["node", "./dist/main.js"]
#   Pre-deploy : node /app/scripts/self-host-predeploy.js
#                (generates EC private key, runs Prisma migrate deploy)
# =============================================================================

echo "========================================="
echo "  AFFiNE - Pterodactyl"
echo "  github.com/DNAniel213/affine-self-hosted-pterodactyl-egg"
echo "========================================="

# ---------------------------------------------------------------------------
# 1. Detect the runtime home directory.
#    AFFiNE's predeploy script calls Node's os.homedir() to resolve
#    ~/.affine/config and ~/.affine/storage. We match that exactly so our
#    symlinks target the right location regardless of which user runs the
#    container.
# ---------------------------------------------------------------------------
AFFINE_USER_HOME=$(node -e "const{homedir}=require('os');process.stdout.write(homedir())")
if [ -z "$AFFINE_USER_HOME" ]; then
    AFFINE_USER_HOME="/root"
fi
echo "[ptero] Home: $AFFINE_USER_HOME"

# ---------------------------------------------------------------------------
# 2. Persistent storage symlinks.
#    Pterodactyl guarantees /home/container persists across restarts.
#    AFFiNE reads/writes $HOME/.affine/{storage,config}.
#    Symlink those paths into /home/container so data survives reboots.
# ---------------------------------------------------------------------------
mkdir -p /home/container/storage
mkdir -p /home/container/config
mkdir -p /home/container/redis-data

mkdir -p "$AFFINE_USER_HOME/.affine"
rm -f "$AFFINE_USER_HOME/.affine/storage" "$AFFINE_USER_HOME/.affine/config"
ln -sfn /home/container/storage "$AFFINE_USER_HOME/.affine/storage"
ln -sfn /home/container/config  "$AFFINE_USER_HOME/.affine/config"
echo "[ptero] Symlinks: $AFFINE_USER_HOME/.affine/{storage,config} -> /home/container/{storage,config}"

# ---------------------------------------------------------------------------
# 3. Port forwarding.
#    Pterodactyl injects SERVER_PORT (the panel-allocated port).
#    AFFiNE reads AFFINE_SERVER_PORT.
# ---------------------------------------------------------------------------
export AFFINE_SERVER_PORT="${SERVER_PORT:-3010}"
echo "[ptero] Port: $AFFINE_SERVER_PORT"

# ---------------------------------------------------------------------------
# 4. Bundled Redis (conditional).
#    Starts the Redis bundled in this image when REDIS_SERVER_HOST is localhost
#    (the default). Set REDIS_SERVER_HOST to an external address to skip this.
# ---------------------------------------------------------------------------
REDIS_HOST="${REDIS_SERVER_HOST:-localhost}"

if [ "$REDIS_HOST" = "localhost" ] || [ "$REDIS_HOST" = "127.0.0.1" ]; then
    echo "[ptero] Starting bundled Redis..."
    redis-server /etc/redis/redis-ptero.conf \
        --daemonize yes \
        --pidfile /home/container/redis.pid \
        --dir /home/container/redis-data \
        --logfile /home/container/redis.log \
        --loglevel notice

    echo "[ptero] Waiting for Redis to be ready..."
    REDIS_READY=0
    for i in $(seq 1 30); do
        if redis-cli ping 2>/dev/null | grep -q PONG; then
            REDIS_READY=1
            break
        fi
        sleep 1
    done

    if [ "$REDIS_READY" != "1" ]; then
        echo "[ERROR] Bundled Redis did not respond within 30 seconds."
        echo "[ERROR] Check /home/container/redis.log for details."
        exit 1
    fi
    echo "[ptero] Bundled Redis ready."
else
    echo "[ptero] Using external Redis at ${REDIS_HOST}:${REDIS_SERVER_PORT:-6379}"
fi

# ---------------------------------------------------------------------------
# 5. Pre-deploy migration (idempotent — runs on every start).
#    - Generates /home/container/config/private.key on first boot if absent
#    - Runs Prisma migrate deploy (schema creation + upgrades)
# ---------------------------------------------------------------------------
echo "[ptero] Running AFFiNE pre-deploy migration..."
cd /app
if ! node scripts/self-host-predeploy.js; then
    echo "[ERROR] Pre-deploy migration failed."
    echo "[ERROR] Verify DATABASE_URL is set and reachable (PostgreSQL 16+ required)."
    exit 1
fi
echo "[ptero] Migration complete."

# ---------------------------------------------------------------------------
# 6. Start AFFiNE.
#    exec replaces this shell process — Wings monitors it correctly.
#    $@ is the CMD passed by Wings (e.g. node /app/dist/main.js).
#    Falls back to the upstream image CMD if Wings passes nothing.
# ---------------------------------------------------------------------------
echo "[ptero] Starting AFFiNE server..."
if [ "$#" -gt 0 ]; then
    exec "$@"
else
    exec node /app/dist/main.js
fi
