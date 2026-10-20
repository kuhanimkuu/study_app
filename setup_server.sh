#!/usr/bin/env bash
# =============================================================================
# Study OS - one-time server setup for a fresh Ubuntu 24.04 VPS (Contabo).
#
# Usage (as root):
#   bash setup_server.sh                          # no domain yet: HTTP on the IP
#   bash setup_server.sh api.example.com you@example.com   # domain + HTTPS
#
# Safe to run again: it skips what is already done, keeps the existing .env
# (database password, JWT secret), and re-applies nginx/systemd config.
# Re-run it with a domain later to add HTTPS.
# =============================================================================
set -euo pipefail

DOMAIN="${1:-}"
EMAIL="${2:-}"

REPO_URL="https://github.com/kuhanimkuu/study_app.git"
BRANCH="main"
APP_USER="studyos"
APP_DIR="/opt/study_os"
ENV_FILE="$APP_DIR/.env"
DB_NAME="study_os"
DB_USER="study_os_app"
SERVICE="study-os"
APP_PORT="8000"
# Google Sign-In "Web application" client id (same value render.yaml uses).
GOOGLE_CLIENT_ID="396041418818-nj9krnthuc95trqosmgpoun0tkg3h30k.apps.googleusercontent.com"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warning] %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m[error] %s\033[0m\n' "$*"; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run this as root (log in as root, or use: sudo bash setup_server.sh)"
if [[ -n "$DOMAIN" && -z "$EMAIL" ]]; then
  fail "When you give a domain, also give an email for the HTTPS certificate: bash setup_server.sh $DOMAIN you@example.com"
fi
cd /

. /etc/os-release
if [[ "${VERSION_ID:-}" != "24.04" ]]; then
  warn "This script was tested on Ubuntu 24.04. You are on ${PRETTY_NAME:-unknown}. Continuing anyway."
fi

# ---------------------------------------------------------------------------
step "1/11  Swap file (2 GB safety net for memory spikes)"
if swapon --show | grep -q .; then
  echo "Swap already on - skipping."
else
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "2 GB swap added."
fi

# ---------------------------------------------------------------------------
step "2/11  System updates and packages (takes a few minutes)"
export DEBIAN_FRONTEND=noninteractive
# Ubuntu's needrestart can otherwise stop and ask which services to restart
# after the upgrade; "a" restarts them automatically.
export NEEDRESTART_MODE=a
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
apt-get update -q
apt-get upgrade "${APT_OPTS[@]}" -q
apt-get install "${APT_OPTS[@]}" -q \
  git curl openssl ca-certificates sudo cron \
  python3 python3-venv python3-dev build-essential \
  postgresql \
  nginx certbot python3-certbot-nginx \
  tesseract-ocr \
  ufw fail2ban unattended-upgrades

PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "Python $PY_VER"
[[ "$PY_VER" == "3.12" ]] || warn "Tested with Python 3.12; you have $PY_VER. If pip fails below, reinstall the VPS with Ubuntu 24.04."

# ---------------------------------------------------------------------------
step "3/11  Firewall (allow only SSH, HTTP, HTTPS) and brute-force protection"
# Open the port(s) SSH really uses - not just 22. Many VPSes run SSH on a
# custom port, and enabling the firewall without it locks you out (only the
# Contabo VNC console gets you back in). Ports come from sshd's own config,
# from Ubuntu 24.04's socket-activated ssh.socket (systemd owns the port
# there, not sshd) and from what sshd is listening on right now; 22 only if
# none of them finds anything.
SSH_PORTS=$( { sshd -T 2>/dev/null | awk '$1 == "port" {print $2}'
               systemctl show ssh.socket -p Listen --value 2>/dev/null | grep -oE ':[0-9]+ ' | tr -d ': '
               ss -tlnpH 2>/dev/null | awk '/"sshd"/ {n = split($4, a, ":"); print a[n]}'; } | sort -un | tr '\n' ' ')
[[ -n "${SSH_PORTS// /}" ]] || SSH_PORTS="22"
for port in $SSH_PORTS; do
  ufw allow "$port/tcp" comment 'SSH' >/dev/null
done
echo "SSH port(s) kept open: $SSH_PORTS"
ufw allow 'Nginx Full' >/dev/null
ufw --force enable >/dev/null
ufw status | sed -n '1,12p'
# fail2ban's sshd jail watches port 22 by default; point it at the real port(s).
mkdir -p /etc/fail2ban/jail.d
printf '[sshd]\nenabled = true\nport = %s\n' "$(echo "$SSH_PORTS" | xargs | tr ' ' ',')" > /etc/fail2ban/jail.d/study-os-sshd.local
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban >/dev/null 2>&1 || warn "fail2ban did not start - not critical, continuing."
systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
# The app's log (journald) records visitors' IP addresses; keep it at most 30
# days so the Privacy Policy can say so (nginx's own logs rotate after 14).
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nMaxRetentionSec=30day\n' > /etc/systemd/journald.conf.d/study-os.conf
systemctl restart systemd-journald

# ---------------------------------------------------------------------------
step "4/11  App user and code ($APP_DIR)"
if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "/home/$APP_USER" --shell /usr/sbin/nologin "$APP_USER"
  echo "Created user $APP_USER."
fi
if [[ -d "$APP_DIR/.git" ]]; then
  sudo -u "$APP_USER" -H git -C "$APP_DIR" pull --ff-only
else
  mkdir -p "$APP_DIR"
  chown "$APP_USER:$APP_USER" "$APP_DIR"
  sudo -u "$APP_USER" -H git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
fi
sudo -u "$APP_USER" -H git -C "$APP_DIR" log -1 --format='Code at commit %h (%ad): %s' --date=short

# ---------------------------------------------------------------------------
step "5/11  Python environment and packages (the slowest step, ~5-10 min)"
[[ -x "$APP_DIR/.venv/bin/python" ]] || sudo -u "$APP_USER" -H python3 -m venv "$APP_DIR/.venv"
sudo -u "$APP_USER" -H "$APP_DIR/.venv/bin/pip" install -q --upgrade pip wheel
sudo -u "$APP_USER" -H "$APP_DIR/.venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"
echo "Python packages installed."

# ---------------------------------------------------------------------------
step "6/11  Settings file (.env) with fresh secrets"
if [[ -f "$ENV_FILE" ]]; then
  echo ".env already exists - keeping it (same database password and JWT secret)."
  DB_PASS=$(sed -n "s#^DATABASE_URL=postgresql+asyncpg://$DB_USER:\([^@]*\)@.*#\1#p" "$ENV_FILE")
  [[ -n "$DB_PASS" ]] || fail "Could not read the database password from $ENV_FILE"
else
  DB_PASS=$(openssl rand -hex 24)
  JWT_SECRET=$(openssl rand -hex 32)
  cat > "$ENV_FILE" <<EOF
# Study OS production settings - created by setup_server.sh on $(date -u +%F).
# Keep this file private. Backed up nightly to /var/backups/study_os.
DATABASE_URL=postgresql+asyncpg://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME
JWT_SECRET=$JWT_SECRET
GOOGLE_OAUTH_CLIENT_ID=$GOOGLE_CLIENT_ID
# Browser origins allowed to call the API (only matters for a web build of the
# app; the Android app is not affected). Comma-separated.
CORS_ALLOWED_ORIGINS=*
# Optional: your own pooled AI keys for the hosted tier (leave unset for BYOK only).
# HOSTED_ANTHROPIC_API_KEY=
# HOSTED_OPENAI_API_KEY=
# HOSTED_DEEPSEEK_API_KEY=
EOF
  echo "Created $ENV_FILE with a new database password and JWT secret."
fi
if [[ -n "$DOMAIN" ]]; then
  sed -i "s#^CORS_ALLOWED_ORIGINS=.*#CORS_ALLOWED_ORIGINS=https://$DOMAIN#" "$ENV_FILE"
fi
chown "$APP_USER:$APP_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# ---------------------------------------------------------------------------
step "7/11  PostgreSQL database"
systemctl enable --now postgresql >/dev/null
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
  sudo -u postgres psql -q -c "ALTER ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS'"
else
  sudo -u postgres psql -q -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS'"
fi
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
  sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
fi
echo "Database '$DB_NAME' ready (only reachable from inside this server)."

step "      Creating/updating tables (alembic upgrade head)"
sudo -u "$APP_USER" -H bash -c "cd '$APP_DIR' && set -a && . ./.env && set +a && .venv/bin/alembic upgrade head"

# ---------------------------------------------------------------------------
step "8/11  Background service (starts on boot, restarts if it crashes)"
cat > "/etc/systemd/system/$SERVICE.service" <<EOF
[Unit]
Description=Study OS API (FastAPI/uvicorn)
After=network-online.target postgresql.service
Wants=network-online.target
Requires=postgresql.service

[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$ENV_FILE
Environment=FASTEMBED_CACHE_PATH=/home/$APP_USER/.cache/fastembed
# One worker on purpose: login rate limits and pending clarifications live in
# memory. --proxy-headers makes the real client IP (from nginx) visible to the app.
ExecStart=$APP_DIR/.venv/bin/uvicorn server.main:app --host 127.0.0.1 --port $APP_PORT --workers 1 --proxy-headers --forwarded-allow-ips 127.0.0.1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null
systemctl restart "$SERVICE"

# ---------------------------------------------------------------------------
step "9/11  nginx (website, API, upload limit, long AI timeouts)"
SERVER_NAME="${DOMAIN:-_}"
# The public website (website/, React + Vite) is built on a dev machine and
# uploaded here by website/deploy.sh, along with the APK in download/. A
# placeholder keeps "/" from erroring before the first upload.
SITE_DIR=/var/www/studyos
mkdir -p "$SITE_DIR/download"
[[ -f "$SITE_DIR/index.html" ]] || echo '<!doctype html><title>Study OS</title><p>Study OS — website coming soon.</p>' > "$SITE_DIR/index.html"
# Where the public website officially lives. Since 2026-10-20 it's on
# HelioHost, so this server only redirects its website pages there and keeps
# serving the API, chat files and the APK. Set it to "" to serve the website
# from $SITE_DIR on this server instead (website/deploy.sh --contabo).
WEBSITE_URL="https://studyos.helioho.st"
if [[ -n "$WEBSITE_URL" ]]; then
  WEBSITE_LOCATIONS="    # The website lives at $WEBSITE_URL — send its pages there.
    location / {
        return 301 $WEBSITE_URL\$request_uri;
    }
    # Let's Encrypt renewals still answer here.
    location ^~ /.well-known/acme-challenge/ {
    }"
else
  WEBSITE_LOCATIONS='    # The website: everything that isn'"'"'t the app'"'"'s API. Each page is a
    # pre-rendered folder (/features/ -> features/index.html).
    error_page 404 /404.html;
    location / {
        try_files $uri $uri/ =404;
    }
    # Vite'"'"'s built files have content hashes in their names — cache for good.
    location /assets/ {
        include snippets/study-os-headers.conf;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }'
fi
# Security headers for every response. A snippet, because nginx drops the
# server-level add_header lines in any location that sets its own headers —
# so each such location includes it again. The website runs no inline or
# third-party scripts, which is what lets script-src be 'self' only.
mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/study-os-headers.conf <<'EOF'
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
add_header Strict-Transport-Security "max-age=31536000" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'" always;
EOF
cat > /etc/nginx/sites-available/$SERVICE <<EOF
server {
    listen 80;
    server_name $SERVER_NAME;

    # Uploads are capped at 25 MB by the app; leave room for form overhead.
    client_max_body_size 30m;

    gzip on;
    gzip_types text/css application/javascript image/svg+xml application/json application/xml text/plain;

    include snippets/study-os-headers.conf;
    server_tokens off;

    root $SITE_DIR;
    index index.html;
$WEBSITE_LOCATIONS
    # The APK, served from here whichever host has the website.
    location ~* \.apk\$ {
        include snippets/study-os-headers.conf;
        # so Android recognises the file as an app to install
        types { application/vnd.android.package-archive apk; }
        add_header Content-Disposition "attachment";
    }

    # The app (FastAPI): its API and the files chats generate.
    location ~ ^/(api|generated)/ {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # AI answers (e.g. reasoning models) can take a while.
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/$SERVICE /etc/nginx/sites-enabled/$SERVICE
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

# ---------------------------------------------------------------------------
step "10/11  HTTPS certificate"
PUBLIC_IP=$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)
[[ -n "$PUBLIC_IP" ]] || PUBLIC_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$DOMAIN" ]]; then
  echo "No domain given - skipping HTTPS. Re-run with your domain once its DNS points here:"
  echo "  bash setup_server.sh api.yourdomain.com you@example.com"
else
  DNS_IP=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1 {print $1}' || true)
  if [[ -n "$PUBLIC_IP" && "$DNS_IP" != "$PUBLIC_IP" ]]; then
    warn "$DOMAIN points to '${DNS_IP:-nothing}', but this server is $PUBLIC_IP."
    warn "Fix the A record (and turn off any Cloudflare proxy/orange cloud), wait a few minutes, then re-run this script."
  elif certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect --keep-until-expiring; then
    echo "HTTPS is on for https://$DOMAIN (renews automatically)."
  else
    warn "Certificate request failed. Check the DNS record, then re-run this script."
  fi
fi

# ---------------------------------------------------------------------------
step "11/11  Nightly backups and the update command"
cat > /usr/local/bin/study-os-backup <<EOF
#!/usr/bin/env bash
# Nightly Study OS backup: database dump + uploaded/generated files + .env.
# Keeps 14 days in /var/backups/study_os. Download copies off the server now and then.
set -euo pipefail
umask 077
DEST=/var/backups/study_os
STAMP=\$(date +%F-%H%M)
mkdir -p "\$DEST"; chmod 700 "\$DEST"
cd /
# pg_dump runs as postgres; root writes the file (on purpose).
# shellcheck disable=SC2024
sudo -u postgres pg_dump -Fc $DB_NAME > "\$DEST/db-\$STAMP.dump"
PATHS=()
for p in .env server/uploads features/rag/projects/projects features/moderator/generated; do
  [[ -e "$APP_DIR/\$p" ]] && PATHS+=("\$p")
done
tar -czf "\$DEST/files-\$STAMP.tar.gz" -C "$APP_DIR" "\${PATHS[@]}"
find "\$DEST" -type f -mtime +14 -delete
echo "Backup done: \$DEST (\$STAMP)"
EOF
chmod 755 /usr/local/bin/study-os-backup
echo "30 2 * * * root /usr/local/bin/study-os-backup >> /var/log/study-os-backup.log 2>&1" > /etc/cron.d/study-os-backup
chmod 644 /etc/cron.d/study-os-backup

cat > /usr/local/bin/study-os-update <<EOF
#!/usr/bin/env bash
# Pull the latest code from GitHub ($BRANCH), install packages, migrate, restart.
set -euo pipefail
[[ \$EUID -eq 0 ]] || { echo "Run as root: sudo study-os-update"; exit 1; }
cd /
sudo -u $APP_USER -H git -C $APP_DIR pull --ff-only
sudo -u $APP_USER -H $APP_DIR/.venv/bin/pip install -q -r $APP_DIR/requirements.txt
sudo -u $APP_USER -H bash -c "cd $APP_DIR && set -a && . ./.env && set +a && .venv/bin/alembic upgrade head"
systemctl restart $SERVICE
for _ in \$(seq 1 60); do
  if curl -fsS http://127.0.0.1:$APP_PORT/api/health >/dev/null 2>&1; then
    echo "Updated and running: \$(sudo -u $APP_USER -H git -C $APP_DIR log -1 --format='%h %s')"; exit 0
  fi
  sleep 2
done
echo "App did not come back up. Check: journalctl -u $SERVICE -n 100"; exit 1
EOF
chmod 755 /usr/local/bin/study-os-update

cat > /usr/local/bin/study-os-import <<EOF
#!/usr/bin/env bash
# Copy all data from another Postgres database (e.g. Render's External Database
# URL) into this server's Study OS database, REPLACING what is here now.
# Usage: study-os-import "postgresql://user:pass@host/dbname"
set -euo pipefail
[[ \$EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
URL="\${1:-}"
[[ -n "\$URL" ]] || { echo 'Usage: study-os-import "postgresql://user:pass@host/dbname"'; exit 1; }
echo "This REPLACES all Study OS data on this server with the data from that database."
read -r -p "Type yes to continue: " OK
[[ "\$OK" == "yes" ]] || { echo "Cancelled."; exit 1; }
umask 077
cd /
DUMP=/root/import-\$(date +%F-%H%M).dump
echo "Downloading the other database..."
pg_dump "\$URL" -Fc -f "\$DUMP"
echo "Safety backup of the current data first..."
/usr/local/bin/study-os-backup
systemctl stop $SERVICE
echo "Restoring..."
if ! sudo -u postgres pg_restore --clean --if-exists --no-owner --no-privileges --role=$DB_USER -d $DB_NAME < "\$DUMP"; then
  echo "[warning] pg_restore reported some errors (often harmless). Check that you can log in."
fi
/usr/local/bin/study-os-update
echo "Import done. Users from the old server should log in again."
EOF
chmod 755 /usr/local/bin/study-os-import
echo "Backups run nightly at 02:30 server time. Update later with: study-os-update"

# ---------------------------------------------------------------------------
step "Waiting for the app to start (first start can take ~30 s)"
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:$APP_PORT/api/health" >/dev/null 2>&1; then
    APP_UP=1; break
  fi
  sleep 2
done
if [[ "${APP_UP:-0}" != 1 ]]; then
  fail "The app did not start. See the error with: journalctl -u $SERVICE -n 100 --no-pager"
fi

if [[ -n "$DOMAIN" ]] && [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
  BASE_URL="https://$DOMAIN"
else
  BASE_URL="http://${DOMAIN:-$PUBLIC_IP}"
fi

cat <<EOF

=====================================================================
 Study OS is running.

 API address:   $BASE_URL
 Health check:  $BASE_URL/api/health   (should show {"status":"ok"})

 Useful commands:
   systemctl status $SERVICE          is it running?
   journalctl -u $SERVICE -f          live logs (Ctrl+C to stop)
   systemctl restart $SERVICE         restart the app
   study-os-update                    pull new code from GitHub and restart
   study-os-backup                    run a backup now
   study-os-import "<postgres URL>"   copy data in from another database (e.g. Render)

 Settings file: $ENV_FILE
=====================================================================
EOF
