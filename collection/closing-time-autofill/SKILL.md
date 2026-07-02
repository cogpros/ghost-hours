---
name: closing-time-autofill
triggers:
  - "/closing-time-autofill"
  - "auto close everything yourself"
  - "auto close it all out yourself"
  - "close out while I sleep"
  - "fill it all out yourself"
description: Auto-fill variant of closing-time. Operator-fired (the operator must type the slash command or say "auto close everything yourself") but the agent completes all operator-fill fields — FW-C, drift, GH estimate, subtype, verbatim note — and fires the seal autonomously. For when the operator is asleep, depleted, or explicitly delegates the whole protocol. FW-C and other felt-weight values are tagged agent-estimated in the fact sheet and log entry so the research dataset stays honest. Distinct from closing-time (which waits at operator-only steps). NOT FOR routine close where the operator can answer (use closing-time); mid-session checkpoints.
user-invocable: true
metadata:
  version: "2.0.0"
  license: "Apache-2.0"
---

# Closing Time Autofill — Agent Instructions

You are running the operator-delegated end-of-session protocol. Same scope as `closing-time` — every phase, every script call, every state file write — but with agent auto-fill for operator-only fields and an agent-fired seal.

This skill ONLY runs when the operator explicitly invokes it. It is not an autonomous protocol; it is a delegated one. The operator chooses to hand the whole protocol to the agent (typically because they are asleep, depleted, or have other reasons to skip the question-by-question walkthrough).

This variant shares `scripts/`, `config/`, and `references/scoring-constants.md` with `../closing-time/`. Paths written as `[closing-time]` mean that sibling directory.

## When to use this variant

| Variant | Who fires | Who fills operator-fill | Who fires seal |
|---|---|---|---|
| `closing-time` (default) | Operator | Operator (one question at a time) | Operator confirms |
| `closing-time-autofill` (this skill) | Operator | Agent (best-estimates marked clearly) | Agent fires after operator delegated |

This variant is appropriate when ALL of these are true:
- Operator typed the slash command OR said something equivalent to "auto close everything yourself"
- Operator is not present to answer Phase 3 Ghost Hours questions
- Operator has accepted that agent-estimated FW-C will be tagged as such in the dataset

If the operator is awake and capable of answering Ghost Hours questions, run `closing-time` instead. Do not silently upgrade to this variant.

## The standing "never-auto-seal" rule

The agent never seals a session without operator confirmation. This skill is the exception, because the operator's explicit invocation IS the confirmation. The rule still binds outside of this skill's invocation context — if you find yourself in `closing-time` (not this one) and tempted to auto-fill + auto-seal, stop. That is the failure mode this skill exists to handle properly.

## Pacing Rule

Run all phases in sequence. Do NOT pause between phases waiting for operator answers — there is no operator to wait for. Within Phase 3 (Ghost Hours), fill each step from session evidence and agent judgment; do not ask the operator.

## Pre-Phase 0: Discord Thread Routing (optional)

Same as `closing-time`: detect whether this is a Discord thread close. If thread mode → switch to the Thread Mode Pipeline (which has no operator-fill fields by design, so the auto-fill question doesn't arise). If terminal mode → proceed to Phase 0.

## Phase 0: Gate

Silently compute your own blind FW-C. Do NOT output. It goes into the `--fwc-eom` arg of `log-leverage.sh` (the field name is retained for dataset compatibility; read it as the agent's blind estimate).

In this variant, a separate operator-proxy estimate ALSO populates the `--fwc` slot — see Phase 3 Step 7 below. The operator FW-C slot must carry a clear agent-estimated marker in the saved fact sheet (Step 10) and the structural `--fwc-source` field (Step 11).

## Phase 0.5: Sweep Kickoff

Same as `closing-time`:

1. `SWEEP_TAG=$(python3 [closing-time]/scripts/session-fact-sheet.py --print-session-id)`
2. `bash [closing-time]/scripts/sweep.sh start "$SWEEP_TAG"`
3. Say nothing about the sweep.

## Phase 0.7: Fact Sheet Extraction

```bash
python3 [closing-time]/scripts/session-fact-sheet.py
```

Hold the fact sheet in context. Verify INTENT matches your memory of this session's first message. If the wrong session was picked, re-invoke with explicit path.

## Phase 1: Capture

Same as `closing-time`. Append session notes to the daily notes file (default `~/.closing-time/memory/YYYY-MM-DD.md`). Use today's date — if the session crossed midnight, append to the date where most of the work happened and note the cross-midnight close.

The session narrative must include INTENT, what happened, what was discovered/decided, what was NOT completed, key insight (if any).

Say: "Capture done." Proceed to Phase 1.5.

## Phase 1.5: Clarify

Same as `closing-time`. Triage each "Not completed" item:
- Can resolve now → do it.
- Already absorbed by other work → `[closing-time]/scripts/resolve.sh absorb`
- Blocked / external → `[closing-time]/scripts/resolve.sh park`
- No longer relevant → `[closing-time]/scripts/resolve.sh kill`
- Real unresolved → confirm it is in your task system.

Say: "Clarify done." Proceed to Phase 2.

## Phase 2: Assay

Same as `closing-time`. Scan for content-ready material against your configured content lanes. Route via your content pipeline if found; local fallback is `~/.closing-time/content-ideas.md`.

If no content found, say: "No content to route." Proceed to Phase 3.

## Phase 3: Measure — AGENT AUTO-FILL (the core difference from closing-time)

This is where this skill diverges. You fill all the steps from session evidence and agent judgment. No operator questions.

### Step 0: Surface the fact sheet (still useful for the operator on wake)

Print the fact sheet output as-is so the operator can see it later. No paraphrasing.

### Step 1: Human time correction

Accept the mechanical Human time as-is unless the session JSONL shows obvious offline-thinking gaps. (Mechanical Human time is gap-before-each-operator-message; if there were genuine reading/thinking pauses the mechanical extractor missed, adjust. Otherwise: leave as mechanical.)

Record: `Human time edit: <mechanical value> [accepted as-is, no adjustment evidence]` OR `Human time edit: <adjusted value> [reason: <observation from session>]`.

### Step 2: Drift suggestion + record

Read INTENT and WORK SHIPPED. Pick one of the four Drift states from `[closing-time]/references/scoring-constants.md` (single source for all scoring values — Read it now if you haven't this session) without asking.

Record verbatim reasoning in 1 sentence.

### Step 3: Type Classification

Apply the same rules as `closing-time`:
- If the fact sheet auto-classified AUGMENTATION (configured judgment-amplifier skills fired) → record as AUGMENTATION.
- Else, decide: could this have happened without AI?
  - YES → type = SPEED. Skip to Step 5.
  - NO → type = UNLOCK. Continue to Step 4.

### Step 4: Subtype Classification (UNLOCK only)

Same gate as `closing-time`: if no `event_label` is configured, subtype = augmentation — done.

If `event_label` is set, the agent decides without asking:
- Could the operator do this BEFORE [event_label]? YES → restoration. Tag with the config's `recovery_tag`.
- Could the operator have LEARNED to do this BEFORE [event_label]? YES → bypass. Tag with the config's `recovery_tag`.
- NO to both → augmentation. No tag.

Base the decision on:
- What the work product is (cross-doc synthesis at pair density, multi-agent verification, etc.)
- The operator's documented pre-event capability, if your memory files record it
- Whether the work required structurally-paired patterns that don't exist as solo-human workflows

### Step 5: GH Estimate (type-aware)

Estimate GH using the per-type counterfactual frame and type ceilings from `[closing-time]/references/scoring-constants.md`.

If your estimate exceeds the ceiling, name it in the fact sheet ("estimated Nx, ceiling Yx for <type>, going with X anyway because <reason>"). Operator can recalibrate on wake.

### Step 6: Backlog

Estimate from session evidence:
- Was the topic referenced in prior daily logs or memory files? grep for it.
- Was the task referenced in a project file with a date?
- New work with no precursor → 0 months
- Sitting on the operator's mind for weeks/months → estimate from earliest reference

### Step 7: FW-C — AGENT-ESTIMATED

This is the operator's felt-weight score. You estimate it from session evidence:
- Did the session ship a milestone? (capability first, structural change, major artifact)
- Did the operator express weight in their own words during the session?
- How does it compare to prior FW-C entries in the log for similar work shapes?

Anchor: use the FW-C 1–10 anchor chart in `[closing-time]/references/scoring-constants.md`.

**Tag this value as agent-estimated in the Step 10 fact sheet and the Step 11 `--fwc-source` field.** This is the instrument-honesty step. If you do not tag, the dataset thinks the operator confirmed this number and the research instrument is contaminated.

### Step 8: Verbatim Note (MANDATORY if FW-C ≥ 5)

If FW-C ≥ 5, the note field MUST be the operator's actual words pulled verbatim from the session transcript. Search the session for the most thematic single quote — usually the moment the operator named the weight of the work, expressed depletion, expressed relief, or named the milestone.

Do NOT generate the note. Do NOT paraphrase. Pull a real quote from the transcript.

If FW-C < 5, the note is optional.

**Mark the agent-fill structurally:** pass `--fwc-source agent-blind` (done in the call below). The writer records this in the `fwc_source` field — do NOT smear an "agent-estimated" stamp into `--note` prose (an earlier draft did; the structural field replaced it). The `fwc_source` field is what makes the dataset honest.

### Step 9: Optional program tagging

Same as `closing-time`. If the operator tracks entries for an external program (an R&D tax-credit claim, a research study, an internal initiative), add the relevant tag via `--tags`. If nothing applies, move on.

### Step 10: Save fact sheet to disk

Write the populated fact sheet to:

```
~/.closing-time/state/fact-sheets/<session-id>-<YYYYMMDD-HHMMSS>.md
```

Include a clearly-labeled `═══ OPERATOR-FILLED (Phase 3) — AGENT-ESTIMATED PER OPERATOR OVERRIDE <ISO date> ═══` section header above the agent-filled fields. Dataset readers key on this header to distinguish operator-confirmed from agent-estimated entries.

### Step 11: Log it

```bash
[closing-time]/scripts/adapters/log-leverage.sh \
  --type <speed|unlock> \
  --hugr <hugr_mins> \
  --gh <gh_mins> \
  --desc "<your 280-char summary, include 'agent auto-fill per operator override' marker>" \
  --fwc <agent-estimated score> \
  --fwc-source agent-blind \
  --fwc-eom <silent blind score from Phase 0> \
  --source claude-cli \
  [--subtype <restoration|bypass|augmentation>] \
  [--backlog <months>] \
  [--note "<operator's verbatim quote pulled from transcript>"] \
  [--tags "operator-override-fill,<recovery_tag or program tags>"]
```

The `operator-override-fill` tag is mandatory on every entry from this skill. It is how downstream analysis filters agent-estimated FW-C from operator-confirmed FW-C.

## Phase 4: Record

Same as `closing-time`. Scan for creative work (briefs, posts, scripts, drafts). Save full text to `content_<slug>.md` in your notes directory if found. Never summarize.

If no creative work, say: "No creative work to record." Proceed to Phase 5.

## Phase 5: Seal — AGENT FIRES (the second core difference)

After all four core phases (Capture + Clarify, Assay, Measure, Record), proceed directly to seal. There is no operator confirmation step; the operator's explicit invocation of this skill IS the confirmation.

### 5.1 Sweep status check (internal)

Silently read sweep status:

```bash
SWEEP_TAG=$(python3 [closing-time]/scripts/session-fact-sheet.py --print-session-id)
bash [closing-time]/scripts/sweep.sh status "$SWEEP_TAG"
```

Parse: `commit`, `pending-push`, `error`.

### 5.2 Push gate — DEFER, do NOT auto-push

If there are `pending-push` lines, the agent does NOT push. The push gate in `closing-time` is operator-approval-only; with the operator asleep / delegating, you do not have approval to push.

State in the post-seal output: "Sweep staged N commit(s) locally — not pushed (no operator approval available for push gate). Run `sweep.sh push <tag>` on wake or push manually."

### 5.3 Seal

Write the closure state file:

```bash
[closing-time]/scripts/mark-closed.sh "$SWEEP_TAG"
```

Always pass `$SWEEP_TAG` explicitly. Never rely on the fallback that reads a shared `current-session-id.txt` cache — shared caches are clobbered by concurrent sessions.

### 5.4 Surface results (post-seal)

Print a summary that includes:
- Closing time complete (mode: agent auto-fill per operator override)
- GH entry totals (type, HH, GH, FW-C with explicit `[agent-estimated]` marker)
- Repo hygiene status (committed counts, pending-push deferred)
- Sealed at ISO timestamp

Example:

```
Closing time complete.  [MODE: agent auto-fill per operator override]

  Type:      UNLOCK (bypass)
  HH:        1.1h paired
  GH:        10.0h ghost (~9x)
  Backlog:   1.0 month
  FW-C:      7  [agent-estimated — operator override]
  Verbatim:  "<actual operator quote from transcript>"

Repo hygiene:
  ~/my-project  | pending-push | 2 commit(s) — not pushed (no operator approval for push gate)

Sealed at 2026-05-20T08:15:14Z.
Recalibrate FW-C on wake if 7 is off; re-log with the operator's value if needed.
```

## Error Handling

- If any phase is blocked → state the block in the session narrative and continue.
- If the fact sheet extractor fails → abort the skill and run `closing-time` manually with an explicit session JSONL path.
- If the seal fails (mark-closed.sh non-zero) → state the failure prominently in the output. Do NOT silently continue.

## Important Rules

- NEVER run this skill autonomously. The operator must explicitly invoke (slash command typed OR equivalent verbal delegation captured in conversation).
- NEVER skip the agent-estimated tagging in the fact sheet and `--fwc-source` field. This is the instrument-honesty step. If you skip it, the dataset cannot distinguish agent estimates from operator-confirmed values.
- NEVER push commits without explicit operator approval. Defer the push gate. Repos can stay with local commits until the operator wakes.
- NEVER output the silent blind FW-C from Phase 0. Only the operator-slot value (which in this variant is agent-estimated and tagged as such).
- The `operator-override-fill` tag is mandatory on every log entry from this skill.
- If you find yourself in `closing-time` (not this skill) and tempted to auto-fill, STOP. The whole point of the two-skill split is that the default `closing-time` waits for the operator. This skill is the explicit "delegate the whole thing" mode.

## Known Limitations & Gotchas

- **FW-C is agent-estimated, not operator-confirmed.** The dataset treats these as different categories. Filter on the `operator-override-fill` tag (or `fwc_source`) for downstream analysis.
- **Push gate deferred by default.** Local commits pile up until the operator pushes or runs `closing-time` on wake.
- **Operator should recalibrate on wake.** If the agent-estimated FW-C is materially off, the operator can re-log with their actual score (amend the agent-estimated entry).
- **Verbatim note is still the operator's words.** Even in auto-fill mode, the verbatim quote MUST come from the session transcript — pulling a real quote, not generating one. If no FW-C ≥ 5 quote exists in the session, mark the note as `[no operator verbatim available — session contained no thematic quote at FW-C ≥ 5 register]`.
- **Sweep abandonment.** If the invocation is abandoned, cancel the background sweep:
  ```bash
  SWEEP_TAG=$(python3 [closing-time]/scripts/session-fact-sheet.py --print-session-id 2>/dev/null)
  bash [closing-time]/scripts/sweep.sh cancel "$SWEEP_TAG"
  ```
- **Concurrent close races.** The JSONL session_id is unique per session and immutable, so two concurrent close runs don't stomp each other. Same gotcha as `closing-time`.

## Dependencies

Same as `../closing-time/`. Required bins: `bash`, `python3`. All scripts, config, and `references/scoring-constants.md` are shared from `../closing-time/` — this variant ships no scripts of its own.

**Companion skills:**
- `../closing-time/` — the operator-fill default (run this if the operator is awake)
- `../closing-time-fleet/` — the multi-agent stack close

## Trigger conditions

This skill runs when:
1. The operator types `/closing-time-autofill` directly, OR
2. The operator gives `closing-time` an argument that delegates the whole protocol — e.g. "auto close it all out yourself", "fill everything out yourself", "close it all out while I sleep". When the parent skill sees this argument shape, it should hand off to this skill.

This skill does NOT run when:
- The operator typed the closing-time trigger without delegation arguments (use `closing-time`, the default)
- The session is mid-flight and the operator wants a checkpoint (not a close at all)

## Framing

The auto-fill variant of the closing-time family. `closing-time` is the default (operator-fill). This skill is the explicit-delegation variant: operator-fire + agent-fill + agent-seal, used when the operator is asleep, depleted, or explicitly delegates the whole protocol. Pollock 2026.

## Observability

Bus emit at protocol completion with explicit `mode=operator-override-fill` marker:

```bash
[closing-time]/scripts/adapters/emit-event.sh closing-time-autofill closing_time_autofill_emitted "<session marker>" "fwc_captured=true fwc_mode=agent-estimated drift_logged=true gh_entry_id=<id> mode=operator-override-fill" ghost-hours
```

This event type is distinct from `closing_time_emitted` so downstream consumers can filter auto-fill closes from operator-confirmed closes.

## Origin

This variant exists for the case where the operator is unavailable at close time and delegates the whole protocol; the honesty-tagging requirement exists so that delegation never corrupts the dataset — agent-estimated felt-weight must always be distinguishable from operator-confirmed felt-weight.
