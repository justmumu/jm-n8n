#!/bin/bash
# A script to back up multiple n8n Docker volumes to Google Drive using rclone.

# Exit immediately if a command exits with a non-zero status.
set -e

# =================================================================
# ===              EDIT THE SETTINGS SECTION BELOW            ===
# =================================================================

# 1. An array of n8n-related Docker volume names you want to back up.
DOCKER_VOLUMES=("CHANGE_THIS")

# 2. The name of your rclone remote configuration.
RCLONE_REMOTE="CHANGE_THIS"

# 3. The UNIQUE FOLDER ID of your "N8N-Backups" folder on Google Drive.
GDRIVE_ROOT_FOLDER_ID="CHANGE_THIS"

# 4. Retention period for old backups.
RETENTION_PERIOD="30d"

# =================================================================
# ===         NO NEED TO EDIT ANYTHING BELOW THIS LINE        ===
# =================================================================

# --- Self-configured Variables ---
TEMP_BASE_DIR="/tmp/n8n-multi-backup"
WORKER_ID="$(hostname)"

# --- 1. PRE-RUN CHECKS ---
echo "Step 1: Verifying required commands..."
REQUIRED_COMMANDS=("rclone" "tar" "docker" "sudo")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: Required command '$cmd' is not installed. Please install it to continue." >&2
    exit 1
  fi
done
echo "✔ All dependencies are met."

if [[ "$GDRIVE_ROOT_FOLDER_ID" == "YOUR_GDRIVE_FOLDER_ID_HERE" || -z "$GDRIVE_ROOT_FOLDER_ID" ]]; then
    echo "ERROR: Please edit the script and set the 'GDRIVE_ROOT_FOLDER_ID' variable." >&2
    exit 1
fi

# --- 2. PREPARE WORKSPACE & VARIABLES ---
DATE_FORMAT=$(date +'%d-%m-%Y')
WORKER_FOLDER="N8N-Worker-$WORKER_ID"

echo "Preparing temporary workspace..."
sudo rm -rf "$TEMP_BASE_DIR"
mkdir -p "$TEMP_BASE_DIR"
echo "✔ Workspace ready at $TEMP_BASE_DIR"

echo "================================================="
echo "n8n Multi-Volume Backup Process Started: $(date)"
echo "Worker ID:           $WORKER_ID"
echo "Volumes to back up:  ${DOCKER_VOLUMES[@]}"
echo "================================================="

# --- 3. LOOP THROUGH EACH VOLUME AND PROCESS IT ---
for volume_name in "${DOCKER_VOLUMES[@]}"; do
  echo "-------------------------------------------------"
  echo "Processing Volume: $volume_name"
  echo "-------------------------------------------------"
  
  TEMP_VOLUME_DATA_DIR="$TEMP_BASE_DIR/$volume_name-data"
  mkdir -p "$TEMP_VOLUME_DATA_DIR"

  echo "--> [1/5] Copying data from Docker volume..."
  docker run --rm \
    --mount source="$volume_name",target=/mount_point \
    -v "$TEMP_VOLUME_DATA_DIR:/backup" \
    busybox sh -c "cp -a /mount_point/. /backup/"
  echo "    Done."

  echo "--> [2/5] Correcting file permissions..."
  sudo chown -R $USER:$USER "$TEMP_VOLUME_DATA_DIR"
  echo "    Done."

  ARCHIVE_NAME="backup_${volume_name}_${DATE_FORMAT}.tar.gz"
  LOCAL_ARCHIVE_PATH="$TEMP_BASE_DIR/$ARCHIVE_NAME"

  echo "--> [3/5] Compressing data into '$ARCHIVE_NAME'..."
  tar -czf "$LOCAL_ARCHIVE_PATH" -C "$TEMP_VOLUME_DATA_DIR" .
  
  if [ ! -f "$LOCAL_ARCHIVE_PATH" ]; then
    echo "    !!! ERROR: Failed to create the archive. Skipping this volume. !!!"
    continue
  fi
  echo "    Done."
  
  REMOTE_DESTINATION_PATH="$RCLONE_REMOTE:$WORKER_FOLDER"
  echo "--> [4/5] Uploading archive to Google Drive..."
  /usr/bin/rclone copy "$LOCAL_ARCHIVE_PATH" "$REMOTE_DESTINATION_PATH" \
    --drive-root-folder-id "$GDRIVE_ROOT_FOLDER_ID" -v
  
  if [ $? -ne 0 ]; then
    echo "    !!! ERROR: rclone upload failed. The local archive is kept for inspection. !!!"
    continue 
  fi
  echo "    Upload successful."

done

# --- 4. CLEAN UP LOCAL FILES ---
echo "-------------------------------------------------"
echo "--> [5/5] Cleaning up local temporary files..."
sudo rm -rf "$TEMP_BASE_DIR"
echo "    Local cleanup complete."

# --- 5. CLEAN UP OLD REMOTE BACKUPS ---
echo "-------------------------------------------------"
echo "Cleaning up old remote backups (older than $RETENTION_PERIOD)..."
REMOTE_CLEANUP_PATH="$RCLONE_REMOTE:$WORKER_FOLDER"

for volume_name in "${DOCKER_VOLUMES[@]}"; do
  filename_pattern="backup_${volume_name}_*.tar.gz"
  echo "--> Checking for old backups matching: '$filename_pattern'"
  /usr/bin/rclone delete "$REMOTE_CLEANUP_PATH" \
    --drive-root-folder-id "$GDRIVE_ROOT_FOLDER_ID" \
    --include "$filename_pattern" --min-age "$RETENTION_PERIOD" -v
done

echo ">>> Remote cleanup finished."
echo "================================================="
echo "All Operations Completed: $(date)"
echo "================================================="
