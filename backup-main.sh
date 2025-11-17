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

# 5. The full URL to your n8n instance.
N8N_URL="https://n8n.justmumu.com"

# 6. Your n8n API Key (get it from Settings -> API in the n8n UI).
N8N_API_KEY="CHANGE_THIS"

# =================================================================
# ===         NO NEED TO EDIT ANYTHING BELOW THIS LINE        ===
# =================================================================

# --- Self-configured Variables ---
TEMP_BASE_DIR="/tmp/n8n-multi-backup"
WORKER_ID="$(hostname)"

# --- 1. PRE-RUN CHECKS ---
echo "Step 1: Verifying required commands..."
REQUIRED_COMMANDS=("rclone" "tar" "docker" "sudo", "jq")
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
WORKER_FOLDER="N8N-Main-$WORKER_ID"

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

  echo "--> [1/11] Copying data from Docker volume..."
  docker run --rm \
    --mount source="$volume_name",target=/mount_point \
    -v "$TEMP_VOLUME_DATA_DIR:/backup" \
    busybox sh -c "cp -a /mount_point/. /backup/"
  echo "    Done."

  echo "--> [2/11] Correcting file permissions..."
  sudo chown -R $USER:$USER "$TEMP_VOLUME_DATA_DIR"
  echo "    Done."

  ARCHIVE_NAME="backup_${volume_name}_${DATE_FORMAT}.tar.gz"
  LOCAL_ARCHIVE_PATH="$TEMP_BASE_DIR/$ARCHIVE_NAME"

  echo "--> [3/11] Compressing data into '$ARCHIVE_NAME'..."
  tar -czf "$LOCAL_ARCHIVE_PATH" -C "$TEMP_VOLUME_DATA_DIR" .
  
  if [ ! -f "$LOCAL_ARCHIVE_PATH" ]; then
    echo "    !!! ERROR: Failed to create the archive. Skipping this volume. !!!"
    continue
  fi
  echo "    Done."
  
  REMOTE_DESTINATION_PATH="$RCLONE_REMOTE:$WORKER_FOLDER"
  echo "--> [4/11] Uploading archive to Google Drive..."
  /usr/bin/rclone copy "$LOCAL_ARCHIVE_PATH" "$REMOTE_DESTINATION_PATH" \
    --drive-root-folder-id "$GDRIVE_ROOT_FOLDER_ID" -v
  
  if [ $? -ne 0 ]; then
    echo "    !!! ERROR: rclone upload failed. The local archive is kept for inspection. !!!"
    continue 
  fi
  echo "    Upload successful."
done

echo "================================================="
echo "n8n Workflow Backup Process Started: $(date)"
echo "Worker ID:           $WORKER_ID"
echo "================================================="

# --- 4. PREPARE WORKFLOWS DATA VARIABLES
TEMP_WORKFLOWS_DATA_DIR="$TEMP_BASE_DIR/workflows-data"
mkdir -p "$TEMP_WORKFLOWS_DATA_DIR"

# --- 5. LOOP THROUGH ALL PAGES of THE WORKFLOW LIST ---
workflow_cursor=""
workflow_page_num=1
workflow_total_workflows=0

while true; do
  # Construct the API URL. For the first page, cursor is empty.
  if [ -z "$workflow_cursor" ]; then
    workflow_api_url="$N8N_URL/api/v1/workflows"
  else
    workflow_api_url="$N8N_URL/api/v1/workflows?cursor=$workflow_cursor"
  fi

  echo ">>> Fetching page $workflow_page_num of workflow list..."
  # Fetch the API response for the current page
  workflow_api_response=$(curl -s --request GET "$workflow_api_url" --header "X-N8N-API-KEY: $N8N_API_KEY")

  # Extract the list of workflows for this specific page
  workflow_list_page=$(echo "$workflow_api_response" | jq -r '.data[] | "\(.id) \(.name)"')

  if [ -z "$workflow_list_page" ]; then
    echo "--> [5/11] No more workflows found on this page."
  else
    # --- 6. LOOP THROUGH THE WORKFLOWS ON THE CURRENT PAGE AND SAVE EACH ONE ---
    while read -r id name; do
      # Sanitize the workflow name to create a valid filename
      workflow_sanitized_name=$(echo "$name" | tr -s '[:space:]' '_' | tr -cd '[:alnum:]_-')
      workflow_filename="${workflow_sanitized_name}_${id}.json"
      workflow_filepath="$TEMP_WORKFLOWS_DATA_DIR/$workflow_filename"

      echo "  --> [6/11] Backing up: \"$name\" (ID: $id) -> $workflow_filename"

      # Fetch the FULL JSON for the specific workflow ID and save it to the file
      curl -s --request GET "$N8N_URL/api/v1/workflows/$id" \
        --header "X-N8N-API-KEY: $N8N_API_KEY" > "$workflow_filepath"

      workflow_total_workflows=$((workflow_total_workflows + 1))
    done <<< "$workflow_list_page"
  fi

  # Check for the next cursor to see if there is another page
  workflow_cursor=$(echo "$workflow_api_response" | jq -r '.nextCursor')

  # If the cursor is null, we have reached the last page, so break the loop
  if [ "$workflow_cursor" == "null" ]; then
    break
  fi

  workflow_page_num=$((workflow_page_num + 1))
done

# --- 7. COMPRESS WORKFLOW DATA ---
WORKFLOW_ARCHIVE_NAME="backup_workflows_${DATE_FORMAT}.tar.gz"
WORKFLOW_LOCAL_ARCHIVE_PATH="$TEMP_BASE_DIR/$WORKFLOW_ARCHIVE_NAME"

echo "--> [7/11] Compressing workflow data into '$WORKFLOW_ARCHIVE_NAME'..."
tar -czf "$WORKFLOW_LOCAL_ARCHIVE_PATH" -C "$TEMP_WORKFLOWS_DATA_DIR" .

if [ ! -f "$WORKFLOW_LOCAL_ARCHIVE_PATH" ]; then
  echo "    !!! ERROR: Failed to create the archive."
  exit 1
fi
echo "    Done."

REMOTE_DESTINATION_PATH="$RCLONE_REMOTE:$WORKER_FOLDER"
echo "--> [8/11] Uploading workflow archive to Google Drive..."
/usr/bin/rclone copy "$WORKFLOW_LOCAL_ARCHIVE_PATH" "$REMOTE_DESTINATION_PATH" \
  --drive-root-folder-id "$GDRIVE_ROOT_FOLDER_ID" -v

if [ $? -ne 0 ]; then
  echo "    !!! ERROR: rclone upload failed. The local archive is kept for inspection. !!!"
  exit 1 
fi
echo "    Upload successful."

# --- 8. CLEAN UP LOCAL FILES ---
echo "-------------------------------------------------"
echo "--> [9/11] Cleaning up local temporary files..."
sudo rm -rf "$TEMP_BASE_DIR"
echo "    Local cleanup complete."

# --- 9. CLEAN UP OLD REMOTE BACKUPS ---
echo "-------------------------------------------------"
echo "Cleaning up old remote backups (older than $RETENTION_PERIOD)..."
REMOTE_CLEANUP_PATH="$RCLONE_REMOTE:$WORKER_FOLDER"

for volume_name in "${DOCKER_VOLUMES[@]}"; do
  filename_pattern="backup_${volume_name}_*.tar.gz"
  echo "--> [10/11] Checking for old backups matching: '$filename_pattern'"
  /usr/bin/rclone delete "$REMOTE_CLEANUP_PATH" \
    --drive-root-folder-id "$GDRIVE_ROOT_FOLDER_ID" \
    --include "$filename_pattern" --min-age "$RETENTION_PERIOD" -v
done

workflow_filename_pattern="backup_workflows_*.tar.gz"
echo "--> [11/11] Checking for old backups matching: '$workflow_filename_pattern'"
/usr/bin/rclone delete "$REMOTE_CLEANUP_PATH" \
  --drive-root-folder-id "$GDRIVE_ROOT_FOLDER_ID" \
  --include "$workflow_filename_pattern" --min-age "$RETENTION_PERIOD" -v

echo ">>> Remote cleanup finished."
echo "================================================="
echo "All Operations Completed: $(date)"
echo "================================================="
