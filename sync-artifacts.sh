#!/usr/bin/env sh
# sync-artifacts.sh - Sync non-SNAPSHOT artifacts between Artifactory instances
set -u

# Defaults
SOURCE_URL=""
SOURCE_USER=""
SOURCE_TOKEN=""
DEST_URL=""
DEST_USER=""
DEST_TOKEN=""
OUTPUT_DIR="backup"
DRY_RUN="true"
LIMIT=""

# Show help if no arguments
if [ $# -eq 0 ]; then
  cat <<EOF
Usage: $0 --source <URL> --dest <URL> [OPTIONS]

Sync non-SNAPSHOT artifacts between two Artifactory instances.

Required:
  --source <URL>          Source Artifactory Storage API URL
  --dest <URL>            Destination Artifactory UI URL

Authentication:
  --source-user <USER>    Source username (optional)
  --source-token <TOKEN>  Source API token (optional)
  --dest-user <USER>      Destination username (optional)
  --dest-token <TOKEN>    Destination API token (optional)

Options:
  --output <DIR>          Temp directory (default: backup)
  --limit <N>             Process only first N folders (for testing)
  --no-dry-run            Actually upload (default: dry-run)
  -h, --help              Show this help

Example:
  $0 --source "https://source/artifactory/api/storage/repo/path" \\
     --source-user user1 --source-token token1 \\
     --dest "https://dest/ui/repos/tree/General/repo/path" \\
     --dest-user user2 --dest-token token2 \\
     --limit 1 --no-dry-run

EOF
  exit 0
fi

# Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      SOURCE_URL="$2"
      shift 2
      ;;
    --source-user)
      SOURCE_USER="$2"
      shift 2
      ;;
    --source-token)
      SOURCE_TOKEN="$2"
      shift 2
      ;;
    --dest)
      DEST_URL="$2"
      shift 2
      ;;
    --dest-user)
      DEST_USER="$2"
      shift 2
      ;;
    --dest-token)
      DEST_TOKEN="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --no-dry-run)
      DRY_RUN="false"
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage: $0 --source <URL> --dest <URL> [OPTIONS]

Sync non-SNAPSHOT artifacts between two Artifactory instances.

Required:
  --source <URL>          Source Artifactory Storage API URL
  --dest <URL>            Destination Artifactory UI URL

Authentication:
  --source-user <USER>    Source username (optional)
  --source-token <TOKEN>  Source API token (optional)
  --dest-user <USER>      Destination username (optional)
  --dest-token <TOKEN>    Destination API token (optional)

Options:
  --output <DIR>          Temp directory (default: backup)
  --limit <N>             Process only first N folders (for testing)
  --no-dry-run            Actually upload (default: dry-run)
  -h, --help              Show this help

Example:
  $0 --source "https://source/artifactory/api/storage/repo/path" \\
     --source-user user1 --source-token token1 \\
     --dest "https://dest/ui/repos/tree/General/repo/path" \\
     --dest-user user2 --dest-token token2 \\
     --limit 1 --no-dry-run

EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# Validate
if [ -z "$SOURCE_URL" ]; then
  echo "Error: --source is required" >&2
  exit 1
fi

if [ -z "$DEST_URL" ] && [ "$DRY_RUN" = "false" ]; then
  echo "Error: --dest is required when using --no-dry-run" >&2
  exit 1
fi

# Helper: extract host from URL
get_host() { printf '%s' "$1" | sed -E 's#^(https?://[^/]+).*#\1#'; }

# Parse source (API format: .../api/storage/repo/path)
SRC_HOST=$(get_host "$SOURCE_URL")
SRC_REPO_PATH=$(printf '%s' "$SOURCE_URL" | sed -E 's#^.*/artifactory/api/storage/([^?]+).*#\1#')
SRC_REPO=$(printf '%s' "$SRC_REPO_PATH" | cut -d/ -f1)
SRC_PATH=$(printf '%s' "$SRC_REPO_PATH" | cut -d/ -f2-)

# Parse dest (UI format: .../ui/repos/tree/General/repo/path)
if [ -n "$DEST_URL" ]; then
  DEST_HOST=$(get_host "$DEST_URL")
  DEST_AFTER=$(printf '%s' "$DEST_URL" | sed -E 's#^.*/ui/repos/tree/General/##')
  DEST_REPO=$(printf '%s' "$DEST_AFTER" | cut -d/ -f1)
  DEST_PATH=$(printf '%s' "$DEST_AFTER" | cut -d/ -f2-)
  [ "$DEST_PATH" = "$DEST_REPO" ] && DEST_PATH=""
fi

# Build auth options
SRC_AUTH=""
[ -n "$SOURCE_USER" ] && [ -n "$SOURCE_TOKEN" ] && SRC_AUTH="-u \"$SOURCE_USER:$SOURCE_TOKEN\""

DEST_AUTH=""
[ -n "$DEST_USER" ] && [ -n "$DEST_TOKEN" ] && DEST_AUTH="-u \"$DEST_USER:$DEST_TOKEN\""

# Display config
echo "Source: $SRC_HOST/$SRC_REPO/$SRC_PATH"
[ -n "$DEST_URL" ] && echo "Dest:   $DEST_HOST/$DEST_REPO/${DEST_PATH:-/}"
echo "Mode:   $([ "$DRY_RUN" = "true" ] && echo "DRY-RUN" || echo "LIVE")"
[ -n "$LIMIT" ] && echo "Limit:  $LIMIT folder(s)"
echo ""

# Get non-SNAPSHOT folders
FOLDERS_LIST=$(mktemp)
eval curl -sS $SRC_AUTH "\"$SOURCE_URL\"" | jq -r '.children[]? | select(.folder==true) | select(.uri | test("SNAPSHOT"; "i") | not) | .uri' | sed 's#^/##' > "$FOLDERS_LIST"

[ ! -s "$FOLDERS_LIST" ] && { echo "No folders found"; rm -f "$FOLDERS_LIST"; exit 1; }

TOTAL_FOLDERS=$(wc -l < "$FOLDERS_LIST" | tr -d ' ')
echo "Found $TOTAL_FOLDERS artefacts(s)"

[ -n "$LIMIT" ] && head -n "$LIMIT" "$FOLDERS_LIST" > "$FOLDERS_LIST.tmp" && mv "$FOLDERS_LIST.tmp" "$FOLDERS_LIST"

# Process each folder
while IFS= read -r folder; do
  echo "Processing: $folder"

  FOLDER_URL="$SRC_HOST/artifactory/api/storage/$SRC_REPO/$SRC_PATH/$folder"
  FILES_LIST=$(mktemp)
  eval curl -sS $SRC_AUTH "\"$FOLDER_URL\"" | jq -r '.children[]? | select(.folder==false and (.uri | endswith(".tar.gz"))) | .uri' | sed 's#^/##' > "$FILES_LIST"

  while IFS= read -r file; do
    [ -z "$file" ] && continue

    echo "  -> $file"

    # Download
    DOWNLOAD_URL="$SRC_HOST/artifactory/$SRC_REPO/$SRC_PATH/$folder/$file"
    LOCAL_FILE="$OUTPUT_DIR/$folder/$file"
    mkdir -p "$(dirname "$LOCAL_FILE")"

    if eval curl -fsSL $SRC_AUTH "\"$DOWNLOAD_URL\"" -o "\"$LOCAL_FILE\""; then
      echo "     ✓ Downloaded successfully"
    else
      echo "     ✗ Download failed"
      continue
    fi

    UPLOAD_URL="$DEST_HOST/artifactory/$DEST_REPO/${DEST_PATH:+$DEST_PATH/}$folder/$file"

    if [ "$DRY_RUN" = "true" ]; then
      echo "     [DRY-RUN] Would upload to: $UPLOAD_URL"
    else
      echo "     Uploading to: $UPLOAD_URL"
      HTTP_STATUS=$(eval curl -o /dev/null -w '%{http_code}' -sSL $DEST_AUTH -X PUT "\"$UPLOAD_URL\"" -T "\"$LOCAL_FILE\"" 2>/dev/null || echo "000")
      if [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "200" ]; then
        echo "     ✓ Uploaded successfully (HTTP $HTTP_STATUS)"
      else
        echo "     ✗ Upload failed (HTTP $HTTP_STATUS)"
      fi
    fi
  done < "$FILES_LIST"
  rm -f "$FILES_LIST"
done < "$FOLDERS_LIST"
rm -f "$FOLDERS_LIST"

echo ""
echo "Done."
