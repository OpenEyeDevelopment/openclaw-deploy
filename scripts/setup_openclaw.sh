#!/usr/bin/env bash
# Copyright 2026 - Ronald Portier (Open Eye Development)
# SPDX-License-Identifier: AGPL-3.0-or-later  (https://www.gnu.org/licenses/agpl.html)
#
# Install and configure the OpenClaw gateway on a Debian-based VPS.
# Creates a dedicated 'openclaw' system user, installs Node.js + OpenClaw,
# deploys config, and sets up a systemd service.
#
# Requires a .env-secret file in the repo root. Copy .env-secret.sample to
# .env-secret, fill in your values, then run this script as root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env-secret"
CONFIG_TEMPLATE="${SCRIPT_DIR}/../config/openclaw.json"

OPENCLAW_USER="openclaw"
OPENCLAW_HOME="/home/${OPENCLAW_USER}"
OPENCLAW_DIR="${OPENCLAW_HOME}/.openclaw"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo "[INFO]  $*"; }
error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Run a command as the openclaw user with nvm sourced.
as_openclaw() {
    sudo -u "$OPENCLAW_USER" bash -c "
        export HOME=${OPENCLAW_HOME}
        export NVM_DIR=${OPENCLAW_HOME}/.nvm
        [[ -s \"\${NVM_DIR}/nvm.sh\" ]] && source \"\${NVM_DIR}/nvm.sh\"
        $*
    "
}

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------

load_config() {
    [[ -f "$ENV_FILE" ]] ||
        error "Config file not found: ${ENV_FILE}\n  Copy .env-secret.sample to .env-secret and fill in your values."
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    [[ -n "${CORTECS_API_KEY:-}" ]] || error "CORTECS_API_KEY is not set in ${ENV_FILE}"
    [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] || error "TELEGRAM_BOT_TOKEN is not set in ${ENV_FILE}"
    [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]] || error "OPENCLAW_GATEWAY_TOKEN is not set in ${ENV_FILE}"
    info "Config loaded."
}

# ---------------------------------------------------------------------------
# 1. Create the openclaw system user
# ---------------------------------------------------------------------------

create_user() {
    if id "$OPENCLAW_USER" &>/dev/null; then
        info "User ${OPENCLAW_USER} already exists, skipping."
        return
    fi
    info "Creating user ${OPENCLAW_USER}..."
    useradd --create-home --shell /bin/bash "$OPENCLAW_USER"
    # Allow openclaw to query the Tailscale daemon for the tailnet IP
    if getent group tailscale &>/dev/null; then
        usermod -aG tailscale "$OPENCLAW_USER"
    fi
    info "User ${OPENCLAW_USER} created."
}

# ---------------------------------------------------------------------------
# 2. Install Node.js via nvm for the openclaw user
# ---------------------------------------------------------------------------

install_node() {
    if as_openclaw "command -v node" &>/dev/null; then
        info "Node.js already installed for ${OPENCLAW_USER}, skipping."
        return
    fi
    info "Installing nvm and Node.js LTS for ${OPENCLAW_USER}..."
    as_openclaw "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash"
    as_openclaw "source ~/.nvm/nvm.sh && nvm install --lts && nvm alias default lts/*"
    info "Node.js $(as_openclaw 'node --version') installed."
}

# ---------------------------------------------------------------------------
# 3. Deploy config and secrets (before install so OpenClaw finds it on first run)
# ---------------------------------------------------------------------------

deploy_config() {
    info "Deploying OpenClaw config..."
    mkdir -p "$OPENCLAW_DIR"

    # Secrets file — OpenClaw loads this natively from ~/.openclaw/.env
    cat >"${OPENCLAW_DIR}/.env" <<EOF
CORTECS_API_KEY=${CORTECS_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
EOF
    chmod 0600 "${OPENCLAW_DIR}/.env"

    cp "$CONFIG_TEMPLATE" "${OPENCLAW_DIR}/openclaw.json"
    chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "$OPENCLAW_DIR"
    info "Config deployed to ${OPENCLAW_DIR}."
}

# ---------------------------------------------------------------------------
# 4. Install OpenClaw via npm (avoids interactive wizard in install.sh)
# ---------------------------------------------------------------------------

install_openclaw() {
    if as_openclaw "command -v openclaw" &>/dev/null; then
        info "OpenClaw already installed, skipping."
        return
    fi
    info "Installing OpenClaw via npm..."
    as_openclaw "npm install -g openclaw@latest"
    info "OpenClaw $(as_openclaw 'openclaw --version 2>/dev/null || echo unknown') installed."
}

# ---------------------------------------------------------------------------
# 5. Install and start the OpenClaw gateway daemon (user service + linger)
# ---------------------------------------------------------------------------

setup_gateway() {
    local uid
    uid=$(id -u "$OPENCLAW_USER")
    local xdg="XDG_RUNTIME_DIR=/run/user/${uid}"

    # Enable linger so the user service survives logout and starts at boot
    loginctl enable-linger "$OPENCLAW_USER"

    # Ensure the user's runtime dir exists (needed before first login)
    mkdir -p "/run/user/${uid}"
    chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "/run/user/${uid}"
    chmod 0700 "/run/user/${uid}"

    info "Installing OpenClaw gateway daemon..."
    as_openclaw "${xdg} openclaw gateway install"

    info "Starting OpenClaw gateway service..."
    as_openclaw "${xdg} systemctl --user enable --now openclaw-gateway.service"
    info "OpenClaw gateway service enabled and started."
}

# ---------------------------------------------------------------------------
# 6. Install lock-cleanup wrapper in the openclaw user's .bashrc
# ---------------------------------------------------------------------------

install_lock_cleanup() {
    install -m 0755 "${SCRIPT_DIR}/clean-openclaw-locks.sh" \
        /usr/local/sbin/clean-openclaw-locks

    # Systemd drop-in: run lock cleanup before every gateway start/restart.
    local dropin_dir="${OPENCLAW_HOME}/.config/systemd/user/openclaw-gateway.service.d"
    mkdir -p "$dropin_dir"
    install -m 0644 "${SCRIPT_DIR}/../config/systemd/openclaw-gateway-lock-cleanup.conf" \
        "${dropin_dir}/lock-cleanup.conf"
    chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "$dropin_dir"

    # Shell wrapper: also clean locks before interactive openclaw invocations.
    local marker="# openclaw-lock-cleanup"
    local bashrc="${OPENCLAW_HOME}/.bashrc"
    if grep -qF "$marker" "$bashrc" 2>/dev/null; then
        info "Lock-cleanup shell wrapper already in ${bashrc}, skipping."
    else
        cat >>"$bashrc" <<'EOF'

# openclaw-lock-cleanup
# Cleans stale session locks before every openclaw invocation.
openclaw() {
    bash /usr/local/sbin/clean-openclaw-locks
    command openclaw "$@"
}
EOF
        chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "$bashrc"
    fi
    info "Lock-cleanup installed (systemd drop-in + shell wrapper)."
}

# ---------------------------------------------------------------------------
# (continued) Firewall
# ---------------------------------------------------------------------------

setup_firewall() {
    # Restrict gateway port to Tailscale interface only.
    # The gateway binds to 0.0.0.0 so it is reachable via both localhost and
    # the Tailscale IP; UFW ensures it is not reachable on the public interface.
    if command -v ufw &>/dev/null; then
        info "Adding UFW rule: allow port 18789 on tailscale0 only..."
        ufw allow in on tailscale0 to any port 18789
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    [[ $EUID -eq 0 ]] || error "Run this script as root."
    load_config
    create_user
    install_node
    deploy_config
    install_openclaw
    setup_gateway
    install_lock_cleanup
    setup_firewall

    local uid
    uid=$(id -u "$OPENCLAW_USER")
    echo
    info "OpenClaw setup complete."
    info "  Tailscale IP: $(tailscale ip -4 2>/dev/null || echo '<run: tailscale ip -4>')"
    info "  Status: XDG_RUNTIME_DIR=/run/user/${uid} sudo -u ${OPENCLAW_USER} systemctl --user status openclaw-gateway.service"
    info "  Logs:   XDG_RUNTIME_DIR=/run/user/${uid} sudo -u ${OPENCLAW_USER} journalctl --user -u openclaw-gateway.service -f"
}

main "$@"
