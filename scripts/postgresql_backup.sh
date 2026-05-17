#!/usr/bin/env bash
# Copyright 2026 - Ronald Portier (Open Eye Development)
# SPDX-License-Identifier: AGPL-3.0-or-later  (https://www.gnu.org/licenses/agpl.html)
#
# Back up all PostgreSQL databases to /var/backups/postgresql.
# Intended to be run as the 'postgres' system user via /etc/cron.d.
#
# Each run creates a dated subdirectory:
#   /var/backups/postgresql/YYYY-MM-DD/globals.sql.gz  — roles and tablespaces
#   /var/backups/postgresql/YYYY-MM-DD/<dbname>.sql.gz — per-database dump
#
# Backups older than RETENTION_DAYS are removed automatically.
# Override RETENTION_DAYS by setting it in the environment before calling.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgresql}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DATE=$(date +%F)
DEST="${BACKUP_DIR}/${DATE}"

log() { echo "[$(date +%T)] postgresql-backup: $*"; }

# Ensure the working directory is accessible to the postgres user
# (avoids 'failed to restore working directory' from find when invoked via sudo)
cd "$BACKUP_DIR" 2>/dev/null || cd /tmp

log "Starting backup to ${DEST}"
mkdir -p "$DEST"

# Dump globals (roles, tablespaces) — needed to fully restore a cluster
log "Dumping globals..."
pg_dumpall --globals-only | gzip >"${DEST}/globals.sql.gz"

# Dump each non-template database individually
failed=0
while IFS= read -r db; do
    log "Dumping database: ${db}"
    if pg_dump "$db" | gzip >"${DEST}/${db}.sql.gz"; then
        log "  OK: ${db}"
    else
        log "  FAILED: ${db}"
        failed=$((failed + 1))
    fi
done < <(psql -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;")

# Remove dated directories older than the retention window
log "Removing backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -maxdepth 1 -type d -name "????-??-??" -mtime "+${RETENTION_DAYS}" -exec rm -rf {} +

log "Backup complete."
ls -lh "$DEST"

if [[ $failed -gt 0 ]]; then
    log "WARNING: ${failed} database(s) failed to back up."
    exit 1
fi
