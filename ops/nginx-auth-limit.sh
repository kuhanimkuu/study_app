#!/usr/bin/env bash
# Adds nginx's per-address limit on /api/auth/ (login, signup, Google
# sign-in) to an existing Study OS server — the same block setup_server.sh
# writes for new servers. Safe to run again; run as root on the server:
#   bash nginx-auth-limit.sh [port]
#
# Generous on purpose: a whole class on one school Wi-Fi shares one public
# address. 1 request a second with a burst of 60 lets that through, while a
# single machine firing thousands is turned away by nginx before the app
# sees it (the app's own limits and password lanes handle the rest — see
# server/core/security.py).
set -euo pipefail
SITE=/etc/nginx/sites-available/study-os
APP_PORT=${1:-8000}

cat > /etc/nginx/conf.d/study-os-limits.conf <<'EOF'
# Per-address request budget for /api/auth/ (see the study-os site file).
limit_req_zone $binary_remote_addr zone=study_os_auth:10m rate=60r/m;
EOF

if ! grep -q "location ^~ /api/auth/" "$SITE"; then
  cp "$SITE" "$SITE.bak-$(date +%F-%H%M)"
  python3 - "$SITE" "$APP_PORT" <<'PYEOF'
import sys
path, port = sys.argv[1], sys.argv[2]
s = open(path).read()
anchor = "    location ~ ^/(api|generated)/ {"
assert s.count(anchor) == 1, "anchor not found exactly once"
block = f"""    # Login/signup: per-address limit, answered in JSON like the app's own
    # errors. ^~ so it wins over the regex location below.
    location ^~ /api/auth/ {{
        limit_req zone=study_os_auth burst=60 nodelay;
        limit_req_status 429;
        error_page 429 = @auth_limited;
        proxy_pass http://127.0.0.1:{port};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }}
    location @auth_limited {{
        default_type application/json;
        return 429 '{{"detail":"too many attempts — please try again later"}}';
    }}

"""
open(path, "w").write(s.replace(anchor, block + anchor))
PYEOF
fi
nginx -t
systemctl reload nginx
echo "nginx auth limit active"
