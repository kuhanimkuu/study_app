#!/usr/bin/env bash
# Brings an existing server's helper scripts in line with setup_server.sh as
# of release 1.0.7 (2026-10-21 audit). Safe to run again; run as root:
#   bash server-scripts-1.0.7.sh
#
#   - study-os-backup no longer copies .env into the nightly files tarball
#     (it holds the login-token secret, DB password and hosted AI keys, and
#     backups get copied to the PC). Keep one copy of .env in a password
#     manager instead. Older tarballs that still contain it expire after
#     14 days.
#   - study-os-update waits for /api/health/ready, which also checks the
#     database, instead of /api/health.
set -euo pipefail
BACKUP=/usr/local/bin/study-os-backup
UPDATE=/usr/local/bin/study-os-update

sed -i 's/^for p in \.env server\/uploads /for p in server\/uploads /' "$BACKUP"
sed -i 's/^# Nightly Study OS backup: database dump + uploaded\/generated files + \.env\./# Nightly Study OS backup: database dump + uploaded\/generated files (not .env)./' "$BACKUP"
sed -i 's#/api/health >/dev/null#/api/health/ready >/dev/null#' "$UPDATE"

grep -q '^for p in server/uploads ' "$BACKUP" || { echo "study-os-backup: expected line not found"; exit 1; }
grep -q '/api/health/ready' "$UPDATE" || { echo "study-os-update: expected line not found"; exit 1; }
echo "Backups no longer include .env; updates wait for the database check."
