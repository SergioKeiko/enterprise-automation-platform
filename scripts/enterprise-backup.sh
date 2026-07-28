#!/usr/bin/env bash
# ============================================================
# enterprise-backup.sh — nightly CONFIG backup + disk janitor
#
# Backs up everything needed to rebuild the stack (compose files,
# .env files, traefik config, n8n encryption key) and keeps the
# disk clean. Database CONTENT is backed up by data-backup.sh.
#
# IMPORTANT: n8n-stack/data/config.json holds the n8n encryption
# key. Without it, credential backups are unreadable. This script
# includes it in every backup.
#
# Install via scripts/install-backups.sh, or manually:
#   crontab -e   ->   0 2 * * * /root/enterprise-automation-platform/scripts/enterprise-backup.sh
# ============================================================
set -euo pipefail

# --- Configuration (override via environment if your paths differ) ---
REPO_DIR="${REPO_DIR:-/root/enterprise-automation-platform}"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/root/backups/configs}"
DAILY_BACKUP_DIR="${DAILY_BACKUP_DIR:-/root/backups/daily}"
LOG_FILE="${LOG_FILE:-/var/log/enterprise-backup.log}"
MAX_CONFIGS_RETENTION=7     # days of unpacked config backups to keep
MAX_DAILY_RETENTION=3       # number of daily tarballs to keep
MIN_FREE_SPACE_GB=15        # emergency threshold

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

emergency_cleanup() {
    log "Disk pressure: running emergency cleanup..."
    docker system prune -f >/dev/null 2>&1 || true
    find "$BACKUP_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +3 -exec rm -rf {} + 2>/dev/null || true
    if [ -d "$DAILY_BACKUP_DIR" ]; then
        find "$DAILY_BACKUP_DIR" -name 'stack-backup-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | tail -n +2 | cut -d' ' -f2- | xargs -r rm -f
    fi
    log "Emergency cleanup completed"
}

check_disk_space() {
    local available_gb used_percent
    available_gb=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
    used_percent=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    log "Disk: ${available_gb}GB free, ${used_percent}% used"
    if [ "$used_percent" -gt 85 ] || [ "$available_gb" -lt "$MIN_FREE_SPACE_GB" ]; then
        emergency_cleanup
    fi
}

regular_cleanup() {
    find "$BACKUP_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$MAX_CONFIGS_RETENTION" -exec rm -rf {} + 2>/dev/null || true
    if [ -d "$DAILY_BACKUP_DIR" ]; then
        find "$DAILY_BACKUP_DIR" -name 'stack-backup-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | tail -n +$((MAX_DAILY_RETENTION + 1)) | cut -d' ' -f2- | xargs -r rm -f
    fi
    docker system prune -f >/dev/null 2>&1 || true
}

create_backup() {
    local timestamp config_dir daily_file
    timestamp=$(date +%Y%m%d_%H%M%S)
    config_dir="$BACKUP_BASE_DIR/stack-$timestamp"
    daily_file="$DAILY_BACKUP_DIR/stack-backup-$timestamp.tar.gz"
    mkdir -p "$config_dir" "$DAILY_BACKUP_DIR"

    log "Backing up configuration..."
    cp "$REPO_DIR/n8n-stack/docker-compose.yml" "$config_dir/" 2>/dev/null || true
    cp "$REPO_DIR/n8n-stack/.env"               "$config_dir/n8n-stack.env" 2>/dev/null || true
    cp -r "$REPO_DIR/n8n-stack/traefik"         "$config_dir/" 2>/dev/null || true
    cp "$REPO_DIR/supabase/docker-compose.yml"  "$config_dir/supabase-compose.yml" 2>/dev/null || true
    cp "$REPO_DIR/supabase/.env"                "$config_dir/supabase.env" 2>/dev/null || true
    # n8n encryption key — restore-critical!
    mkdir -p "$config_dir/data"
    cp "$REPO_DIR/n8n-stack/data/config.json"   "$config_dir/data/" 2>/dev/null || true

    log "Creating compressed daily backup..."
    tar -czf "$daily_file" -C "$config_dir" . 2>/dev/null || true

    log "Backup sizes: config=$(du -sh "$config_dir" | cut -f1), daily=$(du -sh "$daily_file" | cut -f1)"
}

main() {
    log "=== Config backup started ==="
    check_disk_space
    regular_cleanup
    create_backup
    log "=== Config backup completed ==="
}

main "$@"
