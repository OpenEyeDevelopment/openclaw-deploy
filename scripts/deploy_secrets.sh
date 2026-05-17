#!/usr/bin/env bash
# Copyright 2026 - Ronald Portier (Open Eye Development)
# SPDX-License-Identifier: AGPL-3.0-or-later  (https://www.gnu.org/licenses/agpl.html)
#
# Decrypt a SOPS-encrypted secrets file and install it for OpenClaw.
# The decrypted file is written to SECRETS_DEST with mode 0600.
# If the OpenClaw systemd service is running it is restarted afterwards.
#
# Usage: deploy_secrets.sh [encrypted-secrets-file]
#   Default encrypted file: secrets.enc.env
#
# Required env vars (or defaults):
#   SOPS_AGE_KEY_FILE  — path to the age private key (default: /etc/openclaw/age-key.txt)
#   OPENCLAW_USER      — owner of the decrypted secrets file (default: openclaw)

set -euo pipefail

SECRETS_SRC="${1:-secrets.enc.env}"
SECRETS_DEST="/etc/openclaw/secrets.env"
OPENCLAW_USER="${OPENCLAW_USER:-openclaw}"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-/etc/openclaw/age-key.txt}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo "[INFO]  $*"; }
error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

[[ -f "$SECRETS_SRC" ]] || error "Encrypted secrets file not found: $SECRETS_SRC"
[[ -f "$SOPS_AGE_KEY_FILE" ]] || error "age key not found: $SOPS_AGE_KEY_FILE"
command -v sops &>/dev/null || error "sops is not installed."

# ---------------------------------------------------------------------------
# Decrypt
# ---------------------------------------------------------------------------

info "Decrypting $SECRETS_SRC -> $SECRETS_DEST"
mkdir -p "$(dirname "$SECRETS_DEST")"

# Write to a temp file first so SECRETS_DEST is never half-written.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

sops --decrypt "$SECRETS_SRC" >"$tmp"
mv "$tmp" "$SECRETS_DEST"

chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "$SECRETS_DEST"
chmod 0600 "$SECRETS_DEST"

info "Secrets deployed to $SECRETS_DEST"

# ---------------------------------------------------------------------------
# Restart OpenClaw if it is already running
# ---------------------------------------------------------------------------

if systemctl is-active --quiet openclaw 2>/dev/null; then
    info "Restarting OpenClaw service..."
    systemctl restart openclaw
    info "OpenClaw restarted."
else
    info "OpenClaw service is not running; skipping restart."
fi
