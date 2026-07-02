#!/usr/bin/env bash
# Adapter: Ghost Hours row write. Routes to an upstream writer when one exists;
# otherwise records the full argument vector to a local JSONL so no measurement
# is ever lost on machines without a wider stack.
#
# Wire to your stack by setting CLOSING_TIME_UPSTREAM_DIR (a directory holding a
# log-leverage.sh). If it is unset, or nothing
# executable is found there, the local fallback under ~/.closing-time/ is used.
set -euo pipefail
UPSTREAM_DIR="${CLOSING_TIME_UPSTREAM_DIR:-}"
UPSTREAM="$UPSTREAM_DIR/log-leverage.sh"
if [[ -x "$UPSTREAM" ]]; then exec "$UPSTREAM" "$@"; fi
mkdir -p "$HOME/.closing-time"
printf '%s\n' "$(python3 - "$@" <<'PY'
import json, sys, datetime
print(json.dumps({"ts": datetime.datetime.now().astimezone().isoformat(),
                  "adapter": "log-leverage-fallback", "args": sys.argv[1:]}))
PY
)" >> "$HOME/.closing-time/leverage-log.jsonl"
echo "logged (local fallback: ~/.closing-time/leverage-log.jsonl)"
