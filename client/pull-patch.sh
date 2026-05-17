#!/usr/bin/env bash
# Pull ~/current.patch from the VPS into the local repo for review and apply.
#
# Usage: bash client/pull-patch.sh <vps-host>
#   vps-host  SSH target, e.g. root@openclaw.openeyedev.com
#             Can also be set via the VPS environment variable.
#
# Workflow:
#   1. Run on VPS:    bash scripts/dev-patch.sh
#   2. Run locally:   bash client/pull-patch.sh <vps-host>
#   3. Review:        git apply --stat current.patch
#   4. Apply:         git apply current.patch
#   5. Commit + push
#   6. Reset VPS:     ssh <vps-host> 'cd ~/openclaw-deploy && git reset --hard HEAD && git pull'

set -euo pipefail

VPS="${VPS:-${1:-}}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

info() { echo "[INFO]  $*"; }
error() {
    echo "[ERROR] $*" >&2
    exit 1
}

[[ -n "$VPS" ]] || error "Specify the VPS host: bash client/pull-patch.sh <vps-host>"

info "Pulling patch from ${VPS}..."
rsync "${VPS}:~/current.patch" "${REPO_DIR}/current.patch"

echo
git -C "$REPO_DIR" apply --stat current.patch

echo
info "Patch saved to current.patch — review it, then:"
info "  git apply current.patch"
info "  git add -A && git commit && git push"
info "  ssh ${VPS} 'cd ~/openclaw-deploy && git reset --hard HEAD && git pull'"
