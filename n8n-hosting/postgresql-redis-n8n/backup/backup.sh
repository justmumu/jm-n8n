#!/bin/bash
set -e

# ==========================================
# CONFIGURATION
# ==========================================
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB}"
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
# Remote name must match RCLONE_CONFIG_<NAME>_* env vars
GDRIVE_REMOTE="gdrive"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Notification settings
NOTIFICATION_URL="${BACKUP_SVC_NOTIFICATION_URL:-}"
NOTIFICATION_HEADER="${BACKUP_SVC_API_HEADER:-}"
NOTIFICATION_KEY="${BACKUP_SVC_API_KEY:-}"

# Timestamp and paths
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
TEMP_DIR="/tmp/backup_process_${TIMESTAMP}"
FINAL_FILENAME="n8n_full_backup_${TIMESTAMP}.tar.gz"
FINAL_ARCHIVE="/tmp/${FINAL_FILENAME}"
START_TIME=$(date +%s)

# Log accumulator for notification
LOG_OUTPUT=""

# ==========================================
# NOTIFICATION FUNCTION
# ==========================================
send_notification() {
    local title="$1"
    local subtitle="$2"
    local message="$3"
    
    # Skip if notification URL is not set
    if [ -z "${NOTIFICATION_URL}" ]; then
        return 0
    fi
    
    # Escape special characters for JSON (convert newlines to <br>)
    message=$(echo "$message" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/<br>/g')
    
    # Build JSON payload
    local payload=$(cat <<EOF
{
  "title": "${title}",
  "subtitle": "${subtitle}",
  "message": "${message}"
}
EOF
)
    
    # Send notification
    if [ -n "${NOTIFICATION_HEADER}" ] && [ -n "${NOTIFICATION_KEY}" ]; then
        curl -s -X POST "${NOTIFICATION_URL}" \
            -H "Content-Type: application/json" \
            -H "${NOTIFICATION_HEADER}: ${NOTIFICATION_KEY}" \
            -d "${payload}" > /dev/null 2>&1 || true
    else
        curl -s -X POST "${NOTIFICATION_URL}" \
            -H "Content-Type: application/json" \
            -d "${payload}" > /dev/null 2>&1 || true
    fi
}

log() {
    local msg="$1"
    echo "$msg"
    LOG_OUTPUT="${LOG_OUTPUT}${msg}<br>"
}

echo "=========================================="
echo "🚀 n8n Backup - ${TIMESTAMP}"
echo "=========================================="
LOG_OUTPUT="**Backup Started:** ${TIMESTAMP}<br><br>"

# ==========================================
# ERROR HANDLING (trap)
# ==========================================
cleanup_on_error() {
    local error_msg="$1"
    echo ""
    echo "=========================================="
    echo "❌ ERROR: Backup failed!"
    echo "=========================================="
    
    # Send error notification
    send_notification \
        "🚨 Backup Error 🚨" \
        "We have encountered an error while backing up the n8n instance." \
        "**Error Details:**<br><br>${LOG_OUTPUT}<br><br>**Last Error:** ${error_msg:-Unknown error}"
    
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
    rm -f "${FINAL_ARCHIVE}" 2>/dev/null || true
    exit 1
}
trap 'cleanup_on_error "Command failed at line $LINENO"' ERR

# Create temp directory
mkdir -p "${TEMP_DIR}"

# ==========================================
# [1/5] PostgreSQL Backup
# ==========================================
log "[1/5] 🐘 Creating PostgreSQL dump..."
export PGPASSWORD="${POSTGRES_PASSWORD}"
pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    --format=custom --compress=9 \
    --file="${TEMP_DIR}/database.dump"

if [ -f "${TEMP_DIR}/database.dump" ]; then
    DB_SIZE=$(du -h "${TEMP_DIR}/database.dump" | cut -f1)
    log "      ✅ Database dump created (${DB_SIZE})"
else
    cleanup_on_error "Database dump file not created"
fi

# ==========================================
# [2/5] n8n Storage Backup (excluding large/unnecessary files)
# ==========================================
log "[2/5] 📂 Archiving n8n storage..."
tar -czf "${TEMP_DIR}/n8n_files.tar.gz" \
    -C /data/n8n . \
    --exclude='./binaryData' \
    --exclude='*.log'

FILES_SIZE=$(du -h "${TEMP_DIR}/n8n_files.tar.gz" | cut -f1)
log "      ✅ n8n files archived (${FILES_SIZE})"

# ==========================================
# [3/5] Create Final Archive (single file)
# ==========================================
log "[3/5] 📦 Creating final archive..."
tar -czf "${FINAL_ARCHIVE}" -C "${TEMP_DIR}" database.dump n8n_files.tar.gz

FINAL_SIZE=$(du -h "${FINAL_ARCHIVE}" | cut -f1)
log "      ✅ Final archive created (${FINAL_SIZE})"

# ==========================================
# [4/5] Upload to Google Drive
# ==========================================
log "[4/5] ☁️  Uploading to Google Drive (Team Drive)..."
rclone copy "${FINAL_ARCHIVE}" "${GDRIVE_REMOTE}:" --progress
log "      ✅ Upload complete!"

# ==========================================
# [5/5] Cleanup
# ==========================================
log "[5/5] 🧹 Cleaning up..."

# Delete old backups on Drive (in root folder)
rclone delete "${GDRIVE_REMOTE}:" --min-age "${RETENTION_DAYS}d" 2>/dev/null || true
log "      ✅ Old backups cleaned (>${RETENTION_DAYS} days)"

# Remove local temp files
rm -rf "${TEMP_DIR}"
rm -f "${FINAL_ARCHIVE}"
log "      ✅ Local temp files removed"

# ==========================================
# DONE
# ==========================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "✅ Backup completed successfully!"
echo "   File: ${FINAL_FILENAME}"
echo "   Size: ${FINAL_SIZE}"
echo "   Time: ${DURATION}s"
echo "=========================================="

# Send success notification
SUMMARY="• *File:* ${FINAL_FILENAME}<br>• *Size:* ${FINAL_SIZE}<br>• *Duration:* ${DURATION}s<br>• *Database:* ${DB_SIZE}<br>• *Config Files:* ${FILES_SIZE}<br>• *Retention:* ${RETENTION_DAYS} days"

send_notification \
    "✅ Backup Successful ✅" \
    "We have successfully backed up the n8n instance with file ${FINAL_FILENAME}" \
    "**Backup Summary:**<br><br>${SUMMARY}<br><br>**Log Output:**<br><br>\`\`\`<br>${LOG_OUTPUT}\`\`\`"
