#!/usr/bin/env bash
# Publish the website, and optionally a new Android APK.
#
# The website lives on HelioHost (https://studyos.helioho.st); the APK and the
# app's API live on the Contabo server, which redirects its own website pages
# to HelioHost (setup_server.sh, WEBSITE_URL).
#
#   ./deploy.sh                 build for HelioHost -> ~/Downloads/studyos-website.zip
#                               (then upload it in Plesk, see the printed steps)
#   ./deploy.sh path/to.apk     the same, plus upload the APK to Contabo
#   ./deploy.sh --contabo [apk] publish the website to the Contabo server instead
#                               (only if setup_server.sh has WEBSITE_URL="")
#
# Override the Contabo target with STUDY_OS_SSH, STUDY_OS_SSH_PORT, STUDY_OS_SSH_KEY.
set -euo pipefail
cd "$(dirname "$0")"

HELIOHOST_URL=https://studyos.helioho.st
CONTABO_URL=https://studytutor.duckdns.org
HOST="${STUDY_OS_SSH:-root@62.171.182.123}"
PORT="${STUDY_OS_SSH_PORT:-1257}"
KEY="${STUDY_OS_SSH_KEY:-$HOME/.ssh/study_os_deploy}"
SITE=/var/www/studyos
SSH=(ssh -i "$KEY" -p "$PORT" -o IdentitiesOnly=yes -o BatchMode=yes "$HOST")

TARGET=heliohost
if [[ "${1:-}" == "--contabo" ]]; then
  TARGET=contabo
  shift
fi
APK="${1:-}"
if [[ -n "$APK" && ! -f "$APK" ]]; then
  echo "APK not found: $APK" >&2
  exit 1
fi

# The app's version (frontend/pubspec.yaml, "1.0.10+11" -> "1.0.10") names
# the download: study-os-1.0.10.apk. The site shows src/site.ts's
# appVersion, so the two must agree.
VERSION=$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' ../frontend/pubspec.yaml)
if ! grep -q "appVersion: '$VERSION'" src/site.ts; then
  echo "src/site.ts appVersion doesn't match the app's version $VERSION — update it first." >&2
  exit 1
fi
APK_NAME="study-os-$VERSION.apk"

if [[ -n "$APK" ]]; then
  echo "Uploading the APK to Contabo as $APK_NAME ($(du -h "$APK" | cut -f1))..."
  # Older versioned files go; study-os.apk stays as "the latest" for old links.
  "${SSH[@]}" "set -e; cd $SITE/download 2>/dev/null || mkdir -p $SITE/download && cd $SITE/download; \
    cat > $APK_NAME.part && mv $APK_NAME.part $APK_NAME && chmod a+r $APK_NAME; \
    cp $APK_NAME study-os.apk.part && mv study-os.apk.part study-os.apk && chmod a+r study-os.apk; \
    find . -maxdepth 1 -name 'study-os-*.apk' ! -name '$APK_NAME' -delete" < "$APK"
fi

if [[ "$TARGET" == heliohost ]]; then
  VITE_SITE_URL=$HELIOHOST_URL VITE_APK_URL=$CONTABO_URL/download/$APK_NAME npm run build
  ZIP="$HOME/Downloads/studyos-website.zip"
  rm -f "$ZIP"
  python - "$ZIP" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk("dist"):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, "dist").replace(os.sep, "/"))
PY
  cat <<EOF

Built $ZIP. To publish it:
  1. HelioHost -> Plesk -> Websites & Domains -> studyos.helioho.st -> Files
  2. Open httpdocs, Upload the zip, tick it, Extract Files (replace existing)
  3. Delete the zip from httpdocs
Then check $HELIOHOST_URL/
EOF
else
  VITE_APK_URL=/download/$APK_NAME npm run build
  echo "Uploading the website to Contabo..."
  tar -czf - -C dist . | "${SSH[@]}" "set -e
    rm -rf $SITE.new && mkdir -p $SITE.new && tar -xzf - -C $SITE.new
    mkdir -p $SITE.new/download
    # keep the published APK; everything else in download/ comes from the new build
    for f in $SITE/download/*.apk; do if [ -e \"\$f\" ]; then cp -a \"\$f\" $SITE.new/download/; fi; done
    rm -rf $SITE.old
    if [ -d $SITE ]; then mv $SITE $SITE.old; fi
    mv $SITE.new $SITE
    rm -rf $SITE.old
    chmod -R a+rX $SITE"
  echo "Done. $CONTABO_URL/"
fi
