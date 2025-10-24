#!/usr/bin/env bash

# ==============================================================================
# Restore Credentials - Copy saved credentials back to working location
# ==============================================================================
# The original script deletes credentials on exit, so this restores them
# ==============================================================================

BACKUP_CREDS="/root/userData.json"
TARGET_DIR="/root/rl-swarm/modal-login/temp-data"

if [ -f "$BACKUP_CREDS" ]; then
    mkdir -p "$TARGET_DIR"
    cp "$BACKUP_CREDS" "$TARGET_DIR/userData.json"
    echo "✓ Credentials restored to $TARGET_DIR/userData.json"
    
    # Extract ORG_ID for info
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' "$BACKUP_CREDS")
    echo "  ORG_ID: $ORG_ID"
else
    echo "✗ No backup credentials found at $BACKUP_CREDS"
    exit 1
fi

