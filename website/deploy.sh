#!/usr/bin/env bash
# Build the website and publish it to the Study OS server, optionally with a
# new Android APK. The server has no Node, so the build happens here.
#
#   ./deploy.sh                                   # website only
#   ./deploy.sh ../frontend/build/app/outputs/flutter-apk/app-release.apk
#
# The new site is unpacked next to the live one and swapped in with a rename,
# so visitors never see a half-uploaded site. The APK in download/ is kept
# across site deploys. nginx serves /var/www/studyos (see setup_server.sh).
# Override the target with STUDY_OS_SSH, STUDY_OS_SSH_PORT, STUDY_OS_SSH_KEY.
set -euo pipefail
cd "$(dirname "$0")"

HOST="${STUDY_OS_SSH:-root@62.171.182.123}"
PORT="${STUDY_OS_SSH_PORT:-1257}"
KEY="${STUDY_OS_SSH_KEY:-$HOME/.ssh/study_os_deploy}"
SITE=/var/www/studyos
APK="${1:-}"
SSH=(ssh -i "$KEY" -p "$PORT" -o IdentitiesOnly=yes -o BatchMode=yes "$HOST")

if [[ -n "$APK" && ! -f "$APK" ]]; then
  echo "APK not found: $APK" >&2
  exit 1
fi

npm run build

echo "Uploading the website..."
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

if [[ -n "$APK" ]]; then
  echo "Uploading the APK ($(du -h "$APK" | cut -f1))..."
  "${SSH[@]}" "cat > $SITE/download/study-os.apk.part && mv $SITE/download/study-os.apk.part $SITE/download/study-os.apk && chmod a+r $SITE/download/study-os.apk" < "$APK"
fi

echo "Done. https://studytutor.duckdns.org/"
