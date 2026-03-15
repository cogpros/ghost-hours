# Ghost Hours

Measure what AI actually does for you.

Not time saved. What changed.

```
=== Participant: ANON-001 | 31 days ===

Total sessions:        170
  Speed:                62
  Unlock:              108
Human Hours invested:  169.5h  (21.2 work-days)
Ghost Hours conjured:  1,977.8h (247.2 work-days)
Overall Conjure Rate:  11.7x

Backlog cleared:       109.3 years (self-reported)
Felt Weight avg:       7.3 / 10

FW-C Distribution:
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

Sources: 2 agents, 1 file. 59 automated, 109 manual, 2 autonomous.
```

That is real data from one person using Ghost Hours daily for 31 days. No descriptions. No notes. No project names. Just the math and the felt weight.

---

## What Ghost Hours Is

Ghost Hours is a Claude Code skill that classifies every AI-assisted session and logs it.

It is two things at once:

**A personal tool.** You see your leverage ratios, capability expansion, backlog cleared, and a record of what mattered most.

**A measurement framework.** Every installation generates data in the same schema, using the same taxonomy, on the same scales. If you opt in, your de-identified data joins The Ghost Hours Open Dataset 2026.

## The Taxonomy

This is the core contribution. Everything else is interface.

### Speed vs. Unlock

| Type | What it means |
|------|--------------|
| **Speed** | You could have done this without AI. AI made it faster. |
| **Unlock** | You could not have done this without AI. Knowledge barrier, complexity barrier, or accumulated inaction blocked it. |

Most productivity tools only measure speed. Ghost Hours measures capability delta.

### Unlock Subtypes

| Subtype | What it means |
|---------|--------------|
| **Restoration** | You had this capability. A life event took it. AI gave it back. |
| **Bypass** | You could have learned this before the event, but the event blocked the learning path. AI routes around the gap. |
| **Augmentation** | No human could do this alone, event or not. AI grants a new capability. |

The restoration/bypass distinction matters for disability and rehabilitation research. A restoration that later appears as a speed session is measurable functional recovery -- clinical evidence generated as a byproduct of daily work.

## Core Metrics

| Symbol | Name | What it measures |
|--------|------|-----------------|
| GH | Ghost Hours | Estimated time a human working alone would need to produce the same output |
| HH | Human Hours | Time you actually spent |
| CR | Conjure Rate | GH / HH -- your leverage ratio |
| BW | Backlog Weight | sqrt(BM / 12) -- the psychological cost of tasks that waited months or years |
| FW-C | Felt Weight of Completion | 1-10. How heavy did finishing this feel? |
| FW-R | Felt Weight at Retrospection | Same scale, logged later. How heavy does it feel now? |

## Install

Copy the `ghost-hours/` directory into your Claude Code skills folder:

```bash
# Clone
git clone https://github.com/cogpros/ghost-hours.git

# Copy to your skills directory
cp -r ghost-hours ~/.claude/skills/ghost-hours
```

Then run `/ghost-hours setup` in Claude Code.

### Requirements

- Claude Code (or any agent that can run bash + read .md skill files)
- Python 3.6+
- No pip install. No virtual environment. No external packages.

### Other Agents

Ghost Hours works on any platform that can run bash and Python:

| Integration | Experience |
|-------------|-----------|
| **Claude Code / Cowork** | Full guided flow via SKILL.md |
| **Cursor, Windsurf, Cline** | Full guided flow (reads skill files) |
| **Any CLI agent with shell** | Run the scripts directly |
| **Manual (terminal)** | `bash scripts/log-ghost-hours.sh --type unlock --human 30 --gh 480 --desc "description"` |
| **Any language** | Write valid JSONL matching the schema |

## Commands

| Command | What it does |
|---------|-------------|
| `/ghost-hours setup` | First-time configuration |
| `/ghost-hours log` | Guided logging flow. The decision tree. |
| `/ghost-hours report` | Aggregate stats (all time, week, month, custom range) |
| `/ghost-hours why` | Last 5 sessions where FW-C >= 5, with notes |
| `/ghost-hours retro` | Log a retrospection score against a past session |
| `/ghost-hours amend` | Correct a past entry without editing the file |
| `/ghost-hours share` | Export de-identified data for research |

### The Logging Flow

One question at a time. 60 seconds start to finish.

1. Agent summarizes what you accomplished
2. "How heavy was this?" (FW-C, 1-10)
3. "Could this have happened without AI?" (speed or unlock)
4. Subtype classification (after 5 sessions, if applicable)
5. Agent estimates GH as a range, you pick a spot
6. "How long was this waiting?" (backlog)
7. "Want to say anything about why?" (if FW-C >= 5)
8. Logged.

## Data Format

JSONL. One file. One line per entry. Human-readable.

```json
{
  "session_id": "a1b2c3d4-...",
  "ts": "2026-03-15T04:48:29Z",
  "date": "2026-03-15",
  "type": "unlock",
  "subtype": "restoration",
  "human_mins": 120,
  "gh_mins": 2400,
  "gh_confidence": "medium",
  "desc": "Short description",
  "fwc": 8,
  "note": "User's own words",
  "source": "claude-cli",
  "schema_version": "0.9"
}
```

Default location: `~/.ghost-hours/log.jsonl`

Process it with Python, jq, R, anything. The JSONL format is the API.

## What the Proof-of-Concept Means

**11.7x Conjure Rate.** For every hour invested, AI produced 11.7 hours of output. Logged session by session. Perceived leverage, not objective measurement -- GH estimates are self-reported.

**108 of 170 sessions were unlocks.** 63% of work done in that month was not possible without AI. Not faster. Not possible.

**109.3 years of backlog cleared.** Self-reported estimates representing perceived delay. The Backlog Weight function dampens outliers. Cumulative weight: 50.08.

**Average FW-C of 7.3.** On a scale where 5 is "solid work" and 10 is "the trajectory changed." 36 sessions rated 10. Early adopter data clusters high -- expected during initial capability expansion. The distribution should spread as calibration improves.

**2 agents, 1 dataset.** Two distinct agents logging to the same JSONL file. The autonomous agent was barely online (2 of 170 sessions). This is the floor, not the ceiling.

## Sharing Your Data

Ghost Hours can export your data for research. The export strips:
- Descriptions
- Notes
- Project names
- Tags
- Timestamps (date only retained)

What remains: date, type, subtype, minutes, confidence, backlog, FW-C, FW-R. A random participant ID links your exports. You review the exact payload before anything leaves your machine.

```
/ghost-hours share
```

In v0.9, the export saves to a local file. No network transmission.

## Limitations

Read these before using Ghost Hours data in research.

**GH estimates are self-reported.** There is no ground truth. Conjure Rate is perceived leverage, not objective measurement. The agent provides a range, the user picks a spot. Anchoring bias may inflate estimates.

**FW-C is not a validated psychometric instrument.** It is a self-report scale with anchor points derived from one user. Cross-user comparisons of absolute FW-C values are not supported. Analyze trends within participants, not means across participants.

**No peer review.** The Ghost Hours Framework (Pollock 2026) is self-published by Raven Systems Inc. The taxonomy is a proposed classification, not an established standard. External validation is welcomed.

**n=1.** The proof-of-concept is one participant over 31 days. Patterns may not generalize. The dataset becomes meaningful at n>10 with longitudinal coverage.

**Schema version 0.9.** The schema may change before 1.0. A migration script ships from day one.

## The FW-C Anchor Chart

| Score | Anchor |
|-------|--------|
| 1 | Checked a box. Wouldn't remember it happened. |
| 3 | Plumbing. Had to happen. No emotional weight. |
| 5 | Solid work. Moved things forward. Meaningful. |
| 7 | The compound is working. System building on itself. |
| 8 | Capability milestone. First time doing something real. |
| 10 | New altitude. The trajectory changed. |

These are examples, not rules. You develop your own calibration over time. Early data clusters high at 10 -- that is expected and normalizes with use.

## Security

- All data stays local. Nothing phones home.
- `~/.ghost-hours/` directory: `700` permissions.
- All files: `600` permissions.
- The `event_label` in config may contain health information. Disk encryption is your responsibility.
- File locking via Python (`fcntl` on Mac/Linux, `msvcrt` on Windows).
- All JSON constructed by Python, never string concatenation.

## Citation

Ghost Hours is a measurement framework developed by Raven Systems Inc.

If you use Ghost Hours or its data in published work, please cite:

> Pollock, D. (2026). The Ghost Hours Framework: A Mathematical Model for Measuring AI-Assisted Human Output and the Experience of Capability Expansion. Raven Systems Inc.

## License

Apache 2.0. Copyright 2026 Raven Systems Inc.

Free for personal, academic, and commercial use. Attribution required.
