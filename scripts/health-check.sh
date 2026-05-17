#!/usr/bin/env bash
# Copyright 2026 - Ronald Portier (Open Eye Development)
# SPDX-License-Identifier: AGPL-3.0-or-later  (https://www.gnu.org/licenses/agpl.html)
#
# Health check for the OpenClaw VPS deployment.
# Verifies all services are running and resources are within limits.
# Exit code: 0 = all OK, 1 = at least one failure.
# Suitable for monitoring crons.
#
# Usage: bash scripts/health-check.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env-secret"

OPENCLAW_USER="openclaw"
DISK_THRESHOLD=90 # alert if disk use (%) exceeds this
RAM_MIN_MB=1024   # alert if available RAM (MB) drops below this
CERT_WARN_DAYS=30 # alert if TLS certificate expires within this many days

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# shellcheck source=/dev/null
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

ok() {
    echo "[OK]   $*"
    ((PASS++)) || true
}

fail() {
    echo "[FAIL] $*"
    ((FAIL++)) || true
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

check_ports() {
    local -A ports=(
        [5432]="PostgreSQL"
        [80]="nginx HTTP"
        [443]="nginx HTTPS"
        [18789]="OpenClaw gateway"
    )
    for port in "${!ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":${port}"; then
            ok "Port ${port} (${ports[$port]}) listening"
        else
            fail "Port ${port} (${ports[$port]}) not listening"
        fi
    done
}

check_services() {
    local -A services=(
        [tailscaled]="Tailscale daemon"
        [headscale]="Headscale"
        [nginx]="nginx"
        [postgresql]="PostgreSQL"
    )
    for svc in "${!services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "${services[$svc]} service active"
        else
            fail "${services[$svc]} service not running"
        fi
    done

    if tailscale status --json 2>/dev/null | grep -q '"BackendState":[[:space:]]*"Running"'; then
        ok "Tailscale connected (IP: $(tailscale ip -4 2>/dev/null || echo unknown))"
    else
        fail "Tailscale not connected to network"
    fi
}

check_openclaw() {
    local uid
    uid=$(id -u "$OPENCLAW_USER" 2>/dev/null) || {
        fail "OpenClaw gateway: user '${OPENCLAW_USER}' not found"
        return
    }
    if sudo -u "$OPENCLAW_USER" \
        env \
        XDG_RUNTIME_DIR="/run/user/${uid}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
        systemctl --user is-active --quiet openclaw-gateway.service 2>/dev/null; then
        ok "OpenClaw gateway service active"
    else
        fail "OpenClaw gateway service not running"
    fi
}

check_postgresql() {
    if pg_isready --quiet 2>/dev/null; then
        ok "PostgreSQL accepting connections"
    else
        fail "PostgreSQL not accepting connections"
    fi
}

check_tls() {
    [[ -n "${HEADSCALE_DOMAIN:-}" ]] || return 0
    local cert="/etc/letsencrypt/live/${HEADSCALE_DOMAIN}/cert.pem"
    if [[ ! -f "$cert" ]]; then
        fail "TLS certificate not found: ${cert}"
        return
    fi
    if openssl x509 -noout -checkend $((CERT_WARN_DAYS * 86400)) -in "$cert" 2>/dev/null; then
        local expiry
        expiry=$(openssl x509 -noout -enddate -in "$cert" 2>/dev/null | cut -d= -f2)
        ok "TLS certificate valid (expires: ${expiry})"
    else
        fail "TLS certificate for ${HEADSCALE_DOMAIN} expires within ${CERT_WARN_DAYS} days"
    fi
}

check_disk() {
    local usage
    usage=$(df / --output=pcent | tail -1 | tr -d ' %')
    if [[ $usage -lt $DISK_THRESHOLD ]]; then
        ok "Disk usage: ${usage}% (threshold: ${DISK_THRESHOLD}%)"
    else
        fail "Disk usage: ${usage}% exceeds threshold of ${DISK_THRESHOLD}%"
    fi
}

check_ram() {
    local free_mb
    free_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    if [[ $free_mb -ge $RAM_MIN_MB ]]; then
        ok "Available RAM: ${free_mb} MB"
    else
        fail "Available RAM: ${free_mb} MB (minimum: ${RAM_MIN_MB} MB)"
    fi
}

check_backups() {
    local backup_dir="/var/backups/postgresql"
    if find "$backup_dir" -name "globals.sql.gz" -mtime -1 2>/dev/null | grep -q .; then
        ok "PostgreSQL backup from last 24 hours present"
    else
        fail "No PostgreSQL backup from last 24 hours in ${backup_dir}"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    echo "=== OpenClaw Health Check ==="
    echo "Date: $(date)"
    echo "---"

    check_ports
    check_services
    check_openclaw
    check_postgresql
    check_tls
    check_disk
    check_ram
    check_backups

    echo "---"
    echo "Result: ${PASS} OK, ${FAIL} failure(s)"

    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
    echo "All systems operational."
}

main "$@"
