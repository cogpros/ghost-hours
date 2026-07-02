#!/usr/bin/env bash
# Adapter: operator notification. Uses an upstream poster when one exists;
# otherwise prints to stdout (the terminal IS the notification surface).
#
# Wire to your stack by setting CLOSING_TIME_UPSTREAM_DIR (a directory holding a
# discord-post.sh or equivalent notifier). The default points at the author's
# stack layout; if nothing executable is found there, stdout is the fallback.
set -euo pipefail
UPSTREAM_DIR="${CLOSING_TIME_UPSTREAM_DIR:-}"
UPSTREAM="$UPSTREAM_DIR/discord-post.sh"
if [[ -x "$UPSTREAM" ]]; then exec "$UPSTREAM" "$@"; fi
echo "[notify] $*"
