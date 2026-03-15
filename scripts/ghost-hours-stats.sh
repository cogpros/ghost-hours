#!/usr/bin/env bash
# ghost-hours-stats.sh -- Show Ghost Hours aggregate stats
#
# Usage:
#   ghost-hours-stats.sh           # all-time
#   ghost-hours-stats.sh --week    # last 7 days
#   ghost-hours-stats.sh --month   # last 30 days
#   ghost-hours-stats.sh --since YYYY-MM-DD
#
# Copyright 2026 Raven Systems Inc. Licensed under Apache 2.0.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRITER="$SCRIPT_DIR/ghost_hours_writer.py"
FILTER="all"
SINCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --week)  FILTER="week";  shift ;;
    --month) FILTER="month"; shift ;;
    --since) FILTER="since"; SINCE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

python3 - "$FILTER" "$SINCE" "$WRITER" << 'PYEOF'
import sys
import importlib.util
import json
from datetime import datetime, timedelta, timezone
from collections import Counter

filter_mode, since_str, writer_path = sys.argv[1], sys.argv[2], sys.argv[3]

spec = importlib.util.spec_from_file_location("ghost_hours_writer", writer_path)
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)

raw_entries = w.read_log()
entries = w.apply_amendments(raw_entries)

sessions = [e for e in entries if e.get("type") in ("speed", "unlock")]
retros = [e for e in entries if e.get("type") == "retrospection"]

now = datetime.now(timezone.utc)
if filter_mode == "week":
    cutoff = now - timedelta(days=7)
    sessions = [e for e in sessions if datetime.fromisoformat(e["ts"].replace("Z", "+00:00")) >= cutoff]
    label = "Last 7 Days"
elif filter_mode == "month":
    cutoff = now - timedelta(days=30)
    sessions = [e for e in sessions if datetime.fromisoformat(e["ts"].replace("Z", "+00:00")) >= cutoff]
    label = "Last 30 Days"
elif filter_mode == "since" and since_str:
    cutoff = datetime.fromisoformat(since_str).replace(tzinfo=timezone.utc)
    sessions = [e for e in sessions if datetime.fromisoformat(e["ts"].replace("Z", "+00:00")) >= cutoff]
    label = f"Since {since_str}"
else:
    label = "All Time"

if not sessions:
    print(f"No sessions found for: {label}")
    sys.exit(0)

speed = [e for e in sessions if e["type"] == "speed"]
unlock = [e for e in sessions if e["type"] == "unlock"]

speed_hh = sum(e.get("human_mins", 0) for e in speed)
speed_gh = sum(e.get("gh_mins", 0) for e in speed)
unlock_hh = sum(e.get("human_mins", 0) for e in unlock)
unlock_gh = sum(e.get("gh_mins", 0) for e in unlock)
total_hh = speed_hh + unlock_hh
total_gh = speed_gh + unlock_gh
cr = total_gh / max(total_hh, 1)
speed_cr = speed_gh / max(speed_hh, 1)

def fmt(mins):
    h = mins / 60
    if h >= 8:
        return f"{h:.0f}h ({h/8:.1f} work-days)"
    return f"{h:.1f}h"

print()
print(f"  ======================================")
print(f"   GHOST HOURS -- {label}")
print(f"  ======================================")
print()
print(f"  TOTAL")
print(f"  Sessions:   {len(sessions)}")
print(f"    Speed:    {len(speed)}")
print(f"    Unlock:   {len(unlock)}")
print(f"  Human:      {fmt(total_hh)}")
print(f"  Ghost:      {fmt(total_gh)}")
print(f"  CR:         {cr:.1f}x")
print()

if speed:
    print(f"  SPEED")
    print(f"  HH: {fmt(speed_hh)} | GH: {fmt(speed_gh)} | CR: {speed_cr:.1f}x")
    print()

if unlock:
    subtypes = Counter(e.get("subtype", "unclassified") for e in unlock)
    print(f"  UNLOCK")
    print(f"  HH: {fmt(unlock_hh)} | GH: {fmt(unlock_gh)}")
    print(f"  Subtypes:")
    for st, count in subtypes.most_common():
        print(f"    {st}: {count}")
    print()

# Backlog
backlog_entries = [e for e in sessions if e.get("backlog_months")]
if backlog_entries:
    total_bm = sum(e["backlog_months"] for e in backlog_entries)
    total_bw = sum(e.get("backlog_weight", 0) for e in backlog_entries)
    print(f"  BACKLOG")
    print(f"  Sessions:   {len(backlog_entries)}")
    print(f"  Cleared:    {total_bm:.1f} months ({total_bm/12:.1f} years)")
    print(f"  Weight:     {total_bw:.2f}")
    print()

# FW-C
fwc_entries = [e for e in sessions if e.get("fwc")]
if fwc_entries:
    fwc_values = [e["fwc"] for e in fwc_entries]
    avg = sum(fwc_values) / len(fwc_values)
    c5 = sum(1 for v in fwc_values if v >= 5)
    c8 = sum(1 for v in fwc_values if v >= 8)
    c10 = sum(1 for v in fwc_values if v == 10)
    print(f"  FELT WEIGHT OF COMPLETION")
    print(f"  Sessions:   {len(fwc_values)}")
    print(f"  Average:    {avg:.1f}")
    print(f"  >= 5:       {c5}")
    print(f"  >= 8:       {c8}")
    print(f"  = 10:       {c10}")
    print()
    dist = Counter(fwc_values)
    print(f"  Distribution:")
    for score in range(1, 11):
        count = dist.get(score, 0)
        bar = "#" * count
        print(f"    {score:2d}: {bar} ({count})")
    print()

# Top 3 by FW-C
top = sorted(fwc_entries, key=lambda e: e.get("fwc", 0), reverse=True)[:3]
if top:
    print(f"  TOP SESSIONS")
    for e in top:
        print(f"    [{e['date']}] FW-C={e['fwc']} | {e['type']} | {e['desc'][:60]}")
    print()

# Notes count
notes = [e for e in sessions if e.get("note")]
print(f"  QUALITATIVE: {len(notes)} sessions with notes")

# Sources
sources = Counter(e.get("source", "unknown") for e in sessions)
print(f"  SOURCES:")
for src, count in sources.most_common():
    print(f"    {src}: {count}")
print()
PYEOF
