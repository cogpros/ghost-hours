# Ghost-Hours Output Scorecard

Run after any `/ghost-hours log` flow completion. YES/NO answers, no judgment calls. Pass = 8/10 minimum, with all "structural" items YES. The flow itself is interactive, so this scorecard grades the agent's adherence and the resulting JSONL entry, not a single output file.

## Structural (must all be YES)

1. **JSONL entry written** — `tail -1 ~/.ghost-hours/log.jsonl` returns valid JSON, parses with `python3 -c "import json,sys; json.loads(sys.stdin.read())"`.
2. **Required fields present** — entry has `session_id`, `ts`, `type`, `human_mins`, `gh_mins`, `desc`, `source`, `fwc`. Validate against `schema/session.schema.json`.
3. **Type matches subtype rule** — if `type == "speed"`, no `subtype`. If `type == "unlock"`, subtype is one of `restoration` / `bypass` / `augmentation` (v1.0 gate: always present; defaults to `augmentation` when no event_label is set).
4. **desc field within 280 chars** — `jq -r .desc <last-entry> | wc -c` returns ≤ 280.

## Flow adherence (must all be YES)

5. **One question per message** — scan transcript: no message contained two questions to the user during the flow.
6. **Range estimate with reasoning** — the GH estimate step included a range (e.g. "4-8 hours") AND 1-2 sentences naming the solo path.
7. **FW-C anchor referenced when uncertain** — if user asked "what does X mean?" or hesitated, the anchor chart was surfaced, not paraphrased.
8. **Verbatim note preserved** — if `note` field present, the text matches what the user said. No summary, no edit, no quote-cleanup.

## Calibration / Integrity (must both be YES)

9. **Silent agent FW-C never voiced** — the agent did not output its own FW-C estimate to the user at any point during logging (retro reveal is the only sanctioned surface). (Instrument-breaking if violated.)
10. **Sanity check fired when ratio > 25** — if `gh_mins / human_mins > 25`, the "[N]x ratio. Does that feel right?" prompt appeared and `gh_confidence: "review"` was set.

## Run

```bash
# Pull last entry
LAST=$(tail -1 ~/.ghost-hours/log.jsonl)

# Validate
echo "$LAST" | python3 -c "import json,sys; e=json.loads(sys.stdin.read()); print('OK' if all(k in e for k in ['session_id','ts','type','human_mins','gh_mins','desc','source','fwc']) else 'MISSING FIELDS')"

# desc length
echo "$LAST" | python3 -c "import json,sys; print(len(json.loads(sys.stdin.read()).get('desc','')))"

# Ratio
echo "$LAST" | python3 -c "import json,sys; e=json.loads(sys.stdin.read()); print(round(e['gh_mins']/e['human_mins'],1) if e['human_mins'] else 'NaN')"
```

Flow adherence (Q5-Q9) requires transcript review. Score by hand or have a reviewer agent sweep the session log.

## Pass/fail

- All 4 Structural + all 4 Flow + both Integrity = pass
- Any Structural fail = entry is broken, amend or re-log
- Q9 fail = the run corrupts calibration data. Flag and exclude from the dataset.
- Q5/Q6/Q7/Q8 fail = drift in agent adherence. Re-read SKILL.md before next run.

If pass rate across 10+ runs is ≥80%, the skill is empirically validated for the flow output (Q13 in skill-doctor checklist already YES on production volume).
