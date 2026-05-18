#!/usr/bin/env bash
# Copyright 2026 - Ronald Portier (Open Eye Development)
# SPDX-License-Identifier: AGPL-3.0-or-later  (https://www.gnu.org/licenses/agpl.html)
#
# Remove stale OpenClaw session lock files.
# A lock is stale when the process that created it is no longer running.
# Safe to run at any time — locks held by live processes are left untouched.
#
# Usage: bash scripts/clean-openclaw-locks.sh

set -euo pipefail

OPENCLAW_DIR="${HOME}/.openclaw"

# The gateway process holds no session locks; locks referencing its PID are
# always stale (see github.com/openclaw/openclaw/issues/49603).
gateway_pid=""
if gateway_pid=$(XDG_RUNTIME_DIR="/run/user/$(id -u)" \
    systemctl --user show openclaw-gateway.service \
    --property MainPID --value 2>/dev/null) && [[ "$gateway_pid" == "0" ]]; then
    gateway_pid=""
fi

removed=0
while IFS= read -r -d '' lockfile; do
    pid=$(grep -oE '[0-9]+' "$lockfile" 2>/dev/null | head -1)
    if [[ -n "$pid" && "$pid" != "$gateway_pid" ]] && kill -0 "$pid" 2>/dev/null; then
        continue
    fi
    rm -f "$lockfile"
    ((removed++)) || true
done < <(find "$OPENCLAW_DIR" -name "*.lock" -print0 2>/dev/null)

[[ $removed -gt 0 ]] && echo "[INFO]  Removed ${removed} stale OpenClaw lock(s)."
exit 0
