#!/usr/bin/env bash
# Copyright 2026 - Ronald Portier (Open Eye Development)
# SPDX-License-Identifier: AGPL-3.0-or-later  (https://www.gnu.org/licenses/agpl.html)
#
# Configure Headscale with an nginx reverse proxy and Let's Encrypt TLS.
# Run as root on the VPS. DNS for HEADSCALE_DOMAIN must already point to this server.
#
# Requires a .env-secret file in the repo root. Copy .env-secret.sample to
# .env-secret, fill in your values, then run this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env-secret"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo "[INFO]  $*"; }
error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------

load_config() {
    [[ -f "$ENV_FILE" ]] ||
        error "Config file not found: ${ENV_FILE}\n  Copy .env-secret.sample to .env-secret and fill in your values."
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    [[ -n "${HEADSCALE_DOMAIN:-}" ]] || error "HEADSCALE_DOMAIN is not set in ${ENV_FILE}"
    [[ -n "${LE_EMAIL:-}" ]] || error "LE_EMAIL is not set in ${ENV_FILE}"
    HEADSCALE_ADDR="${HEADSCALE_ADDR:-127.0.0.1:8080}"
    HEADSCALE_CONFIG="${HEADSCALE_CONFIG:-/etc/headscale/config.yaml}"
    info "Config loaded (domain: ${HEADSCALE_DOMAIN}, email: ${LE_EMAIL})"
}

# ---------------------------------------------------------------------------
# 1. Install nginx and certbot
# ---------------------------------------------------------------------------

install_nginx_certbot() {
    info "Installing nginx and certbot..."
    apt-get install -y nginx certbot
    info "nginx and certbot installed."
}

# ---------------------------------------------------------------------------
# 2. Update Headscale server_url and start the service
# ---------------------------------------------------------------------------

configure_headscale() {
    [[ -f "$HEADSCALE_CONFIG" ]] || error "Headscale config not found: $HEADSCALE_CONFIG"
    info "Setting Headscale server_url to https://${HEADSCALE_DOMAIN}..."
    sed -i "s|^server_url:.*|server_url: https://${HEADSCALE_DOMAIN}|" "$HEADSCALE_CONFIG"
    systemctl enable --now headscale
    info "Headscale service enabled and started."
}

# ---------------------------------------------------------------------------
# 3. Obtain Let's Encrypt certificate (certbot standalone)
# ---------------------------------------------------------------------------

obtain_certificate() {
    info "Obtaining Let's Encrypt certificate for ${HEADSCALE_DOMAIN}..."
    # Stop nginx so certbot can bind to port 80
    systemctl stop nginx 2>/dev/null || true
    certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email "$LE_EMAIL" \
        -d "$HEADSCALE_DOMAIN"
    info "Certificate obtained."
}

# ---------------------------------------------------------------------------
# 4. Write nginx site config
# ---------------------------------------------------------------------------

configure_nginx() {
    info "Writing nginx configuration..."

    cat >/etc/nginx/sites-available/headscale <<EOF
map \$http_upgrade \$connection_upgrade {
    default      upgrade;
    ''           close;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${HEADSCALE_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443      ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${HEADSCALE_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${HEADSCALE_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${HEADSCALE_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://${HEADSCALE_ADDR};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$server_name;
        proxy_redirect http:// https://;
        proxy_buffering off;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/headscale /etc/nginx/sites-enabled/headscale
    nginx -t
    systemctl enable --now nginx
    info "nginx configured and started."
}

# ---------------------------------------------------------------------------
# 5. Open firewall ports
# ---------------------------------------------------------------------------

configure_firewall() {
    if ufw status | grep -q "Status: active"; then
        info "Opening ports 80 and 443 in UFW..."
        ufw allow 80/tcp
        ufw allow 443/tcp
    else
        info "UFW is not active; skipping firewall rules."
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    [[ $EUID -eq 0 ]] || error "Run this script as root."
    load_config
    install_nginx_certbot
    configure_headscale
    obtain_certificate
    configure_nginx
    configure_firewall

    echo
    info "Headscale setup complete."
    info "  URL:    https://${HEADSCALE_DOMAIN}"
    info "  Status: systemctl status headscale nginx"
}

main "$@"
