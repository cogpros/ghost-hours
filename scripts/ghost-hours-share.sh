#!/usr/bin/env bash
# ghost-hours-share.sh -- Export de-identified Ghost Hours data
#
# Generates a share-ready export file stripped of descriptions,
# notes, project names, tags, and timestamps. Date only.
#
# Usage:
#   ghost-hours-share.sh           # interactive
#   ghost-hours-share.sh --yes     # skip confirmation
#
# Copyright 2026 Raven Systems Inc. Licensed under Apache 2.0.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRITER="$SCRIPT_DIR/ghost_hours_writer.py"
AUTO_YES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) AUTO_YES="true"; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

python3 - "$AUTO_YES" "$WRITER" << 'PYEOF'
import sys
import os
import json
import importlib.util
from datetime import datetime
from pathlib import Path

auto_yes, writer_path = sys.argv[1], sys.argv[2]

spec = importlib.util.spec_from_file_location("ghost_hours_writer", writer_path)
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)

config = w.load_config()
raw_entries = w.read_log()
entries = w.apply_amendments(raw_entries)

sessions = [e for e in entries if e.get("type") in ("speed", "unlock")]
retros = [e for e in entries if e.get("type") == "retrospection"]

if not sessions:
    print("No sessions to export.")
    sys.exit(0)

# Fields to retain in export (no desc, note, project, tags, ts)
KEEP_FIELDS = {
    "date", "type", "subtype", "human_mins", "gh_mins", "gh_confidence",
    "backlog_months", "backlog_weight", "fwc", "schema_version"
}

RETRO_KEEP = {"date", "type", "session_id", "fwr", "schema_version"}

participant_id = config.get("participant_id", "unknown")

export_entries = []
for e in sessions:
    stripped = {k: v for k, v in e.items() if k in KEEP_FIELDS}
    stripped["participant_id"] = participant_id
    export_entries.append(stripped)

for e in retros:
    stripped = {k: v for k, v in e.items() if k in RETRO_KEEP}
    stripped["participant_id"] = participant_id
    export_entries.append(stripped)

export = {
    "dataset": "The Ghost Hours Open Dataset 2026",
    "schema_version": w.SCHEMA_VERSION,
    "participant_id": participant_id,
    "export_date": datetime.now().strftime("%Y-%m-%d"),
    "session_count": len(sessions),
    "retrospection_count": len(retros),
    "entries": export_entries,
}

export_json = json.dumps(export, indent=2, ensure_ascii=False)

# Size check
size_bytes = len(export_json.encode("utf-8"))
if size_bytes > 1_000_000:
    print(f"WARNING: Export is {size_bytes} bytes (>1MB limit). Consider exporting a date range.")

print()
print("=== GHOST HOURS SHARE EXPORT PREVIEW ===")
print(f"Participant: {participant_id[:8]}...")
print(f"Sessions: {len(sessions)}")
print(f"Retrospections: {len(retros)}")
print(f"Size: {size_bytes:,} bytes")
print()
print("Fields included: date, type, subtype, human_mins, gh_mins,")
print("  gh_confidence, backlog_months, backlog_weight, fwc, fwr")
print()
print("Fields EXCLUDED: desc, note, project, tags, ts, session_id")
print()

if auto_yes != "true":
    confirm = input("Export this data? (y/n): ").strip().lower()
    if confirm != "y":
        print("Cancelled.")
        sys.exit(0)

# Write export
share_dir = Path(config.get("log_path", str(w.DEFAULT_LOG_PATH))).parent / "share"
share_dir.mkdir(parents=True, exist_ok=True)
share_dir.chmod(0o700)

export_file = share_dir / f"{datetime.now().strftime('%Y-%m-%d')}-export.json"
with open(export_file, "w") as f:
    f.write(export_json)
export_file.chmod(0o600)

print(f"Export saved: {export_file}")
print()
print("In v0.9, no network transmission occurs.")
print("Review the file before sharing manually.")
PYEOF
