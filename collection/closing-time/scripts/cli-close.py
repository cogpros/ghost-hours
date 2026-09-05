#!/usr/bin/env python3
"""Bound-session receipts for delegated CLI closing. No sweep or outbound pushes."""
import argparse
import contextlib
import io
import math
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "scripts"))
import ghost_hours_writer as writer

SOURCES = {"claude": "claude-cli", "codex": "codex-cli", "grok": "grok-cli"}


def read(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".close-")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(value, f, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def state():
    return Path(os.environ.get("CLOSING_TIME_STATE", str(Path.home() / ".closing-time/state"))).expanduser()


def log_path():
    return writer.resolve_log_path()


def run(argv, explain=False):
    result = subprocess.run([str(x) for x in argv], text=True, capture_output=True)
    if result.returncode:
        # Writer stdout can contain the private blind score. Do not echo it.
        if explain and result.stderr.strip():
            raise ValueError(result.stderr.strip().splitlines()[-1])
        raise ValueError(f"{Path(argv[0]).name} failed (exit {result.returncode}); no completion receipt")
    return result.stdout


def rows(path):
    if path.exists():
        with path.open() as f:
            for line in f:
                if line.strip():
                    yield json.loads(line)


def measurement(binding):
    found = [r for r in rows(log_path()) if r.get("session_id") == binding["session_id"]
             and r.get("type") in ("speed", "unlock")]
    if len(found) != 1:
        raise ValueError("Expected one canonical measurement for the bound session")
    row = found[0]
    required = {"source": SOURCES[binding["runtime"]], "seat": binding["seat"],
                "entry_class": "human", "fwc_source": "agent-blind",
                "fwc_eom": binding["blind_fwc"]}
    if any(row.get(k) != v for k, v in required.items()):
        raise ValueError("Measurement attribution or blind-score receipt does not match binding")
    if "operator-override-fill" not in row.get("tags", []):
        raise ValueError("Missing delegated-estimate tag")
    return row


def validate_sheet(path, binding):
    text = path.read_text()
    if binding["session_id"] not in text or "agent-estimated" not in text.lower():
        raise ValueError("Fact sheet must identify this session and mark agent-estimated appraisal")


def prepare(args):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,159}", args.session_id):
        raise ValueError("Unsafe session ID")
    target = state() / "closing-time-cli" / f"{args.session_id}.json"
    identity = {"session_id": args.session_id, "runtime": args.runtime, "seat": args.seat,
                "transcript_path": str(Path(args.transcript).expanduser().resolve())}
    if target.exists():
        binding = read(target)
        if any(binding.get(k) != v for k, v in identity.items()):
            raise ValueError("Existing close binding belongs to a different runtime or transcript")
        print(target)  # Keep the original blind score on retries.
        return
    output = run([sys.executable, HERE / "session-fact-sheet.py", "--runtime", args.runtime,
                  "--session-id", args.session_id, "--transcript", args.transcript,
                  "--seat", args.seat, "--json"], explain=True)
    binding = json.loads(output)
    if any(binding.get(k) != v for k, v in identity.items()):
        raise ValueError("Extractor identity does not match the requested session")
    binding.update(identity, blind_fwc=args.blind_score)
    save(target, binding)
    print(target)


def write_log(args, binding):
    appraisal = read(args.appraisal)
    sheet = Path(args.fact_sheet).expanduser().resolve()
    validate_sheet(sheet, binding)
    mins = binding.get("hugr_mins")
    if type(mins) not in (int, float) or not math.isfinite(mins) or mins <= 0:
        raise ValueError("Mechanical timing unavailable; cannot log this close as measured")
    if appraisal.get("type") not in ("speed", "unlock"):
        raise ValueError("Appraisal type must be speed or unlock")
    for key in ("gh_mins", "fwc"):
        if type(appraisal.get(key)) is not int:
            raise ValueError(f"Appraisal {key} must be an integer")
    note = appraisal.get("note", "")
    if note and not any(note in quote for quote in binding.get("user_quotes", [])):
        raise ValueError("Note is not a verbatim substring of an operator message")
    tags = list(dict.fromkeys(["operator-override-fill"] + appraisal.get("tags", [])))
    entry = writer.build_session_entry(
        type_=appraisal["type"], human_mins=max(1, round(mins)),
        gh_mins=appraisal["gh_mins"], desc=appraisal["desc"],
        source=SOURCES[binding["runtime"]], seat=binding["seat"],
        session_id=binding["session_id"], fwc_source="agent-blind",
        fwc_eom=binding["blind_fwc"], fwc=appraisal["fwc"], tags=tags,
        subtype=appraisal.get("subtype"), backlog_months=appraisal.get("backlog_months"),
        note=note, project=appraisal.get("project"),
        gh_confidence=appraisal.get("gh_confidence"),
    )
    existing = [r for r in rows(log_path()) if r.get("session_id") == binding["session_id"]
                and r.get("type") in ("speed", "unlock")]
    def stable(row):
        return {k: v for k, v in row.items() if k not in ("ts", "date")}
    if existing:
        if len(existing) != 1 or stable(existing[0]) != stable(entry):
            raise ValueError("Session already logged with different values; refusing duplicate close")
    else:
        # Failed writer recovery output includes the private blind score. Keep it
        # out of the public receipt; the appraisal and binding remain available.
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                writer.log_entry(entry)
        except writer.GhostHoursError as exc:
            raise ValueError("Canonical measurement write failed; session remains unsealed") from exc
    row = measurement(binding)
    binding["fact_sheet"] = str(sheet)
    binding["measurement_receipt"] = {k: row.get(k) for k in
                                       ("session_id", "ts", "source", "seat", "fwc_source")}
    save(Path(args.binding), binding)
    print(json.dumps({"session_id": binding["session_id"], "logged": True,
                      "source": row["source"], "fwc": row["fwc"], "fwc_source": row["fwc_source"]}))


def seal(args, binding):
    if not binding.get("measurement_receipt"):
        raise ValueError("No successful measurement receipt; session remains unsealed")
    measurement(binding)
    validate_sheet(Path(binding["fact_sheet"]), binding)
    sid = binding["session_id"]
    marker = state() / "closing-time" / f"{sid}.json"
    was_sealed = marker.exists()
    if not was_sealed:
        run(["bash", HERE / "mark-closed.sh", sid])
    closed = read(marker)
    if closed.get("session_id") != sid or not closed.get("closed_at"):
        raise ValueError("Seal does not match the bound session")
    event_type = "closing_time_cli_facts_emitted"
    event_files = [Path.home() / ".closing-time/events.jsonl"]
    # Only recovery after a seal without a local event receipt needs a bus scan.
    seen = binding.get("event_emitted", False)
    if was_sealed and not seen:
        seen = any(r.get("subject") == sid and r.get("event_type", r.get("type")) == event_type
                   for file in event_files for r in rows(file))
    if not seen:
        body = (f"mode=operator-override-fill fwc_mode=agent-estimated "
                f"seat={binding['seat']} runtime={binding['runtime']} gh_entry_id={sid}")
        run(["bash", HERE / "adapters/emit-event.sh", "closing-time-cli-facts", event_type, sid, body, "ghost-hours"])
    binding["event_emitted"] = True
    save(Path(args.binding), binding)
    print(json.dumps({"session_id": sid, "seat": binding["seat"], "runtime": binding["runtime"],
                      "fact_sheet": binding["fact_sheet"], "closed_at": closed["closed_at"]}))


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("prepare")
    prep.add_argument("--runtime", choices=SOURCES, required=True)
    prep.add_argument("--seat", required=True, help="Your agent seat name (free text)")
    prep.add_argument("--session-id", required=True)
    prep.add_argument("--transcript", required=True)
    prep.add_argument("--blind-score", type=int, choices=range(1, 11), required=True)
    logging = sub.add_parser("log")
    logging.add_argument("--appraisal", required=True)
    logging.add_argument("--fact-sheet", required=True)
    for command in (logging, sub.add_parser("seal")):
        command.add_argument("--binding", required=True)
    args = parser.parse_args()
    sid = args.session_id if args.command == "prepare" else read(args.binding)["session_id"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,159}", sid):
        raise ValueError("Unsafe session ID")
    lock = state() / "closing-time-cli" / f"{sid}.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        if args.command == "prepare":
            prepare(args)
        else:
            binding = read(args.binding)
            (write_log if args.command == "log" else seal)(args, binding)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, writer.GhostHoursError) as exc:
        sys.exit(f"Close incomplete: {exc}")
