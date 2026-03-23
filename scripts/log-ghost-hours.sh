#!/usr/bin/env bash
# log-ghost-hours.sh -- Log a Ghost Hours session entry
#
# Usage:
#   log-ghost-hours.sh --type unlock --hugr 30 --gh 480 --desc "Built the thing"
#   log-ghost-hours.sh --type speed --hugr 60 --gh 120 --desc "Wrote social posts"
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
AMEND="" AMEND_FIELDS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)     TYPE="$2";     shift 2 ;;
    --hugr|--human) HUMAN="$2"; shift 2 ;;
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
    --amend)    AMEND="$2";    shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# --- Amend mode ---
if [[ -n "$AMEND" ]]; then
  # Collect changed fields into a JSON object
  # At least one field must be provided
  python3 - "$AMEND" "$NOTE" "$FWC" "$DESC" "$SUBTYPE" "$GH_CONF" "$TAGS" "$BACKLOG" "$HUMAN" "$GH" "$TYPE" "$PROJECT" "$SOURCE" "$WRITER" << 'AMENDEOF'
import sys
import os
import json
import importlib.util

args = sys.argv[1:]
session_prefix = args[0]
note, fwc, desc, subtype = args[1], args[2], args[3], args[4]
gh_conf, tags_str, backlog, human = args[5], args[6], args[7], args[8]
gh, type_, project, source, writer_path = args[9], args[10], args[11], args[12], args[13]

# Import writer
spec = importlib.util.spec_from_file_location("ghost_hours_writer", writer_path)
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)

# Find the full session_id by prefix
entries = w.read_log()
match = None
for e in entries:
    sid = e.get("session_id", "")
    if sid.startswith(session_prefix):
        match = e
        break

if not match:
    print(f"Error: No session found matching prefix '{session_prefix}'", file=sys.stderr)
    sys.exit(1)

full_sid = match["session_id"]

# Build changes dict from provided fields
changes = {}
if note:
    changes["note"] = note
if fwc:
    changes["fwc"] = int(fwc)
if desc:
    changes["desc"] = desc
if subtype:
    changes["subtype"] = subtype
if gh_conf:
    changes["gh_confidence"] = gh_conf
if tags_str:
    changes["tags"] = [t.strip() for t in tags_str.split(",") if t.strip()]
if backlog:
    changes["backlog_months"] = float(backlog)
    changes["backlog_weight"] = w.calculate_backlog_weight(float(backlog))
if human:
    changes["human_mins"] = int(human)
if gh:
    changes["gh_mins"] = int(gh)
if type_:
    changes["type"] = type_
if project:
    changes["project"] = project

if not changes:
    print("Error: --amend requires at least one field to change.", file=sys.stderr)
    print("  Supported: --note, --fwc, --desc, --subtype, --confidence,", file=sys.stderr)
    print("             --tags, --backlog, --hugr, --gh, --type, --project", file=sys.stderr)
    sys.exit(1)

# Build and log the amendment
entry = w.build_amendment_entry(full_sid, changes, source=source or "claude-cli")
w.log_entry(entry)

print(f"\nAmendment logged:")
print(f"  Session    : {full_sid[:8]}...")
print(f"  Changed    : {', '.join(changes.keys())}")
for k, v in changes.items():
    print(f"  {k:12s}: {v}")
print(f"\nOriginal entry preserved. Reports will show corrected values.")
print()
AMENDEOF
  exit $?
fi

# --- Normal log mode ---
if [[ -z "$TYPE" || -z "$HUMAN" || -z "$GH" || -z "$DESC" ]]; then
  echo "Usage: log-ghost-hours.sh --type <unlock|speed> --hugr <mins> --gh <mins> --desc \"description\""
  echo ""
  echo "Required:"
  echo "  --type      unlock | speed"
  echo "  --hugr      minutes the hugr (human+AI) spent"
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
  echo ""
  echo "Amend mode:"
  echo "  --amend     session-id (prefix or full) to amend"
  echo "              Combine with any field flags to change them."
  echo "              Original entry is never mutated."
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
print(f"  Hugr       : {hh_hrs:.1f}h")
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
