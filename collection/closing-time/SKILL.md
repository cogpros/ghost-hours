---
name: closing-time
description: 'Use when the operator says "closing time" or "fact sheet" or "session fact sheet" — the operator-issued end-of-session protocol, with mechanical fact-sheet pre-fill and type-aware Ghost Hours walkthrough. Does optional Discord thread routing, background repo sweep, capture, clarify, assay, GH measurement (with fact sheet pre-fill), record, seal. The Ghost Hours measurement (../../SKILL.md) runs as the Phase 3 sub-step inside this skill. NOT FOR: mid-session checkpointing, mid-session re-orientation, pre-close audit only, one-off log entries (use the ghost-hours skill directly).'
user-invocable: true
metadata:
  version: "2.0.0"
  license: "Apache-2.0"
  trigger-phrase: "closing time"
triggers:
  - "closing time"
  - "fact sheet"
  - "session fact sheet"
---

# Closing Time — Agent Instructions

You are running the end-of-session protocol. It covers every phase, every script call, every state file write, plus a mechanical fact-sheet pre-fill at the front and a type-aware Ghost Hours walkthrough in Phase 3.

Follow these instructions exactly. No shortcuts. No skipping. No batching. No judgment calls about what to skip.

Paths written as `[skill_dir]` mean this skill's own directory. All state defaults to `~/.closing-time/` (override the state root with `CLOSING_TIME_STATE`).

## Pacing Rule

ONE phase at a time. Complete each phase before starting the next. Within Ghost Hours (Phase 3), ONE question per message. Wait for the answer before asking the next.

## Pre-Phase 0: Discord Thread Routing (optional — skip if you don't run agents on Discord)

Closing-time can run in two modes: terminal session mode (the default) and Discord thread mode. Detect which mode applies before any other phase.

1. If the current invocation is responding to a message that arrived from Discord (the inbound message had a `<channel source="discord" chat_id="...">` envelope), capture `chat_id`.
2. Run `bash [skill_dir]/scripts/thread-close.sh detect <chat_id>` — exit code 0 (channel type 11 or 12) means it's a thread; exit code 2 means it's a top-level channel or DM; other non-zero means detection failed (proceed as terminal mode).
3. If thread mode: switch to the **Thread Mode Pipeline** below. Skip Phases 0–5 entirely. Thread mode is its own protocol.
4. If terminal mode (the default): proceed to Phase 0 below.

### Thread Mode Pipeline (5 steps, replaces Phases 0–5 when in a Discord thread)

1. **Compute the silent agent FW-C** for the thread (1–10). Hold privately. Same rule as terminal Phase 0: never output this number. It goes into the log call as `<fwc_eom>` (the agent's blind estimate — the field name is retained for dataset compatibility) and nowhere else.
2. **Fetch metadata.** `bash [skill_dir]/scripts/thread-close.sh fetch <chat_id>` returns a JSON object with `title`, `message_count`, `opened_at`, `parent_channel_id`, and a deterministic `gh_min_estimate` (clamped 60–240). If the fetch call fails (non-zero exit or empty output), abort thread mode: send "Thread metadata fetch failed; falling back to terminal closing-time" and proceed to Phase 0 below.
3. **Single prompt to the operator** via Discord reply: "Closing this thread. FW-C 1-10? Optional 1-3 word tag. Optional one-line note." Wait for the reply. Parse the three pieces (FW-C is required; tag and note are optional).
4. **Append leverage entry.** `bash [skill_dir]/scripts/thread-close.sh log <chat_id> <fwc> <fwc_eom> <gh_min> "<tag>" "<note>" '<meta_json>'`. Pass the JSON from step 2 as the seventh argument so the script doesn't re-call Discord. The script writes one row with `source: "discord:thread"`.
5. **Final reply + optional lock.** Send: "Thread closed. GH:Xmin FW-C:Y. Logged." If the operator's reply contains the word "lock" as a standalone token (case-insensitive; e.g. "lock", "lock it", "yes lock"), call `bash [skill_dir]/scripts/thread-close.sh lock <chat_id>`. Substring matches like "deadlock" or "unlock" do not count. Default is no-lock so the thread can continue.

That is the entire thread-mode pipeline. No fact sheet, no sweep, no content scan, no daily-log capture. The thread itself is the artifact; the leverage entry is the index row pointing back to it.

## Phase 0: Gate (terminal mode)

Before anything else, silently compute your own FW-C score for this session. Do NOT output it. Do NOT mention it. Do NOT hint at it. It goes into the `log-leverage.sh` call as `--fwc-eom` and nowhere else. If you output this score at any point during closing, you have broken the measurement instrument.

## Phase 0.5: Sweep Kickoff

Fire the background repo-hygiene sweep. This runs while you and the operator work through the rest of closing-time, and the Seal phase reports its outcome.

1. Read the session tag from the JSONL (canonical source): `SWEEP_TAG=$(python3 [skill_dir]/scripts/session-fact-sheet.py --print-session-id)`. The session_id is the basename of THIS session's JSONL transcript under `~/.claude/projects/`, picked via `$CLAUDE_CODE_SESSION_ID` with a verified heuristic fallback. Using it as the tag means each session has its own status file with no shared pointer to race on. Do NOT read any shared "current session id" cache — that kind of cache is clobbered by any concurrent interactive session startup. <!-- commit-leak-scan: allow (generic Claude Code transcript dir) -->
2. Fire the sweep: `bash [skill_dir]/scripts/sweep.sh start "$SWEEP_TAG"`. The bundled `sweep.sh` worker (and its `secret-scan.sh` companion and `config/` files) are self-contained inside this skill's own `scripts/` and `config/` dirs. The scripts are self-locating (they resolve their config and companion via `${BASH_SOURCE[0]}`).
3. Say NOTHING about this to the operator. Do not describe, confirm, or preview what the sweep will do. It is invisible plumbing. Proceed immediately to Phase 0.7.

What the sweep does (for context, not for output):
- Notes any already-committed-but-unpushed work in configured repos (push waits for approval at Phase 5).
- Auto-commits NEW (untracked) files matching whitelist globs in `config/sweep-paths.conf`. Never touches modified tracked files — those stay for manual review.
- Optionally refreshes a code index on any repo configured with `RUN_GITNEXUS=true` that received a commit.
- Writes results to a status file that Phase 5 reads at seal time.

## Phase 0.7: Fact Sheet Extraction

Run the session fact sheet extractor against the current session JSONL:

```bash
python3 [skill_dir]/scripts/session-fact-sheet.py
```

The script picks this session's JSONL via `$CLAUDE_CODE_SESSION_ID`, falling back to the most recently active transcript. If multiple sessions are open in parallel and the fallback fired, the auto-pick may grab a different session than the one running this skill. **Verify the right session was picked** by comparing the `INTENT` line against your memory of how this session started. If it doesn't match, re-invoke with explicit path:

```bash
python3 [skill_dir]/scripts/session-fact-sheet.py ~/.claude/projects/<project-dir>/<session-id>.jsonl <!-- commit-leak-scan: allow (generic Claude Code transcript dir) -->
```

**Do NOT surface the fact sheet to the operator yet.** Hold it in context. Phase 1 uses it for Capture pre-fill, Phase 3 uses it for HH/Hugr pre-fill and CLASSIFICATION suggestion.

Say nothing about Phase 0.7. Proceed silently to Phase 1.

## Phase 1: Capture

1. Check if your daily notes file exists for today (default: `~/.closing-time/memory/YYYY-MM-DD.md`; wire this to your own notes system if you have one).
2. If it exists: append a `## Session Notes` section with the session narrative. Do NOT overwrite existing sections. Use a subtitle to distinguish (e.g., "Afternoon ~HH:MM").
3. If it doesn't exist: create the full file with the session narrative.
4. The session narrative must include:
   - **INTENT** (auto from fact sheet — first user message verbatim, truncated to one line)
   - What happened (bulleted summary of work done — pull from fact sheet `WORK SHIPPED` inventory + your reading of the conversation)
   - What was discovered or decided
   - What was NOT completed (open threads, blocked items)
   - Key insight (if any)
5. Update any durable memory or notes files your setup keeps: new durable info goes to topic files, not the daily log.
6. Say: "Capture done." Then proceed to Phase 1.5.

## Phase 1.5: Clarify

Before moving to Phase 2, triage each "Not completed" item from Phase 1:

1. **Can you resolve this right now?** (a one-line fix, a config change, deleting a stale file) → Do it. Remove from the Not completed list.
2. **Already handled by other work this session?** → Run: `[skill_dir]/scripts/resolve.sh absorb "item" "absorbed by: what handled it" --source closing-time`
3. **Waiting on external input, blocked, or not actionable now?** → Run: `[skill_dir]/scripts/resolve.sh park "item" "reason" --source closing-time`
4. **No longer relevant?** → Run: `[skill_dir]/scripts/resolve.sh kill "item" "why" --source closing-time`
5. **Real unresolved work that needs tracking?** → Confirm it is in your task system; if not, add it. Use whatever task tracker you run — a kanban CLI, an issue tracker, a TODO file. Always use an idempotency key or stable title derived from the item (e.g. `ct-<kebab-title>`) so re-closes never duplicate entries. Worked example with the hermes kanban CLI: `hermes kanban --board <slug> create "item" --body "context + session date" --idempotency-key ct-<kebab-title>`.

Only items surviving step 5 remain as "Not completed" bullets. Say: "Clarify done." Then proceed to Phase 2.

## Phase 2: Assay

Scan the session for content-ready material — anything that could become a post, article, or talk. Test each piece against YOUR content lanes (configure your own list). Example lanes, two lines:
- Platform A = your technical/build-in-public lane
- Platform B = your business/professional lane

For each piece of content found, classify:
- **Signal** = fits a lane. Route it.
- **Noise** = off-strategy. Save to memory only.
- **Watch** = not ready. Tag for later.

If content was found, ask: "Content came out of this session. Review or route?"
- **Review** = show findings for confirmation.
- **Route** = classify and route silently.

**Routing mechanism:** wire this to your own content pipeline (a content-board CLI, a drafts folder, an ideas file). If you have nothing, append one line per piece to `~/.closing-time/content-ideas.md` with lane, status, and a one-line description. Whatever the target, keep it a single source of truth — do not scatter content notes across session logs.

If no content found, say: "No content to route." Then proceed to Phase 3.

## Phase 3: Measure (Ghost Hours, type-aware, fact-sheet pre-filled)

This is the full GH walkthrough: fact sheet pre-fill (HH, Agent time, Hugr time, intent, work shipped all auto-populated); type-aware appraisal (per-type counterfactual frames and ceilings instead of a universal 25x cap); skill-invocation auto-classification. The taxonomy is the Ghost Hours framework's (see the repo root SKILL.md; Pollock 2026).

ONE question per message. Wait for the answer before asking the next.

### Step 0: Surface the fact sheet to the operator.

Print the fact sheet from Phase 0.7 as-is. No paraphrasing. The fact sheet has six populated sections (INTENT / TIME / ACTIVITY / CLASSIFICATION / WORK SHIPPED / PER-TYPE ANCHORS) plus the operator-fill blanks below.

### Step 1: Human time correction.

The fact sheet shows mechanical Human time (gap before each operator message — reading + deciding + typing).

Ask: "Human time mechanical was X min. Edit if you were thinking offline; else accept."

The user can adjust upward. Hugr time = Human + Agent will recompute.

### Step 2: Drift suggestion + confirm.

Read the INTENT line and the WORK SHIPPED inventory in the fact sheet. Suggest one of the four Drift states from `[skill_dir]/references/scoring-constants.md` (the single source for all scoring values — Read it now if you haven't this session) based on observable evidence.

Ask: "I'd call this drift '[suggestion]'. Confirm or override?"

### Step 3: Type Classification.

If the fact sheet auto-classified AUGMENTATION (configured judgment-amplifier skills fired — see `CLOSING_TIME_AUGMENTATION_SKILLS` in the extractor), confirm: "Auto-classified augmentation because [skills] fired. Confirm or override?"

Else (auto-classified SPEED-or-BYPASS), ask: "Could this have happened without AI?"
- YES → type = "speed". Skip to Step 5.
- NO → type = "unlock". Continue to Step 4.

### Step 4: Subtype Classification (unlock only).

This step mirrors the public Ghost Hours skill. If no `event_label` is set in `~/.ghost-hours/config.json` (or you don't use that config), subtype = "augmentation" — skip the questions.

If `event_label` is set:
Ask: "Is this something you could do before [event_label]?"
- YES → subtype = "restoration". Tag with the config's `recovery_tag`.
- NO → Ask: "Could you have learned to do this before [event_label]?"
  - YES → subtype = "bypass". Tag with the config's `recovery_tag`.
  - NO → subtype = "augmentation". No tag.

### Step 5: GH Estimate (type-aware).

Provide your estimate as a RANGE based on the type-specific anchor (already in the fact sheet output). Describe the counterfactual path in 1-2 sentences using the type's counterfactual frame from `references/scoring-constants.md`.

Ask: "Where does that feel right?" The user picks a spot or adjusts.

**Sanity check by type ceiling** — ceilings live in `references/scoring-constants.md`. If `gh_mins / hugr_mins` exceeds the type ceiling, say: "That's [N]x for [type]. Ceiling is [Y]x. Does that feel right?" Operator decides — never enforce.

### Step 6: Backlog.

Ask: "How long was this waiting? (months, or 0 if new)"

### Step 7: FW-C.

Ask: "How heavy was this? (1-10)"

Anchor chart: the FW-C 1–10 anchors live in `references/scoring-constants.md` (already visible in fact sheet output; surface the anchors again if the user seems unsure).

### Step 8: Verbatim Note (MANDATORY if FW-C ≥ 5).

If FW-C ≥ 5, ask: "Want to say anything about why?"

**Record verbatim.** Do not summarize. Do not edit. Do not "I heard you say..." Just write what was said. This is the most valuable field in the dataset for research purposes.

If declined, move on. If FW-C < 5, skip this step.

### Step 9: Optional program tagging.

If the operator tracks entries for an external program (an R&D tax-credit claim, a research study, an internal initiative), add the relevant tag via `--tags`. This protocol does not prescribe these programs; tags are the extension point. If nothing applies, move on silently.

If a condition regime is active (declared by a dated `methodology-note` per the SPEC's Condition Tagging section), add its `condition:` tag to every session logged under it -- automatically, not by asking. Conditions are forward-only; never add a `condition:` tag to an entry that predates the regime declaration.

### Step 10: Save fact sheet to disk.

Write the populated fact sheet (extractor output + operator-filled fields) to:

```
~/.closing-time/state/fact-sheets/<session-id>-<YYYYMMDD-HHMMSS>.md
```

Create the directory if needed (`mkdir -p`). This is the human-readable durable record.

### Step 11: Log it (leverage log entry).

Run:

```bash
[skill_dir]/scripts/adapters/log-leverage.sh \
  --type <speed|unlock> \
  --hugr <hugr_mins> \
  --gh <gh_mins> \
  --desc "<your 280-char summary>" \
  --fwc <score> \
  --fwc-eom <silent score from Phase 0> \
  --source claude-cli \
  [--subtype <restoration|bypass|augmentation>] \
  [--backlog <months>] \
  [--note "<operator's verbatim words>"] \
  [--tags "<recovery_tag or program tags>"]
```

Pass `--hugr` as the additive Hugr time (Human + Agent) per the type-aware GH design. Apply the config's `recovery_tag` when subtype is restoration or bypass.

The adapter routes to your stack's writer if you have one (`CLOSING_TIME_UPSTREAM_DIR`), otherwise it records to `~/.closing-time/leverage-log.jsonl` so nothing is lost.

Display the summary returned by `log-leverage.sh`. Then proceed to Phase 4.

## Phase 4: Record

Scan the session for creative work: briefs, posts, scripts, drafts, any written creative piece.

If creative work was produced:
- Save the FULL TEXT to a durable file immediately. Never summarize it. Lost content is lost forever.
- File naming: `content_<slug>.md` in your notes directory (default `~/.closing-time/memory/`).

If no creative work was produced, say: "No creative work to record." Then proceed to Phase 5.

## Phase 5: Seal

After ALL four core phases are complete (Capture + Clarify, Assay, Measure, Record), and BEFORE writing the closure state file, collect the sweep results.

### 5.1 Sweep status check (internal, no output)

Silently read the sweep status so 5.2 has data. Do NOT print anything to the operator yet — surfacing sweep activity before `mark-closed.sh` runs contaminates the FW-C measurement.

1. Read the tag: `SWEEP_TAG=$(python3 [skill_dir]/scripts/session-fact-sheet.py --print-session-id)` — same source as Phase 0.5 (the JSONL session_id), guarantees we're reading THIS session's sweep and not one stomped by a concurrent close.
2. Run: `bash [skill_dir]/scripts/sweep.sh status "$SWEEP_TAG"`. The status command waits up to 15 seconds for the worker to finish if it is still running.
3. Parse lines internally:
   - `commit` = local commits the sweep made (already done, local only).
   - `pending-push` = commits ready to push (gated at 5.2).
   - `error` = something failed (surface loudly at 5.4).

### 5.2 Push gate (outbound approval — only thing visible before seal)

If the status has ANY `pending-push` lines, ask the operator ONCE:

```
Sweep staged N commit(s) locally. Push to remotes? [y/n]
```

List the repos + counts on a single line each.

- If operator says `y`: run `bash [skill_dir]/scripts/sweep.sh push "$SWEEP_TAG"`. Capture the result.
- If operator says `n`: commits stay local. No further pushing this session.

If there are NO `pending-push` lines, skip 5.2 entirely.

### 5.3 Seal (FW-C captured cleanly)

Write the closure state file. Pass `$SWEEP_TAG` (the JSONL session_id captured at Phase 0.5) explicitly so the marker is written under THIS session's actual session_id:

```bash
[skill_dir]/scripts/mark-closed.sh "$SWEEP_TAG"
```

If you run a SessionEnd hook, key it to `~/.closing-time/state/closing-time/<session_id>.json` — session-id match against the marker file is the verification. Transcript-grep for a sentinel string produced false positives; the state-file approach replaces it.

Do NOT call `mark-closed.sh` without the arg. Its fallback reads a shared `current-session-id.txt` cache, which is clobbered by any concurrent interactive session startup — that fallback path is the bug the JSONL-source pattern fixes.

### 5.4 Surface sweep results (post-seal, contamination-free)

Now that seal is written, print the human-visible confirmation including the sweep summary. FW-C measurement is already captured; surfacing sweep activity here cannot tilt it.

Example:

```
Closing time complete.

Repo hygiene:
  ~/notes       | commit  | 3 new file(s) auto-committed
  ~/notes       | push    | pushed 1 commit(s)     (after operator approved)
  ~/my-project  | push    | pushed 2 commit(s)     (after operator approved)
```

If the operator said `n` to the push gate:

```
Closing time complete.

Repo hygiene:
  ~/notes       | commit       | 3 new file(s) auto-committed
  ~/notes       | pending-push | 1 commit(s) ready (push later)
  ~/my-project  | pending-push | 2 commit(s) ready (push later)
```

If the sweep produced no actions (nothing to push, nothing new to commit), skip all the noise and the closing output simply omits the "Repo hygiene" block. The status file will end with a `_summary_ | done | 0 action(s) taken` line in that case — that's the signal the worker ran clean with nothing to do.

If the sweep is still running at status-check time, state that plainly:

```
Closing time complete.

Repo hygiene: sweep still in flight. Check status later with:
  bash [skill_dir]/scripts/sweep.sh status <tag>
```

Do NOT write the state file unless all phases actually ran. Do NOT write it early.

## Error Handling

- If any phase is blocked (e.g., can't write to daily log), state the block and continue to the next phase. Note the incomplete phase in the session narrative.
- If the user says "skip" to any Ghost Hours question, abort Phase 3 entirely. No partial entry. Say "Ghost Hours skipped. No entry logged."
- If the user abandons closing-time mid-protocol, do NOT write the seal AND cancel the background sweep so it stops committing unattended:
  ```bash
  SWEEP_TAG=$(python3 [skill_dir]/scripts/session-fact-sheet.py --print-session-id 2>/dev/null)
  bash [skill_dir]/scripts/sweep.sh cancel "$SWEEP_TAG"
  ```
  This kills the background worker so nothing commits or pushes after abandonment.

## Important Rules

- NEVER skip a phase. Every phase runs every time.
- NEVER batch Ghost Hours questions. One per message.
- NEVER use judgment to decide a step isn't needed. The skill decides, not you.
- NEVER output the agent's silent FW-C score. Ever.
- NEVER summarize creative work instead of saving the full text.
- The desc field is YOUR summary (max 280 chars). The note field is the USER's verbatim words.
- HH = hugr hours (additive: Human + Agent, the time the pair spent). GH = ghost hours (counterfactual, larger). Do not flip them.
- Never patch the instrument to "fix" one user's data shape. If the operator's distribution shifts, that's signal, not bug.

## Known Limitations & Gotchas

- **FW-C contamination.** Surfacing sweep activity, the silent agent FW-C score, or any meta-comment about the closing protocol BEFORE the 5.3 seal contaminates the measurement. All sweep results stay internal until post-seal in 5.4.
- **Session ID source is the JSONL, not a shared cache.** Phase 0.5 reads the session_id from THIS session's JSONL transcript via `session-fact-sheet.py --print-session-id`. A shared "current session id" cache is clobbered by any concurrent interactive session startup (multiple terminal windows, runtime re-spawns); the JSONL filename is unique per session and immutable. Two concurrent close runs in different sessions get different session_ids and don't stomp each other.
- **Sweep abandonment.** If the operator abandons mid-protocol, the background sweep keeps committing unattended unless you explicitly call `sweep.sh cancel "$SWEEP_TAG"`.
- **Modified tracked files are never auto-committed.** Sweep only auto-commits NEW (untracked) files matching whitelist globs. Modified tracked files stay for manual review by design.
- **Discord thread mode is its own protocol.** When invoked from a Discord thread, Phases 0-5 are SKIPPED entirely. The Thread Mode Pipeline replaces them.
- **HH/GH directionality.** HH = additive Hugr time. GH = ghost (solo or hire-and-coordinate counterfactual, larger).
- **State file Seal replaces transcript-grep.** Grepping the transcript for a sentinel produced false positives. `mark-closed.sh` writes a state file verified by session_id match.
- **Parallel session JSONL pick.** When `$CLAUDE_CODE_SESSION_ID` is absent the fact sheet falls back to a most-recent heuristic. If multiple sessions are open, verify the INTENT line matches before proceeding.
- **Phase 1.5 Clarify can silently drop work.** `resolve.sh kill` removes items entirely. Confirm before kill on ambiguous items.
- **Bundled sweep scripts are self-contained in this skill.** `sweep.sh`, `secret-scan.sh`, and `config/` (`sweep-paths.conf`, `sensitivity-patterns.txt`) live under this skill's own `scripts/` and `config/`. The scripts are self-locating — `sweep.sh` derives `CONFIG` and the `secret-scan.sh` call from `${BASH_SOURCE[0]}`, and `secret-scan.sh` derives its patterns file the same way.

## Dependencies

**Required bins:** `bash`, `python3`, `jq` optional (only if your upstream adapters use it).

**Skill-internal scripts (`[skill_dir]/scripts/`):**
- `session-fact-sheet.py` — Phase 0.7 fact sheet extractor
- `adapters/log-leverage.sh` — Phase 3 Step 11 Ghost Hours row writer (upstream or local fallback)
- `adapters/emit-event.sh` — observability emit (upstream or local fallback)
- `adapters/discord-post.sh` — operator notification (upstream or stdout)
- `mark-closed.sh` — Phase 5.3 seal writer
- `thread-close.sh` — Discord thread mode pipeline (deprecated record shape; reference)
- `resolve.sh` — Phase 1.5 absorb/park/kill verbs
- `sweep.sh` + `secret-scan.sh` — bundled sweep worker, self-locating, config in `[skill_dir]/config/`

**Required state paths (defaults; state root overridable via `CLOSING_TIME_STATE`):**
- `~/.claude/projects/<project-dir>/<session-id>.jsonl` — canonical session_id + transcript source <!-- commit-leak-scan: allow (generic Claude Code transcript dir) -->
- `~/.closing-time/state/fact-sheets/` — fact sheet output dir (auto-created)
- `~/.closing-time/memory/YYYY-MM-DD.md` — daily log target (or your own notes system)
- `~/.closing-time/leverage-log.jsonl` — local fallback Ghost Hours log

**Companion skills:**
- `ghost-hours` (the repo root SKILL.md) — taxonomy reference; this protocol's Phase 3 is its measurement step
- `../closing-time-autofill/` — the delegated auto-fill variant
- `../closing-time-fleet/` — the multi-agent stack close

**Optional:**
- Discord bot token (only if using thread mode)
- gitnexus (only for repos with `RUN_GITNEXUS=true` in `config/sweep-paths.conf`)

## Framing

The session-close protocol. Workflow orchestration (capture, clarify, assay, measure, record, seal) paired with the type-aware GH design and mechanical fact-sheet pre-fill. Pollock 2026.

## Observability

Bus emit at protocol completion. Fire-and-forget.

```bash
[skill_dir]/scripts/adapters/emit-event.sh closing-time closing_time_emitted "<session marker>" "<body>" ghost-hours
```

**Lifecycle:**
- `closing_time_emitted` — fact sheet generated, appraisal walkthrough complete. Subject: session marker. Body: `fwc_captured=<bool> drift_logged=<bool> gh_entry_id=<id>`.
