"""Regression test for the share export's tag-value privacy boundary."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARE_SCRIPT = ROOT / "scripts" / "ghost-hours-share.sh"


def test_condition_tag_value_never_occurs_in_emitted_export_json():
    with tempfile.TemporaryDirectory() as temp_dir:
        temp = Path(temp_dir)
        home = temp / "home"
        ghost_hours_dir = home / ".ghost-hours"
        ghost_hours_dir.mkdir(parents=True)
        log_path = temp / "input.jsonl"
        config_path = ghost_hours_dir / "config.json"

        log_path.write_text(json.dumps({
            "session_id": "session-privacy-fixture",
            "ts": "2026-01-02T03:04:05Z",
            "date": "2026-01-02",
            "type": "speed",
            "entry_class": "human",
            "human_mins": 10,
            "gh_mins": 20,
            "desc": "fixture",
            "tags": ["condition:diagnosed-tbi", "other:private"],
            "source": "manual",
            "schema_version": "1.0",
        }) + "\n")
        config_path.write_text(json.dumps({
            "participant_id": "fixture-participant",
            "log_path": str(log_path),
        }))

        env = os.environ.copy()
        env.update({"HOME": str(home), "GHOST_HOURS_LOG": str(log_path)})
        result = subprocess.run(
            [str(SHARE_SCRIPT), "--yes"],
            cwd=ROOT,
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )

        export_files = list((log_path.parent / "share").glob("*-export.json"))
        assert len(export_files) == 1
        emitted = json.loads(export_files[0].read_text())
        emitted_json = json.dumps(emitted)
        assert "condition:diagnosed-tbi" not in emitted_json
        assert "diagnosed-tbi" not in emitted_json
        assert all("condition" not in entry for entry in emitted["entries"])
        assert "all tag values are excluded" in result.stdout


if __name__ == "__main__":
    sys.exit(test_condition_tag_value_never_occurs_in_emitted_export_json() or 0)