#!/usr/bin/env bash
# Copyright 2026 - Ronald Portier (Open Eye Development)
# SPDX-License-Identifier: AGPL-3.0-or-later  (https://www.gnu.org/licenses/agpl.html)
#
# Set up the OpenClaw client to connect to a remote gateway.
# Installs Tailscale, Node.js (via nvm), and OpenClaw, then configures
# the local client for remote gateway access over the Tailscale network.
#
# Run as a regular user with sudo access — do NOT run as root.
# Requires a .client-secret-env file in this directory.
# Copy .client-secret-env.sample to .client-secret-env and fill in values.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.client-secret-env"
OPENCLAW_DIR="${HOME}/.openclaw"
OPENCLAW_CONFIG="${OPENCLAW_DIR}/openclaw.json"
OPENCLAW_ENV="${OPENCLAW_DIR}/.env"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo "[INFO]  $*"; }
error() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" &>/dev/null || error "Required command not found: $1"
}

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------

load_config() {
    [[ -f "$ENV_FILE" ]] ||
        error "Config file not found: ${ENV_FILE}\n  Copy .client-secret-env.sample to .client-secret-env and fill in your values."
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    [[ -n "${OPENCLAW_GATEWAY_URL:-}" ]] || error "OPENCLAW_GATEWAY_URL is not set in ${ENV_FILE}"
    [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]] || error "OPENCLAW_GATEWAY_TOKEN is not set in ${ENV_FILE}"
    info "Config loaded."
}

# ---------------------------------------------------------------------------
# 1. Install Tailscale
# ---------------------------------------------------------------------------

install_tailscale() {
    if command -v tailscale &>/dev/null; then
        info "Tailscale already installed, skipping."
        return
    fi
    info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sudo bash
    info "Tailscale installed."
}

# ---------------------------------------------------------------------------
# 2. Join the Tailscale network
# ---------------------------------------------------------------------------

join_tailnet() {
    # Skip if already connected
    if tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
        info "Already connected to Tailscale network, skipping."
        return
    fi

    if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
        info "TAILSCALE_AUTH_KEY not set — skipping automatic network join."
        info "  Run manually: sudo tailscale up${HEADSCALE_URL:+ --login-server ${HEADSCALE_URL}} --authkey <key>"
        return
    fi

    info "Joining Tailscale network..."
    local -a args=("--authkey" "$TAILSCALE_AUTH_KEY" "--accept-routes")
    [[ -n "${HEADSCALE_URL:-}" ]] && args+=("--login-server" "$HEADSCALE_URL")
    sudo tailscale up "${args[@]}"
    info "Joined Tailscale network. IP: $(tailscale ip -4 2>/dev/null || echo '<pending>')"
}

# ---------------------------------------------------------------------------
# 3. Install Node.js via nvm
# ---------------------------------------------------------------------------

install_node() {
    export NVM_DIR="${HOME}/.nvm"
    # shellcheck source=/dev/null
    [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"

    if command -v node &>/dev/null; then
        info "Node.js already installed ($(node --version)), skipping."
        return
    fi

    info "Installing nvm and Node.js LTS..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
    # shellcheck source=/dev/null
    source "${NVM_DIR}/nvm.sh"
    nvm install --lts
    nvm alias default lts/*
    info "Node.js $(node --version) installed."
}

# ---------------------------------------------------------------------------
# 4. Install or update OpenClaw
# ---------------------------------------------------------------------------

install_openclaw() {
    export NVM_DIR="${HOME}/.nvm"
    # shellcheck source=/dev/null
    [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"

    if command -v openclaw &>/dev/null; then
        info "OpenClaw already installed, updating to latest..."
        npm update -g openclaw
        info "OpenClaw $(openclaw --version 2>/dev/null || echo unknown) is up to date."
        return
    fi
    info "Installing OpenClaw via npm..."
    npm install -g openclaw@latest
    info "OpenClaw $(openclaw --version 2>/dev/null || echo unknown) installed."
}

# ---------------------------------------------------------------------------
# 5. Configure OpenClaw for remote gateway
# ---------------------------------------------------------------------------

configure_openclaw() {
    mkdir -p "$OPENCLAW_DIR"

    if [[ -f "$OPENCLAW_CONFIG" ]]; then
        info "Patching existing OpenClaw config..."
        if ! command -v jq &>/dev/null; then
            if command -v apt-get &>/dev/null; then
                sudo apt-get install -y jq
            else
                error "jq is required to patch the existing config. Please install jq and re-run."
            fi
        fi
        jq --arg url "$OPENCLAW_GATEWAY_URL" \
            --arg token "$OPENCLAW_GATEWAY_TOKEN" \
            '.gateway = {"mode": "remote", "remote": {"url": $url, "token": $token}}' \
            "$OPENCLAW_CONFIG" >"${OPENCLAW_CONFIG}.tmp"
        mv "${OPENCLAW_CONFIG}.tmp" "$OPENCLAW_CONFIG"
    else
        info "Creating OpenClaw config..."
        cat >"$OPENCLAW_CONFIG" <<EOF
{
  "gateway": {
    "mode": "remote",
    "remote": {
      "url": "${OPENCLAW_GATEWAY_URL}",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    }
  }
}
EOF
    fi
    info "Remote gateway configured: ${OPENCLAW_GATEWAY_URL}"
}

# ---------------------------------------------------------------------------
# 6. Set required environment variables
# ---------------------------------------------------------------------------

configure_env() {
    mkdir -p "$OPENCLAW_DIR"
    touch "$OPENCLAW_ENV"
    chmod 0600 "$OPENCLAW_ENV"

    # ws:// over a WireGuard/Tailscale link is safe — the transport is already
    # encrypted. This variable tells OpenClaw to allow it on non-loopback addresses.
    if [[ "$OPENCLAW_GATEWAY_URL" == ws://* ]]; then
        local var="OPENCLAW_ALLOW_INSECURE_PRIVATE_WS"

        if ! grep -q "^${var}=" "$OPENCLAW_ENV" 2>/dev/null; then
            echo "${var}=1" >>"$OPENCLAW_ENV"
            info "Set ${var}=1 in ${OPENCLAW_ENV}."
        else
            info "${var} already set in ${OPENCLAW_ENV}."
        fi

        # Also add to .bashrc so it is present in interactive shells without
        # relying on openclaw's own .env loading.
        local profile="${HOME}/.bashrc"
        if ! grep -q "$var" "$profile" 2>/dev/null; then
            echo "export ${var}=1" >>"$profile"
            info "Added export ${var}=1 to ${profile}."
        fi
    fi
}

# ---------------------------------------------------------------------------
# 7. Disable local gateway service (if running)
# ---------------------------------------------------------------------------

disable_local_gateway() {
    if systemctl --user is-active openclaw-gateway.service &>/dev/null 2>&1; then
        info "Disabling local openclaw-gateway service..."
        systemctl --user disable --now openclaw-gateway.service
        info "Local gateway service disabled."
    else
        info "No local openclaw-gateway service active, skipping."
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    [[ $EUID -ne 0 ]] || error "Do not run this script as root. Run as a regular user with sudo access."
    require_cmd curl

    load_config
    install_tailscale
    join_tailnet
    install_node
    install_openclaw
    configure_openclaw
    configure_env
    disable_local_gateway

    echo
    info "OpenClaw client setup complete."
    info "  Gateway:      ${OPENCLAW_GATEWAY_URL}"
    info "  Tailscale IP: $(tailscale ip -4 2>/dev/null || echo '<run: tailscale ip -4>')"
    info "  Test with:    openclaw"
    [[ "$OPENCLAW_GATEWAY_URL" == ws://* ]] &&
        info "  Note: start a new shell or run 'source ~/.bashrc' to pick up the env var."
}

main "$@"
