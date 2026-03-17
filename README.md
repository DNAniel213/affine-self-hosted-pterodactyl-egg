# AFFiNE — Pterodactyl Egg

> Host [AFFiNE](https://affine.pro) — the next-gen knowledge base and workspace — on your Pterodactyl panel.

**Redis is bundled inside the container.** An external **PostgreSQL 16+** database is required.

---

## Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Step 1 — Build & Publish the Docker Image](#step-1--build--publish-the-docker-image)
- [Step 2 — Import the Egg into Pterodactyl](#step-2--import-the-egg-into-pterodactyl)
- [Step 3 — Create a Server](#step-3--create-a-server)
- [Step 4 — Configure Environment Variables](#step-4--configure-environment-variables)
- [Step 5 — Run the Installer](#step-5--run-the-installer)
- [Step 6 — Start the Server](#step-6--start-the-server)
- [Step 7 — Create Your Admin Account](#step-7--create-your-admin-account)
- [Reverse Proxy Setup](#reverse-proxy-setup)
- [Upgrading AFFiNE](#upgrading-affine)
- [Troubleshooting](#troubleshooting)
- [Appendix A — Using External Redis](#appendix-a--using-external-redis)
- [Appendix B — Pterodactyl Built-in Database Hosts (Limitations)](#appendix-b--pterodactyl-built-in-database-hosts-limitations)

---

## Architecture

AFFiNE's official deployment method is a four-service Docker Compose stack (AFFiNE app, PostgreSQL, Redis, Prometheus). Pterodactyl gives each server **one container** with one persistent volume. This egg bridges those two worlds:

| Concern | How it's handled |
|---|---|
| **AFFiNE app** | Runs directly inside the container from `ghcr.io/toeverything/affine` |
| **Redis** | Bundled inside our custom image (`ghcr.io/dnaniel213/affine-pterodactyl`) alongside the AFFiNE process. Started automatically at boot. |
| **PostgreSQL** | **External** — you provide a connection string. PostgreSQL 16+ is required. |
| **Persistent storage** | AFFiNE writes to `/root/.affine/{storage,config}`. The startup script symlinks these into `/home/container/` which is Pterodactyl's persistent volume. |
| **Schema migration** | AFFiNE's `self-host-predeploy.js` script is run on **every server start** (it is idempotent). This handles first-boot schema creation and post-upgrade migrations automatically. |

**Boot sequence:**
```
Pterodactyl starts container
  → start.sh runs
    → Detect AFFiNE installation directory
    → Create /home/container/{storage,config,redis-data} if missing
    → Symlink /root/.affine/{storage,config} → /home/container/
    → Set AFFINE_SERVER_PORT = Pterodactyl-allocated port
    → Start bundled Redis (unless REDIS_SERVER_HOST is set to an external host)
    → Run schema migration (node scripts/self-host-predeploy.js)
    → exec AFFiNE server process (becomes PID 1)
```

---

## Prerequisites

Before creating your first AFFiNE server, you need:

### 1. PostgreSQL 16+ Database

AFFiNE **requires PostgreSQL 16**. Most Pterodactyl panel built-in database hosts run older versions — see [Appendix B](#appendix-b--pterodactyl-built-in-database-hosts-limitations) for details.

**Recommended free options:**
- **[Supabase](https://supabase.com)** — Free tier includes PostgreSQL 15/16, 500 MB storage
- **[Neon](https://neon.tech)** — Free tier includes PostgreSQL 16, serverless-friendly

Create a database and note down your connection string in the format:
```
postgresql://USERNAME:PASSWORD@HOST:5432/DATABASE_NAME
```

### 2. A Pterodactyl Panel

Version 1.11+ recommended. Wings must be running on the nodes where you plan to deploy AFFiNE.

### 3. A GitHub Account (for the Docker image)

The egg uses a custom Docker image (`ghcr.io/dnaniel213/affine-pterodactyl`) that bundles Redis. You need to fork this repository and build/publish your own copy. See [Step 1](#step-1--build--publish-the-docker-image).

---

## Step 1 — Build & Publish the Docker Image

The egg requires a custom Docker image. This repo includes a GitHub Actions workflow that builds and publishes it automatically to GitHub Container Registry (GHCR).

1. **Fork this repository** on GitHub.

2. **Enable GitHub Actions** on your fork: go to your fork's **Actions** tab and click **"I understand my workflows, go ahead and enable them"** if prompted.

3. **Enable GHCR publishing**: go to your fork's **Settings → Actions → General → Workflow permissions** and select **"Read and write permissions"**.

4. **Trigger the first build**: push any change to `main`, or manually run the **"Build & Push Docker Images"** workflow from the Actions tab.

5. **Make the packages public**: after the first workflow run, go to your GitHub profile → **Packages** → find `affine-pterodactyl` → **Package settings** → set visibility to **Public**. (Required for Pterodactyl Wings to pull the image without credentials.)

6. **Note your image names** — they will be:
   - `ghcr.io/YOUR_GITHUB_USERNAME/affine-pterodactyl:stable`
   - `ghcr.io/YOUR_GITHUB_USERNAME/affine-pterodactyl:beta`
   - `ghcr.io/YOUR_GITHUB_USERNAME/affine-pterodactyl:canary`

> **If you forked this repo**, you must update the `docker_images` URLs in `egg-affine.json` to point to your own GHCR namespace before importing the egg. Open `egg-affine.json` and replace all occurrences of `dnaniel213` with your GitHub username.

---

## Step 2 — Import the Egg into Pterodactyl

1. Log in to your Pterodactyl **admin panel** (the `/admin` area).
2. Navigate to **Nests** in the left sidebar.
3. Either create a new Nest (e.g. "Productivity") or use an existing one.
4. Click **Import Egg** within the Nest.
5. Upload the `egg-affine.json` file from this repository.
6. The egg is now available in that Nest.

---

## Step 3 — Create a Server

Go to **Servers → Create New** in the admin panel.

### Resource Recommendations

| Resource | Minimum | Recommended |
|---|---|---|
| **RAM** | 2048 MB | 4096 MB |
| **CPU** | 200% (2 cores) | 400% (4 cores) |
| **Disk** | 4096 MB | 8192 MB+ |
| **Swap** | 512 MB | 1024 MB |

> Memory note: The 2 GB minimum covers AFFiNE + bundled Redis. AFFiNE's sync system can spike to 1 GB+  for large documents. 4 GB is strongly recommended for production use.

### Port Allocation

Assign the server **one port** from your node's allocation pool. AFFiNE will listen on whatever port you assign. The startup script automatically forwards `SERVER_PORT` (injected by Pterodactyl) to AFFiNE's `AFFINE_SERVER_PORT`.

If your panel's default port range conflicts with AFFiNE's default (3010), that's fine — any allocated port works.

### Nest / Egg

Select the Nest and Egg you imported in Step 2. Under **Docker Image**, choose:
- **AFFiNE Stable (Recommended)** — for production
- **AFFiNE Beta** — for early access features
- **AFFiNE Canary** — for the absolute latest (unstable)

---

## Step 4 — Configure Environment Variables

After creating the server, go to its **Startup** tab in the admin panel. Fill in all variables:

### Required Variables

| Variable | Description | Example |
|---|---|---|
| `AFFINE_PRIVATE_KEY` | 64-char hex key (from installer output). **Never change after data exists.** | `a3f2...` |
| `DATABASE_URL` | PostgreSQL 16+ connection string | `postgresql://user:pass@db.supabase.co:5432/affine` |
| `AFFINE_SERVER_HOST` | Your domain or public IP | `affine.example.com` |

### Optional but Recommended

| Variable | Description | Default |
|---|---|---|
| `AFFINE_SERVER_HTTPS` | Set `true` if behind an SSL reverse proxy | `false` |
| `AFFINE_SERVER_EXTERNAL_URL` | Full URL override (e.g. `https://affine.example.com`) | *(auto-computed)* |
| `AFFINE_REVISION` | Must match selected Docker image tag | `stable` |

### Redis Variables

Leave these at their defaults if using bundled Redis.

| Variable | Description | Default |
|---|---|---|
| `REDIS_SERVER_HOST` | `localhost` for bundled, or external hostname | `localhost` |
| `REDIS_SERVER_PORT` | Redis port | `6379` |
| `REDIS_SERVER_PASSWORD` | Redis password (blank for bundled) | *(blank)* |
| `REDIS_SERVER_DATABASE` | Starting DB index; AFFiNE uses N through N+4 | `0` |

### Email (Optional)

| Variable | Description |
|---|---|
| `MAILER_HOST` | SMTP server hostname (e.g. `smtp.gmail.com`) |
| `MAILER_PORT` | SMTP port (commonly `465` or `587`) |
| `MAILER_USER` | SMTP username |
| `MAILER_PASSWORD` | SMTP password (use App Password for Gmail) |
| `MAILER_SENDER` | From address (e.g. `AFFiNE <noreply@example.com>`) |

### Advanced

| Variable | Description | Default |
|---|---|---|
| `AFFINE_INDEXER_ENABLED` | Full-text search indexer (resource-intensive) | `false` |

---

## Step 5 — Run the Installer

On the server's page, click **Reinstall** (or it runs automatically on first server creation). Watch the console output in the admin panel.

At the end of a successful install, you will see:

```
=========================================
  INSTALLATION COMPLETE
=========================================

  >>> COPY THIS PRIVATE KEY NOW <<<
  Paste into your server's AFFINE_PRIVATE_KEY variable
  BEFORE starting. Do NOT change it after data exists.

  AFFINE_PRIVATE_KEY=a3f2c1d4e5b6...

  ...
=========================================
```

**Copy the `AFFINE_PRIVATE_KEY` value immediately** and paste it into the `AFFINE_PRIVATE_KEY` variable in the server's Startup tab. You will not be shown this key again (though you can reinstall to generate a new one — but only before any data exists).

---

## Step 6 — Start the Server

Click **Start** on the server's console page. You should see startup output like:

```
=========================================
  AFFiNE - Pterodactyl
=========================================
[ptero] AFFiNE found at: /app
[ptero] Persistent storage symlinks configured.
[ptero] Port: 3010
[ptero] Starting bundled Redis...
[ptero] Bundled Redis ready.
[ptero] Running migration...
[ptero] Migration complete.
[ptero] Starting AFFiNE server...

[Nest] LOG [NestApplication] Nest application successfully started
```

Once you see `Nest application successfully started`, AFFiNE is ready.

---

## Step 7 — Create Your Admin Account

Open a browser and navigate to:

```
http://<YOUR_SERVER_IP>:<ALLOCATED_PORT>/admin
```

(Or `https://affine.example.com/admin` if you've set up a reverse proxy with SSL.)

You will be redirected to a one-time admin registration page. Fill in your email and password to become the admin user. After this, the `/admin` page becomes the administration panel.

> You can also access the main AFFiNE workspace at `http://<SERVER>:<PORT>/` after creating your admin account.

---

## Reverse Proxy Setup

AFFiNE should be served behind a reverse proxy for production use. Set `AFFINE_SERVER_HTTPS=true` and `AFFINE_SERVER_HOST=affine.example.com` (and optionally `AFFINE_SERVER_EXTERNAL_URL=https://affine.example.com`) in your variables.

### Nginx

```nginx
server {
    listen 80;
    server_name affine.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name affine.example.com;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    # Required for AFFiNE's WebSocket-based sync system
    location / {
        proxy_pass http://127.0.0.1:3010;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
    }
}
```

### Caddy

```caddyfile
affine.example.com {
    reverse_proxy 127.0.0.1:3010 {
        transport http {
            dial_timeout 10s
        }
    }
}
```

Caddy auto-provisions TLS via Let's Encrypt. Replace `3010` with your allocated port.

---

## Upgrading AFFiNE

The migration script that runs on every boot (`self-host-predeploy.js`) handles schema upgrades automatically. To upgrade:

1. In the Pterodactyl admin panel, go to your server's **Configuration** tab.
2. Change the **Docker Image** to the same tag (e.g. switch from `stable` to `stable` does nothing, but the image will be re-pulled on next start).
3. To force a re-pull of the latest image, you can temporarily switch to `canary` and back to `stable`, or wait for Pterodactyl to pull the new image digest.

> **Best practice**: Before upgrading, back up your database with `pg_dump` and note the current AFFiNE version. See the [official AFFiNE upgrade guide](https://docs.affine.pro/self-host-affine/install/upgrade).

---

## Troubleshooting

### "Cannot locate AFFiNE" on startup

The startup script couldn't find `scripts/self-host-predeploy.js` in any of the expected directories. Verify the Docker image is set correctly. If the AFFiNE image has changed its directory structure, [open an issue](https://github.com/DNAniel213/affine-self-hosted-pterodactyl-egg/issues).

### "Bundled Redis failed to start"

Check `/home/container/redis.log` in the server's file manager. Common causes:
- `/home/container/redis-data` directory missing (run Reinstall to recreate it)
- Insufficient disk space

### "Migration failed. Verify DATABASE_URL"

Check that:
1. `DATABASE_URL` is correctly formatted: `postgresql://user:pass@host:5432/dbname`
2. The PostgreSQL server is reachable from the Pterodactyl node's network
3. PostgreSQL version is 16+ (`SELECT version();` in psql)
4. The database user has `CREATE TABLE` and `ALTER TABLE` permissions

### Server starts but is unreachable

1. Verify the port in your Pterodactyl allocation matches the port AFFiNE is listening on (check console output for `[ptero] Port: XXXX`)
2. Check your node's firewall allows the allocated port
3. Verify your reverse proxy config is pointing at the correct port

### "Nest application successfully started" never appears

AFFiNE may be failing silently after migration. Check if:
- The database migration output showed any errors
- Available RAM is sufficient (minimum 2 GB, 4 GB recommended)
- The AFFiNE entry point script was found (look for `[ptero] Starting AFFiNE server...` in the log)

---

## Appendix A — Using External Redis

By default, Redis runs bundled inside the container. This is convenient but means Redis data lives in `/home/container/redis-data/` (persistent across restarts, but not separate from your AFFiNE instance).

For high-availability setups or shared Redis deployments, you can point AFFiNE at an external Redis:

1. In the Pterodactyl admin panel, go to your server's **Startup** variables.
2. Set `REDIS_SERVER_HOST` to your external Redis hostname or IP.
3. Set `REDIS_SERVER_PORT` if non-standard.
4. Set `REDIS_SERVER_PASSWORD` if your Redis requires auth.
5. Set `REDIS_SERVER_DATABASE` to a starting index that doesn't conflict with other apps (AFFiNE uses N through N+4).

**Free external Redis options:**
- [Upstash](https://upstash.com) — Serverless Redis with a generous free tier
- Self-hosted Redis 6.x or 7.x on a separate VPS

When `REDIS_SERVER_HOST` is set to anything other than `localhost` or `127.0.0.1`, the bundled Redis will **not** be started.

---

## Appendix B — Pterodactyl Built-in Database Hosts (Limitations)

Pterodactyl panels have a built-in database host manager that provisions MySQL/MariaDB databases for game servers. **This does NOT work for AFFiNE** for two reasons:

1. **AFFiNE only supports PostgreSQL** — MySQL and MariaDB are not supported at all.
2. **PostgreSQL 16 is required** — Even if a panel admin adds a PostgreSQL host, it must be version 16+.

**Do not** use the Pterodactyl panel's "Create Database" button for AFFiNE. Instead, provision a separate PostgreSQL 16+ database via one of the providers listed in the [Prerequisites](#prerequisites) section and paste the full connection URL into `DATABASE_URL`.

---

## Contributing

Pull requests are welcome. For significant changes, open an issue first to discuss your proposal.

If the AFFiNE image changes its internal directory structure and breaks the startup script's entry point detection, please open an issue with the new path information.

## License

[MIT](LICENSE)
