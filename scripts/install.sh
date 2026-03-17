#!/bin/bash
# =============================================================================
# AFFiNE Pterodactyl - One-Time Installation Script
# =============================================================================
# Runs inside: ghcr.io/pterodactyl/installers:alpine
# Writes to:   /mnt/server/  (becomes /home/container/ at runtime)
#
# This script is the REFERENCE copy. The canonical version embedded in
# egg-affine.json is what Pterodactyl actually executes. Keep them in sync.
# =============================================================================

# Install required tools (Alpine doesn't have openssl by default)
apk add --no-cache openssl bash 2>/dev/null || true

echo "========================================="
echo "  AFFiNE - Pterodactyl Installer"
echo "  github.com/DNAniel213/affine-self-hosted-pterodactyl-egg"
echo "========================================="
echo ""

# ---------------------------------------------------------------------------
# Create persistent data directories inside the server's file volume.
# These directories survive container restarts because /home/container
# (which maps to /mnt/server here) is the Pterodactyl persistent mount.
# ---------------------------------------------------------------------------
mkdir -p /mnt/server/storage
mkdir -p /mnt/server/config
mkdir -p /mnt/server/redis-data
echo "[install] Persistent directories created:"
echo "[install]   /home/container/storage    <- blob/file uploads"
echo "[install]   /home/container/config     <- AFFiNE config files"
echo "[install]   /home/container/redis-data <- bundled Redis RDB snapshots"
echo ""

# ---------------------------------------------------------------------------
# Write the runtime startup script to the persistent volume.
# On every server start, Pterodactyl executes: bash /home/container/start.sh
# ---------------------------------------------------------------------------
cat > /mnt/server/start.sh << 'AFFINE_START_SCRIPT'
#!/bin/bash
echo "========================================="
echo "  AFFiNE - Pterodactyl"
echo "  github.com/DNAniel213/affine-self-hosted-pterodactyl-egg"
echo "========================================="

AFFINE_HOME=""
for candidate in /app /affine /srv/affine /home/affine; do
    if [ -f "$candidate/scripts/self-host-predeploy.js" ]; then
        AFFINE_HOME="$candidate"
        break
    fi
done
if [ -z "$AFFINE_HOME" ]; then
    echo "[ERROR] Cannot locate AFFiNE (scripts/self-host-predeploy.js not found)."
    echo "[ERROR] Is the Docker image set to ghcr.io/dnaniel213/affine-pterodactyl:stable?"
    exit 1
fi
echo "[ptero] AFFiNE found at: $AFFINE_HOME"

mkdir -p /home/container/storage /home/container/config /home/container/redis-data
mkdir -p /root/.affine
rm -f /root/.affine/storage /root/.affine/config
ln -sfn /home/container/storage /root/.affine/storage
ln -sfn /home/container/config  /root/.affine/config
echo "[ptero] Persistent storage symlinks configured."

export AFFINE_SERVER_PORT="${SERVER_PORT:-3010}"
echo "[ptero] Port: $AFFINE_SERVER_PORT"

REDIS_HOST="${REDIS_SERVER_HOST:-localhost}"
if [ "$REDIS_HOST" = "localhost" ] || [ "$REDIS_HOST" = "127.0.0.1" ]; then
    echo "[ptero] Starting bundled Redis..."
    redis-server /etc/redis/redis-ptero.conf \
        --daemonize yes \
        --dir /home/container/redis-data \
        --logfile /home/container/redis.log \
        --loglevel notice
    REDIS_READY=0
    for i in $(seq 1 30); do
        if redis-cli ping 2>/dev/null | grep -q PONG; then
            REDIS_READY=1
            break
        fi
        echo "[ptero]   waiting for Redis ($i/30)..."
        sleep 1
    done
    if [ "$REDIS_READY" != "1" ]; then
        echo "[ERROR] Bundled Redis failed. Check /home/container/redis.log"
        exit 1
    fi
    echo "[ptero] Bundled Redis ready."
else
    echo "[ptero] External Redis: ${REDIS_HOST}:${REDIS_SERVER_PORT:-6379}"
fi

echo "[ptero] Running migration..."
cd "$AFFINE_HOME"
if ! node scripts/self-host-predeploy.js; then
    echo "[ERROR] Migration failed. Verify DATABASE_URL and PostgreSQL 16+ connectivity."
    exit 1
fi
echo "[ptero] Migration complete."

echo "[ptero] Starting AFFiNE server..."
if [ -f "$AFFINE_HOME/packages/backend/server/dist/index.js" ]; then
    exec node "$AFFINE_HOME/packages/backend/server/dist/index.js"
elif [ -f "$AFFINE_HOME/dist/index.js" ]; then
    exec node "$AFFINE_HOME/dist/index.js"
elif [ -f "$AFFINE_HOME/packages/backend/server/dist/main.js" ]; then
    exec node "$AFFINE_HOME/packages/backend/server/dist/main.js"
else
    echo "[ERROR] Cannot find AFFiNE entry point. Please report:"
    echo "        https://github.com/DNAniel213/affine-self-hosted-pterodactyl-egg/issues"
    ls -la "$AFFINE_HOME/" 2>/dev/null || true
    exit 1
fi
AFFINE_START_SCRIPT

chmod +x /mnt/server/start.sh
echo "[install] Startup script written to /home/container/start.sh"
echo ""

# ---------------------------------------------------------------------------
# Generate AFFINE_PRIVATE_KEY
# This 64-character hex key is used to sign auth tokens and encrypt data.
# It MUST be set before first boot and MUST NOT change after data is written.
# ---------------------------------------------------------------------------
PRIVATE_KEY="$(openssl rand -hex 32)"

echo "========================================="
echo "  INSTALLATION COMPLETE"
echo "========================================="
echo ""
echo "  >>> ACTION REQUIRED: COPY THIS KEY NOW <<<"
echo ""
echo "  Paste the following into your server's AFFINE_PRIVATE_KEY variable"
echo "  in the Pterodactyl panel before starting. It CANNOT be changed"
echo "  after your instance has data — changing it will break all logins."
echo ""
echo "  AFFINE_PRIVATE_KEY=${PRIVATE_KEY}"
echo ""
echo "  ============================================"
echo ""
echo "  REQUIRED VARIABLES (set before first start):"
echo "  1. AFFINE_PRIVATE_KEY  <- see above"
echo "  2. DATABASE_URL        <- PostgreSQL 16+ connection string"
echo "     Format: postgresql://user:password@host:5432/dbname"
echo "     Recommended free option: Supabase (https://supabase.com)"
echo ""
echo "  3. AFFINE_SERVER_HOST  <- your domain (e.g. affine.example.com)"
echo "     or your server's public IP for HTTP-only testing."
echo ""
echo "  OPTIONAL:"
echo "  4. AFFINE_SERVER_HTTPS <- set to 'true' when behind an SSL reverse proxy"
echo "  5. REDIS_SERVER_HOST   <- leave as 'localhost' for bundled Redis (default)"
echo "     Set to an external host to use your own Redis 6.x/7.x instance."
echo ""
echo "  Full setup guide:"
echo "  https://github.com/DNAniel213/affine-self-hosted-pterodactyl-egg#readme"
echo "========================================="
