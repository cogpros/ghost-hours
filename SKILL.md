---
name: ghost-hours
description: |
  Use when (1) closing a work session and measuring what AI did for you,
  (2) logging a single completed task as a Ghost Hours entry, (3) running
  reports on accumulated sessions, (4) retrospecting an old entry with FW-R,
  (5) amending a prior entry, or (6) sharing de-identified data. Classifies
  sessions as speed (faster) or unlock (not possible without AI), with
  subtypes for restoration, bypass, and augmentation. Pairs objective
  metrics with Felt Weight of Completion. Research-compatible data format.
  Your session-close protocol can invoke this skill as its measurement
  step. Standalone invocation is correct for one-off task logging.
  NOT FOR: timing in-progress work, capacity planning, billable-hour
  tracking, pre-close audits of open items, or any use that exposes the
  agent's silent FW-C score to the user before retro.
  Cite: Pollock 2026.
version: 1.0.0
author: Raven Systems Inc.
license: Apache-2.0
repository: https://github.com/cogpros/ghost-hours
user-invocable: true
commands:
  - log
  - report
  - why
  - retro
  - amend
  - share
  - setup
metadata:
  requires:
    bins:
      - python3
      - bash
  compatibility: "Python 3.6+, macOS/Linux/Windows. No pip install. No external packages."
triggers:
  - "ghost hours"
  - "run ghost hours"
  - "Measure what AI actually does for you"
---

# Ghost Hours -- Agent Instructions

You are running the Ghost Hours measurement framework. Follow these instructions exactly.

## Setup Detection

Before any command, check if `~/.ghost-hours/config.json` exists.
- If NOT: run the setup flow before proceeding.
- If YES: load the config and proceed.

The log file lives at `~/.ghost-hours/log.jsonl` by default. Users can relocate it via `log_path` in `config.json` or the `GHOST_HOURS_LOG` environment variable.

## /ghost-hours setup

Lightweight on-ramp. Do NOT ask about life events here.

1. Say: "Ghost Hours measures what AI does for you -- both speed and capability expansion. Let me set things up."
2. Create `~/.ghost-hours/` directory.
3. Run: `python3 [skill_dir]/scripts/ghost_hours_writer.py` to verify Python 3 works.
4. Ask: "Want a reminder to share your de-identified data periodically? (weekly / monthly / quarterly / no)"
5. Save config via the writer module.
6. Say: "Done. Log your first session with /ghost-hours log."

## /ghost-hours log

The guided logging flow. This is the core protocol.

### Pacing Rule
ONE question per message. Wait for the answer before asking the next. Never batch questions.

### State Machine

`scripts/advance.sh` is the flow's state machine. Call it; never emulate it. It returns exactly one output per call -- relay that output verbatim, collect the answer, and feed it back with `--answer`. Start each entry with `advance.sh --reset` then `advance.sh --start`.

### Flow

**Step 0: Session Triage**
List what was accomplished in the session, grouped by natural boundaries (different type, different project, different cognitive load). Show the groups to the user for confirmation. A session where you fixed a bug (speed, 20 min) and built a new system (unlock, 3 hours) should NOT be one entry.

Ask: "Here's what I see. Does this grouping look right, or should anything be split or combined?"

Then run Steps 0.5-9 for EACH group separately (reset the state machine between groups).

**Step 0.5: SILENT agent FW-C**
Compute your own FW-C score for this group. Do NOT output it. Do NOT mention it. Do NOT hint at it. Pass it to the state machine (`fwc_eom=N`) and log it via `--fwc-eom`. This is blind calibration data, revealed ONLY during /ghost-hours retro, AFTER the user gives their FW-R. Any earlier mention breaks the measurement instrument.

**Step 1: FW-C**
Ask: "How heavy was this? (1-10)"

Reference the anchor chart if the user seems unsure:
- 1 = Checked a box. Wouldn't remember it happened.
- 3 = Plumbing. Had to happen. No emotional weight.
- 5 = Solid work. Moved things forward. Meaningful.
- 7 = The compound is working. System building on itself.
- 8 = Capability milestone. First time doing something real.
- 10 = New altitude. The trajectory changed.

**Step 2: Type Classification**
Ask: "Could this have happened without AI?"
- YES -> type = "speed". Skip to Step 4.
- NO -> type = "unlock". Continue to Step 3.

**Step 3: Subtype Classification (only if event_label is set in config)**
If `event_label` is null or `event_label_asked` is false, skip this step. All unlocks are "augmentation."

If event_label exists:
Ask: "Is this something you could do before [event_label]?"
- YES -> subtype = "restoration". Done with classification.
- NO -> Ask: "Could you have learned to do this before [event_label]?"
  - YES -> subtype = "bypass". Done.
  - NO -> subtype = "augmentation". Done.

Restoration and bypass entries get tagged with the config's `recovery_tag`.

**Step 4: GH Estimate**
Provide your estimate as a RANGE, not a single number.

Consider: task complexity, tools/knowledge required, the likely solo approach (research, trial-and-error, debugging), and state your reasoning in 1-2 sentences.

Say something like: "Without AI, this would mean [describe the solo path]. I'd estimate **4-8 hours** -- where does that feel right?"

The user picks a spot or adjusts.

**Calibration prompt (first 5 sessions only):**
Check `sessions_logged` in config. If < 5, prepend:
"Think about what this would take if you had to Google every step, write every line, debug every error, with no AI help. Not the best-case scenario -- the realistic one."

**Sanity check:** If the resulting ratio (gh_mins / human_mins) exceeds 25, say:
"That's a [N]x ratio. Does that feel right?"
User can confirm or adjust. Entries above 25x are auto-tagged `gh_confidence: "review"`.

Also ask: "How confident is that estimate? (low / medium / high)" -- store as `gh_confidence`.

**Step 5: Backlog**
Ask: "How long was this waiting? (months, or 0 if new)"

**Step 6: Note (conditional)**
If FW-C >= 5, ask: "Want to say anything about why?"
Record verbatim. Do not summarize or edit. If the user declines, move on.

**Step 7: Log It**
Run the logging script:
```bash
bash [skill_dir]/scripts/log-ghost-hours.sh \
  --type [type] --hugr [mins] --gh [mins] --desc "[desc]" \
  --source claude-cli \
  [--subtype subtype] [--confidence conf] [--tags "tag1,tag2"] \
  [--backlog months] [--fwc score] [--fwc-eom score] \
  [--note "text"] [--project name]
```

`--hugr` is the minutes the hugr (the human+AI pair) spent; `--human` is accepted as an alias. `--fwc-eom` carries your silent blind estimate from Step 0.5.

Display the summary. Move to the next group, or done.

**Step 8: Optional program tagging**
If the user tracks entries for an external program (an R&D tax-credit claim, a research study, an internal initiative), add the relevant tag via `--tags`. Ghost Hours does not prescribe these programs; tags are the extension point.

**Step 9: Event Label Check (after 5 sessions)**
After logging all groups, if `sessions_logged >= 5` AND `event_label_asked` is false:
Say: "You've logged 5 sessions. Ghost Hours can track something deeper -- whether AI is restoring capability you lost to a life event."
Ask: "Do you have a life event (injury, disability, career change) that affects what you can do?"
- YES: "How would you describe it in a few words?" Store as event_label. Generate recovery_tag. Set event_label_asked = true.
- NO: Set event_label_asked = true. Move on. Never ask again.

### Error Handling
- "Skip" or "cancel" at any point: abort. No entry written. Say "Cancelled. No entry logged."
- Invalid input (non-numeric FW-C, out of range): repeat the question once. If still invalid, abort.
- "Go back": replay the previous question.
- If the conversation ends mid-flow, no entry is written.

## /ghost-hours report

Run the stats script:
```bash
bash [skill_dir]/scripts/ghost-hours-stats.sh [--week | --month | --since YYYY-MM-DD]
```
Display the output.

## /ghost-hours why

Read the log file. Find the last 5 entries where `fwc >= 5`. Display:
- Date
- Description
- FW-C score
- Verbatim note (if present)
- Type and subtype

If no entries with FW-C >= 5 exist, say: "No high-weight sessions logged yet."

## /ghost-hours retro

The retrospective felt-weight collection. This is where the blind protocol lives.

### Pacing Rule
ONE question per message. Same as /ghost-hours log.

### Flow

1. Read the log. Show the last 10 session entries with: date, session_id (first 8 chars), desc, fwc.
2. User picks one.
3. Show the anchor chart (same as Step 1 of /ghost-hours log). Ask: "Looking back, how heavy does this feel now? (1-10)". This is **FW-R**.
4. Ask: "Why?" Record verbatim as `fwr_note`.
5. **NOW reveal the agent's blind FW-C** from the original session (stored at logging time as `fwc_eom`). Show all three numbers together:
   - FW-C (user's score at completion): [X]
   - FW-R (user's score looking back): [Y]
   - Agent FW-C (agent's blind estimate): [Z]
   - Delta (FW-C to FW-R): [X-Y]
   - Delta (user FW-C to agent FW-C): [X-Z]
6. Give thoughts on the deltas. What shifted? Why might it have shifted?
7. Log the retrospection entry via the writer module (`build_retrospection_entry`, keyed by session_id).

### CRITICAL: Blind Protocol
The agent's FW-C is NEVER shown until Step 5 of retro. Not during /ghost-hours log. Not at session end. Not in summaries. Not in any other context. The ONLY place the agent's FW-C appears is here, after the user has given both their FW-C (at completion) and their FW-R (looking back). This prevents anchoring and preserves the integrity of the research data.

## /ghost-hours amend

1. Read the log. Show the last 10 session entries with: date, session_id (first 8 chars), desc, type.
2. User picks one.
3. Show the full entry.
4. Ask: "Which fields do you want to change?"
5. For each field, get the new value.
6. Log an amendment entry. Original is never mutated.
7. Say: "Amendment logged. Original preserved. Reports will show the corrected values."

## /ghost-hours share

Run the share script:
```bash
bash [skill_dir]/scripts/ghost-hours-share.sh
```
The script handles the preview and confirmation. Retrospection scores are folded into their session rows at export time; session IDs never leave the machine.

## Important Rules

- NEVER write entries by constructing JSON manually. Always use the shell scripts or the Python writer module.
- NEVER skip the pacing rule. One question per message.
- NEVER reword the decision tree questions. The tree is the structure.
- NEVER log a partial entry. The full flow must complete before anything is written.
- NEVER summarize or edit the user's verbatim note.
- The `desc` field should be YOUR summary of the session (max 280 chars). The `note` field is the USER's words.

## Known Limitations & Gotchas

Real footguns. Read before editing the flow.

- **The silent agent FW-C is instrument-breaking if voiced early.** Step 0.5 computes the agent's own FW-C estimate for blind calibration. Mentioning it to the user before retro Step 5, even once, contaminates the calibration data set permanently. The user's FW-C must be elicited cold. No comparison, no nudge, no "I would have said X." Log it only via `--fwc-eom`.
- **Pacing rule violations corrupt calibration.** Batched questions ("rate it 1-10 and tell me if AI was needed") trigger anchoring. The one-question-per-message rule is a measurement constraint, not a UX preference. Do not collapse steps even if the user seems impatient.
- **The 25x ratio cap is soft.** Entries above 25x are not rejected, only auto-tagged `gh_confidence: "review"`. Do not refuse a high-ratio entry. The tag is the signal; review happens later.
- **Partial entries are not recovered.** If the conversation ends mid-flow, no entry is written. There is no resume. The agent must complete all steps in the same session before the logging script runs.
- **Subtype gate is state-dependent.** Step 3 fires only if `event_label_asked: true` AND `event_label` is non-null in `~/.ghost-hours/config.json`. If `event_label_asked: false`, all unlocks default to `augmentation`. Step 9 sets the flag after 5 sessions and never re-asks. Do not preempt Step 9.
- **The v1.0 writer gate requires a subtype on every unlock.** `build_session_entry` rejects unlock entries without a subtype. When the event_label gate is closed, pass `--subtype augmentation` explicitly.
- **`desc` vs `note` mix-up corrupts the dataset.** `desc` = agent summary (max 280 chars). `note` = user's verbatim words, never edited or summarized. Crossing these breaks downstream analysis (FW-R retrospection, research exports).
- **The NEVER list in "Important Rules" is load-bearing.** Each NEVER protects measurement integrity. Reframing them as "prefer" weakens the instrument. Do not soften without explicit review.
- **Triage before logging.** Multi-thread sessions logged as one entry blur the type boundary and inflate GH. Step 0 exists to split them; do not skip it because a session "feels like one thing."

## Worked Example

End-to-end run from a real session shape. Illustrative, not exhaustive.

**Session context:** User spent 45 minutes pairing with an AI agent to refactor a Python script that previously took 6 hours by hand. First time using AST manipulation.

**Agent flow:**

```
Step 0 (triage): one group -- single thread, single project.
  - Refactored parse_log.py from regex spaghetti to ast.NodeVisitor
  - Replaced 8 brittle regex matches with structured visitor pattern
  - All 12 existing tests pass; added 3 new edge-case tests

Step 0.5 (silent): agent computes its blind FW-C = 7. Not voiced.

Step 1: "How heavy was this? (1-10)"
  User: 8

Step 2: "Could this have happened without AI?"
  User: No, never used AST before.
  -> type = "unlock"

Step 3 (event_label = "TBI"):
  "Is this something you could do before TBI?"
  User: No.
  "Could you have learned to do this before TBI?"
  User: Yes, I had the runway then.
  -> subtype = "bypass", tag = "tbi-recovery"

Step 4: "Without AI, this would mean reading the ast docs, trial-and-error
  on the visitor pattern, and debugging by print. I'd estimate
  6-10 hours. Where does that feel right?"
  User: 6 is fair.
  -> gh_mins = 360
  Confidence? -> "high"
  Ratio: 360/45 = 8x. Under cap. No sanity prompt.

Step 5: "How long was this waiting?"
  User: 2 months

Step 6 (FW-C >= 5): "Want to say anything about why?"
  User: "First time I felt like I built something I couldn't have built before.
         The compound is real."
  -> note = verbatim above

Step 7: log-ghost-hours.sh fires with all flags, including --fwc-eom 7.
```

**Resulting JSONL line (formatted):**

```json
{
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "schema_version": "1.0",
  "ts": "2026-04-26T22:14:08Z",
  "date": "2026-04-26",
  "type": "unlock",
  "subtype": "bypass",
  "entry_class": "human",
  "human_mins": 45,
  "gh_mins": 360,
  "desc": "Refactored parse_log.py from regex to ast.NodeVisitor. 12 tests pass plus 3 new edge cases. First AST work.",
  "source": "claude-cli",
  "fwc": 8,
  "fwc_source": "operator",
  "fwc_eom": 7,
  "gh_confidence": "high",
  "backlog_months": 2.0,
  "backlog_weight": 0.4082,
  "tags": ["tbi-recovery"],
  "note": "First time I felt like I built something I couldn't have built before. The compound is real."
}
```

Scorecard pass: see `references/output-scorecard.md`.

## Dependencies

Everything this skill needs to run. Audit before any environment change.

**Runtime:**
- `python3` 3.6+ on PATH (no pip packages required)
- `bash` 3.2+ on PATH
- macOS / Linux / Windows (WSL or git-bash)

**Skill-internal scripts (`[skill_dir]/scripts/`):**
- `ghost_hours_writer.py` — Python writer module. Single source of truth for JSONL writes and config mutation.
- `log-ghost-hours.sh` — entry-point for `/ghost-hours log` Step 7.
- `ghost-hours-stats.sh` — backend for `/ghost-hours report`.
- `ghost-hours-share.sh` — backend for `/ghost-hours share`. Handles preview + de-identification.
- `advance.sh` — the logging flow's state machine.
- `migrate-legacy-log.py` — one-shot migration for pre-1.0 logs.

**Schema (`[skill_dir]/schema/`):**
- `session.schema.json` — contract for one logged entry. Validate against this before treating any line as canonical.
- `export.schema.json` — contract for shared/de-identified export bundles.

**Operator state (`~/.ghost-hours/`):**
- `config.json` — user config. Holds `event_label`, `event_label_asked`, `recovery_tag`, `sessions_logged`, `share_reminder`, `log_path`. Created at setup. Mutated only via the writer module.
- `log.jsonl` — append-only log of all entries. Source of truth. Relocatable via `log_path` in config or the `GHOST_HOURS_LOG` environment variable.
- `share/` — de-identified export bundles produced by `ghost-hours-share.sh` (created beside the active log).

**References (`[skill_dir]/references/`):**
- `output-scorecard.md` — post-run scorecard for flow output (10 items).

**No network calls. No external services. No third-party Python packages.**
