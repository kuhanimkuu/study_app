#!/usr/bin/env bash
# Brings an existing server's APK download in line with setup_server.sh:
# the file is saved under the name it's served as (study-os-<version>.apk,
# see website/deploy.sh). Firefox for Android crashed downloading it with a
# bare "attachment" (2026-10-21). Safe to run again; run as root:
#   bash apk-download-name.sh
set -euo pipefail
SITE=/etc/nginx/sites-available/study-os
if ! grep -q 'filename=$1' "$SITE"; then
  cp "$SITE" "$SITE.bak-$(date +%F-%H%M)"
  python3 - "$SITE" <<'PYEOF'
import re, sys
path = sys.argv[1]
s = open(path).read()
s, n1 = re.subn(r"location ~\* \\\.apk\$ \{", r"location ~* /([^/]+\\.apk)$ {", s)
s, n2 = re.subn(r'add_header Content-Disposition "attachment[^"]*";', 'add_header Content-Disposition "attachment; filename=$1";', s)
assert n1 == 1 and n2 == 1, (n1, n2)
open(path, "w").write(s)
PYEOF
fi
nginx -t
systemctl reload nginx
echo "APK downloads are saved under their own (versioned) name"
