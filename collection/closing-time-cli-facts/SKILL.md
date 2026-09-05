---
name: closing-time-cli-facts
description: >-
  Use when the operator delegates the whole CLI session close, including
  estimated appraisal and seal, in Claude Code, Codex, or Grok Build.
  Supports explicit session binding and honest agent attribution. Use
  closing-time for interactive appraisal.
license: Apache-2.0
metadata:
  version: "1.0.0"
---

# Closing Time CLI Facts

Explicit invocation delegates the whole close: capture, clarify, assay,
measurement, creative-work recording, and seal. The operator may be present or
absent. Discussing this skill does not invoke it. Complete delegated appraisal
without questions; ordinary `closing-time` remains interactive.

Use shared scripts in `../closing-time/scripts/`, resolved from this skill's
real directory. In examples, set `SCRIPTS` to that directory in each shell call.
The helper writes state under `${CLOSING_TIME_STATE:-$HOME/.closing-time/state}`
and measurements to the Ghost Hours log selected by `GHOST_HOURS_LOG` or the
normal Ghost Hours configuration. It uses the bundled writer directly;
argument-only adapter fallback records are not completed measurements.

## Bind once

Identify the current host, its native session ID, and exact transcript from
runtime context. Never substitute the newest transcript from another session.

| Host | Runtime argument | Transcript | Recorded source |
|---|---|---|---|
| Claude Code | `claude` | Session JSONL | `claude-cli` |
| Codex | `codex` | Rollout JSONL | `codex-cli` |
| Grok Build | `grok` | `chat_history.jsonl` with sibling `events.jsonl` | `grok-cli` |

Read `../closing-time/references/scoring-constants.md`. Compute a private blind
FW-C before estimating the operator-proxy score, then bind it:

```bash
python3 "$SCRIPTS/cli-close.py" prepare --runtime codex \
  --seat assistant --session-id <native-id> \
  --transcript <exact-transcript-path> --blind-score <1-10>
```

`--seat` is your configured agent label; runtime is the actual host, not its
model vendor. The command prints the saved binding path. Retain it as `BINDING`
and retain its session ID as `SWEEP_TAG` for the entire close. Read the binding's
`fact_sheet` text for capture and verify intent against the session. Do not
print its blind score. A retry keeps the original binding and score.

Missing session identity, mismatched transcript, or invalid timing stops before
measurement or seal. Explain the specific block. Do not improvise a format
conversion or fabricate missing time. After binding succeeds, start the shared
sweep with `bash "$SCRIPTS/sweep.sh" start "$SWEEP_TAG"`.

## Capture, clarify, and assay

Use the base `closing-time` capture/clarify/assay rules with delegated choices:
append intent, work completed, decisions, open work, and insights to your daily
notes; resolve cheap authorized loose ends and park genuine blockers in your
existing task system. Use stable task keys on retries. Route actual content
candidates through your configured pipeline or local content-ideas file.
Do not start unrelated work, publish content, or expand memory permissions.

## Measure

Use the shared scoring constants and the root Ghost Hours taxonomy:

1. Retain the binding's mechanical Human/Agent/Hugr timing and its provenance.
2. Record drift with a short reason.
3. Choose speed or unlock. For unlock, use the configured `event_label` and
   documented operator context for restoration/bypass; without that context,
   use augmentation as the base skill specifies.
4. Estimate GH against the type's counterfactual and ceiling; explain excess.
5. Estimate backlog from available evidence; new work is zero.
6. Estimate the operator-proxy FW-C separately from the saved blind score.
7. For FW-C >= 5, select a real thematic operator quote. If none exists, omit
   `note` and mark quote unavailable in the fact sheet. Never manufacture a quote.
8. Apply configured program or forward-only condition tags where applicable.

Save the populated fact sheet under the state root's `fact-sheets/` directory,
using the session ID in its filename. Include session ID, seat, runtime, timing
provenance, and an `AGENT-ESTIMATED PER OPERATOR DELEGATION` appraisal heading.

Save appraisal JSON with this shape (values below illustrate the format):

```json
{"type":"speed","gh_mins":60,"fwc":4,"desc":"Completed the requested work",
 "backlog_months":0,"tags":[]}
```

Optional fields: `subtype` and `note`. Keep provenance out of `desc` and `note`.
The helper supplies `agent-blind`, `operator-override-fill`, actual source/seat,
and the saved blind score. The historical `fwc_eom` field name remains for
compatibility; it means the agent's blind estimate.

```bash
python3 "$SCRIPTS/cli-close.py" log --binding "$BINDING" \
  --appraisal <appraisal-json-path> --fact-sheet <populated-fact-sheet-path>
```

This checks any quote against operator messages and requires a persisted
canonical measurement. Matching retries do not append a second row; changed
appraisals require an explicit amendment rather than another close.

## Record and seal

Save creative work in full in your configured notes directory. Read this
session's sweep status once. **Pushes require explicit authorization.** Delegating
appraisal and seal alone does not authorize publishing commits. Defer pending
pushes and include them in the final receipt when authorization is absent.

After required capture/record work and measurement succeed:

```bash
python3 "$SCRIPTS/cli-close.py" seal --binding "$BINDING"
```

The helper checks measurement and fact-sheet receipts, writes the per-session
seal, and emits one `closing_time_cli_facts_emitted` event. Required write failure
leaves the close incomplete. Optional routing failures and deferred pushes stay
visible as pending items. Never claim a fallback argument log is a saved session.

Return one concise receipt: runtime/seat, session ID, fact-sheet path, HH/GH,
proxy FW-C marked agent-estimated, pending work, repository outcome, and seal
timestamp. Keep the blind score private and skip routine phase announcements.
If the operator cancels, cancel this session's sweep and leave it unsealed.

## Dependencies and limitations

Python 3.10+, bash, the sibling closing-time scripts, and the bundled Ghost Hours
writer are required. Native Grok parsing joins query order with turn events;
ambiguous joins fail rather than assigning another turn's timing. Runtime
support follows transcript format, not model name. Historic rows are untouched.

The former `closing-time-autofill` command forwards here. Event readers should
accept its historical `closing_time_autofill_emitted` records alongside the new
event name; the helper does not emit both for a single close.
