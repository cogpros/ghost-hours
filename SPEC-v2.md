# Ghost Hours -- Open Source Skill Specification

**Version:** 0.9 (public beta)
**Author:** D. Pollock, Raven Systems Inc.
**Date:** 2026-03-15
**Status:** PRISM-reviewed (2 rounds, 3 reviewers). Ready to build.

---

## What This Is

Ghost Hours is an open-source Claude Code skill that measures what AI actually does for people.

Not time saved. Time conjured from the AI's work. What changed.

It classifies every AI-assisted session into a taxonomy that separates speed (faster at what you could already do) from unlock (doing what you couldn't do before), then further separates unlocks into restoration, bypass, and augmentation. It pairs objective metrics (hours conjured, conjure rate) with a subjective experiential measure (Felt Weight of Completion) to produce structured, comparable data from the act of simply using AI and reflecting on it for 60 seconds at the end.

It is two things at once:

1. **A personal productivity instrument.** The user sees their own leverage ratios, capability expansion over time, backlog cleared, and a record of what mattered most.

2. **A distributed research framework.** Every installation generates data in the same schema, using the same taxonomy, on the same scales. Comparable across users without centralized collection. Opt-in sharing routes de-identified data to a research dataset. Cite: Pollock 2026.

The taxonomy is the contribution. The tool is the delivery mechanism.

---

## Positioning

**Name:** Ghost Hours
**Tagline:** Measure what AI actually does for you.
**Publisher:** Raven Systems Inc.
**License:** Apache 2.0 with Raven Systems Inc. copyright
**Repository:** `cogpros/ghost-hours` (GitHub)
**Citation:** Pollock, D. (2026). The Ghost Hours Framework: A Mathematical Model for Measuring AI-Assisted Human Output and the Experience of Capability Expansion. Raven Systems Inc.

---

## The Taxonomy

This is the core intellectual property. Everything else is interface.

### Session Types

| Type | Definition |
|------|-----------|
| **Speed** | Task could have been completed without AI. AI made it faster. |
| **Unlock** | Task could not have been completed without AI. Knowledge barrier, complexity barrier, or accumulated inaction blocked it. |

### Unlock Subtypes

| Subtype | Definition | Tag |
|---------|-----------|-----|
| **Restoration** | Had the capability, lost it to injury/disability/life event, AI gave it back. | tbi-recovery (or user-defined) |
| **Bypass** | Could have learned it before the disabling event, but the event blocked the learning path. AI routes around the gap. | tbi-recovery (or user-defined) |
| **Augmentation** | Never possible for any human working alone, injury or not. AI grants a capability that didn't exist. | -- |

### Why This Matters

No existing framework makes these distinctions. Productivity tools measure speed. Ghost Hours measures capability delta -- the distance between what you are with AI and what you are without it, and whether that distance represents recovery, workaround, or genuine new ground.

For disability and rehabilitation research, the restoration/bypass distinction is the signal. A restoration that later appears as a speed session is measurable functional recovery. That's clinical evidence generated as a byproduct of daily work.

---

## Core Metrics

| Symbol | Name | Definition |
|--------|------|-----------|
| HH | Hugr Hours | Time the hugr (human+AI pair) spent working. Minutes in data, displayed as hours. |
| GH | Ghost Hours | Estimated time a human working alone would need to produce the same output |
| CR | Conjure Rate | GH / HH -- leverage ratio |
| BM | Backlog Months | How long the task sat undone before AI made it possible |
| BW | Backlog Weight | sqrt(BM / 12) -- sub-linear psychological cost of inaction |
| FW-C | Felt Weight of Completion | Self-reported 1-10. How heavy did finishing this feel? |
| FW-R | Felt Weight at Retrospection | Same scale, logged later. How heavy does it feel now? |
| delta-FW | Felt Weight Delta | FW-C minus FW-R. Measures insight accuracy. |

### FW-C Anchor Points

Users should calibrate against these descriptions:

| Score | Anchor |
|-------|--------|
| 1 | Checked a box. Wouldn't remember it happened. |
| 3 | Plumbing. Had to happen. No emotional weight. |
| 5 | Solid work. Moved things forward. Meaningful. |
| 7 | The compound is working. System building on itself. |
| 8 | Capability milestone. First time doing something real. |
| 10 | New altitude. The trajectory changed. |

These anchors are examples, not rules. Users develop their own calibration over time.

**Known pattern:** Early adopter data shows ceiling clustering at FW-C=10 (38% of rated sessions in the first month). This is expected during initial capability expansion -- when everything is new, many completions genuinely feel like new altitude. The distribution should spread as users calibrate against the anchor points over time. Researchers analyzing FW-C distributions should account for onboarding period effects and consider that FW-C may behave logarithmically at the upper end -- the subjective distance between 9 and 10 is not the same as between 4 and 5. Linear analysis of the 1-10 scale may mask real variation at the top.

---

## Data Schema

### Log Format: JSONL

One line per entry. One file. Human-readable. Grep-friendly.

**Default location:** `~/.ghost-hours/log.jsonl`

### Session Entry

```json
{
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "ts": "2026-03-15T04:48:29Z",
  "date": "2026-03-15",
  "type": "unlock",
  "subtype": "restoration",
  "human_mins": 120,
  "gh_mins": 2400,
  "gh_confidence": "medium",
  "desc": "Short description of what was accomplished",
  "tags": ["tbi-recovery", "code"],
  "backlog_months": 24.0,
  "backlog_weight": 1.414,
  "fwc": 8,
  "note": "Verbatim reflection in the user's own words",
  "project": "optional-project-name",
  "source": "claude-cli",
  "schema_version": "0.9"
}
```

### Required Fields

| Field | Type | Description |
|-------|------|------------|
| session_id | UUID v4 | Unique identifier for this session. Generated at log time. Required for retrospection linking. |
| ts | ISO 8601 | UTC timestamp |
| date | YYYY-MM-DD | Local date |
| type | "speed" or "unlock" | Session classification |
| human_mins | integer | Minutes the hugr (human+AI pair) spent working |
| gh_mins | integer | Estimated minutes this would take solo |
| desc | string | What was accomplished |
| source | string | Which agent/tool logged this |
| schema_version | string | "0.9" -- schema may change before 1.0. Migration script ships from day one. |

### Optional Fields

| Field | Type | Description |
|-------|------|------------|
| subtype | "restoration", "bypass", "augmentation" | Unlock classification. MUST be null/absent when type is "speed". JSON Schema encodes this as a conditional. |
| gh_confidence | "low", "medium", "high" | How confident is the GH estimate? |
| tags | string[] | User-defined tags |
| backlog_months | float | How long this waited |
| backlog_weight | float | Calculated: sqrt(BM/12) |
| fwc | integer 1-10 | Felt Weight of Completion |
| note | string | Verbatim reflection |
| project | string | Project name |

### Retrospection Entry

```json
{
  "ts": "2026-03-22T10:00:00Z",
  "date": "2026-03-22",
  "type": "retrospection",
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "fwr": 7,
  "source": "claude-cli",
  "schema_version": "0.9"
}
```

Retrospection entries reference `session_id`, not date. This eliminates ambiguity on multi-session days.

### Schema Version

All entries carry `schema_version`. Schema changes follow these rules: (a) new optional fields are additive and require no migration, (b) field type changes or required field additions trigger a migration script that (i) creates a timestamped backup (`log.jsonl.bak.YYYYMMDD-HHMMSS`), (ii) validates the migrated output has the same entry count as the original, (iii) only replaces the original after validation passes, (c) analysis code must handle mixed-version files by filtering on `schema_version`. Derived fields (backlog_weight) are recomputed during any migration that touches their source fields.

### Concurrency

Multiple agents can write to the same log file. Write safety relies on two mechanisms:

1. **POSIX append atomics (defense-in-depth).** Each entry should stay under 3500 bytes to remain within the PIPE_BUF threshold (4096 bytes). This provides best-effort atomicity on POSIX systems but is not the primary safety mechanism.
2. **Python-based file locking (primary).** All write operations use Python for both JSON construction and file locking. `fcntl.flock()` on macOS/Linux, `msvcrt.locking()` on Windows. Locking and writing happen in the same Python call. No shell-based locking (flock CLI) is used -- it is not available on macOS or Windows.

All writers MUST use the shell scripts (which delegate to Python) or a Python tool for constructing and appending entries. String concatenation or echo-based JSON construction is prohibited.

### Field Length Limits

To maintain write atomicity and data quality:
- `desc` MUST be under 280 characters.
- `note` MUST be under 1000 characters.
- Writers MUST validate before appending. Entries exceeding limits are rejected with an error, not silently truncated.

### Error Handling

All write operations MUST verify the append succeeded (check exit code / exception). On failure, the entry MUST be printed to stdout so the user can manually recover it. The skill MUST NOT silently discard a completed log entry. A user who just answered 7 questions deserves to see their data even if the write fails.

### Log Integrity

v0.9 does not include checksums or integrity verification on the log file. The report and share commands validate each line as parseable JSON and skip malformed entries with a warning rather than failing silently. A per-entry hash chain is considered for v1.0 but excluded from v0.9 for simplicity.

### File Permissions

The `~/.ghost-hours/` directory MUST be created with `700` permissions. All files within MUST be created with `600` permissions. The setup script enforces this. The logging script checks permissions on each write and warns if they have been changed. The `event_label` and recovery tags constitute self-disclosed health information and must not be readable by other users on shared machines.

---

## Commands

### `/ghost-hours log`

The guided logging flow. Runs the decision tree.

**Flow:**

```
1. Session summary (agent provides 3-5 bullets of what was accomplished)
2. "How heavy was this?" --> FW-C (1-10)
3. "Could this have happened without AI?" --> yes = speed, no = continue
4. "Is this something you could do before [the event]?" --> yes = restoration, no = continue
   (skipped if event_label not set -- all unlocks default to augmentation)
5. "Could you have learned to do this before [the event]?" --> yes = bypass, no = augmentation
   (skipped if event_label not set)
6. "How long was this waiting?" --> backlog_months (0 if new)
7. If FW-C >= 5: "Want to say anything about why?" --> note (verbatim)
8. Log entry written. Summary displayed.
```

**Rules:**
- One question per message. Wait for answer before next question.
- Do not reword the questions. The tree is the structure.
- Q4/Q5 only activate after event_label is set (after 5 sessions). Until then, all unlocks are augmentation.
- The agent provides the GH estimate as a **range** with reasoning (e.g., "I'd estimate 4-8 hours -- where does that feel right?"). The user picks a spot or adjusts. Ranges force active estimation instead of rubber-stamping a number.
- **GH sanity check:** If the resulting ratio exceeds 25x (gh_mins / human_mins > 25), the agent prompts: "That's a [N]x ratio. Does that feel right?" User can confirm or adjust. Entries above 25x are auto-tagged `gh_confidence: "review"` regardless of user confirmation.
- **Calibration prompt (first 5 sessions):** Before the GH estimate, the agent says: "Think about what this would take if you had to Google every step, write every line, debug every error, with no AI help. Not the best-case scenario -- the realistic one." Drops after 5 sessions. Session count tracked in config.

**Error handling:**
- "Skip" or "cancel" at any point aborts. No partial entry is written.
- Invalid input (non-numeric for FW-C, out of range) gets one retry with the question repeated.
- "Go back" replays the previous question.
- If the conversation ends mid-flow, no entry is written. Nothing logs until the full flow completes.

**Agent estimation logic:**
The agent considers: task complexity, tools/knowledge required, likely solo approach (research, trial-and-error, debugging), and states its reasoning in 1-2 sentences before giving the range. The user confirms or adjusts. This is the most consequential step in the flow -- the quality of GH data depends on it.

### `/ghost-hours amend`

Correct a past entry without hand-editing the log file.

```
1. Shows recent sessions (last 10) with session_id, date, desc, type
2. User picks one by session_id or number
3. Shows the full entry
4. User specifies which fields to change and new values
5. Appends an amendment entry:
   {
     "type": "amendment",
     "session_id": "[original session_id]",
     "ts": "[now]",
     "changes": { "field": "new_value", ... },
     "source": "claude-cli",
     "schema_version": "0.9"
   }
6. Original entry is never mutated. Audit trail preserved.
   Report/share commands apply amendments on read.
```

### `/ghost-hours report`

Displays aggregate stats.

**Modes:**
- `report` -- all time
- `report --week` -- last 7 days
- `report --month` -- last 30 days
- `report --since YYYY-MM-DD` -- custom range

**Output includes:**
- Total sessions, split by type
- Total GH conjured (hours and work-days)
- Total HH invested
- Overall CR (conjure rate)
- Unlock breakdown by subtype (restoration / bypass / augmentation)
- Backlog cleared (months and weighted score)
- FW-C distribution (average, count of 5+, count of 8+)
- Top 3 highest-FW-C sessions with descriptions

### `/ghost-hours why`

Surfaces the human layer.

Returns the last 5 entries where FW-C >= 5, showing:
- Date
- Description
- FW-C score
- Verbatim note (if present)
- Type and subtype

This is the command you run when someone asks "why does this matter?"

### `/ghost-hours retro`

Log a retrospection score against a past session.

```
1. Shows recent sessions (last 10)
2. User picks one
3. "Looking back, how heavy does that completion feel now?" --> FW-R (1-10)
4. Entry written. Delta displayed if FW-C exists.
```

### `/ghost-hours share`

Opt-in research data export.

**Flow:**
1. Explains what will be shared (Tier 1: de-identified numbers only)
2. User confirms
3. Generates export file at `~/.ghost-hours/share/YYYY-MM-DD-export.json` with:
   - Random participant ID (generated once, stored in config)
   - All session entries stripped of: desc, note, project, tags, ts
   - Retains: date, type, subtype, human_mins, gh_mins, gh_confidence, backlog_months, backlog_weight, fwc, fwr, schema_version
4. Displays the export file contents for review before any transmission
5. In v1.0, no network transmission occurs. When the endpoint ships (v1.1), the share command will POST this file to ghosthours.ca/api/share with a 30-second timeout, single retry, and local confirmation of success/failure. Maximum payload: 1MB (~3,500 de-identified entries).

**Privacy guarantees:**
- No descriptions. No notes. No project names. No file paths. No timestamps (date only).
- Participant ID is random, not derived from any personal info.
- User reviews the exact payload before it leaves the machine.
- Share is always manual. Never automatic. Never silent.
- **Residual risk:** De-identified data retains session frequency, type distributions, and backlog values, which are quasi-identifiers. Full anonymization is not claimed. Users should be aware that de-identification reduces but does not eliminate re-identification risk.

### `/ghost-hours setup`

First-time configuration. Lightweight on-ramp. The heavy question comes later.

```
1. "Ghost Hours measures what AI does for you -- both speed and capability expansion."
2. Sets log file location (default: ~/.ghost-hours/log.jsonl)
3. Generates participant ID (UUID, stored locally)
4. "Want a reminder to share your de-identified data periodically?"
   --> yes: "How often? (weekly / monthly / quarterly)" (stored as share_reminder)
   --> no: share_reminder = null. Never asked again.
5. Validates Python 3 availability and UUID generation capability.
6. Done. "Log your first session with /ghost-hours log."
```

**After 5 sessions logged (triggered automatically):**

```
"You've logged 5 sessions. Ghost Hours can track something deeper --
whether AI is restoring capability you lost to a life event."
"Do you have a life event (injury, disability, career change) that
affects what you can do?"
   --> yes: "How would you describe it in a few words?" (stored as event_label)
         recovery_tag generated: lowercase, spaces to hyphens, strip
         non-alphanumeric except hyphens, append "-recovery", max 50 chars.
         Done in Python, not shell.
         "TBI" -> "tbi-recovery"
         "post-traumatic stress" -> "post-traumatic-stress-recovery"
   --> no: event_label = null. All unlocks remain augmentation.
```

Until the event_label question is answered, Q4/Q5 in the decision tree are skipped. All unlocks default to augmentation. This lets users experience the value before hitting the heavy question.

Config stored in `~/.ghost-hours/config.json`:

```json
{
  "log_path": "~/.ghost-hours/log.jsonl",
  "participant_id": "a1b2c3d4-...",
  "share_reminder": "monthly",
  "sessions_logged": 0,
  "event_label": null,
  "recovery_tag": null,
  "event_label_asked": false,
  "schema_version": "0.9",
  "setup_date": "2026-03-15"
}
```

The `sessions_logged` counter is advisory. In multi-agent scenarios, the count may drift by 1-2 sessions. This is acceptable -- the event_label prompt is guidance, not a gate. The `event_label_asked` flag ensures the question is asked exactly once.

### Config Security

The `config.json` file may contain the user's `event_label`, which constitutes self-disclosed health information. File permissions (600) provide user-level protection. Disk-level protection (full-disk encryption) is the user's responsibility. Ghost Hours does not implement application-level encryption in v0.9 -- the tradeoff is simplicity and inspectability over encryption at rest.

---

## Skill File Structure

```
ghost-hours/
  SKILL.md              # Skill definition (Claude Code reads this)
  README.md             # For humans. Teaches the taxonomy. Explains the research.
  LICENSE               # Apache 2.0, Raven Systems Inc.
  scripts/
    log-ghost-hours.sh  # Core logging script (JSONL writer)
    ghost-hours-stats.sh # Report generator
    ghost-hours-share.sh # Export/share script
  schema/
    session.schema.json  # JSON Schema for validation
    export.schema.json   # JSON Schema for share exports
```

### SKILL.md Structure

```markdown
---
name: ghost-hours
description: Measure what AI actually does for you. Productivity and capability tracking built as a research framework.
version: 0.9.0
author: Raven Systems Inc.
commands:
  - log
  - report
  - why
  - retro
  - amend
  - share
  - setup
---

[Skill instructions for the agent -- the decision tree, the taxonomy,
the logging rules, the pacing rules. Everything the agent needs to
run the guided flow correctly.]
```

---

## What Ships in v0.9 (public beta)

- [ ] SKILL.md with full decision tree, taxonomy, estimation logic, and error handling
- [ ] README.md that teaches the framework, the taxonomy, and the limitations
- [ ] Proof-of-concept sample report (ANON-001 data) in README
- [ ] Limitations section in README
- [ ] log command with guided flow, GH range estimation, 25x sanity check
- [ ] report command with all-time, week, month, since filters
- [ ] why command
- [ ] retro command (references session_id)
- [ ] amend command (append-only corrections, audit trail preserved)
- [ ] share command (de-identified export to local file, endpoint stubbed)
- [ ] setup command (lightweight on-ramp, event_label delayed to session 5)
- [ ] Shell scripts for logging, reporting, sharing (agent-agnostic, any CLI)
- [ ] Python-based file locking (fcntl on Mac/Linux, msvcrt on Windows)
- [ ] session_id (UUID) on every session entry (uuidgen with Python uuid4 fallback)
- [ ] gh_confidence field (optional, low/medium/high, auto-tagged "review" above 25x)
- [ ] Field length validation (desc < 280, note < 1000)
- [ ] Write failure recovery (print entry to stdout on failed append)
- [ ] File permissions enforcement (700 directory, 600 files)
- [ ] JSON-safe construction (Python json module, never string concatenation)
- [ ] JSON Schema for session and export formats
- [ ] Schema version 0.9 (signals schema may change before 1.0)
- [ ] Apache 2.0 license with Raven Systems Inc. copyright
- [ ] config.json with participant ID, sessions counter, event_label_asked flag
- [ ] GH estimation calibration prompts (first 5 sessions, range format)
- [ ] Tag sanitization (lowercase, hyphens, strip non-alphanumeric, append -recovery, max 50 chars, Python)
- [ ] Multi-agent documentation (Cowork, other CLI agents, manual logging)
- [ ] Configurable recovery tags (auto-generated from event_label after session 5)
- [ ] Migration script for Dustin's existing log.jsonl (add session_id, schema_version, timestamped backup with entry-count validation)
- [ ] Conditional schema validation (subtype only valid when type=unlock)

## What Ships in v1.0

- Schema version promoted to 1.0 (schema stable, migration contract honored)
- Live share endpoint at ghosthours.ca/api/share (HTTPS required, participant_id auth, rate limiting, full spec in v1.0 doc)
- Dashboard (local HTML)
- `/ghost-hours delta` -- entries with both FW-C and FW-R, sorted by delta magnitude
- Capability Delta integration (weekly growth proof from GH data)
- Log rotation strategy for high-volume installations (>50K entries)
- Periodic recalibration nudge (every 50 sessions or quarterly) -- pending data on drift
- Per-entry hash chain for log integrity
- Participant ID rotation (`/ghost-hours setup --reset-id`)

---

## Design Decisions

### Why JSONL, not SQLite?
Grep-friendly. Human-readable. One file to back up. No dependencies. Research teams can process it with Python, jq, R, anything. SQLite is better for queries but worse for portability and inspection.

### Why shell scripts, not a Python package?
Minimal dependencies: bash and Python 3. No pip install. No virtual environment. The skill tells the agent what to run. The scripts do the work. Python handles all JSON construction (never string concatenation). If someone wants to build a wrapper in another language, the JSONL format is the API.

### Why Apache 2.0?
Permissive enough that anyone can use it. Attribution required (Raven Systems Inc.). Patent grant included. Compatible with academic and commercial use. AGPL would block adoption in corporate research settings.

### Why not just a CLI tool?
The guided flow is the product. The decision tree, the pacing (one question at a time), the agent providing the GH estimate -- these require a conversational interface. A CLI tool logs data. A skill runs a protocol.

### Why FW-C before type classification?
Asking "how heavy was this?" before "could this have happened without AI?" captures the emotional weight before the analytical frame kicks in. If you classify first, the type contaminates the felt weight. FW-C is the raw signal. Type is the structured signal. Capture raw first.

### Why not require the note?
The note is the richest data in the entire system. But making it mandatory turns a 60-second flow into a chore. Optional with a nudge (only prompted when FW-C >= 5) means the notes that exist are genuine, not obligatory. Quality over volume.

### Why the event_label after 5 sessions, not in setup?
Ghost Hours works for everyone. The restoration/bypass subtypes are most meaningful for people with a specific disabling event (TBI, stroke, chronic illness, etc.). But asking about disability on first run is heavy. Delaying to session 5 lets users experience the value before the deeper question. Until then, all unlocks are augmentation. The taxonomy stays adaptive without front-loading the heaviest question.

---

## Scrutiny: What Holds Up and What Doesn't

### An Honest Assessment

This framework was built by one person, on one dataset, over 15 days. Before it can claim broader validity, it must survive the following challenges.

**What holds up:**

The Speed vs Unlock distinction is the strongest contribution. Most AI productivity research treats all output as equivalent: time saved is time saved. The insight that some work was *never going to happen* regardless of speed is a meaningful conceptual departure. A person who could not code before AI is not "faster" at coding: they are *newly capable*. These are categorically different phenomena and deserve different measurement.

The sub-linear shape of BW is defensible. The psychological literature on procrastination, particularly research on avoidance behavior and task aversion, consistently shows that the cost of inaction does not grow linearly with time. The first year of avoidance carries the most active psychological weight. Later years shift toward resigned acceptance. A square root function captures this shape without overclaiming a precise empirical fit.

**What doesn't hold up universally, and why it holds up here:**

> *"The GH estimates are subjective. A skeptic will say, and they'll be right, that you can make these numbers say whatever you want. The BW exponent was derived intuitively, not empirically. There's no study backing sqrt specifically over 0.6 or 0.7." -- D. Pollock, Feb 2026*

This is true. The framework does not hold up as universal science. It holds up as a **personal measurement system**, and the distinction matters.

The person logging the data is the same person who did the work and lived the backlog. There is no information asymmetry. The incentive is not to inflate numbers for an external audience: it is to have a metric that actually reflects reality, because the metric is for personal use. In this context, subjective estimation is not a flaw. It is the only honest approach. A third party estimating someone else's GH would introduce more error, not less.

This is the same epistemological position as a training log, a food journal, or a pain scale. None of these are objective in the scientific sense. All of them are useful precisely because the person recording them has direct access to the experience being measured.

**The framework does not claim to be science. It claims to be a mirror.**

### Making GH More Objective

The primary weakness of GH is that it has no anchor. "40 hours of developer time" is a guess. To improve it, three methods are available:

**Method 1: Reference Benchmarks**

Establish reference points by task category before estimating. Examples:

| Task Type | Solo Human Benchmark |
|-----------|---------------------|
| Simple web app (CRUD, no auth) | 40-80h developer |
| Marketing copy, 500 words | 2-4h copywriter |
| Audio transcription, 1 hour of audio | 4-6h manual |
| Research summary, 10 sources | 3-5h analyst |
| Data pipeline script | 8-20h developer |

When logging, choose the closest benchmark category first, then adjust up or down based on complexity. This transforms an open-ended guess into a bounded estimate.

**Method 2: Triangulation**

For significant Unlock sessions, estimate GH three ways:
1. *Low:* Best-case scenario: skilled professional, fully focused
2. *Mid:* Realistic scenario: average competent person, normal conditions
3. *High:* Realistic for the specific human logging the session, accounting for their prior skill level

Use the mid estimate by default. Record all three for high-stakes sessions.

**Method 3: Longitudinal Calibration**

As the dataset grows, patterns emerge. If a user consistently estimates 40h for app builds that later prove to take contractors 20h, apply a personal calibration factor. The tracker already stores all raw estimates: retrospective calibration is possible without re-logging.

### Honing the Backlog Weight Function

The current function is:

    BW = sqrt(BM / 12)

This uses an exponent of 0.5. The honest question is: why 0.5 and not 0.6 or 0.4?

**The case for 0.5 (current):** Clean, memorable, computationally trivial. Intuitively correct: growth is fast early, slow later. Requires no calibration data to apply.

**The case for a higher exponent (e.g. 0.65):** Some research on task aversion suggests weight continues to grow meaningfully beyond 5 years. A higher exponent would give more credit to decade-long backlogs. Example: 10 years at 0.5 = BW 3.16; at 0.65 = BW 4.22.

**The case for a lower exponent (e.g. 0.35):** Resigned acceptance sets in faster for some task types (especially tasks requiring skills the person doubts they'll ever acquire). A lower exponent acknowledges that after ~3 years, most of the weight is already accounted for.

**Path to calibration:**

The exponent should eventually be fit to data. As more users adopt the framework and self-report both backlog age and psychological weight (on a simple 1-10 scale at time of logging), a regression can determine the empirical exponent. Until that data exists, 0.5 is the honest default.

A future version of the log entry will include an optional `--weight-felt` field (1-10) allowing users to record their subjective sense of how heavy the backlog felt. Over time, plotting `weight_felt` against BW across many users will either validate sqrt or suggest a correction.

**Task-type variation:**

A creative project deferred for 5 years may carry more weight than a technical task deferred for the same period, because the creative work is more identity-adjacent. Future versions of the framework may apply task-type multipliers:

    BW = sqrt(BM / 12) x TM

Where TM (Task Multiplier) is 1.0 for technical tasks, 1.2 for creative work, 1.5 for identity-defining projects (documentary, business, creative legacy work).

This is speculative. It is noted here as a direction, not a recommendation.

---

## Summary Equations

```
THE GHOST HOURS FRAMEWORK

GH  = estimated human-solo hours for same output
HH  = actual human hours invested
CR  = GH / HH              [Conjure Rate]

BM  = months task sat undone
BW  = sqrt(BM / 12)        [Backlog Weight]
BS  = sum(BW_i)             [Backlog Score, cumulative]

Speed:   CR is the story
Unlock:  GH + BW are the story
```

---

## Limitations

This section is required reading for anyone using Ghost Hours data in research. Honest framing of what this framework is and what it is not.

### GH estimates are self-reported and unvalidated

Ghost Hours (the metric) is the user's estimate of how long a task would take without AI. There is no ground truth. No inter-rater reliability. The calibration prompt ("Think about what this would take if you had to Google every step...") provides a starting frame, but estimates vary by user, task type, and experience level. Conjure Rate should be understood as **perceived leverage**, not an objective measurement. Anecdotal evidence from early use suggests estimation accuracy improves with practice rather than drifting, but this has not been formally tested.

### FW-C is not a validated psychometric instrument

Felt Weight of Completion is a self-report scale with anchor points derived from one user's experience. It has not undergone psychometric validation (test-retest reliability, construct validity, factor analysis). The anchors are suggestive, not standardized. Cross-user comparability is aspirational, not proven. Users are told the anchors are "examples, not rules" -- this makes the tool adaptive for personal use but weakens its power as a cross-user research measure.

### No peer review

The Ghost Hours Framework paper (Pollock 2026) is self-published by Raven Systems Inc. It has not been peer-reviewed. The taxonomy (speed/unlock, restoration/bypass/augmentation) is a proposed classification, not an established standard. External validation is welcomed and needed.

### n=1

The proof-of-concept data comes from one participant over 31 days. Patterns observed (FW-C ceiling clustering, estimation improvement over time, multi-agent logging stability) may not generalize. The dataset becomes meaningful at n>10 with longitudinal coverage.

### Calibration drift

The GH estimation calibration prompt drops after 5 sessions. If estimation accuracy changes over time (in either direction), there is no automatic recalibration mechanism in v0.9. Monitoring for drift is a research question the dataset can answer once sufficient longitudinal data exists.

### Agent anchoring effect

The agent provides the GH estimate as a range, and the user picks a spot. This is better than a single number (forces active estimation), but the agent's range still anchors the user's thinking. Confirmation bias may inflate GH numbers systematically. Researchers should be aware that agent-provided estimates are subject to this effect.

### FW-C is a within-subject measure

Cross-user comparisons of absolute FW-C values are not supported without calibration studies. The anchor points are suggestive, not standardized. Researchers should analyze FW-C trends within participants, not means across participants.

### Backlog months are self-reported

Backlog months represent perceived delay, not measured duration. A user who says "this waited 36 months" may be estimating from memory. The Backlog Weight function dampens outliers, but the raw number should be interpreted as subjective.

---

## The Research Angle

When someone installs Ghost Hours and starts logging, three things happen:

1. They get a personal record of what AI does for them. That's the immediate value.
2. They internalize the taxonomy. Speed vs. unlock becomes a lens they apply naturally. That changes how they think about AI -- from "it saves time" to "it changes what I can do."
3. If they opt into sharing, their de-identified data joins a dataset that doesn't exist anywhere else: longitudinal, multi-user measurement of AI-assisted capability expansion with experiential data attached.

The dataset grows through utility, not recruitment. People use the tool because it's useful. The research happens as a byproduct.

**Citation line in README and SKILL.md:**

> Ghost Hours is a measurement framework developed by Raven Systems Inc.
> If you use Ghost Hours data in published work, please cite:
>
> Pollock, D. (2026). The Ghost Hours Framework: A Mathematical Model
> for Measuring AI-Assisted Human Output and the Experience of
> Capability Expansion. Raven Systems Inc.

---

## Proof of Concept: Real Data from Participant ANON-001

This is not a demo. This is the de-identified output from the first person to use Ghost Hours daily for 31 days. No descriptions. No notes. No project names. Just the math and the felt weight.

**This goes in the README.** When someone lands on `cogpros/ghost-hours`, this is what they see before they read a single line of documentation.

```
=== THE GHOST HOURS OPEN DATASET 2026 -- SAMPLE REPORT ===
=== Participant: ANON-001 | Period: 2026-02-24 to 2026-03-14 ===

Span: 31 days | Days active: 31 | Sessions: 170

--- AGGREGATE ---
Total sessions:        170
  Speed:                62
  Unlock:              108
Hugr Hours invested:   169.5h  (21.2 work-days)
Ghost Hours conjured:  1,977.8h (247.2 work-days)
Overall Conjure Rate:  11.7x

--- SPEED SESSIONS ---
Sessions: 62
HH: 18.1h | GH: 88.1h | CR: 4.9x

--- UNLOCK SESSIONS ---
Sessions: 108
HH: 151.4h | GH: 1,889.6h

--- BACKLOG ---
Sessions with backlog:       39
Total backlog cleared:       109.3 years
Cumulative Backlog Weight:   50.08

--- FELT WEIGHT OF COMPLETION ---
Sessions with FW-C: 94
Average FW-C: 7.3 / 10

Distribution:
   1:  # (1)
   2:  ### (3)
   3:  ##### (5)
   4:  ########## (10)
   5:  ######### (9)
   6:  ###### (6)
   7:  ############# (13)
   8:  ######## (8)
   9:  ### (3)
  10:  #################################### (36)

FW-C >= 5 (meaningful+):   75 sessions
FW-C >= 8 (milestone+):    47 sessions
FW-C = 10 (new altitude):  36 sessions

--- QUALITATIVE DATA ---
Sessions with verbatim notes: 69

--- SOURCES ---
  claude-cli:      109
  openclaw-cron:    59
  openclaw-odin:     2

--- MULTI-AGENT ---
3 distinct agents logging to the same file.
59 sessions logged by automated cron agents.
```

### What the numbers mean

**11.7x Conjure Rate.** For every hour this person invested, AI produced 11.7 hours of output. Not theoretical. Logged session by session over 31 days.

**108 of 170 sessions were unlocks.** 63% of all work done in this period was not possible without AI. Not faster -- not possible. The distinction between speed and unlock is the core of the taxonomy.

**109.3 years of backlog cleared.** Tasks that had been waiting months or years, finally completed. Backlog months are self-reported estimates representing perceived delay, not measured duration. The Backlog Weight function (BW = sqrt(BM/12)) captures the sub-linear psychological cost of that inaction. Cumulative weight: 50.08.

**Average FW-C of 7.3.** On a scale where 5 is "solid work" and 10 is "the trajectory changed," the average session landed between "the compound is working" and "capability milestone." 36 sessions rated 10. This person was not maintaining. They were climbing.

**69 verbatim notes.** Qualitative data captured at the moment of completion. Not visible in this report (privacy). Available to the participant. Available to research if they opt into Tier 2 sharing.

**3 agents, 1 dataset.** Multi-agent logging proven in production. Claude CLI, Odin (autonomous agent), and cron-based automated logging all writing to the same JSONL file with distinct source tags. The schema handles it. The data is clean. And the autonomous agent (Odin) was barely online -- 2 of 170 sessions. This data is almost entirely one human working with one agent. The multi-agent layer is the floor, not the ceiling.

### What this proves

One person. One month. One framework. Structured, comparable data generated as a byproduct of daily work.

This is what the README shows. Not what Ghost Hours could do. What it did.

---

## Resolved Design Questions

1. **Tag flexibility.** YES. Recovery tags are auto-generated from the user's `event_label` set during setup. "TBI" produces `tbi-recovery`. "Stroke" produces `stroke-recovery`. The `subtype` field (restoration/bypass/augmentation) stays standardized across all users -- that's what researchers query on. The tag is the human-readable layer.

2. **Multi-agent support.** YES. Documented and supported from v1. The JSONL schema is the universal layer. Any agent or script that writes valid JSONL to the log file is a valid data source. The `source` field distinguishes entries. Claude Code gets the full guided skill experience. Other CLI agents run the shell scripts directly. Manual logging via terminal is also supported. Cowork compatibility is a v1 requirement -- multiple agents in a shared session each log with their own source tag to the same file.

3. **GH estimation guidance.** YES. The skill includes a calibration prompt for the first 5 sessions: "Think about what this would take if you had to Google every step, write every line, debug every error, with no AI help. Not the best-case scenario -- the realistic one." After 5 sessions, the prompt drops. Users calibrate fast. Session count tracked in config.

4. **Export frequency.** User's choice, asked once during setup. "Want a reminder to share your data periodically?" Yes stores a flag and interval. No means silence forever. Zero nagware. One question, permanent setting.

5. **Dataset name.** The Ghost Hours Open Dataset 2026. Year-stamped. Implies future editions. Signals open access.

---

## Changelog

- **2026-03-22:** HH renamed from Human Hours to Hugr Hours. The label "human hours" implied solo time, which is what GH measures. Hugr hours = paired time. Internal field `human_mins` unchanged for backwards compatibility.

---

*Raven Systems Inc. -- Measure what changes.*
