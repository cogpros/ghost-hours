---
name: closing-time-fleet
description: 'Discord-wide stack close. Use when the operator says "closing time discord", "close the stack", or "discord fact sheet" — the Discord-native end-of-session protocol that closes an ENTIRE fleet of agents across many channels, not one CLI session. Builds the agent roster, determines liveness by fusing each agent''s auth-heartbeat (authoritative) with its tmux pane — a launch banner is never treated as proof of life, so a banner-up but auth-dead agent reads ZOMBIE, not ALIVE — pulls per-agent work-shipped from the bus, synthesizes cross-agent zombies/divergences, computes a first-cut Ghost Hours timing for the home channel, writes daily memory + a stack-day seal, emits a distinct bus event, and ends by printing the coordinator runtime restart command (context-shed). Run from the coordinator agent''s Discord runtime. NOT FOR: a single CLI session close (use closing-time or closing-time-autofill), a single Discord thread close (that is closing-time thread mode), mid-session checkpoints.'
user-invocable: true
metadata:
  version: "1.0.0"
  license: "Apache-2.0"
  trigger-phrase: "closing time discord"
triggers:
  - "closing time discord"
  - "close out discord"
  - "close the stack"
  - "discord fact sheet"
  - "discord close"
---

# Closing Time Fleet — Agent Instructions

You are running the **Discord-wide stack close** — the Discord-native end-of-session
protocol. One call closes the *entirety* of a Discord agent fleet: many agents across many
channels, not a single session.

This skill exists because `closing-time` and `closing-time-autofill` are
**CLI-session-bound** — they read a CLI session JSONL via `session-fact-sheet.py`. A
Discord runtime has no such JSONL, so those skills grab the wrong session and would log a
**false close**. And Discord isn't one session: it's `1 operator : N agents across M
channels`, often in parallel. This skill reads the stack externally and synthesizes the
cross-agent view a per-agent close can never see.

Run it **from the coordinator agent's Discord runtime** (the one with Discord tools +
filesystem access).

This variant shares `references/scoring-constants.md` and the emit adapter with
`../closing-time/`. Its own helper lives in `[skill_dir]/scripts/`.

## Configuration first

The helper probes a specific fleet runtime shape: tmux panes named `<agent>-discord`, a
JSONL event bus, an auth-heartbeat, and a message-archive SQLite store. **Adapt these
probes to your fleet's runtime.** All identities and paths are config, not code: set them
in `~/.closing-time/fleet.conf` (sourced by the helper) or as env vars. The required ones
for Ghost Hours timing are `FLEET_OPERATOR_USER_ID` (your Discord user id) and
`FLEET_HOME_CHANNEL_ID` (the coordinator's home channel). The full knob list is in the
helper's header comment. Nothing ships hardcoded.

## The single load-bearing rule

**Liveness is VERIFIED against the agent's real artifact — its actual tmux pane — never a
proxy probe — and crucially, the launch banner is NOT that artifact.** This is the entire
reason the skill exists, and getting it backwards is the exact failure it must prevent:
verify against ground truth, never against a proxy that merely correlates with it.

The trap: a Claude Code pane prints its model banner at **launch, before any API call**. A
freshly-relaunched but 401-dead agent shows that banner over an empty prompt. So
**banner-present is at most LAUNCHED, never ALIVE.** The verdict is FUSED: the
**auth-heartbeat is the authority** (it actually probes the token), the pane is a secondary
process signal. A `FAILED` heartbeat can NEVER be upgraded to ALIVE by a banner.

The fused precedence the helper enforces:

| heartbeat | pane | VERDICT |
|---|---|---|
| FAILED | process up (any pane) | **ZOMBIE** — banner does not override a dead token |
| FAILED | no pane / capture-fail | **DOWN** — auth dead, no live process |
| OK/NONE | proven post-launch turn (`⏺`/`⎿`/`◯`) | **ALIVE** — the only path to ALIVE |
| OK/NONE | banner only, no turn | **LAUNCHED** — up, not flagged, but unproven |
| OK/NONE | 401 at line-start in pane tail | **ZOMBIE** — pane proves the auth error |
| OK/NONE | no pane / banner scrolled out | **UNVERIFIED** — never counted alive |

The "ALIVE (turn-proven)" rollup reflects the FUSED verdict, so a dead or merely-launched
agent can't land in the alive count. If the skill reports a dead agent as alive — or counts
a banner-only agent as alive — it has failed at its one job.

## Pacing Rule

Run the phases in sequence. The capture (Phase 1) is mechanical — one helper invocation.
The synthesis (Phase 2) and Ghost Hours (Phase 3) are yours to read and judge. FW-C
(Phase 4) is the only operator-confirmed field; everything else is read off the stack.

## Phase 0: Roster + Mechanical Capture

Run the helper. It is **READ-ONLY and idempotent** — running it never changes state (the
only write is the optional `--emit` telemetry event):

```bash
bash [skill_dir]/scripts/discord-stack-facts.sh --ghost-hours
```

What it does:

1. **Builds the roster** — unions four sources and drops decommissioned agents
   (configured via `FLEET_DECOMMISSIONED`):
   - tmux `*-discord` sessions (the Discord runtimes — strongest live signal)
   - agent workspace dirs (`FLEET_AGENT_DIRS`; each subdirectory names an agent)
   - a gateway-runtime roster command (`FLEET_GATEWAY_LIST_CMD`, if your fleet has one)
   - a channels JSON (`FLEET_CHANNELS_JSON`; home channel ids) + any bus-only agents
     (`FLEET_BUS_ONLY_AGENTS`)
2. **Fused liveness verdict** per agent — the pane is read (`tmux capture-pane -S -`, with
   the 401 check scoped to the current-turn tail after the last `❯` prompt so stray
   scrollback can't false-zombie), classified `BANNER` / `TURN` / `PANE-401` / `QUIET` /
   `NO-PANE` / `UNREACHABLE`; then FUSED with the heartbeat into the final
   `ALIVE` / `LAUNCHED` / `ZOMBIE` / `DOWN` / `UNVERIFIED` verdict per the table above. The
   row shows BOTH the verdict and the raw pane state, each with evidence.
3. **Auth-heartbeat consume** (not reimplement, and it is the AUTHORITY) — reads today's
   `auth-heartbeat:<agent>` `*_auth_failed` events off the bus + the `baseline-expiry` state
   files. The close *consumes* the heartbeat, and the heartbeat outranks the pane banner in
   the fused verdict.
4. **Work shipped today** per agent — counts that agent's real outputs on the bus,
   **deduped to real outputs**: no-op cron ticks (`posted=0`, `filed=0`, `no new events`,
   `0 candidates`, `count=0`) are EXCLUDED and reported separately as idle ticks, so the
   count is throughput not heartbeat noise.
5. **Last-response timestamp + loose ends** per agent — last bot post in the agent's home
   channel (from the message archive, for silent-zombie detection) and any flagged/failed
   items it emitted on the bus today.
6. Emits the **per-agent state table + stack-wide synthesis** to stdout.

Hold the output in context. Do not paraphrase it away — the evidence strings are the proof.

## Phase 1: Per-Agent Read (verify each capture points at evidence)

Read the per-agent table. For each agent confirm the verdict and the evidence behind it:

- `VERDICT` — the FUSED liveness call. ALIVE only if a real post-launch turn was proven AND
  the heartbeat is not FAILED. ZOMBIE/DOWN whenever the heartbeat FAILED, regardless of the
  banner.
- `pane` — the raw process signal (BANNER means launched-but-unproven, not alive).
- `heartbeat` — the auth authority. A FAILED heartbeat is decisive.
- `shipped` — real outputs (idle ticks excluded).
- `last-resp` / `loose-end` — silent-zombie clock and flagged items.

If any source reads `UNREACHABLE` for an agent, **say so for that agent.** One silent
source must never read as "all clean" — that is the false-green failure mode.

## Phase 2: Stack-Wide Synthesis (the "entirety" view)

The helper's synthesis block gives you:

- **ALIVE (turn-proven) count** — only agents with a proven post-launch turn and a
  not-FAILED heartbeat. A banner-only or auth-dead agent is NOT in this count.
- **LAUNCHED / ZOMBIE / DOWN / UNVERIFIED lists** — named explicitly so silence can't read
  as clean.
- **TRUE divergence** — the genuine contradiction: an agent whose pane proved a live
  post-launch turn AND whose heartbeat fired FAILED. **This is the only real divergence.**
  A `NO-PANE` or `QUIET` agent with a FAILED heartbeat is *agreement* that it's down, not
  divergence — the helper does NOT flag those. When a true divergence appears, surface BOTH
  facts and verify by hand.
- **Cross-agent divergence/contradiction** — if two agents reported different root causes
  for the same thing today (e.g. divergent cron diagnoses), surface it.
- **Stack rollup** — what the stack shipped today (sum the deduped `shipped` column) and the
  deduped loose-ends list across agents.

This pass is the reason it's "all of Discord" and not N separate closes. The value is the
cross-agent pattern.

## Phase 3: Ghost Hours (first cut — single-channel home-channel timing)

Timing IS available — do NOT claim it isn't. Two sources: **your message-archive SQLite
store** (`FLEET_MESSAGE_DB`, a `messages` table with `channel_id`, `author_id`,
`created_at`) and the **Discord API** (every message carries an ISO timestamp; reachable
live via the coordinator runtime's `fetch_messages` tool).

The helper's `--ghost-hours` block computes, for **the home channel only**:

- message store **freshness** (latest message timestamp). The archive is a *lagging* store
  synced by cron — **if its freshness date is < today, the timing is stale** and you must
  use the live Discord API path (`fetch_messages` on the home channel) instead. The helper
  prints this caveat; honor it. Do not present stale archive timing as today's.
- per-message **agent-time** (operator message → next agent reply gap, seconds).
- operator/agent message counts for the day.

When the archive is stale, pull the live timing yourself: `fetch_messages` on the home
channel for today, compute the same gaps from the ISO `ts` on each message. Human-time =
gap before each operator message; agent-time = operator-msg → agent-reply gap.

**FW-C stays operator-confirmed** — felt-weight is the operator's, same as every
closing-time variant. HH/GH is *computed from timestamps*, not invented and not deferred.

### v2 TODO — multi-agent parallel attribution (NOT in v1, do not fake)

The real design work is attributing human-time and per-agent agent-time across the
*concurrent* surface — the operator messaging the coordinator while another agent works
elsewhere. Whose human-time when the operator is across several channels? Which agent's
agent-time when N run concurrently? Serial-vs-parallel billable windows (concurrent agent
work is parallel-billable, the CLI "hugr time" concept scaled to N simultaneous agents).
**v1 implements single-channel home-channel timing only.** The cross-agent attribution
model is a marked v2 TODO in both the helper output and here. Do not synthesize a
multi-channel number you cannot derive — say "v1 single-channel only" and stop.

## Phase 4: FW-C (operator-confirmed, the one human field)

Ask the operator, via Discord `reply`, for the stack-day felt-weight:

> Closing the Discord stack for <date>. FW-C 1-10 for the day? Optional one-line note.

Anchor chart: use the FW-C 1–10 anchors from
`../closing-time/references/scoring-constants.md` (single source for all closing-time
scoring values — Read it before asking). If FW-C ≥ 5, capture their verbatim note — their
actual words, never paraphrased.

If the operator is asleep / has delegated the whole close ("close it out yourself"), you
MAY estimate FW-C, but you MUST tag it `[agent-estimated]` in the outputs and the seal —
same honesty rule as `closing-time-autofill`. The dataset must be able to tell an
operator-confirmed FW-C from an agent estimate.

## Phase 5: Outputs

1. **Per-agent state table + stack summary** — the close report. Post it to the home
   channel via `reply` (use headings / the monospace table, not a bold-text wall).
2. **Daily memory append** — append a `## Discord Stack Close` section to your daily notes
   file (default `~/.closing-time/memory/YYYY-MM-DD.md`; today's date; note cross-midnight
   if it applies). Include the roster snapshot, zombies, divergences, stack rollup, FW-C,
   and the verbatim note. Do NOT overwrite existing sections.
3. **Loose-ends board** — if you keep one, update it with stack state + the deduped
   loose-ends list, with the single next action pinned.
4. **Stack-day seal** — write a closure marker keyed to the **Discord stack + date**, NOT a
   CLI session id:
   ```bash
   STATE_ROOT="${CLOSING_TIME_STATE:-$HOME/.closing-time/state}"
   mkdir -p "$STATE_ROOT/closing-time-fleet"
   SEAL_KEY="discord-stack-$(date +%Y-%m-%d)"
   printf '{"sealed_at":"%s","key":"%s","fwc":"%s"}\n' \
     "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SEAL_KEY" "<fwc-or-agent-estimated>" \
     > "$STATE_ROOT/closing-time-fleet/$SEAL_KEY".json
   ```
   One seal per day for the whole stack (a stack-umbrella seal, not per-agent). Re-running
   the close the same day overwrites the same key idempotently.
5. **Bus emit** — the distinct event type so downstream filters it from CLI closes:
   ```bash
   ../closing-time/scripts/adapters/emit-event.sh closing-time-fleet \
     closing_time_fleet_emitted "discord-stack $(date +%Y-%m-%d)" \
     "alive=<n>/<N> launched=<list> zombie=<list> down=<list> diverge=<list> fwc=<v> gh_source=<archive|discord-api>" \
     ghost-hours
   ```
   (The helper's `--emit` writes a *lighter* `discord_stack_facts_generated` telemetry event
   when the fact sheet is generated; this `closing_time_fleet_emitted` is the
   protocol-completion seal event. They are distinct on purpose.)

## Phase 6: Context-Shed

Sealing the *work* is not the same as shedding the *context*. The coordinator's Discord
runtime is **persistent** — sealing the stack-day does not clear the loaded context; the
runtime keeps running with everything it has accreted. An agent **cannot restart its own
runtime mid-conversation** — that is an operator/infra action.

So the close ends by **printing the exact restart command for your runtime supervisor**
(and explaining what it does) so the operator can shed the context. Example for a macOS
launchd-supervised runtime — substitute your own service label and supervisor:

```
Stack sealed. To shed the coordinator's loaded context, restart the runtime:

  launchctl kickstart -k gui/$(id -u)/com.example.coordinator-discord

This kills and relaunches the coordinator process fresh (KeepAlive / a watchdog
auto-relaunch makes it safe). Without this, the "closed" runtime keeps accreting
context indefinitely.
```

Print it. Do NOT run it yourself — you cannot restart the runtime you are running inside.

## Honesty Guardrails

1. **Banner ≠ alive; heartbeat is the authority.** The launch banner prints before any API
   call, so banner-present is LAUNCHED at most. ALIVE requires a proven post-launch turn AND
   a not-FAILED heartbeat. A FAILED heartbeat is decisive — never override it with a banner.
2. **Every captured fact names its evidence.** The table shows the pane state + line, the
   bus event types, the heartbeat subject. If you can't point at evidence, you didn't
   capture it.
3. **GH computed, not invented.** Timing comes from archive/Discord-API timestamps. FW-C
   is operator-confirmed (or tagged `[agent-estimated]`). Never fabricate a GH number.
4. **Silence ≠ clean.** If a source is unreachable for an agent, say so *for that agent*.
   One silent agent must never let the stack read as all-green (the false-green failure).
5. **TRUE divergence only.** The genuine contradiction is pane-proven-TURN AND
   heartbeat-FAILED. No-pane / quiet + dead-heartbeat is agreement it's down, not
   divergence — do not flag it as such.
6. **No-op ticks are not work.** Shipped counts exclude idle cron ticks; report the count
   and the excluded-tick number, never the raw cron-completion total.

## Known Limitations & Gotchas

- **Self-pane reads UNVERIFIED, by design.** When run from inside the coordinator runtime,
  the coordinator's *own* pane typically reads `QUIET` → verdict `UNVERIFIED`, because its
  startup banner has scrolled out and the agent-loop chrome occupies the pane. The helper
  does NOT falsely claim ALIVE for itself — verify the coordinator's own liveness by the
  fact that it is the one running this skill. UNVERIFIED here is honest, not a bug.
- **TURN detection is heuristic.** ALIVE requires a `⏺`/`⎿`/`◯` turn marker in scrollback.
  If a genuinely-live agent's markers have scrolled out, it reads `LAUNCHED`/`UNVERIFIED`,
  not ALIVE — a deliberate false-negative bias (under-claim liveness rather than over-claim
  it). The cost is some live agents read LAUNCHED; the benefit is no dead agent reads ALIVE.
- **The message archive is a lagging store.** Always check the freshness line; if it's
  < today, use the live Discord API (`fetch_messages`) for GH timing.
- **Private channels the coordinator can't read.** The coordinator may hit
  `Unknown Channel` on some private channels. Agent state therefore comes primarily from
  the **bus + filesystem (panes/logs/heartbeat)**; Discord transcripts are the layer only
  for channels the coordinator *can* read. The helper does not depend on reading private
  channels.
- **Multi-agent GH attribution is v2.** v1 is single-channel home-channel timing only (see
  Phase 3).
- **Pane/heartbeat divergence is expected after a restart.** A freshly-restarted agent pane
  reads ALIVE while a stale `*_auth_failed` heartbeat event from earlier the same day still
  matches. The helper flags the divergence; read the heartbeat timestamp vs. the tmux
  session creation time before treating it as a live problem.
- **Gateway-runtime agents have no pane.** Agents running under a gateway process (not a
  `*-discord` tmux session) show `NO-PANE` — liveness for them comes from the heartbeat +
  bus, not a pane. That is correct; `NO-PANE` is not a failure state.

## Dependencies

**Required bins:** `bash`, `tmux`, `python3`, `sqlite3` (for archive timing), `jq`
(optional, for channels JSON).

**Required paths / sources (all configurable — see the helper's header):**
- `FLEET_BUS_FILE` — per-agent work + auth-heartbeat events (JSONL)
- `FLEET_CHANNELS_JSON` — agent home channel ids (optional)
- `FLEET_HEARTBEAT_STATE` — heartbeat baseline-expiry state (optional)
- `FLEET_MESSAGE_DB` — message timestamps for Ghost Hours (`messages` table; optional)
- `FLEET_GATEWAY_LIST_CMD` — gateway roster command (optional)
- tmux sessions `<agent>-discord` — pane liveness ground truth
- `../closing-time/scripts/adapters/emit-event.sh` — bus writer (local fallback built in)

**Bundled:** `scripts/discord-stack-facts.sh` (this skill's own dir; self-contained,
read-only except `--emit`).

**Companion skills:**
- `../closing-time/` — the CLI-session default (run this for a CLI session, not Discord)
- `../closing-time-autofill/` — the CLI auto-fill variant
- `../closing-time/` thread mode — for a single Discord *thread* close

## Framing

The Discord-native, stack-wide member of the closing-time family. `closing-time` closes a
CLI session; `closing-time-autofill` auto-fills it; the thread-mode pipeline closes one
thread. This skill closes the *entire Discord fleet* in one call, reading the stack
externally (no agent grades itself — external is more honest) and surfacing the
cross-agent pattern. Built after a CLI-session-bound close grabbed the wrong session on
Discord and a proxy-liveness bug logged a zombie as alive. Pollock 2026.

## Observability

Bus emit at protocol completion (distinct from the helper's lighter telemetry event):

```bash
../closing-time/scripts/adapters/emit-event.sh closing-time-fleet \
  closing_time_fleet_emitted "<stack-day marker>" "<rollup body>" ghost-hours
```

- `discord_stack_facts_generated` — helper ran, fact sheet produced (telemetry, via `--emit`).
- `closing_time_fleet_emitted` — full protocol complete, stack-day sealed.

Both event types are distinct from `closing_time_emitted` / `closing_time_autofill_emitted`
so downstream consumers filter Discord stack closes from CLI session closes.
