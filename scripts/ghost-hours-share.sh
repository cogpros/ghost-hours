#!/usr/bin/env bash
# ghost-hours-share.sh -- Export de-identified Ghost Hours data
#
# Generates a share-ready export file stripped of descriptions,
# notes, project names, tags, timestamps, and session IDs. Date only.
# Retrospection scores are folded into their session rows so no
# session_id ever leaves the machine (re-identification vector).
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

sessions = [e for e in entries if e.get("type") in ("speed", "unlock", "methodology-note")]
retros = [e for e in entries if e.get("type") == "retrospection"]

if not sessions:
    print("No sessions to export.")
    sys.exit(0)

# Fields to retain in export (no desc, note, project, tags, ts, session_id)
KEEP_FIELDS = {
    "date", "type", "entry_class", "subtype", "human_mins", "gh_mins",
    "gh_confidence", "backlog_months", "backlog_weight", "fwc",
    "fwc_source", "fwc_eom", "schema_version"
}

# Retrospection scores are folded into their session rows by session_id,
# then the session_id is dropped. Retro entries never export standalone
# with a session_id -- that link is a re-identification vector.
RETRO_KEEP = {"date", "type", "fwr", "fwr_source", "schema_version"}

participant_id = config.get("participant_id", "unknown")

# Index latest retrospection per session
retro_by_session = {}
for r in retros:
    sid = r.get("session_id")
    if sid:
        retro_by_session[sid] = r

x_suppressed_tags = 0
x_suppressed_projects = 0

export_entries = []
matched_retro_sids = set()
for e in sessions:
    if e.get("tags"):
        x_suppressed_tags += 1
    if e.get("project"):
        x_suppressed_projects += 1
    stripped = {k: v for k, v in e.items() if k in KEEP_FIELDS}
    stripped["participant_id"] = participant_id
    r = retro_by_session.get(e.get("session_id"))
    if r is not None:
        stripped["fwr"] = r["fwr"]
        if r.get("fwr_source"):
            stripped["fwr_source"] = r["fwr_source"]
        matched_retro_sids.add(e["session_id"])
    export_entries.append(stripped)

# Orphan retrospections (session not in this log) export without session_id
for r in retros:
    if r.get("session_id") in matched_retro_sids:
        continue
    stripped = {k: v for k, v in r.items() if k in RETRO_KEEP}
    stripped.setdefault("date", r.get("ts", "")[:10])
    stripped["participant_id"] = participant_id
    export_entries.append(stripped)

export = {
    "dataset": "The Ghost Hours Open Dataset 2026",
    "schema_version": w.SCHEMA_VERSION,
    "participant_id": participant_id,
    "export_date": datetime.now().strftime("%Y-%m-%d"),
    "session_count": len(sessions),
    "retrospection_count": len(retros),
    "x_suppressed_tags": x_suppressed_tags,
    "x_suppressed_projects": x_suppressed_projects,
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
print("Fields included: date, type, entry_class, subtype, human_mins, gh_mins,")
print("  gh_confidence, backlog_months, backlog_weight, fwc, fwc_source,")
print("  fwc_eom (agent's blind estimate), fwr, fwr_source")
print()
print("Fields EXCLUDED: desc, note, fwr_note, project, tags, ts, session_id")
print()

if auto_yes != "true":
    confirm = input("Export this data? (y/n): ").strip().lower()
    if confirm != "y":
        print("Cancelled.")
        sys.exit(0)

# Write export
share_dir = w.resolve_log_path().parent / "share"
share_dir.mkdir(parents=True, exist_ok=True)
share_dir.chmod(0o700)

export_file = share_dir / f"{datetime.now().strftime('%Y-%m-%d')}-export.json"
with open(export_file, "w") as f:
    f.write(export_json)
export_file.chmod(0o600)

print(f"Export saved: {export_file}")
print()
print("No network transmission occurs.")
print("Review the file before sharing manually.")
PYEOF
