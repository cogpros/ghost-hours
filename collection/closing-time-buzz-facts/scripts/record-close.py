#!/usr/bin/env python3
"""Record a complete local Buzz capture, canonical measurement, and day seal."""
import argparse
import contextlib
from datetime import date, datetime, timezone
import fcntl
import hashlib
import io
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / 'scripts'))
import ghost_hours_writer as writer


def read(path):
    return json.loads(Path(path).read_text())


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def save(path, value):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.buzz-close-')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(value, f, indent=2)
            f.write('\n')
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def stable(row):
    return {k: v for k, v in row.items() if k not in ('ts', 'date')}


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('capture', 'appraisal', 'report', 'seat'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    capture, appraisal = read(args.capture), read(args.appraisal)
    if capture.get('complete') is not True or capture.get('unknown_writers') != []:
        raise ValueError('Capture is incomplete or contains unresolved writers')
    day = capture['date']
    if date.fromisoformat(day).isoformat() != day:
        raise ValueError('Capture date must be YYYY-MM-DD')
    start, end = (capture[k] for k in ('window_start', 'window_end'))
    if any(type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in (start, end)) or start >= end:
        raise ValueError('Capture window must contain ordered Unix timestamps')
    times = [capture[k] for k in ('human_mins', 'agent_mins')]
    if any(type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in times) or sum(times) <= 0:
        raise ValueError('Capture timing must be available, finite, and positive in total')
    report = Path(args.report).expanduser().resolve()
    if not report.is_file() or not report.read_bytes().strip():
        raise ValueError('An existing nonempty HTML report is required')
    if appraisal.get('type') not in ('speed', 'unlock') or appraisal.get('fwc_source') not in ('operator', 'agent-blind'):
        raise ValueError('Appraisal requires a valid type and explicit score provenance')
    for key in ('gh_mins', 'fwc', 'fwc_eom'):
        if type(appraisal.get(key)) is not int or appraisal[key] < 1:
            raise ValueError(f'Appraisal {key} must be a positive integer')
    if appraisal['fwc'] > 10 or appraisal['fwc_eom'] > 10:
        raise ValueError('FW-C scores must be 1-10')
    key = 'buzz-stack-' + day
    tags = list(appraisal.get('tags', []))
    if appraisal['fwc_source'] == 'agent-blind' and 'operator-override-fill' not in tags:
        tags.append('operator-override-fill')
    entry = writer.build_session_entry(
        type_=appraisal['type'], human_mins=max(1, round(sum(times))), gh_mins=appraisal['gh_mins'],
        desc=appraisal['desc'], source='buzz-stack', session_id=key, seat=args.seat,
        fwc=appraisal['fwc'], fwc_eom=appraisal['fwc_eom'], fwc_source=appraisal['fwc_source'],
        tags=tags, note=appraisal.get('note'), subtype=appraisal.get('subtype'),
        backlog_months=appraisal.get('backlog_months'))
    entry['date'] = day
    root = Path(os.environ.get('CLOSING_TIME_STATE', str(Path.home() / '.closing-time/state'))).expanduser() / 'closing-time-buzz'
    root.mkdir(parents=True, exist_ok=True)
    marker, binding = root / (key + '.json'), root / (key + '.binding.json')
    receipt = dict(key=key, date=day, window_start=capture['window_start'], window_end=capture['window_end'],
                   capture_hash=digest(capture), report=str(report),
                   report_hash=hashlib.sha256(report.read_bytes()).hexdigest(), measurement_hash=digest(stable(entry)))
    with (root / (key + '.lock')).open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if binding.exists() and read(binding) != receipt:
            raise ValueError('Conflicting day capture, appraisal, seat, or report; use an explicit amendment')
        if marker.exists() and any(read(marker).get(k) != v for k, v in receipt.items()):
            raise ValueError('Conflicting existing day seal')
        existing = [r for r in writer.read_log() if r.get('session_id') == key and r.get('type') in ('speed', 'unlock')]
        if existing and (len(existing) != 1 or stable(existing[0]) != stable(entry)):
            raise ValueError('Conflicting existing day measurement')
        save(binding, receipt)  # Freeze the capture before a write so crash retries cannot shift it.
        if not existing:
            with contextlib.redirect_stderr(io.StringIO()):
                writer.log_entry(entry)
        found = [r for r in writer.read_log() if r.get('session_id') == key and r.get('type') in ('speed', 'unlock')]
        if len(found) != 1 or stable(found[0]) != stable(entry):
            raise ValueError('Canonical measurement receipt could not be verified')
        seal = read(marker) if marker.exists() else dict(receipt, sealed_at=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
        event = 'closing_time_buzz_facts_emitted'
        if not seal.get('event_emitted'):
            bus = Path.home() / '.closing-time/events.jsonl'
            seen = bus.exists() and any(r.get('type', r.get('event_type')) == event and r.get('subject') == key
                                       for r in (json.loads(line) for line in bus.read_text().splitlines() if line.strip()))
            if not seen:
                result = subprocess.run(['bash', str(HERE.parents[1] / 'closing-time/scripts/adapters/emit-event.sh'),
                                         'closing-time-buzz-facts', event, key, 'Local Buzz close recorded', 'ghost-hours'],
                                        capture_output=True, text=True)
                if result.returncode:
                    raise ValueError('Completion event failed; measurement retained, day remains unsealed')
            seal['event_emitted'] = True
        save(marker, seal)
    print(json.dumps(dict(key=key, report=str(report), sealed_at=seal['sealed_at'],
                         human_mins=entry['human_mins'], gh_mins=entry['gh_mins'],
                         fwc=entry['fwc'], fwc_source=entry['fwc_source'])))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, writer.GhostHoursError):
        sys.exit('Buzz close incomplete: check capture, appraisal, report, and local write access; no new seal was written.')
