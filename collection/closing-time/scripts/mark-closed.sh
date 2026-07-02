#!/usr/bin/env bash
# mark-closed.sh -- Called by closing-time Phase 5 (Seal) to write proof of closure.
#
# Per-session marker ($STATE_ROOT/closing-time/<sid>.json) is authoritative.
# A single-slot file ($STATE_ROOT/closing-time-completed.json) is also written
# for consumers that only care about "the most recent close".
#
# State root defaults to ~/.closing-time/state; override with CLOSING_TIME_STATE.
#
# Usage: mark-closed.sh <session_id>
set -euo pipefail
umask 077

STATE_DIR="${CLOSING_TIME_STATE:-$HOME/.closing-time/state}"
PER_SESSION_DIR="$STATE_DIR/closing-time"
SESSION_ID="${1:-}"

# Fall back to a current-session-id.txt cache if one exists. WARNING: a shared
# cache like this is clobbered by concurrent sessions — always pass the session
# id explicitly when you can.
if [[ -z "$SESSION_ID" && -f "$STATE_DIR/current-session-id.txt" ]]; then
    SESSION_ID=$(cat "$STATE_DIR/current-session-id.txt")
fi

if [[ -z "$SESSION_ID" ]]; then
    echo "ERROR: no session_id provided and $STATE_DIR/current-session-id.txt missing" >&2
    echo "Pass session_id as first argument." >&2
    exit 1
fi

mkdir -p "$PER_SESSION_DIR"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PER_SESSION_FILE="$PER_SESSION_DIR/${SESSION_ID}.json"
LEGACY_FILE="$STATE_DIR/closing-time-completed.json"

# Atomic write helper: tmp + mv.
write_json() {
    local target="$1"
    local body="$2"
    local tmp
    tmp=$(mktemp "$(dirname "$target")/closing-time-XXXX.json")
    printf '%s' "$body" > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$target"
}

BODY=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "closed_at": "$TS"
}
EOF
)

write_json "$PER_SESSION_FILE" "$BODY"
write_json "$LEGACY_FILE"      "$BODY"

echo "closed: $SESSION_ID at $TS"
