#!/usr/bin/env bash
# Bootstrap a Debian-based VPS for OpenClaw (no Docker).
# Based on https://www.openclawfieldplaybook.com (French navigation).
# Run as root or with sudo.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || error "Run this script as root or with sudo."
}

# ---------------------------------------------------------------------------
# 1. System update (section 02-02)
# ---------------------------------------------------------------------------

system_update() {
    info "Updating package lists and upgrading installed packages..."
    apt-get update -y
    apt-get upgrade -y
}

# ---------------------------------------------------------------------------
# 2. Core packages (section 02-02)
# ---------------------------------------------------------------------------

install_packages() {
    info "Installing core packages: curl wget git ufw fail2ban unattended-upgrades"
    apt-get install -y \
        curl \
        wget \
        git \
        ufw \
        fail2ban \
        unattended-upgrades
}

# ---------------------------------------------------------------------------
# 3. Tailscale (section 02-03)
# ---------------------------------------------------------------------------

install_tailscale() {
    if command -v tailscale &>/dev/null; then
        info "Tailscale already installed, skipping."
        return
    fi
    info "Installing Tailscale via official installer..."
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable tailscaled
    info "Tailscale installed. Run 'sudo tailscale up' to authenticate."
}

# ---------------------------------------------------------------------------
# 4. PostgreSQL (section 02-08, installed as Debian package via pgdg)
# ---------------------------------------------------------------------------

install_postgresql() {
    if command -v psql &>/dev/null; then
        info "PostgreSQL already installed, skipping."
        return
    fi
    info "Adding PostgreSQL apt repository (pgdg)..."
    local codename
    codename=$(lsb_release -cs)
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list
    apt-get update -y
    info "Installing PostgreSQL..."
    apt-get install -y postgresql postgresql-contrib
    systemctl enable postgresql
    systemctl start postgresql
    info "PostgreSQL $(psql --version) installed and running."
}

# ---------------------------------------------------------------------------
# 5. HashiCorp Vault (section 02-07, installed as Debian package via HashiCorp repo)
# ---------------------------------------------------------------------------

install_vault() {
    if command -v vault &>/dev/null; then
        info "Vault already installed, skipping."
        return
    fi
    info "Adding HashiCorp apt repository..."
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
    local codename
    codename=$(lsb_release -cs)
    echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] \
https://apt.releases.hashicorp.com ${codename} main" \
        > /etc/apt/sources.list.d/hashicorp.list
    apt-get update -y
    info "Installing Vault..."
    apt-get install -y vault
    info "Vault $(vault version) installed."
    info "Configure /etc/vault.d/vault.hcl and run: sudo systemctl enable --now vault"
}

# ---------------------------------------------------------------------------
# 6. Headscale (https://headscale.net — .deb from GitHub releases)
# ---------------------------------------------------------------------------

install_headscale() {
    if command -v headscale &>/dev/null; then
        info "Headscale already installed, skipping."
        return
    fi
    info "Fetching latest Headscale version from GitHub..."
    local version
    version=$(curl -fsSL https://api.github.com/repos/juanfont/headscale/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    [[ -n "$version" ]] || error "Could not determine latest Headscale version."
    local arch
    arch=$(dpkg --print-architecture)
    local deb="headscale_${version}_linux_${arch}.deb"
    info "Downloading Headscale v${version} (${arch})..."
    wget --output-document="/tmp/${deb}" \
        "https://github.com/juanfont/headscale/releases/download/v${version}/${deb}"
    info "Installing Headscale..."
    apt-get install -y "/tmp/${deb}"
    rm -f "/tmp/${deb}"
    info "Headscale $(headscale version) installed."
    info "Configure /etc/headscale/config.yaml and run: sudo systemctl enable --now headscale"
}

# ---------------------------------------------------------------------------
# 7. Node.js via nvm (section 02-05)
# ---------------------------------------------------------------------------

install_nvm_and_node() {
    # nvm must be installed as the target (non-root) user.
    # When run as root, install for root; operators should re-run for deploy user.
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"

    if [[ -s "$nvm_dir/nvm.sh" ]]; then
        info "nvm already installed at $nvm_dir, skipping nvm install."
    else
        info "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
        nvm_dir="$HOME/.nvm"
    fi

    # Source nvm within this script
    # shellcheck source=/dev/null
    source "$nvm_dir/nvm.sh"

    info "Installing Node.js LTS via nvm..."
    nvm install --lts
    nvm alias default lts/*

    info "Installing PM2 globally..."
    npm install -g pm2
    pm2 startup || true   # prints the command to run; may need manual step

    info "Node $(node --version) and PM2 $(pm2 --version) installed."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    require_root
    system_update
    install_packages
    install_tailscale
    install_postgresql
    install_vault
    install_headscale
    install_nvm_and_node

    echo
    info "Bootstrap complete."
    info "Next steps:"
    info "  - Configure UFW rules, fail2ban, and SSH hardening (section 02-02)"
    info "  - Authenticate Tailscale: sudo tailscale up"
    info "  - Run 'pm2 startup' as your deploy user and follow the printed command"
    info "  - Configure Vault: edit /etc/vault.d/vault.hcl, then: sudo systemctl enable --now vault"
    info "  - Configure Headscale: edit /etc/headscale/config.yaml, then: sudo systemctl enable --now headscale"
}

main "$@"
