#!/usr/bin/env bash
# Pull the latest changes from the remote repository.
# Discards any local modifications and removes untracked files,
# so the working tree matches origin/main exactly.
# Run as root on the VPS.

set -euo pipefail

REPO="${HOME}/openclaw-deploy"
FORCE=false

info() { echo "[INFO]  $*"; }
error() {
    echo "[ERROR] $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f | --force)
            FORCE=true
            shift
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
done

[[ -d "${REPO}/.git" ]] || error "Not a git repository: ${REPO}"

# Check for local changes (modified tracked files or untracked files)
if ! git -C "$REPO" diff --quiet HEAD 2>/dev/null ||
    [[ -n "$(git -C "$REPO" ls-files --others --exclude-standard)" ]]; then
    if [[ "$FORCE" == true ]]; then
        info "Local changes detected — discarding (--force)."
    else
        echo "The following local changes will be discarded:"
        git -C "$REPO" status --short
        echo
        read -r -p "Discard changes and update? [y/N] " answer
        [[ "${answer,,}" == "y" ]] || {
            info "Aborted."
            exit 0
        }
    fi
fi

info "Resetting and cleaning ${REPO}..."
git -C "$REPO" reset --hard HEAD
git -C "$REPO" clean -fd

info "Pulling latest from origin..."
git -C "$REPO" pull

info "Done. Repository is now at $(git -C "$REPO" log --oneline -1)."
