---
name: closing-time-buzz-facts
description: >-
  Use when the operator asks for closing time buzz, a Buzz fact sheet, or a
  Buzz-wide close. Read the community through a read-only Buzz CLI identity,
  capture the working-day evidence, appraise Ghost Hours, and save a local
  report and seal. For a terminal session alone use closing-time-cli-facts.
license: Apache-2.0
metadata:
  version: "1.0.0"
---

# Closing Time Buzz Facts

Close the Buzz working day across channels, threads, and agents. Ask appraisal
questions in the terminal. All relay access is read-only: no messages, reactions,
canvas updates, or presence changes. Reports, measurement, and seals stay local.

## Setup

Requires Python 3.10+, bash, and a Buzz CLI configured with a read-only identity.
Configure credentials through your normal secret manager; never paste them into
this skill or print them. Set `BUZZ_RELAY_URL` to your community and
`BUZZ_OPERATOR_NAME` to the operator's exact display name, or use
`BUZZ_OPERATOR_PUBKEY` for an unambiguous identity. The collector uses
existing CLI authentication; it does not select another identity on failure.

State defaults to `${CLOSING_TIME_STATE:-$HOME/.closing-time/state}/closing-time-buzz`.
`BUZZ_WORK_LOGS_DIR` optionally supplies the work-log directory. The bundled
Ghost Hours writer respects `GHOST_HOURS_LOG` and its normal configuration.
Keep the repository intact so the shared writer and scoring references resolve.

## Capture the working day

Read `../closing-time/references/scoring-constants.md`, then privately compute
and retain the agent's blind FW-C. Do not reveal it during appraisal.

Run the bundled collector and save its JSON output locally:

```bash
bash <skill-dir>/scripts/buzz-stack-facts.sh --json > <capture.json>
```

Without `--json`, the same collector prints a readable fact sheet. For an
explicit calendar-day backfill, add `--date YYYY-MM-DD`. Normally the window runs
from the last seal to now, including work after midnight. With no seal within
48 hours, the collector uses the current calendar day and labels that fallback.
Keep the first successful capture fixed for this close; do not shift the window
while answering appraisal questions.

An unreadable channel, unresolved writer, or truncated message page blocks a
complete capture. Explain the missing evidence and leave the day unsealed.
Do not treat quiet agents as dead or treat unavailable data as zero work.

## Read and synthesize

Deduplicate shipped outcomes across threads and available work logs. Surface
contradictory accounts, dangling threads, and stale or missing canvases. Thread
silence is a prompt for judgment, not proof that the work failed. Root IDs and
timestamps remain attached to the evidence.

Carry forward real loose ends in your existing task system, using stable keys
and enough context to resume: state, attempts, files, first command, done
condition, and source session. Do not turn closing into unrelated implementation.

## Appraise once

Human and agent time come from the captured message timestamps, with the
collector's 30-minute gap cap. These are modeled timing estimates, not direct
observation of attention. GH is a separate counterfactual estimate for the
shipped work; use the shared taxonomy and type-specific anchors.

Ask one question at a time:

1. FW-C 1–10 for the Buzz working day.
2. If FW-C >= 5, request an optional verbatim note about why it mattered.
3. Give a GH range and counterfactual explanation; let the operator choose.

If the operator explicitly delegates the appraisal too, estimate the proxy
FW-C and mark `fwc_source=agent-blind` with `operator-override-fill`. Keep the
original blind score separate. Do not fabricate a quote; omit it when absent.
Use `operator` provenance only for an operator-supplied score.

## Record and seal

Render a local HTML report with shipped work first, followed by the thread
table, roster, timing and appraisal, loose ends, and canvas findings. Do not
post the report to Buzz. Append a short close narrative to your daily notes.

Save appraisal JSON, with values from the current close:

```json
{"type":"speed","gh_mins":120,"fwc":5,"fwc_source":"operator",
 "fwc_eom":4,"desc":"Completed the day's agreed work","tags":[]}
```

Optional fields: `subtype`, `note`, and `backlog_months`. A note must be the
operator's actual words. Then write the measurement and seal:

```bash
python3 <skill-dir>/scripts/record-close.py --capture <capture.json> \
  --appraisal <appraisal.json> --report <report.html> --seat <agent-label>
```

The helper preserves the `buzz-stack-YYYY-MM-DD` join key, uses source
`buzz-stack`, and verifies the canonical measurement before sealing. Matching
retries reuse the record. Changed re-closes require an explicit amendment;
never silently append a duplicate day or rewrite the historical measurement.

Return the report link, captured window, HH/GH, FW-C with its provenance,
remaining work, and seal result. Keep the blind score private. A successful
report alone is not a successful close if the measurement or seal failed.

## Limits

This public skill closes the whole working day; per-thread close is not exposed
by its record helper. Overlapping threads can double-count attention, and gaps
are capped. A page at the configured retrieval limit is treated as incomplete.
The collector does not diagnose runtime health or fill missing relay evidence.
