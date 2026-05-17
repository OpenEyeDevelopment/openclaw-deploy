#!/usr/bin/env bash
# Copyright 2026 - Ronald Portier (Open Eye Development)
# SPDX-License-Identifier: AGPL-3.0-or-later  (https://www.gnu.org/licenses/agpl.html)
#
# Install the PostgreSQL backup script and schedule it via /etc/cron.d.
# Run as root on the VPS after PostgreSQL has been installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SCRIPT_SRC="${SCRIPT_DIR}/postgresql_backup.sh"
BACKUP_SCRIPT_DEST="/usr/local/sbin/postgresql-backup"
CRON_FILE="/etc/cron.d/postgresql-backup"
BACKUP_DIR="/var/backups/postgresql"
CRON_HOUR="${CRON_HOUR:-3}"
CRON_MINUTE="${CRON_MINUTE:-0}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo "[INFO]  $*"; }
error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

[[ $EUID -eq 0 ]] || error "Run this script as root."
[[ -f "$BACKUP_SCRIPT_SRC" ]] || error "Backup script not found: ${BACKUP_SCRIPT_SRC}"
command -v pg_dump &>/dev/null || error "pg_dump not found — is PostgreSQL installed?"
id postgres &>/dev/null || error "System user 'postgres' not found — is PostgreSQL installed?"

# ---------------------------------------------------------------------------
# 1. Install the backup script
# ---------------------------------------------------------------------------

info "Installing backup script to ${BACKUP_SCRIPT_DEST}..."
install -m 0755 -o root -g root "$BACKUP_SCRIPT_SRC" "$BACKUP_SCRIPT_DEST"

# ---------------------------------------------------------------------------
# 2. Create the backup directory
# ---------------------------------------------------------------------------

info "Creating backup directory ${BACKUP_DIR}..."
mkdir -p "$BACKUP_DIR"
chown postgres:postgres "$BACKUP_DIR"
chmod 0750 "$BACKUP_DIR"

# ---------------------------------------------------------------------------
# 3. Write the cron entry
# ---------------------------------------------------------------------------

info "Writing cron entry to ${CRON_FILE}..."
cat >"$CRON_FILE" <<EOF
# PostgreSQL nightly backup — managed by scripts/setup_postgresql_backup.sh
# Runs as the 'postgres' user so no password is needed (peer authentication).
PATH=/usr/bin:/bin
${CRON_MINUTE} ${CRON_HOUR} * * * postgres ${BACKUP_SCRIPT_DEST}
EOF
chmod 0644 "$CRON_FILE"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo
info "PostgreSQL backup configured."
info "  Schedule:  daily at $(printf '%02d:%02d' "$CRON_HOUR" "$CRON_MINUTE")"
info "  Script:    ${BACKUP_SCRIPT_DEST}"
info "  Output:    ${BACKUP_DIR}/YYYY-MM-DD/"
info "  Retention: ${RETENTION_DAYS:-7} days (set RETENTION_DAYS env var to override)"
info "  Test run:  sudo -u postgres ${BACKUP_SCRIPT_DEST}"
