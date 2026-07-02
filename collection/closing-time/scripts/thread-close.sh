#!/usr/bin/env bash
# thread-close.sh -- Discord thread closure helper.
#
# DEPRECATED under Ghost Hours schema v1.0 (2026-06). Its output is quarantined:
# the entries it writes are NOT brought to v1.0 shape (no schema_version /
# entry_class, fwc on a session row, etc.). Do not invest in its record shape.
# Left in place for reference only.
#
# Provides the deterministic infrastructure for the thread-close primitive.
# The MODEL drives the conversation (asking FW-C, writing reply via Discord
# tools, etc.). This script handles the things that need a bot token and
# atomic state writes:
#
#   detect <chat_id>                            -> Discord channel type integer
#   fetch <chat_id>                             -> thread metadata JSON
#   log <chat_id> <fwc> <fwc_eom> <gh_min>     -> append leverage entry
#       <tag> <note>                              (tag/note may be empty strings)
#   lock <chat_id>                              -> set Discord thread.locked=true
#
# Config:
#   DISCORD_ENV_FILE  file holding DISCORD_BOT_TOKEN=... (default ~/.closing-time/discord.env)
#   Leverage log, run log, and lock state live under ~/.closing-time/.
#
# Exit codes: 0 success, 1 detect-error, 2 not-a-thread (for detect),
# 3 fetch-error, 4 log-error, 5 lock-error, 7 missing-token.
set -euo pipefail
umask 077

CT_DIR="$HOME/.closing-time"
LEVERAGE_LOG="${CLOSING_TIME_LEVERAGE_LOG:-$CT_DIR/leverage-log.jsonl}"
ENV_FILE="${DISCORD_ENV_FILE:-$CT_DIR/discord.env}"
LOG="$CT_DIR/logs/thread-close.log"
LOCK_DIR="${CLOSING_TIME_STATE:-$CT_DIR/state}/.thread-close-write.lockd"
LOCK_STALE_SECONDS=30
DISCORD_API="https://discord.com/api/v10"

mkdir -p "$(dirname "$LOG")" "$(dirname "$LEVERAGE_LOG")" "$(dirname "$LOCK_DIR")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

read_token() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "ERROR: missing $ENV_FILE" >&2
        return 7
    fi
    DISCORD_BOT_TOKEN=$(grep -E '^DISCORD_BOT_TOKEN=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
    if [[ -z "$DISCORD_BOT_TOKEN" ]]; then
        echo "ERROR: DISCORD_BOT_TOKEN not set in $ENV_FILE" >&2
        return 7
    fi
}

# ----- subcommands -----

cmd_detect() {
    local chat_id="${1:-}"
    [[ -z "$chat_id" ]] && { echo "usage: detect <chat_id>" >&2; return 1; }
    read_token || return $?
    local resp
    resp=$(curl -s -m 10 -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        "$DISCORD_API/channels/$chat_id" 2>/dev/null) || true
    if [[ -z "$resp" ]]; then
        log "detect: empty response for $chat_id"
        return 1
    fi
    local type
    type=$(printf '%s' "$resp" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('type', ''))
except Exception:
    print('')
")
    if [[ -z "$type" ]]; then
        log "detect: parse failed; response head: $(printf '%s' "$resp" | head -c 200)"
        return 1
    fi
    echo "$type"
    log "detect: $chat_id -> type=$type"
    case "$type" in
        11|12) return 0 ;;     # PUBLIC_THREAD, PRIVATE_THREAD
        *)     return 2 ;;     # not a thread
    esac
}

cmd_fetch() {
    local chat_id="${1:-}"
    [[ -z "$chat_id" ]] && { echo "usage: fetch <chat_id>" >&2; return 3; }
    read_token || return $?

    local channel_resp messages_resp
    channel_resp=$(curl -s -m 10 -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        "$DISCORD_API/channels/$chat_id" 2>/dev/null) || true
    messages_resp=$(curl -s -m 10 -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        "$DISCORD_API/channels/$chat_id/messages?limit=100" 2>/dev/null) || true

    if [[ -z "$channel_resp" || -z "$messages_resp" ]]; then
        log "fetch: empty response for $chat_id"
        return 3
    fi

    CHANNEL_RESP="$channel_resp" MESSAGES_RESP="$messages_resp" python3 - <<'PYEOF' || return 3
import json, os, sys
try:
    ch = json.loads(os.environ["CHANNEL_RESP"])
    msgs = json.loads(os.environ["MESSAGES_RESP"])
except Exception as e:
    sys.stderr.write(f"fetch parse error: {type(e).__name__}\n")
    sys.exit(3)

if not isinstance(msgs, list):
    sys.stderr.write(f"fetch: messages response not a list (probably error): {str(msgs)[:200]}\n")
    sys.exit(3)

# Messages come newest-first; reverse for chronological.
msgs_chrono = list(reversed(msgs))
opened_at = msgs_chrono[0].get("timestamp", "") if msgs_chrono else ""
closed_at = msgs_chrono[-1].get("timestamp", "") if msgs_chrono else ""

# Estimate active gh_min from opened_at to now. Cap to a sensible band so a
# week-old thread doesn't claim a week of GH. Floor 60 so a 5-min ping still
# registers as an entry.
from datetime import datetime, timezone
gh_min = 0
if opened_at:
    try:
        dt = datetime.fromisoformat(opened_at.replace("Z", "+00:00"))
        delta = datetime.now(timezone.utc) - dt
        gh_min = int(delta.total_seconds() / 60)
        gh_min = max(60, min(gh_min, 240))
    except Exception:
        gh_min = 60

out = {
    "chat_id":           ch.get("id", ""),
    "title":             ch.get("name", ""),
    "parent_channel_id": ch.get("parent_id", ""),
    "type":              ch.get("type", -1),
    "message_count":     len(msgs),
    "opened_at":         opened_at,
    "latest_at":         closed_at,
    "gh_min_estimate":   gh_min,
}
print(json.dumps(out))
PYEOF
}

cmd_log() {
    local chat_id="${1:-}" fwc="${2:-}" fwc_eom="${3:-}" gh_min="${4:-}" tag="${5:-}" note="${6:-}" prefetched_meta="${7:-}"
    if [[ -z "$chat_id" || -z "$fwc" || -z "$gh_min" ]]; then
        echo "usage: log <chat_id> <fwc> <fwc_eom> <gh_min> [tag] [note] [prefetched_meta_json]" >&2
        return 4
    fi

    # Single-instance lock for the append. Multiple thread-closes shouldn't
    # interleave writes mid-line.
    local i age
    for i in 1 2 3 4 5 6 7 8; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then break; fi
        age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
        if (( age > LOCK_STALE_SECONDS )); then
            rmdir "$LOCK_DIR" 2>/dev/null || true
            continue
        fi
        sleep 0.2
    done
    [[ -d "$LOCK_DIR" ]] || { echo "lock acquire failed" >&2; return 4; }
    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

    local meta_json
    if [[ -n "$prefetched_meta" ]]; then
        meta_json="$prefetched_meta"
    else
        meta_json=$(cmd_fetch "$chat_id") || { log "log: cmd_fetch failed"; return 4; }
    fi

    META_JSON="$meta_json" \
    CHAT_ID="$chat_id" FWC="$fwc" FWC_EOM="$fwc_eom" GH_MIN="$gh_min" \
    TAG="$tag" NOTE="$note" LEVERAGE_LOG="$LEVERAGE_LOG" \
    python3 - <<'PYEOF' || return 4
import json, os, re, sys
from datetime import datetime, timezone

meta = json.loads(os.environ["META_JSON"])
now_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
date_local = datetime.now().strftime("%Y-%m-%d")

# fwc_eom is the agent's silent blind FW-C, may be empty; convert to int when present.
def maybe_int(v):
    try: return int(v)
    except Exception: return None

entry = {
    "session_id":        f"discord-thread-{meta.get('chat_id','')}",
    "ts":                now_utc,
    "date":              date_local,
    "type":              "unlock",
    "human_mins":        maybe_int(os.environ["GH_MIN"]) or 0,
    "gh_mins":           maybe_int(os.environ["GH_MIN"]) or 0,
    "desc":              meta.get("title", "") or "(thread)",
    "source":            "discord:thread",
    "tags":              [t for t in re.split(r"[,\s]+", os.environ.get("TAG","").strip()) if t],
    "fwc":               maybe_int(os.environ["FWC"]) or 0,
    "fwc_eom":           maybe_int(os.environ["FWC_EOM"]),
    "note":              os.environ.get("NOTE","") or "",
    "subtype":           "augmentation",
    "provenance":        "thread-close",
    "chat_id":           meta.get("chat_id",""),
    "parent_channel_id": meta.get("parent_channel_id",""),
    "title":             meta.get("title",""),
    "message_count":     meta.get("message_count", 0),
    "opened_at":         meta.get("opened_at",""),
    "closed_at":         now_utc,
}

# Strip None values so consumers using .get(k, default) still work cleanly.
entry = {k: v for k, v in entry.items() if v is not None}

with open(os.environ["LEVERAGE_LOG"], "a") as f:
    f.write(json.dumps(entry) + "\n")
print(json.dumps(entry))
PYEOF

    # Emit observability signal for the thread close. Best-effort.
    EMIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/adapters/emit-event.sh"
    if [[ -x "$EMIT" ]]; then
        "$EMIT" "closing-time" "thread_closed" "Discord thread closed" \
            "chat_id=$chat_id, gh_min=$gh_min, fwc=$fwc" "agent" 2>/dev/null || true
    fi
}

cmd_lock() {
    local chat_id="${1:-}"
    [[ -z "$chat_id" ]] && { echo "usage: lock <chat_id>" >&2; return 5; }
    read_token || return $?
    local resp
    resp=$(curl -s -m 5 -X PATCH \
        -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"locked": true}' \
        "$DISCORD_API/channels/$chat_id" 2>/dev/null) || true
    if [[ -z "$resp" ]]; then
        log "lock: empty response for $chat_id"
        return 5
    fi
    local locked_field
    locked_field=$(printf '%s' "$resp" | python3 -c "
import json, sys
try: print(json.load(sys.stdin).get('locked', ''))
except Exception: print('')
")
    if [[ "$locked_field" == "True" || "$locked_field" == "true" ]]; then
        log "lock: $chat_id locked"
        echo "locked"
        return 0
    fi
    log "lock: $chat_id failed; response head: $(printf '%s' "$resp" | head -c 200)"
    return 5
}

# ----- dispatch -----

CMD="${1:-}"; shift || true
case "$CMD" in
    detect) cmd_detect "$@" ;;
    fetch)  cmd_fetch  "$@" ;;
    log)    cmd_log    "$@" ;;
    lock)   cmd_lock   "$@" ;;
    "")     echo "usage: thread-close.sh {detect|fetch|log|lock} ..." >&2; exit 1 ;;
    *)      echo "unknown subcommand: $CMD" >&2; exit 1 ;;
esac
