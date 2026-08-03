#!/usr/bin/env python3
"""Filter JSONL on stdin to lines whose UTC timestamp falls inside ONE LOCAL calendar day.

Usage:  bus-local-day-filter.py YYYY-MM-DD [--field ts]

The machine layer stores UTC. A local day is a WINDOW over that UTC data:
local midnight -> next local midnight, converted to aware instants and
compared instant-to-instant. Never `grep '"ts": "<local date>'` — the UTC
date prefix is shifted by the UTC offset, so that grep silently drops every
evening event.

Timestamps missing a zone are treated as UTC. Malformed lines are dropped.
"""
import json
import sys
from datetime import datetime, timedelta, timezone


def main():
    args = sys.argv[1:]
    field = "ts"
    if "--field" in args:
        i = args.index("--field")
        field = args[i + 1]
        del args[i : i + 2]
    if len(args) != 1:
        sys.exit("usage: bus-local-day-filter.py YYYY-MM-DD [--field ts]")
    start = datetime.strptime(args[0], "%Y-%m-%d").astimezone()  # local midnight, aware
    end = start + timedelta(days=1)
    for line in sys.stdin:
        s = line.strip()
        if not s:
            continue
        try:
            ts = json.loads(s).get(field, "")
            t = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
        except Exception:
            continue
        if t.tzinfo is None:
            t = t.replace(tzinfo=timezone.utc)
        if start <= t < end:
            sys.stdout.write(line if line.endswith("\n") else line + "\n")


if __name__ == "__main__":
    main()
