#!/usr/bin/env bash
# log-ghost-hours.sh -- Log a Ghost Hours session entry
#
# Usage:
#   log-ghost-hours.sh --type unlock --human 30 --gh 480 --desc "Built the thing"
#   log-ghost-hours.sh --type speed --human 60 --gh 120 --desc "Wrote social posts"
#
# All JSON construction and file locking is handled by Python.
# This script is a thin CLI wrapper for ghost_hours_writer.py.
#
# Copyright 2026 Raven Systems Inc. Licensed under Apache 2.0.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRITER="$SCRIPT_DIR/ghost_hours_writer.py"

if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3 is required. Install it and try again."
    exit 1
fi

TYPE="" HUMAN="" GH="" DESC="" SOURCE="claude-cli"
SUBTYPE="" GH_CONF="" TAGS="" BACKLOG="" FWC="" NOTE="" PROJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)     TYPE="$2";     shift 2 ;;
    --human)    HUMAN="$2";    shift 2 ;;
    --gh)       GH="$2";       shift 2 ;;
    --desc)     DESC="$2";     shift 2 ;;
    --source)   SOURCE="$2";   shift 2 ;;
    --subtype)  SUBTYPE="$2";  shift 2 ;;
    --confidence) GH_CONF="$2"; shift 2 ;;
    --tags)     TAGS="$2";     shift 2 ;;
    --backlog)  BACKLOG="$2";  shift 2 ;;
    --fwc)      FWC="$2";      shift 2 ;;
    --note)     NOTE="$2";     shift 2 ;;
    --project)  PROJECT="$2";  shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$TYPE" || -z "$HUMAN" || -z "$GH" || -z "$DESC" ]]; then
  echo "Usage: log-ghost-hours.sh --type <unlock|speed> --human <mins> --gh <mins> --desc \"description\""
  echo ""
  echo "Required:"
  echo "  --type      unlock | speed"
  echo "  --human     minutes you spent"
  echo "  --gh        estimated minutes this would take solo"
  echo "  --desc      what was accomplished (max 280 chars)"
  echo ""
  echo "Optional:"
  echo "  --subtype   restoration | bypass | augmentation (unlock only)"
  echo "  --confidence low | medium | high"
  echo "  --tags      comma-separated tags"
  echo "  --backlog   months this task waited"
  echo "  --fwc       felt weight of completion (1-10)"
  echo "  --note      verbatim reflection (max 1000 chars)"
  echo "  --project   project name"
  echo "  --source    agent source (default: claude-cli)"
  exit 1
fi

python3 - "$TYPE" "$HUMAN" "$GH" "$DESC" "$SOURCE" "$SUBTYPE" "$GH_CONF" "$TAGS" "$BACKLOG" "$FWC" "$NOTE" "$PROJECT" "$WRITER" << 'PYEOF'
import sys
import os
import importlib.util

args = sys.argv[1:]
type_, human, gh, desc, source = args[0], args[1], args[2], args[3], args[4]
subtype, gh_conf, tags_str, backlog = args[5], args[6], args[7], args[8]
fwc, note, project, writer_path = args[9], args[10], args[11], args[12]

# Import the writer module
spec = importlib.util.spec_from_file_location("ghost_hours_writer", writer_path)
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)

# Parse tags
tags = [t.strip() for t in tags_str.split(",") if t.strip()] if tags_str else None

# Build entry
entry = w.build_session_entry(
    type_=type_,
    human_mins=int(human),
    gh_mins=int(gh),
    desc=desc,
    source=source,
    subtype=subtype or None,
    gh_confidence=gh_conf or None,
    tags=tags,
    backlog_months=float(backlog) if backlog else None,
    fwc=int(fwc) if fwc else None,
    note=note or None,
    project=project or None,
)

# Write it
result = w.log_entry(entry)
w.increment_session_count()

# Summary
ratio = int(gh) / max(int(human), 1)
gh_hrs = int(gh) / 60
hh_hrs = int(human) / 60

print(f"\nLogged to Ghost Hours:")
print(f"  Session ID : {result['session_id'][:8]}...")
if type_ == "unlock":
    sub = f" ({subtype})" if subtype else ""
    print(f"  Type       : UNLOCK{sub}")
else:
    print(f"  Type       : SPEED -- {ratio:.1f}x Conjure Rate")
print(f"  Human      : {hh_hrs:.1f}h")
print(f"  Ghost      : {gh_hrs:.1f}h")
if backlog:
    print(f"  Backlog    : {backlog} months")
if fwc:
    print(f"  FW-C       : {fwc}/10")
if result.get("gh_confidence") == "review":
    print(f"  NOTE       : Ratio >{w.GH_REVIEW_THRESHOLD}x, tagged for review")
print(f"  Desc       : {desc}")
print()
PYEOF
