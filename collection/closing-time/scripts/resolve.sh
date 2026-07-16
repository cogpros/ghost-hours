#!/usr/bin/env bash
# resolve.sh — Resolve work items outside the task board.
#
# Adds terminal states (park, absorb, kill, done) for items that don't
# belong on the board but need a durable record of why they stopped.
#
# Usage:
#   resolve.sh park   "description" "reason"
#   resolve.sh absorb "description" "what absorbed it"
#   resolve.sh kill   "description" "why not relevant"
#   resolve.sh done   "description" "how it was completed"
#   resolve.sh list   [--days N]
#   resolve.sh check  "description"

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVED_FILE="${CLOSING_TIME_RESOLVED:-$HOME/.closing-time/resolved.jsonl}"
mkdir -p "$(dirname "$RESOLVED_FILE")"

usage() {
  cat <<'EOF'
Usage: resolve.sh <command> [args]

Commands:
  park    "item" "reason"     Acknowledged, not now
  absorb  "item" "reason"     Handled as part of other work
  kill    "item" "reason"     No longer relevant
  done    "item" "reason"     Completed outside the board
  list    [--days N]          Show recent resolutions (default: 7 days)
  check   "description"       Check if item is already resolved
  help                        Show this help
EOF
}

cmd_resolve() {
  local type="$1"
  shift

  # Optional --source flag
  local source="manual"
  if [[ "${1:-}" == "--source" ]]; then
    source="${2:-manual}"
    shift 2
  fi

  local item="${1:-}"
  local reason="${2:-}"

  if [[ -z "$item" ]]; then
    echo "Error: missing item description." >&2
    echo "Usage: resolve.sh $type \"description\" \"reason\"" >&2
    exit 1
  fi

  if [[ -z "$reason" ]]; then
    echo "Error: missing reason." >&2
    echo "Usage: resolve.sh $type \"description\" \"reason\"" >&2
    exit 1
  fi

  local id="res-$(date +%s)"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local date_local
  date_local="$(date +"%Y-%m-%d")"

  # Write JSONL entry via python3 for safe JSON encoding
  local entry
  entry=$(RES_ID="$id" RES_TS="$ts" RES_DATE="$date_local" RES_TYPE="$type" \
    RES_ITEM="$item" RES_REASON="$reason" RES_SOURCE="$source" \
    python3 -c "
import json, os
entry = {
    'id': os.environ['RES_ID'],
    'ts': os.environ['RES_TS'],
    'date': os.environ['RES_DATE'],
    'type': os.environ['RES_TYPE'],
    'item': os.environ['RES_ITEM'],
    'reason': os.environ['RES_REASON'],
    'source': os.environ['RES_SOURCE']
}
print(json.dumps(entry))
")

  echo "$entry" >> "$RESOLVED_FILE"
  chmod 600 "$RESOLVED_FILE"
  EMIT="$DIR/adapters/emit-event.sh"
  # park is NOT a closure. "Acknowledged, not now" is the opposite of resolved, so it emits its
  # own event type — a consumer harvesting completion claims by event name must never see a park
  # as done. absorb/kill/done ARE closures (kill = decided-against, which genuinely resolves it).
  # Fixed 2026-07-15: one event name across all four types made every park read as "done".
  if [[ "$type" == "park" ]]; then
    EVENT="work_parked"
  else
    EVENT="work_resolved"
  fi
  [[ -x "$EMIT" ]] && "$EMIT" "resolve" "$EVENT" "$item" "type=$type, reason=$reason" "work" 2>/dev/null || true

  if [[ "$type" == "park" ]]; then
    echo "Parked (deferred, NOT resolved): $item"
  else
    echo "Resolved [$type]: $item"
  fi
}

cmd_list() {
  local days=7
  if [[ "${1:-}" == "--days" ]]; then
    days="${2:-7}"
    shift 2
  fi

  if [[ ! -f "$RESOLVED_FILE" ]]; then
    echo "No resolved items yet."
    return 0
  fi

  python3 -c "
import json, sys
from datetime import datetime, timedelta

days = int('$days')
cutoff = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
count = 0

with open('$RESOLVED_FILE') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
            if e.get('date', '') >= cutoff:
                count += 1
                t = e.get('type', '?')
                item = e.get('item', '?')
                reason = e.get('reason', '')
                date = e.get('date', '')
                print(f'[{t}] \"{item}\" -- {reason} ({date})')
        except json.JSONDecodeError:
            continue

if count == 0:
    print(f'No resolved items in the last {days} days.')
else:
    print(f'\\n{count} items resolved in the last {days} days.')
"
  return 0
}

cmd_check() {
  local query="${1:-}"

  if [[ -z "$query" ]]; then
    echo "Error: missing search description." >&2
    echo "Usage: resolve.sh check \"description\"" >&2
    exit 1
  fi

  if [[ ! -f "$RESOLVED_FILE" ]]; then
    echo "No resolved items yet."
    return 0
  fi

  python3 -c "
import json, sys

query = '''$query'''.lower()
found = 0

with open('$RESOLVED_FILE') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
            item = e.get('item', '').lower()
            if query in item or item in query:
                found += 1
                t = e.get('type', '?')
                reason = e.get('reason', '')
                date = e.get('date', '')
                print(f'[{t}] \"{e.get(\"item\", \"?\")}\" -- {reason} ({date})')
        except json.JSONDecodeError:
            continue

if found == 0:
    print('Not found in resolved items.')
"
  return 0
}

case "${1:-}" in
  park)    shift; cmd_resolve "park" "$@" ;;
  absorb)  shift; cmd_resolve "absorb" "$@" ;;
  kill)    shift; cmd_resolve "kill" "$@" ;;
  done)    shift; cmd_resolve "done" "$@" ;;
  list)    shift; cmd_list "$@" ;;
  check)   shift; cmd_check "$@" ;;
  -h|--help|help|"") usage ;;
  *) echo "Error: Unknown command: $1" >&2; usage; exit 1 ;;
esac
