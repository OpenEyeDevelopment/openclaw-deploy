#!/usr/bin/env bash
# Bootstrap: install git and clone the openclaw-deploy repository.
# Rsync this single file to the server and run it as root.
# All other setup scripts are then available in the cloned repository.
#
# Usage: bash bootstrap.sh [-r <repo-url>] [-b <branch>]
#   -r, --repository  Repository URL to clone
#                     (default: https://github.com/OpenEyeDevelopment/openclaw-deploy.git)
#   -b, --branch      Branch to check out (default: main)

set -euo pipefail

REPO="https://github.com/OpenEyeDevelopment/openclaw-deploy.git"
BRANCH="main"
DEST="${HOME}/openclaw-deploy"

info() { echo "[INFO]  $*"; }
error() {
    echo "[ERROR] $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r | --repository)
            REPO="$2"
            shift 2
            ;;
        -b | --branch)
            BRANCH="$2"
            shift 2
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
done

[[ $EUID -eq 0 ]] || error "Run this script as root."

if ! command -v git &>/dev/null; then
    info "Installing git..."
    apt-get update -y
    apt-get install -y git
fi

if [[ -d "${DEST}/.git" ]]; then
    info "Repository already exists at ${DEST}, updating..."
    git -C "$DEST" fetch origin
    git -C "$DEST" checkout "$BRANCH"
    git -C "$DEST" pull origin "$BRANCH"
elif [[ -d "$DEST" ]]; then
    error "${DEST} exists but is not a git repository. Remove or rename it and re-run."
else
    info "Cloning ${REPO} (branch: ${BRANCH}) to ${DEST}..."
    git clone --branch "$BRANCH" "$REPO" "$DEST"
fi

echo
info "Repository ready at ${DEST}"
info "Next: fill in ${DEST}/.env-secret, then run the setup scripts."
