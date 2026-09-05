#!/usr/bin/env python3
"""
session-fact-sheet.py — extract fact sheet from a Claude Code, Codex, or Grok Build transcript.

Usage:
    session-fact-sheet.py <session.jsonl>
    session-fact-sheet.py            # auto-pick this session (or most recent)
    session-fact-sheet.py --print-session-id
    session-fact-sheet.py --runtime codex --session-id ID --transcript PATH --json

Explicit runtime binding requires a matching native session ID and transcript.
Grok Build expects chat_history.jsonl and its sibling events.jsonl. --seat is
optional caller attribution; its default is the runtime name.

Emits the fact sheet to stdout. No appraisal fields are filled — those are
the operator's hand. This script populates only the mechanical fields.

Mechanical fields produced:
    - Session ID, wall-clock window (hh:mm, local time)
    - Idle gaps (count, durations, total) — gap > IDLE_THRESHOLD_MIN
    - Human time (gap before each operator message: reading + deciding + typing)
    - Agent time (between user→assistant boundaries, below idle threshold)
    - Hugr time (Human total + Agent)
    - Tool calls by type, files created/edited, skills invoked
    - Classification (AUGMENTATION if configured judgment-amplifier skills
      fired, else SPEED/BYPASS pending operator)
    - Intent (first operator string message, truncated)

All operator-fill fields are left as `_____` placeholders.

Config:
    CLOSING_TIME_AUGMENTATION_SKILLS — comma-separated skill names whose
        invocation auto-classifies a session as AUGMENTATION. Populate with
        your own judgment-amplifier skills (adversarial review, synthesis,
        deep-analysis skills). Unset = no auto-classification.
"""

from __future__ import annotations

import argparse
import json
import re
import os
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

# Skills whose invocation triggers AUGMENTATION classification. Configure via
# env; the set ships empty so classification defaults to the operator's pick.
AUGMENTATION_SKILLS = {
    s.strip()
    for s in os.environ.get("CLOSING_TIME_AUGMENTATION_SKILLS", "").split(",")
    if s.strip()
}

# Threshold above which a gap counts as idle (operator stepped away).
IDLE_THRESHOLD_MIN = 15


CODEX_SESSION_ID_RE = re.compile(
    r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$",
    re.IGNORECASE,
)

CODEX_TOOL_NAMES = {
    "apply_patch": "Edit",
    "exec_command": "Bash",
    "read_mcp_resource": "Read",
    "view_image": "Read",
    "web__run": "Web",
}

HOST_INJECTED_USER_PREFIXES = (
    "# AGENTS.md instructions for ",
    "<environment_context>",
)


def parse_ts(s: str) -> datetime:
    """Parse ISO-8601 timestamp from session JSONL."""
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s)


def to_local(dt: datetime) -> datetime:
    return dt.astimezone()


def fmt_hhmm(dt: datetime) -> str:
    return dt.strftime("%H:%M")


def fmt_date(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d %a")


def fmt_mins(mins: float) -> str:
    if mins < 1:
        return "<1m"
    h = int(mins) // 60
    m = int(mins) % 60
    if h:
        return f"{h}h {m}m"
    return f"{m}m"


def _last_event_ts(path: Path) -> float:
    """Return the latest event timestamp in the JSONL as epoch seconds. 0.0 if none.

    Reads from the END of the file (last few KB) — far cheaper than parsing the whole
    file, and the tail is where the freshest event lives. Used as the primary sort key
    in auto_pick_session() so that when multiple sessions are open concurrently and
    share an mtime, the one with the most recent CONVERSATIONAL activity wins —
    not just whichever file the OS happened to flush first.
    """
    try:
        size = path.stat().st_size
        with open(path, "rb") as f:
            f.seek(max(0, size - 8192))
            tail = f.read().decode("utf-8", errors="ignore")
        latest = 0.0
        for line in tail.splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = d.get("timestamp")
            if not ts:
                continue
            try:
                t = parse_ts(ts).timestamp()
                if t > latest:
                    latest = t
            except Exception:
                continue
        return latest
    except Exception:
        return 0.0


def session_id_from_path(path: Path) -> str:
    """Return the runtime session UUID from a Claude or Codex transcript path."""
    match = CODEX_SESSION_ID_RE.search(path.stem)
    return match.group(1) if match else path.stem



def project_dir() -> Path:
    """Resolve the Claude Code projects dir holding this session's JSONL.

    Claude Code stores transcripts under ~/.claude/projects/<cwd with / -> ->.  # commit-leak-scan: allow (generic Claude Code transcript dir, load-bearing)
    If the cwd-derived dir doesn't exist (the close is running from elsewhere),
    fall back to the most recently modified project dir.
    """
    root = Path.home() / ".claude" / "projects"
    derived = root / os.getcwd().replace("/", "-")
    if derived.is_dir():
        return derived
    candidates = [d for d in root.glob("*") if d.is_dir()]
    if not candidates:
        sys.exit(f"No project dirs found under {root}")
    candidates.sort(key=lambda d: d.stat().st_mtime, reverse=True)
    return candidates[0]


def auto_pick_session() -> Path:
    """Pick THIS session's JSONL deterministically via $CLAUDE_CODE_SESSION_ID.

    Claude Code exports CLAUDE_CODE_SESSION_ID into every subprocess env — it is
    the canonical, race-free identity of the session running right now. Use it.
    The most-recent-event heuristic is a guess that can pick the WRONG session
    whenever multiple sessions run in parallel.

    Precedence:
      1. $CLAUDE_CODE_SESSION_ID -> <proj>/<id>.jsonl  (deterministic; the normal case).
      2. Heuristic fallback (latest-event-timestamp) ONLY when the env var is absent —
         e.g. a scheduler-spawned close with no live session env. Warns loudly first.
    """
    proj_dir = project_dir()
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "").strip()
    if sid:
        p = proj_dir / f"{sid}.jsonl"
        if p.exists():
            return p
        sys.stderr.write(
            f"WARN: CLAUDE_CODE_SESSION_ID={sid} but {p} not found; "
            "falling back to most-recent heuristic (may pick wrong session).\n"
        )
    candidates = list(proj_dir.glob("*.jsonl"))
    if not candidates:
        sys.exit(f"No session JSONL found in {proj_dir}")
    if not sid:
        sys.stderr.write(
            "WARN: CLAUDE_CODE_SESSION_ID unset (env-less close?); guessing most-recent "
            "session by event timestamp — verify INTENT before any protocol write.\n"
        )
    # Sort: latest event timestamp first, mtime as tiebreaker.
    candidates.sort(key=lambda p: (_last_event_ts(p), p.stat().st_mtime), reverse=True)
    return candidates[0]


def _codex_message_content(payload: dict) -> list[dict]:
    """Convert Codex input_text/output_text blocks to Claude-style text blocks."""
    out: list[dict] = []
    for block in payload.get("content", []):
        if not isinstance(block, dict):
            continue
        if block.get("type") not in {"input_text", "output_text", "text"}:
            continue
        text = block.get("text", "")
        if text:
            out.append({"type": "text", "text": text})
    return out


def _codex_tool_uses(payload: dict) -> list[dict]:
    """Convert one Codex wrapper call into the concrete nested tool calls it carries."""
    raw_input = payload.get("input", "")
    if not isinstance(raw_input, str):
        raw_input = ""
    nested = re.findall(r"\btools\.([A-Za-z0-9_]+)\s*\(", raw_input)
    names = nested or [payload.get("name", "?")]
    uses = [
        {
            "type": "tool_use",
            "name": CODEX_TOOL_NAMES.get(name, name),
            "input": {},
        }
        for name in names
    ]

    # Codex rollout JSONL has no native Skill invocation event. A SKILL.md read
    # is insufficient evidence because audits and routers read skills without
    # invoking them. Leave skill telemetry empty rather than contaminate the
    # automatic AUGMENTATION classifier with inferred invocations.
    return uses


def normalize_event(event: dict) -> dict:
    """Normalize Codex response_item records to the Claude-style boundary API."""
    if event.get("type") == "event_msg":
        # Codex lifecycle/token events are emitted while the agent is active.
        # Preserve their timestamps as agent boundaries so those gaps are not
        # silently discarded from mechanical Agent time.
        return {
            "type": "assistant",
            "timestamp": event.get("timestamp"),
            "message": {"content": []},
        }
    if event.get("type") != "response_item":
        return event
    payload = event.get("payload", {})
    if not isinstance(payload, dict):
        return event
    payload_type = payload.get("type")
    timestamp = event.get("timestamp")
    if payload_type == "reasoning":
        return {
            "type": "assistant",
            "timestamp": timestamp,
            "message": {"content": []},
        }
    if payload_type == "message" and payload.get("role") in {"user", "assistant", "developer"}:
        return {
            "type": payload.get("role"),
            "timestamp": timestamp,
            "message": {"content": _codex_message_content(payload)},
        }
    if payload_type == "custom_tool_call":
        return {
            "type": "assistant",
            "timestamp": timestamp,
            "message": {"content": _codex_tool_uses(payload)},
        }
    if payload_type == "custom_tool_call_output":
        return {
            "type": "user",
            "timestamp": timestamp,
            "message": {"content": [{"type": "tool_result"}]},
        }
    return event



def load_events(path: Path) -> list[dict]:
    out = []
    with open(path) as f:
        for line in f:
            try:
                out.append(normalize_event(json.loads(line)))
            except json.JSONDecodeError:
                continue
    return out


def _is_host_injected_user_text(text: str) -> bool:
    stripped = text.lstrip()
    return any(stripped.startswith(prefix) for prefix in HOST_INJECTED_USER_PREFIXES)


def is_operator_message(e: dict) -> bool:
    """True if this user event is a real operator message (not a tool_result mirror)."""
    if e.get("type") != "user":
        return False
    msg = e.get("message", {})
    if not isinstance(msg, dict):
        return False
    content = msg.get("content")
    # String content = direct operator message, excluding host context envelopes.
    if isinstance(content, str):
        return bool(content.strip()) and not _is_host_injected_user_text(content)
    # List content with at least one 'text' block (no tool_result-only) = operator message.
    if isinstance(content, list):
        for c in content:
            if c.get("type") == "text" and not _is_host_injected_user_text(c.get("text", "")):
                return True
        return False
    return False


def is_tool_result(e: dict) -> bool:
    """True if this user event is a tool_result mirror (agent's tool returning)."""
    if e.get("type") != "user":
        return False
    msg = e.get("message", {})
    if not isinstance(msg, dict):
        return False
    content = msg.get("content")
    if isinstance(content, list):
        return any(c.get("type") == "tool_result" for c in content)
    return False


def operator_text(e: dict) -> str:
    msg = e.get("message", {})
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        for c in content:
            if c.get("type") == "text" and not _is_host_injected_user_text(c.get("text", "")):
                return c.get("text", "")
    return ""


def assistant_tool_uses(e: dict) -> list[dict]:
    """Return list of tool_use blocks in this assistant event."""
    msg = e.get("message", {})
    if not isinstance(msg, dict):
        return []
    content = msg.get("content", [])
    if not isinstance(content, list):
        return []
    return [c for c in content if c.get("type") == "tool_use"]


def read_records(path: Path) -> list[dict]:
    """Read a stable JSONL prefix, allowing an unfinished last write only."""
    lines = path.read_text().splitlines()
    records = []
    for index, line in enumerate(lines):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            if index == len(lines) - 1:
                break
            raise ValueError(f"Malformed transcript record at line {index + 1}")
        if not isinstance(record, dict):
            raise ValueError("Transcript records must be objects")
        records.append(record)
    return records


def grok_events(path: Path, records: list[dict]) -> list[dict]:
    """Join native query order to native turn order, rejecting ambiguous joins."""
    queries = []
    for record in records:
        if record.get("type") != "user" or record.get("synthetic_reason"):
            continue
        content = record.get("content", "")
        if isinstance(content, list):
            content = "".join(b.get("text", "") for b in content if isinstance(b, dict))
        match = re.search(r"<user_query>(.*?)</user_query>", content, re.DOTALL)
        if match:
            queries.append(match.group(1).strip())
    native_events = read_records(path.with_name("events.jsonl"))
    starts = [e for e in native_events if e.get("type") == "turn_started"]
    if not queries or len(starts) != len(queries):
        raise ValueError("Grok query/turn counts differ; timing join unavailable")
    out = []
    query_index = 0
    active = False
    previous = None
    for event in native_events:
        kind = event.get("type")
        if kind not in {"turn_started", "turn_ended", "tool_started", "tool_ended"}:
            continue
        timestamp = event.get("ts")
        if not timestamp:
            raise ValueError("Grok turn/tool timestamp unavailable")
        parsed = parse_ts(timestamp)
        if parsed.tzinfo is None or (previous is not None and parsed < previous):
            raise ValueError("Grok timestamps must be ordered and timezone aware")
        previous = parsed
        if kind == "turn_started":
            if active:
                raise ValueError("Overlapping Grok turns; timing join unavailable")
            active = True
            out.append({"type": "user", "timestamp": timestamp,
                        "message": {"content": queries[query_index]}})
            query_index += 1
        else:
            if not active:
                raise ValueError("Grok turn/tool event outside a turn")
            content = []
            if kind == "tool_started":
                content.append({"type": "tool_use", "name": event.get("tool_name", "?"), "input": {}})
            out.append({"type": "assistant", "timestamp": timestamp,
                        "message": {"content": content}})
            if kind == "turn_ended":
                active = False
    return out


def bind_transcript(args: argparse.Namespace) -> tuple[Path, str, list[dict]]:
    """Explicit CLI binding never invokes latest-session discovery."""
    if not args.session_id or not args.transcript:
        raise ValueError("--runtime requires --session-id and --transcript")
    path = Path(args.transcript).expanduser().resolve(strict=True)
    records = read_records(path)
    if args.runtime == "grok":
        if path.name != "chat_history.jsonl" or path.parent.name != args.session_id:
            raise ValueError("Grok transcript path does not match session ID")
        return path, args.session_id, grok_events(path, records)
    if session_id_from_path(path) != args.session_id:
        raise ValueError("Transcript filename does not match session ID")
    codex_meta = [e.get("payload", {}) for e in records if e.get("type") == "session_meta"]
    if args.runtime == "codex":
        if not codex_meta or any(e.get("id") != args.session_id for e in codex_meta):
            raise ValueError("Codex session metadata does not match runtime/session ID")
    else:
        if codex_meta or any(e.get("type") == "response_item" for e in records):
            raise ValueError("Transcript is not a Claude transcript")
        native = [e for e in records if e.get("type") in {"user", "assistant"} and isinstance(e.get("message"), dict)]
        if not native or any(e.get("sessionId", args.session_id) != args.session_id for e in records):
            raise ValueError("Claude transcript does not match runtime/session ID")
    events = [normalize_event(e) for e in records]
    for event in events:
        if event.get("type") not in {"user", "assistant"} or not isinstance(event.get("message"), dict):
            continue
        try:
            timestamp = parse_ts(event["timestamp"])
            if timestamp.tzinfo is None:
                raise ValueError("timezone missing")
        except (KeyError, TypeError, ValueError, AttributeError):
            raise ValueError("Conversational timestamp missing or invalid; mechanical timing unavailable")
    return path, args.session_id, events



def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?")
    parser.add_argument("--runtime", choices=("claude", "codex", "grok"))
    parser.add_argument("--session-id")
    parser.add_argument("--transcript")
    parser.add_argument("--seat")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--print-session-id", action="store_true")
    args = parser.parse_args()
    if args.runtime:
        if args.path:
            parser.error("Use --transcript with --runtime, not a positional path")
        try:
            path, session_id, events = bind_transcript(args)
        except (OSError, ValueError, TypeError) as exc:
            parser.error(str(exc))
    else:
        if args.session_id or args.transcript or args.seat or args.json:
            parser.error("Explicit binding and --json require --runtime")
        path = Path(args.path).expanduser() if args.path else auto_pick_session()
        if not path.is_file():
            parser.error(f"Not found: {path}")
        session_id = session_id_from_path(path)
        events = load_events(path)
    if args.print_session_id:
        print(session_id)
        return 0

    if not events:
        sys.exit(f"No events parsed from {path}")

    # ── Wall-clock window ────────────────────────────────────────────────
    timestamps = []
    for e in events:
        ts = e.get("timestamp")
        if ts:
            try:
                timestamps.append((parse_ts(ts), e))
            except Exception:
                pass
    if not timestamps:
        sys.exit("No timestamped events.")
    timestamps.sort(key=lambda x: x[0])
    first_ts = timestamps[0][0]
    last_ts = timestamps[-1][0]
    wall_min = (last_ts - first_ts).total_seconds() / 60.0

    # ── Idle gaps + role-tagged gaps (human / agent) ─────────────────────
    # Classify each gap by the NEXT event:
    #   next event is operator_message → gap is HUMAN (reading/deciding/typing
    #     before sending — the time between agent's last response and operator's next msg)
    #   next event is assistant         → gap is AGENT (processing/generating —
    #     time between operator msg and agent's response, and during tool flows)
    #   next event is other (tool_result, system, file-history, etc.) → skip
    #     (these are sub-second and don't change actor responsibility)
    # If gap > IDLE_THRESHOLD_MIN, it's idle — operator stepped away.
    idle_gaps_min: list[float] = []
    human_gap_min = 0.0
    agent_gap_min = 0.0

    prev_ts = first_ts
    for ts, e in timestamps:
        gap = (ts - prev_ts).total_seconds() / 60.0
        if gap > IDLE_THRESHOLD_MIN:
            idle_gaps_min.append(gap)
        elif gap > 0:
            if is_operator_message(e):
                human_gap_min += gap
            elif e.get("type") == "assistant":
                agent_gap_min += gap
            elif is_tool_result(e):
                # Tool was executing during this gap — agent time.
                agent_gap_min += gap
            # other event types (system, file-history-snapshot, etc.): skip
        prev_ts = ts

    # Human time has only one mechanical signal: the gap before each operator message.
    # That signal lumps reading + deciding + typing together — there's no way to
    # separate them from session events. The operator can override the value if
    # they were thinking offline (e.g., away from the keyboard but still working).
    human_total = human_gap_min
    hugr_total = human_total + agent_gap_min

    # ── Activity counts ──────────────────────────────────────────────────
    tool_names: Counter[str] = Counter()
    skill_invocations: list[str] = []
    files_created: set[str] = set()
    files_edited: set[str] = set()
    files_read: set[str] = set()

    for e in events:
        if e.get("type") != "assistant":
            continue
        for tu in assistant_tool_uses(e):
            name = tu.get("name", "?")
            tool_names[name] += 1
            inp = tu.get("input", {})
            if name == "Skill":
                skill_invocations.append(inp.get("skill", "?"))
            elif name == "Write":
                p = inp.get("file_path")
                if p:
                    files_created.add(p)
            elif name == "Edit":
                p = inp.get("file_path")
                if p:
                    files_edited.add(p)
            elif name == "Read":
                p = inp.get("file_path")
                if p:
                    files_read.add(p)

    files_unique = files_created | files_edited | files_read

    # ── Classification ───────────────────────────────────────────────────
    augmentation_skills_seen = sorted(set(skill_invocations) & AUGMENTATION_SKILLS)
    if augmentation_skills_seen:
        classification = "AUGMENTATION"
        class_reason = f"configured judgment-amplifier skills fired: {', '.join('/' + s for s in augmentation_skills_seen)}"
    else:
        classification = "SPEED-or-BYPASS  (operator pick)"
        class_reason = "no configured judgment-amplifier skills fired"

    # ── Intent (first operator message) ──────────────────────────────────
    intent_text = ""
    for ts, e in timestamps:
        if is_operator_message(e):
            intent_text = operator_text(e).strip().split("\n")[0]
            break
    if len(intent_text) > 240:
        intent_text = intent_text[:237] + "..."

    # ── Render ───────────────────────────────────────────────────────────
    first_loc = to_local(first_ts)
    last_loc = to_local(last_ts)

    out: list[str] = []
    p = out.append

    p("═" * 72)
    p(f"SESSION FACT SHEET — {fmt_date(first_loc)} {fmt_hhmm(first_loc)} → {fmt_date(last_loc)} {fmt_hhmm(last_loc)}")
    p(f"Session ID: {session_id}")
    p("═" * 72)
    p("")
    p("INTENT  (auto, first user message)")
    p(f"  > {intent_text}")
    p("")
    p("TIME")
    p(f"  Wall-clock window:        {fmt_hhmm(first_loc)} → {fmt_hhmm(last_loc)}  ({fmt_mins(wall_min)} raw)")
    if idle_gaps_min:
        gap_strs = ", ".join(fmt_mins(g) for g in idle_gaps_min)
        p(f"  Idle gaps:                {len(idle_gaps_min)} gaps · {gap_strs} · {fmt_mins(sum(idle_gaps_min))} total  (>{IDLE_THRESHOLD_MIN}m threshold)")
    else:
        p(f"  Idle gaps:                none  (>{IDLE_THRESHOLD_MIN}m threshold)")
    p(f"  Human time (mechanical):    {fmt_mins(human_total)}   reading + deciding + typing  →  edit if you were thinking offline: _____")
    p(f"  Agent time (mechanical):    {fmt_mins(agent_gap_min)}   processing + tool execution + generation")
    p(f"  ──────────────────────────────")
    p(f"  HUGR TIME:                  {fmt_mins(hugr_total)}   (Human + Agent, parallel-billable)")
    p("")
    p("ACTIVITY")
    tool_summary = " · ".join(f"{c} {n}" for n, c in tool_names.most_common())
    p(f"  Tool calls:    {tool_summary}")
    p(f"  Files:         {len(files_unique)} unique · {len(files_created)} created · {len(files_edited)} edited · {len(files_read)} read")
    if skill_invocations:
        unique_skills = sorted(set(skill_invocations))
        p(f"  Skills used:   {' · '.join('/' + s for s in unique_skills)}")
    else:
        p(f"  Skills used:   (none)")
    p("")
    p("CLASSIFICATION  (auto)")
    p(f"  Type:          {classification}")
    p(f"  Reason:        {class_reason}")
    p("")
    p("WORK SHIPPED")
    p("  • (auto-pulled bullets from completed TaskList items go here)")
    p("  • (git diff stats if any repo touched)")
    p("  • (new files created on disk)")
    p("  • (memory files written)")
    p("")
    p("  Narrator note:  _____")
    p("")
    p("DRIFT  (agent suggests, you confirm)")
    p("  Suggestion:    _____   (Stayed on intent · Adjacent · Pivoted · Snowballed)")
    p("  Confirmed:     _____")
    p("")
    p("GHOST HOURS APPRAISAL  (your hand)")
    if classification == "AUGMENTATION":
        p("  Frame:         solo-time + team-elapsed wall-clock")
        p('  Anchor:        "Hire-and-coordinate elapsed?"')
        p("  Type ceiling:  no universal cap (use elapsed-with-team frame)")
    else:
        p("  Frame:         (depends on operator pick — see per-type table below)")
    p("")
    p("  Your GH (mins):   _____")
    p("  Your FW-C (1-10): _____    1: Box · 3: Plumbing · 5: Solid · 7: Compound · 8: Milestone · 10: New altitude")
    p("  Note:             _____")
    p("")
    p("PER-TYPE ANCHORS  (reference)")
    p("  Speed         · solo person-hours                · 'If alone, no AI, how long?'         · 10x HH ceiling")
    p("  Restoration   · solo with pain/slowness         · 'Alone now without restored cap?'    · 15x HH ceiling")
    p("  Bypass        · solo + hire-and-coordinate      · 'Your time + freelancer + sync wait' · 50x HH ceiling")
    p("  Augmentation  · solo + team-elapsed wall-clock  · 'Hire-and-coordinate elapsed?'       · no universal cap")
    p("")
    p("═" * 72)

    fact_sheet = "\n".join(out)
    if args.json:
        if len(timestamps) < 2 or last_ts <= first_ts:
            parser.error("Timing unavailable: at least two distinct timestamps are required")
        print(json.dumps({
            "session_id": session_id, "runtime": args.runtime,
            "seat": args.seat or args.runtime,
            "source": args.runtime + "-cli", "transcript_path": str(path),
            "human_mins": human_total, "agent_mins": agent_gap_min,
            "hugr_mins": hugr_total, "timing_source": "mechanical",
            "intent": intent_text, "fact_sheet": fact_sheet,
            "user_quotes": [operator_text(e) for e in events if is_operator_message(e)],
        }))
    else:
        print(fact_sheet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
