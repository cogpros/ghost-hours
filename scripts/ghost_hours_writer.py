#!/usr/bin/env python3
"""
ghost_hours_writer.py -- Core write engine for Ghost Hours.

Handles JSON construction, file locking, UUID generation, validation,
and atomic append. All write operations go through this module.

Platform support: macOS, Linux, Windows.
Dependencies: Python 3.6+ (stdlib only).

Copyright 2026 Raven Systems Inc. Licensed under Apache 2.0.
"""

import json
import os
import sys
import uuid
import math
import stat
from datetime import datetime, timezone
from pathlib import Path

# Platform-specific imports for file locking
if sys.platform == "win32":
    import msvcrt
else:
    import fcntl

SCHEMA_VERSION = "0.9"
MAX_DESC_LENGTH = 280
MAX_NOTE_LENGTH = 1000
MAX_ENTRY_BYTES = 3500
GH_REVIEW_THRESHOLD = 25
DEFAULT_LOG_DIR = Path.home() / ".ghost-hours"
DEFAULT_LOG_PATH = DEFAULT_LOG_DIR / "log.jsonl"
DEFAULT_CONFIG_PATH = DEFAULT_LOG_DIR / "config.json"


class GhostHoursError(Exception):
    pass


class ValidationError(GhostHoursError):
    pass


class WriteError(GhostHoursError):
    pass


def ensure_directory(path=None):
    """Create the ghost-hours directory with correct permissions (700)."""
    d = path or DEFAULT_LOG_DIR
    d = Path(d)
    if not d.exists():
        d.mkdir(parents=True, mode=0o700)
    else:
        current = d.stat().st_mode & 0o777
        if current != 0o700:
            print(f"WARNING: {d} has permissions {oct(current)}, expected 0o700. Fixing.",
                  file=sys.stderr)
            d.chmod(0o700)


def check_file_permissions(filepath):
    """Warn if file permissions are not 600."""
    p = Path(filepath)
    if p.exists():
        current = p.stat().st_mode & 0o777
        if current != 0o600:
            print(f"WARNING: {p} has permissions {oct(current)}, expected 0o600.",
                  file=sys.stderr)


def generate_session_id():
    """Generate a UUID v4 session ID."""
    return str(uuid.uuid4())


def generate_participant_id():
    """Generate a UUID v4 participant ID."""
    return str(uuid.uuid4())


def sanitize_recovery_tag(event_label):
    """
    Generate a recovery tag from event_label.
    Lowercase, spaces to hyphens, strip non-alphanumeric except hyphens,
    append -recovery, max 50 chars.
    """
    if not event_label:
        return None
    tag = event_label.lower().strip()
    tag = tag.replace(" ", "-")
    tag = "".join(c for c in tag if c.isalnum() or c == "-")
    tag = tag.strip("-")
    tag = f"{tag}-recovery"
    if len(tag) > 50:
        tag = tag[:50]
    return tag


def calculate_backlog_weight(backlog_months):
    """BW = sqrt(BM / 12)"""
    if not backlog_months or backlog_months <= 0:
        return 0
    years = backlog_months / 12
    return round(math.sqrt(years), 3)


def validate_session_entry(entry):
    """Validate a session entry against schema rules."""
    required = ["session_id", "ts", "date", "type", "human_mins", "gh_mins",
                "desc", "source", "schema_version"]
    for field in required:
        if field not in entry:
            raise ValidationError(f"Missing required field: {field}")

    if entry["type"] not in ("speed", "unlock"):
        raise ValidationError(f"Invalid type: {entry['type']}. Must be 'speed' or 'unlock'.")

    if entry.get("subtype") and entry["type"] == "speed":
        raise ValidationError("subtype must be null/absent when type is 'speed'.")

    if entry.get("subtype") and entry["subtype"] not in ("restoration", "bypass", "augmentation"):
        raise ValidationError(f"Invalid subtype: {entry['subtype']}")

    if entry.get("fwc") is not None:
        if not (1 <= entry["fwc"] <= 10):
            raise ValidationError(f"FW-C must be 1-10, got {entry['fwc']}")

    desc = entry.get("desc", "")
    if len(desc) > MAX_DESC_LENGTH:
        raise ValidationError(
            f"desc exceeds {MAX_DESC_LENGTH} chars ({len(desc)}). Shorten it.")

    note = entry.get("note", "")
    if note and len(note) > MAX_NOTE_LENGTH:
        raise ValidationError(
            f"note exceeds {MAX_NOTE_LENGTH} chars ({len(note)}). Shorten it.")

    if entry.get("gh_confidence") and entry["gh_confidence"] not in ("low", "medium", "high", "review"):
        raise ValidationError(f"Invalid gh_confidence: {entry['gh_confidence']}")


def validate_retrospection_entry(entry):
    """Validate a retrospection entry."""
    required = ["ts", "date", "type", "session_id", "fwr", "source", "schema_version"]
    for field in required:
        if field not in entry:
            raise ValidationError(f"Missing required field: {field}")
    if entry["type"] != "retrospection":
        raise ValidationError("Retrospection entry must have type 'retrospection'.")
    if not (1 <= entry["fwr"] <= 10):
        raise ValidationError(f"FW-R must be 1-10, got {entry['fwr']}")


def validate_amendment_entry(entry):
    """Validate an amendment entry."""
    required = ["ts", "type", "session_id", "changes", "source", "schema_version"]
    for field in required:
        if field not in entry:
            raise ValidationError(f"Missing required field: {field}")
    if entry["type"] != "amendment":
        raise ValidationError("Amendment entry must have type 'amendment'.")
    if not isinstance(entry["changes"], dict) or not entry["changes"]:
        raise ValidationError("Amendment must contain non-empty 'changes' dict.")


def _lock_and_append(filepath, json_line):
    """
    Acquire exclusive lock, append JSON line, release lock.
    Uses fcntl on Mac/Linux, msvcrt on Windows.
    """
    filepath = Path(filepath)

    line_bytes = (json_line + "\n").encode("utf-8")
    if len(line_bytes) > MAX_ENTRY_BYTES:
        print(f"WARNING: Entry is {len(line_bytes)} bytes (>{MAX_ENTRY_BYTES}). "
              "PIPE_BUF atomicity not guaranteed, but file lock protects integrity.",
              file=sys.stderr)

    try:
        if sys.platform == "win32":
            fd = os.open(str(filepath), os.O_WRONLY | os.O_APPEND | os.O_CREAT)
            try:
                msvcrt.locking(fd, msvcrt.LK_LOCK, 1)
                os.write(fd, line_bytes)
                msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
            finally:
                os.close(fd)
        else:
            with open(filepath, "a") as f:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX)
                try:
                    f.write(json_line + "\n")
                    f.flush()
                finally:
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)

        # Ensure 600 permissions
        filepath.chmod(0o600)

    except Exception as e:
        # CRITICAL: Print the entry so the user can recover it
        print("\n=== WRITE FAILED === Entry preserved below for manual recovery:",
              file=sys.stderr)
        print(json_line, file=sys.stderr)
        print(f"=== Error: {e} ===\n", file=sys.stderr)
        raise WriteError(f"Failed to append to {filepath}: {e}")


def build_session_entry(
    type_,
    human_mins,
    gh_mins,
    desc,
    source="claude-cli",
    subtype=None,
    gh_confidence=None,
    tags=None,
    backlog_months=None,
    fwc=None,
    note=None,
    project=None,
):
    """Build a validated session entry dict."""
    entry = {
        "session_id": generate_session_id(),
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "date": datetime.now().strftime("%Y-%m-%d"),
        "type": type_,
        "human_mins": int(human_mins),
        "gh_mins": int(gh_mins),
        "desc": desc,
        "source": source,
        "schema_version": SCHEMA_VERSION,
    }

    if subtype:
        entry["subtype"] = subtype
    if gh_confidence:
        entry["gh_confidence"] = gh_confidence
    if tags:
        entry["tags"] = tags
    if backlog_months:
        entry["backlog_months"] = float(backlog_months)
        entry["backlog_weight"] = calculate_backlog_weight(float(backlog_months))
    if fwc is not None:
        entry["fwc"] = int(fwc)
    if note:
        entry["note"] = note
    if project:
        entry["project"] = project

    # Auto-tag high ratios
    ratio = int(gh_mins) / max(int(human_mins), 1)
    if ratio > GH_REVIEW_THRESHOLD:
        entry["gh_confidence"] = "review"

    validate_session_entry(entry)
    return entry


def build_retrospection_entry(session_id, fwr, source="claude-cli"):
    """Build a validated retrospection entry dict."""
    entry = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "date": datetime.now().strftime("%Y-%m-%d"),
        "type": "retrospection",
        "session_id": session_id,
        "fwr": int(fwr),
        "source": source,
        "schema_version": SCHEMA_VERSION,
    }
    validate_retrospection_entry(entry)
    return entry


def build_amendment_entry(session_id, changes, source="claude-cli"):
    """Build a validated amendment entry dict."""
    entry = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "type": "amendment",
        "session_id": session_id,
        "changes": changes,
        "source": source,
        "schema_version": SCHEMA_VERSION,
    }
    validate_amendment_entry(entry)
    return entry


def log_entry(entry, log_path=None):
    """Validate, serialize, and append an entry to the log file."""
    log_path = Path(log_path or DEFAULT_LOG_PATH)
    ensure_directory(log_path.parent)
    check_file_permissions(log_path)

    json_line = json.dumps(entry, ensure_ascii=False)
    _lock_and_append(log_path, json_line)
    return entry


def read_log(log_path=None):
    """Read all valid entries from the log file. Skips malformed lines with warning."""
    log_path = Path(log_path or DEFAULT_LOG_PATH)
    if not log_path.exists():
        return []

    entries = []
    with open(log_path, "r") as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                print(f"WARNING: Malformed JSON on line {i}, skipping.", file=sys.stderr)
    return entries


def apply_amendments(entries):
    """Apply amendment entries to their target sessions. Returns resolved list."""
    sessions = {}
    amendments = []
    others = []

    for e in entries:
        if e.get("type") == "amendment":
            amendments.append(e)
        elif e.get("session_id"):
            sessions[e["session_id"]] = dict(e)
            others.append(e)
        else:
            others.append(e)

    for a in amendments:
        sid = a.get("session_id")
        if sid in sessions:
            for field, value in a.get("changes", {}).items():
                sessions[sid][field] = value

    # Return entries with amendments applied
    result = []
    for e in others:
        sid = e.get("session_id")
        if sid and sid in sessions:
            result.append(sessions[sid])
        else:
            result.append(e)
    return result


def load_config(config_path=None):
    """Load config, return defaults if not found."""
    config_path = Path(config_path or DEFAULT_CONFIG_PATH)
    if config_path.exists():
        with open(config_path, "r") as f:
            return json.load(f)
    return {
        "log_path": str(DEFAULT_LOG_PATH),
        "participant_id": generate_participant_id(),
        "share_reminder": None,
        "sessions_logged": 0,
        "event_label": None,
        "recovery_tag": None,
        "event_label_asked": False,
        "schema_version": SCHEMA_VERSION,
        "setup_date": datetime.now().strftime("%Y-%m-%d"),
    }


def save_config(config, config_path=None):
    """Save config with correct permissions."""
    config_path = Path(config_path or DEFAULT_CONFIG_PATH)
    ensure_directory(config_path.parent)
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    config_path.chmod(0o600)


def increment_session_count(config_path=None):
    """Increment sessions_logged counter. Advisory -- drift in multi-agent is acceptable."""
    config = load_config(config_path)
    config["sessions_logged"] = config.get("sessions_logged", 0) + 1
    save_config(config, config_path)
    return config["sessions_logged"]


if __name__ == "__main__":
    print("ghost_hours_writer.py -- Ghost Hours core write engine")
    print(f"Schema version: {SCHEMA_VERSION}")
    print(f"Default log: {DEFAULT_LOG_PATH}")
    print(f"Platform: {sys.platform}")
    print(f"Locking: {'msvcrt' if sys.platform == 'win32' else 'fcntl'}")
