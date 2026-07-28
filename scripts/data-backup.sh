#!/usr/bin/env bash
# ============================================================
# data-backup.sh — nightly DATA backup
#
#   1. Full Supabase Postgres dump (pg_dumpall, gzipped)
#   2. n8n workflows + credentials export (credentials stay
#      encrypted with the key from n8n-stack/data/config.json)
#
# Install via scripts/install-backups.sh, or manually:
#   crontab -e   ->   30 2 * * * /root/enterprise-automation-platform/scripts/data-backup.sh
#
# NOTE: backups land on the SAME disk. Enable your provider's server
# snapshots/backups feature for an off-disk copy.
# ============================================================
set -euo pipefail

# --- Configuration (override via environment if your paths differ) ---
DEST="${DEST:-/root/backups/data}"
N8N_DATA_DIR="${N8N_DATA_DIR:-/root/enterprise-automation-platform/n8n-stack/data}"
LOG_FILE="${LOG_FILE:-/var/log/data-backup.log}"
RETENTION_DAYS=3

TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "$DEST"
log() { echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"; }

log "START data backup $TS"

# 1. Full Supabase Postgres dump
docker exec supabase-db pg_dumpall -U postgres | gzip > "$DEST/supabase-pgdumpall-$TS.sql.gz"
log "supabase dump: $(du -h "$DEST/supabase-pgdumpall-$TS.sql.gz" | cut -f1)"

# 2. n8n workflows + credentials (credentials stay encrypted)
# The export commands fail on a fresh install with zero workflows — that's fine.
docker exec n8n mkdir -p /home/node/.n8n/export/workflows /home/node/.n8n/export/credentials
docker exec n8n n8n export:workflow --backup --output=/home/node/.n8n/export/workflows/ >/dev/null 2>&1 \
  || log "n8n workflow export: nothing to export yet"
docker exec n8n n8n export:credentials --backup --output=/home/node/.n8n/export/credentials/ >/dev/null 2>&1 \
  || log "n8n credentials export: nothing to export yet"
if [ -n "$(ls -A "$N8N_DATA_DIR/export/workflows" 2>/dev/null)$(ls -A "$N8N_DATA_DIR/export/credentials" 2>/dev/null)" ]; then
  tar -czf "$DEST/n8n-export-$TS.tar.gz" -C "$N8N_DATA_DIR/export" .
  log "n8n export: $(du -h "$DEST/n8n-export-$TS.tar.gz" | cut -f1)"
else
  log "n8n export empty — skipping archive (fresh install)"
fi

# 3. Rotation
find "$DEST" -name '*.gz' -mtime +"$RETENTION_DAYS" -delete

log "DONE data backup $TS"
