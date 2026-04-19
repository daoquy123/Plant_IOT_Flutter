#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
cd "$ROOT_DIR"

DB_PATH="server/data/plant_iot.db"
BACKUP_DIR="$ROOT_DIR/backups"
mkdir -p "$BACKUP_DIR"

if [ ! -f "$DB_PATH" ]; then
  echo "Database file not found: $DB_PATH"
  exit 1
fi

TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
BACKUP_FILE="$BACKUP_DIR/plant_iot_${TIMESTAMP}.db"
cp "$DB_PATH" "$BACKUP_FILE"

echo "Backup saved to $BACKUP_FILE"

EXISTING_FILES=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'plant_iot_*.db' | sort)
FILE_COUNT=$(printf '%s\n' "$EXISTING_FILES" | grep -c '^' || true)
KEEP=7

if [ "$FILE_COUNT" -gt "$KEEP" ]; then
  REMOVE_COUNT=$((FILE_COUNT - KEEP))
  printf '%s\n' "$EXISTING_FILES" | head -n "$REMOVE_COUNT" | xargs -r rm --
  echo "Removed $REMOVE_COUNT old backup(s)"
fi
