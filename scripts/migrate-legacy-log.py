#!/usr/bin/env python3
"""
migrate-legacy-log.py -- Migrate existing log.jsonl to Ghost Hours v0.9 schema.

Adds session_id and schema_version to existing entries.
Creates timestamped backup. Validates entry count after migration.

Usage:
    python3 migrate-legacy-log.py [--input PATH] [--dry-run]

Default input: ~/.openclaw/leverage/log.jsonl
Output: same file (in-place with backup)

Copyright 2026 Raven Systems Inc. Licensed under Apache 2.0.
"""

import json
import sys
import uuid
import math
import shutil
from datetime import datetime
from pathlib import Path

SCHEMA_VERSION = "0.9"


def migrate_entry(entry):
    """Add session_id and schema_version to a legacy entry."""
    migrated = dict(entry)

    # Add session_id if missing
    if "session_id" not in migrated:
        migrated["session_id"] = str(uuid.uuid4())

    # Add schema_version if missing
    if "schema_version" not in migrated:
        migrated["schema_version"] = SCHEMA_VERSION

    # Recompute backlog_weight if backlog_months exists (derived field)
    if migrated.get("backlog_months"):
        bm = float(migrated["backlog_months"])
        years = bm / 12
        migrated["backlog_weight"] = round(math.sqrt(years), 3) if years > 0 else 0

    return migrated


def main():
    dry_run = "--dry-run" in sys.argv
    input_path = None

    for i, arg in enumerate(sys.argv[1:], 1):
        if arg == "--input" and i < len(sys.argv) - 1:
            input_path = Path(sys.argv[i + 1])
        elif arg == "--dry-run":
            pass
        elif not arg.startswith("--"):
            continue

    if input_path is None:
        input_path = Path.home() / ".openclaw" / "leverage" / "log.jsonl"

    if not input_path.exists():
        print(f"Error: {input_path} not found.")
        sys.exit(1)

    # Read all lines
    lines = input_path.read_text().strip().splitlines()
    original_count = len([l for l in lines if l.strip()])

    print(f"Input: {input_path}")
    print(f"Entries found: {original_count}")

    # Parse and migrate
    migrated = []
    quarantine = []
    for i, line in enumerate(lines, 1):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            migrated.append(migrate_entry(entry))
        except json.JSONDecodeError:
            print(f"  WARNING: Line {i} is malformed JSON. Quarantined.")
            quarantine.append(line)

    migrated_count = len(migrated)
    print(f"Migrated: {migrated_count}")
    print(f"Quarantined: {len(quarantine)}")

    if migrated_count + len(quarantine) != original_count:
        print(f"ERROR: Count mismatch! {original_count} original vs {migrated_count + len(quarantine)} processed.")
        sys.exit(1)

    # Check what changed
    already_had_session_id = sum(1 for e in migrated if "session_id" in json.loads(lines[0] if lines else "{}"))
    new_session_ids = sum(1 for e in migrated if True)  # all get checked

    if dry_run:
        print()
        print("DRY RUN -- no files modified.")
        print(f"Would add session_id to entries missing it.")
        print(f"Would add schema_version '{SCHEMA_VERSION}' to all entries.")
        print()
        # Show sample
        if migrated:
            print("Sample migrated entry:")
            print(json.dumps(migrated[0], indent=2, ensure_ascii=False))
        return

    # Create timestamped backup
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = input_path.parent / f"{input_path.name}.bak.{timestamp}"
    shutil.copy2(input_path, backup_path)
    print(f"Backup: {backup_path}")

    # Write migrated file
    output_lines = [json.dumps(e, ensure_ascii=False) for e in migrated]
    input_path.write_text("\n".join(output_lines) + "\n")

    # Validate count
    verify_lines = input_path.read_text().strip().splitlines()
    verify_count = len([l for l in verify_lines if l.strip()])

    if verify_count != migrated_count:
        print(f"ERROR: Verification failed! Expected {migrated_count}, got {verify_count}.")
        print(f"Restoring from backup...")
        shutil.copy2(backup_path, input_path)
        sys.exit(1)

    print(f"Verified: {verify_count} entries.")

    # Write quarantine if any
    if quarantine:
        quarantine_path = input_path.parent / f"{input_path.name}.quarantine.{timestamp}"
        quarantine_path.write_text("\n".join(quarantine) + "\n")
        print(f"Quarantine: {quarantine_path}")

    print()
    print("Migration complete.")
    print(f"  {migrated_count} entries migrated to schema {SCHEMA_VERSION}")
    print(f"  {len(quarantine)} entries quarantined")
    print(f"  Backup at {backup_path}")


if __name__ == "__main__":
    main()
