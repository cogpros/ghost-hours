#!/usr/bin/env bash
# Adapter: event-bus emit. Uses an upstream bus writer when one exists; otherwise
# appends to a local JSONL so the protocol runs identically on machines without
# a wider stack.
#
# Wire to your stack by setting CLOSING_TIME_UPSTREAM_DIR (a directory holding an
# emit-event.sh). If it is unset, or nothing
# executable is found there, the local fallback under ~/.closing-time/ is used.
set -euo pipefail
UPSTREAM_DIR="${CLOSING_TIME_UPSTREAM_DIR:-}"
UPSTREAM="$UPSTREAM_DIR/emit-event.sh"
if [[ -x "$UPSTREAM" ]]; then exec "$UPSTREAM" "$@"; fi
mkdir -p "$HOME/.closing-time"
printf '%s\n' "$(python3 - "$@" <<'PY'
import json, sys, datetime
a = sys.argv[1:]
print(json.dumps({"ts": datetime.datetime.now().astimezone().isoformat(),
                  "source": a[0] if a else "", "type": a[1] if len(a)>1 else "",
                  "subject": a[2] if len(a)>2 else "", "body": a[3] if len(a)>3 else "",
                  "topic": a[4] if len(a)>4 else ""}))
PY
)" >> "$HOME/.closing-time/events.jsonl"
