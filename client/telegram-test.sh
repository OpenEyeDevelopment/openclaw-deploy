#!/usr/bin/env bash
# Copyright 2026 - Ronald Portier (Open Eye Development)
# SPDX-License-Identifier: AGPL-3.0-or-later  (https://www.gnu.org/licenses/agpl.html)
#
# Send a test message via the Telegram bot to verify connectivity.
# Reads credentials from .client-secret-env in this directory.
#
# Usage: bash client/telegram-test.sh ["message"]
#   Default message: "OpenClaw Telegram test — $(date)"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.client-secret-env"
MESSAGE="${1:-OpenClaw Telegram test — $(date)}"

info() { echo "[INFO]  $*"; }
error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Load credentials
# ---------------------------------------------------------------------------

[[ -f "$ENV_FILE" ]] ||
    error "Config file not found: ${ENV_FILE}
  Copy .client-secret-env.sample to .client-secret-env and fill in your values."
# shellcheck source=/dev/null
source "$ENV_FILE"

[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] ||
    error "TELEGRAM_BOT_TOKEN is not set in ${ENV_FILE}"
[[ -n "${TELEGRAM_CHAT_ID:-}" ]] ||
    error "TELEGRAM_CHAT_ID is not set in ${ENV_FILE}
  To find your chat ID:
    1. Start a conversation with your bot in Telegram.
    2. Run: curl https://api.telegram.org/bot\${TELEGRAM_BOT_TOKEN}/getUpdates
    3. Look for the 'id' field inside 'chat' in the response."

# ---------------------------------------------------------------------------
# Send message
# ---------------------------------------------------------------------------

info "Sending test message to chat ${TELEGRAM_CHAT_ID}..."

payload="{\"chat_id\": \"${TELEGRAM_CHAT_ID}\","
payload+=" \"text\": \"${MESSAGE}\","
payload+=" \"parse_mode\": \"Markdown\"}"
response=$(curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$payload")

if echo "$response" | grep -q '"ok":true'; then
    info "Message delivered successfully."
else
    error "Telegram API returned an error: ${response}"
fi
