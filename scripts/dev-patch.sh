#!/usr/bin/env bash
# Export current uncommitted changes as a patch for review on the local machine.
#
# Usage: bash scripts/dev-patch.sh
#
# Writes ~/current.patch, then print the instructions for the next steps.

set -euo pipefail

REPO="${HOME}/openclaw-deploy"

info() { echo "[INFO]  $*"; }

cd "$REPO"

git add .

if git diff HEAD --quiet 2>/dev/null; then
    info "No uncommitted changes."
    git reset HEAD --quiet
    exit 0
fi

git diff HEAD >"${HOME}/current.patch"
git reset HEAD --quiet

info "Patch written to ~/current.patch"
echo
git diff HEAD --stat
echo
info "On your local machine:"
info "  bash client/pull-patch.sh <vps-host>"
