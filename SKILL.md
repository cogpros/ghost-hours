---
name: ghost-hours
description: |
  Measure what AI actually does for you. Productivity and capability tracking
  built as a measurement framework. Classifies sessions as speed (faster) or
  unlock (not possible without AI), with subtypes for restoration, bypass,
  and augmentation. Pairs objective metrics with Felt Weight of Completion.
  Research-compatible data format. Cite: Pollock 2026.
version: 0.10.0
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
  openclaw:
    requires:
      bins:
        - python3
        - bash
    compatibility: "Python 3.6+, macOS/Linux/Windows. No pip install. No external packages."
---

# Ghost Hours -- Agent Instructions

You are running the Ghost Hours measurement framework. Follow these instructions exactly.

## Setup Detection

Before any command, check if `~/.ghost-hours/config.json` exists.
- If NOT: run the setup flow before proceeding.
- If YES: load the config and proceed.

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

### Flow

**Step 1: Session Triage**
List what was accomplished in the session, grouped by natural boundaries (different type, different project, different cognitive load). Show the groups to the user for confirmation. A session where you fixed a bug (speed, 20 min) and built a new system (unlock, 3 hours) should NOT be one entry.

Ask: "Here's what I see. Does this grouping look right, or should anything be split or combined?"

Then run Steps 2-10 for EACH group separately.

**Step 2: FW-C**
Always show the anchor chart:
- 1 = Checked a box. Wouldn't remember it happened.
- 3 = Plumbing. Had to happen. No emotional weight.
- 5 = Solid work. Moved things forward. Meaningful.
- 7 = The compound is working. System building on itself.
- 8 = Capability milestone. First time doing something real.
- 10 = New altitude. The trajectory changed.

Ask: "How heavy was this? (1-10)"

**Step 3: Agent FW-C (silent)**
Compute your own FW-C estimate internally. Store it. Do NOT output it. Do NOT hint at it. Do NOT reference it. This value is revealed ONLY during /ghost-hours retro, AFTER the user gives their FW-R. Never before. This is non-negotiable.

**Step 4: Type Classification**
Ask: "Could this have happened without AI?"
- YES -> type = "speed". Skip to Step 6.
- NO -> type = "unlock". Continue to Step 5.

**Step 5: Subtype Classification (only if event_label is set in config)**
If `event_label` is null or `event_label_asked` is false, skip this step. All unlocks are "augmentation."

If event_label exists:
Ask: "Is this something you could do before [event_label]?"
- YES -> subtype = "restoration". Done with classification.
- NO -> Ask: "Could you have learned to do this before [event_label]?"
  - YES -> subtype = "bypass". Done.
  - NO -> subtype = "augmentation". Done.

Restoration and bypass entries get tagged with the config's `recovery_tag`.

**Step 6: GH Estimate**
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

**Step 7: Backlog**
Ask: "How long was this waiting? (months, or 0 if new)"

**Step 8: Note (conditional)**
If FW-C >= 5, ask: "Want to say anything about why?"
Record verbatim. Do not summarize or edit. If the user declines, move on.

**Step 9: SR&ED Check**
Ask: "Was there technological uncertainty in this session?"
If yes: capture the uncertainty as a question and the result/advancement. Ask which business line (cogpros/platform/client/internal). If routine application of known solutions, skip.

**Step 10: Log It**
Run the logging script:
```bash
bash [skill_dir]/scripts/log-ghost-hours.sh \
  --type [type] --hugr [mins] --gh [mins] --desc "[desc]" \
  --source claude-cli \
  [--subtype subtype] [--confidence conf] [--tags "tag1,tag2"] \
  [--backlog months] [--fwc score] [--fwc-eom score] [--note "text"] [--project name] \
  [--uncertainty "question"] [--result "advancement"] [--sred-line line]
```

Display the summary. Move to next group or done.

**Step 11: Event Label Check (after 5 sessions)**
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
3. Show the anchor chart (same as Step 2 of /ghost-hours log). Ask: "Looking back, how heavy does this feel now? (1-10)". This is **FW-R**.
4. Ask: "Why?" Record verbatim.
5. **NOW reveal the agent's FW-C** from the original session (stored at logging time in Step 3 of /ghost-hours log). Show all three numbers together:
   - FW-C (user's score at completion): [X]
   - FW-R (user's score looking back): [Y]
   - Agent FW-C (agent's blind estimate): [Z]
   - Delta (FW-C to FW-R): [X-Y]
   - Delta (user FW-C to agent FW-C): [X-Z]
6. Give thoughts on the deltas. What shifted? Why might it have shifted?
7. Log retrospection entry via the writer module.

### CRITICAL: Blind Protocol
The agent's FW-C is NEVER shown until Step 5. Not during /ghost-hours log. Not at session end. Not in summaries. Not in any other context. The ONLY place the agent's FW-C appears is here, after the user has given both their FW-C (at completion) and their FW-R (looking back). This prevents anchoring and preserves the integrity of the research data.

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
The script handles the preview and confirmation.

## Important Rules

- NEVER write entries by constructing JSON manually. Always use the shell scripts or the Python writer module.
- NEVER skip the pacing rule. One question per message.
- NEVER reword the decision tree questions. The tree is the structure.
- NEVER log a partial entry. The full flow must complete before anything is written.
- NEVER summarize or edit the user's verbatim note.
- The `desc` field should be YOUR summary of the session (max 280 chars). The `note` field is the USER's words.
