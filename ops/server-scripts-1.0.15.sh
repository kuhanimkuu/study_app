#!/usr/bin/env bash
# Adds the helper commands setup_server.sh gained in release 1.0.15 to an
# existing server. Safe to run again; run as root:
#   bash server-scripts-1.0.15.sh
#
#   - study-os-blocklist: sites Go deeper never suggests, and students'
#     "Report this source" reports (list | reports | add | remove).
#   - study-os-costs: what each AI feature really costs, next to its credit
#     price (docs/COST_AND_CREDITS.md).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
APP_USER="studyos"
APP_DIR="/opt/study_os"

cat > /usr/local/bin/study-os-blocklist <<EOF
#!/usr/bin/env bash
# Sites Go deeper never suggests, and students' "Report this source" reports.
# Usage: study-os-blocklist list | reports | add <site or page> [reason] | remove <site or page>
set -euo pipefail
cd /
sudo -u $APP_USER -H bash -c 'cd $APP_DIR && set -a && . ./.env && set +a && exec .venv/bin/python -m server.domains.research.blocklist "\$@"' _ "\$@"
EOF
chmod 755 /usr/local/bin/study-os-blocklist

cat > /usr/local/bin/study-os-costs <<EOF
#!/usr/bin/env bash
# What each AI feature really costs, next to its credit price. Usage: study-os-costs [days, default 30]
set -euo pipefail
cd /
sudo -u $APP_USER -H bash -c "cd $APP_DIR && set -a && . ./.env && set +a && .venv/bin/python -m server.scripts.cost_report --days \${1:-30}"
EOF
chmod 755 /usr/local/bin/study-os-costs
echo "Installed study-os-blocklist and study-os-costs."
