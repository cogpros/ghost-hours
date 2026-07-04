# Ghost Hours

**v1.0.0** · Apache-2.0 · Pollock 2026, Raven Systems Inc.

Measure what AI actually does for you.

Not time saved. What changed.

```
=== Participant: ANON-001 | 140 days ===

Total sessions:        703
  Speed:               151
  Unlock:              552
Hugr Hours invested:   999h    (124.8 work-days)
Ghost Hours conjured:  18,265h (2,283.1 work-days)
Overall Conjure Rate:  18.3x

Backlog cleared:       198.3 years (self-reported, 179 sessions)
Felt Weight avg:       6.5 / 10 (626 scored)

FW-C Distribution:
   1:  ##  (16)
   2:  #   (13)
   3:  ##  (25)
   4:  ####### (82)
   5:  ########## (116)
   6:  ####  (51)
   7:  ######### (101)
   8:  ######  (72)
   9:  ##  (28)
  10:  ########## (122)

Sources: 642 interactive, 61 scheduled/automated.
```

Real data. One person, using Ghost Hours daily for 140 days. No descriptions, no notes, no project names. Just the math and the felt weight.

## What It Is

Ghost Hours is an agent skill that classifies every AI-assisted session and logs it.

**A personal tool.** You see your leverage ratios, your capability expansion, the backlog you cleared, and a record of what mattered most.

**A measurement framework.** Every installation generates data in the same schema, using the same taxonomy, on the same scales. Opt in and your de-identified data joins The Ghost Hours Open Dataset 2026.

The taxonomy is the contribution. The tool is the delivery mechanism.

## Collection protocols

The data above didn't come from ad-hoc logging. It came from a session-close
protocol that runs the Ghost Hours measurement as its final act — every session,
one question at a time, with the agent's blind score kept silent. The
[`collection/`](collection/README.md) directory ships that protocol and its two
variants: an operator-delegated autofill (honesty-tagged) and a multi-agent
Discord stack close.

## Why

Productivity tools measure speed. Ghost Hours measures capability delta: the distance between what you are with AI and what you are without it, and whether that distance is recovery, workaround, or new ground.

For disability and rehabilitation research, the restoration/bypass distinction is the signal. A restoration that later shows up as a speed session is measurable functional recovery, generated as a byproduct of daily work.

## The Taxonomy

The core of the framework. Everything else is interface.

| Type | Subtype | What it means |
|------|---------|--------------|
| **Speed** | — | You could have done this without AI. AI made it faster. |
| **Unlock** | **Restoration** | You had this capability. A life event took it. AI gave it back. |
| **Unlock** | **Bypass** | You could have learned this before the event, but the event blocked the learning path. AI routes around the gap. |
| **Unlock** | **Augmentation** | No human could do this alone, event or not. AI grants a new capability. |

One question splits the types: *could this have happened without AI?* Two more split the subtypes, and they only fire if you have told Ghost Hours about a life event. Until then, every unlock is augmentation.

## Install

### Claude Code

```bash
git clone https://github.com/cogpros/ghost-hours.git
cp -r ghost-hours ~/.claude/skills/ghost-hours
```

Then run `/ghost-hours setup`.

### Other platforms

Any platform that reads SKILL.md works the same way: copy the directory into its skills folder (Cursor, Windsurf, Cline, and compatible agents). Any CLI agent with a shell can run the scripts directly. Any language can write valid JSONL matching the schema — the JSONL format is the API.

### Requirements

- Python 3.6+ (stdlib only)
- bash
- No pip install. No virtual environment. No external packages.

## Quickstart

```bash
/ghost-hours setup     # one-time, under a minute
/ghost-hours log       # at the end of a work session
/ghost-hours report    # see your numbers
```

Or log from any terminal, no agent required:

```bash
bash scripts/log-ghost-hours.sh --type unlock --subtype augmentation \
  --hugr 30 --gh 480 --desc "Built the thing"
```

The log lives at `~/.ghost-hours/log.jsonl`. Relocate it with `log_path` in `~/.ghost-hours/config.json` or the `GHOST_HOURS_LOG` environment variable.

### The logging flow

One question at a time. About 60 seconds per entry.

1. The agent triages the session into groups (a bug fix and a new system are two entries, not one)
2. "How heavy was this?" (FW-C, 1-10)
3. "Could this have happened without AI?" (speed or unlock)
4. Subtype classification (after 5 sessions, if applicable)
5. The agent estimates GH as a range; you pick a spot
6. "How long was this waiting?" (backlog)
7. "Want to say anything about why?" (if FW-C >= 5)
8. Logged.

The agent also computes its own FW-C estimate, silently. You never see it during logging. It surfaces only in `/ghost-hours retro`, after you have scored the session twice yourself — a three-number blind comparison of felt weight at completion, felt weight in hindsight, and the agent's read.

## Metrics

| Symbol | Name | What it measures |
|--------|------|-----------------|
| HH | Hugr Hours | Time the hugr (the human+AI pair) spent working |
| GH | Ghost Hours | Estimated time a human working alone would need for the same output |
| CR | Conjure Rate | GH / HH — your leverage ratio |
| BM | Backlog Months | How long the task sat undone |
| BW | Backlog Weight | sqrt(BM / 12) — sub-linear psychological cost of inaction |
| FW-C | Felt Weight of Completion | 1-10. How heavy did finishing this feel? |
| FW-R | Felt Weight at Retrospection | Same scale, logged later. How heavy does it feel now? |

### The FW-C anchor chart

| Score | Anchor |
|-------|--------|
| 1 | Checked a box. Wouldn't remember it happened. |
| 3 | Plumbing. Had to happen. No emotional weight. |
| 5 | Solid work. Moved things forward. Meaningful. |
| 7 | The compound is working. System building on itself. |
| 8 | Capability milestone. First time doing something real. |
| 10 | New altitude. The trajectory changed. |

Examples, not rules. You develop your own calibration over time. Early data clusters high at 10 — expected, and it normalizes with use.

## Commands

| Command | What it does |
|---------|-------------|
| `/ghost-hours setup` | First-time configuration |
| `/ghost-hours log` | Guided logging flow. The decision tree. |
| `/ghost-hours report` | Aggregate stats (all time, week, month, custom range) |
| `/ghost-hours why` | Last 5 sessions where FW-C >= 5, with notes |
| `/ghost-hours retro` | FW-R scoring plus the three-number blind reveal |
| `/ghost-hours amend` | Correct a past entry without editing the file |
| `/ghost-hours share` | Export de-identified data for research |

## Data Format

JSONL. One file. One line per entry. Human-readable. Process it with Python, jq, R, anything.

```json
{
  "session_id": "a1b2c3d4-...",
  "schema_version": "1.0",
  "ts": "2026-03-15T04:48:29Z",
  "date": "2026-03-15",
  "type": "unlock",
  "subtype": "restoration",
  "entry_class": "human",
  "human_mins": 120,
  "gh_mins": 2400,
  "gh_confidence": "medium",
  "desc": "Short description",
  "fwc": 8,
  "fwc_source": "operator",
  "fwc_eom": 7,
  "note": "User's own words",
  "source": "claude-cli"
}
```

`fwc_eom` is the agent's blind FW-C estimate (read it as `fwc_agent`; the name is retained for dataset compatibility). `entry_class` records who produced the entry — a live human+agent session, an automated scheduler, or a machine-generated artifact — and installs can extend the source map in `ghost_hours_writer.py` for their own agent fleet. Full contracts in `schema/`.

Multiple agents can write to the same log. File locking is handled in Python (`fcntl` on Mac/Linux, `msvcrt` on Windows), and the `source` field distinguishes writers.

## Sharing and Privacy

`/ghost-hours share` exports your data for research. The export strips descriptions, notes, project names, tags, timestamps (date only retained), and session IDs. Retrospection scores are folded into their session rows at export time, so no session ID ever leaves your machine.

What remains: date, type, subtype, entry class, minutes, confidence, backlog, FW-C, agent FW-C, FW-R. A random participant ID links your exports. You review the exact payload before anything leaves your machine.

- All data stays local. Nothing phones home. The export saves to a local file; no network transmission.
- `~/.ghost-hours/`: `700` permissions, files `600`.
- The `event_label` in config may contain health information. Disk encryption is your responsibility.
- De-identification reduces but does not eliminate re-identification risk. Session frequency and type distributions are quasi-identifiers. Full anonymization is not claimed.
- Optional tagging (via `--tags`) lets you mark entries for external programs such as tax-credit documentation or research studies; tags are always stripped from exports.

## Limitations

Read these before using Ghost Hours data in research.

**GH estimates are self-reported.** There is no ground truth. Conjure Rate is perceived leverage, not objective measurement. The agent provides a range, the user picks a spot. Anchoring bias may inflate estimates. Ratios above 25x are auto-tagged for review, not rejected.

**FW-C is not a validated psychometric instrument.** It is a self-report scale with anchor points derived from one user. Cross-user comparisons of absolute FW-C values are not supported. Analyze trends within participants, not means across participants.

**No peer review.** The Ghost Hours Framework (Pollock 2026) is self-published by Raven Systems Inc. The taxonomy is a proposed classification, not an established standard. External validation is welcomed.

**n=1.** The proof-of-concept above is one participant over 140 days. Patterns may not generalize. The dataset becomes meaningful at n>10 with longitudinal coverage.

**Backlog months are self-reported.** Perceived delay, not measured duration. The Backlog Weight function dampens outliers.

## Cite

Ghost Hours is a measurement framework developed by Raven Systems Inc.

If you use Ghost Hours or its data in published work, please cite:

> Pollock, D. (2026). The Ghost Hours Framework: A Mathematical Model for Measuring AI-Assisted Human Output and the Experience of Capability Expansion. Raven Systems Inc.

## Related tools

- [checkpoint](https://github.com/cogpros/checkpoint). Session-state dashboard from the same cognitive prosthetics lineage. Checkpoint shows where a session stands, Ghost Hours measures what the sessions add up to.

## License

Apache 2.0. Copyright 2026 Raven Systems Inc.

Free for personal, academic, and commercial use. Attribution required.
