#!/usr/bin/env bash
# Gives the APK download a file name (Content-Disposition), as
# setup_server.sh now does for new servers. Firefox for Android crashed
# downloading it with a bare "attachment" (2026-10-21). Safe to run again;
# run as root on the server:  bash apk-download-name.sh
set -euo pipefail
SITE=/etc/nginx/sites-available/study-os
if ! grep -q 'filename=study-os.apk' "$SITE"; then
  cp "$SITE" "$SITE.bak-$(date +%F-%H%M)"
  sed -i 's|add_header Content-Disposition "attachment";|add_header Content-Disposition "attachment; filename=study-os.apk";|' "$SITE"
fi
grep -q 'filename=study-os.apk' "$SITE" || { echo "APK location not found in $SITE"; exit 1; }
nginx -t
systemctl reload nginx
echo "APK downloads now carry a file name"
