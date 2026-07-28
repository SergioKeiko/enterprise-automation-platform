#!/usr/bin/env bash
# ============================================================
# install-backups.sh — installs the two nightly backup cron jobs
#
# Run once from the repository root ON THE SERVER:
#   bash scripts/install-backups.sh
#
# Idempotent: running it again will not create duplicate entries.
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT=$(pwd)

chmod +x "$REPO_ROOT/scripts/enterprise-backup.sh" "$REPO_ROOT/scripts/data-backup.sh"

CRON_CONFIG="0 2 * * * $REPO_ROOT/scripts/enterprise-backup.sh >/dev/null 2>&1"
CRON_DATA="30 2 * * * $REPO_ROOT/scripts/data-backup.sh >/dev/null 2>&1"

# keep existing entries (tolerate an empty crontab on a fresh server)
EXISTING=$(crontab -l 2>/dev/null | grep -vF "scripts/enterprise-backup.sh" | grep -vF "scripts/data-backup.sh" || true)
{ [ -n "$EXISTING" ] && echo "$EXISTING"
  echo "$CRON_CONFIG"
  echo "$CRON_DATA"
} | crontab -

echo "Installed cron jobs:"
crontab -l | grep "$REPO_ROOT/scripts"
echo
echo "Test them now with:"
echo "  bash scripts/enterprise-backup.sh"
echo "  bash scripts/data-backup.sh"
