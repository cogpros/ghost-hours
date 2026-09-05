# Collection Protocols

These are the protocols that generate Ghost Hours data. The root skill
(`../SKILL.md`) defines the taxonomy and the log format. The skills in this
directory are how entries actually get produced, day after day: a session-close
ritual that ends with the Ghost Hours measurement built in.

One term used throughout: **hugr** — the human+agent pair, treated as a single
working unit. HH (Hugr Hours) is the time that pair spent; GH (Ghost Hours) is
the counterfactual solo time.

## The pipeline

```
  CLI session or Buzz working day
        |
        v
  capture evidence -> clarify work -> appraise Ghost Hours
        |
        v
  canonical Ghost Hours writer -> verified measurement
        |
        v
  local report / fact sheet -> seal -> completion receipt
```

CLI facts binds a native transcript. Buzz facts captures a relay window through
read-only access. Both use the bundled Ghost Hours writer and verify the saved
row before sealing. The interactive base protocol retains its configurable
logging adapter; an argument-only fallback is a pending write, not a canonical
measurement receipt.

Every measurement records who supplied felt weight and preserves the agent's
separate blind estimate.

## The variants

| Skill | When | Who fills the operator fields |
|---|---|---|
| [`closing-time/`](closing-time/SKILL.md) | Default. Operator present at session end. | Operator, one question at a time |
| [`closing-time-cli-facts/`](closing-time-cli-facts/SKILL.md) | Operator delegates the whole close ("close out while I sleep"). | The agent, with every estimate honesty-tagged (`fwc_source`, `operator-override-fill`) |
| [`closing-time-buzz-facts/`](closing-time-buzz-facts/SKILL.md) | Close the Buzz working day across channels, threads, and agents. | Operator-confirmed, or agent-estimated only on explicit delegation. |

`closing-time-autofill` remains a forwarding alias. The delegated CLI variant
supports Claude Code, Codex, and Grok Build, with Python 3.10+ for its helpers.

The CLI variants share `closing-time/scripts/` and `closing-time/config/`.
All variants reuse the root Ghost Hours writer and
`closing-time/references/scoring-constants.md`.
The CLI variant ships no scripts of its own; its shared helper binds an exact
session and writes through the bundled Ghost Hours writer, requiring a durable
measurement receipt before sealing. Buzz facts adds a read-only relay collector
and a local measurement/seal helper.
The retired Discord fleet skill and its posting/thread helpers are no longer shipped.

## What's configurable

- **Seal/binding state** defaults to `~/.closing-time/state/` (override with `CLOSING_TIME_STATE`).
- **Adapters** (`closing-time/scripts/adapters/`) route log writes, bus events,
  and notifications to your stack via `CLOSING_TIME_UPSTREAM_DIR`, with local
  JSONL fallbacks so the protocol runs identically on a bare machine.
- **Sweep whitelist** and **secret-scan patterns** live in
  `closing-time/config/` — both ship as examples; populate your own.
- **Buzz** uses an already-configured read-only CLI identity, `BUZZ_RELAY_URL`,
  and `BUZZ_OPERATOR_NAME`. Its state lives under the state root in
  `closing-time-buzz/`; work logs can be supplied with `BUZZ_WORK_LOGS_DIR`.

## Why publish the collection layer

The root skill defines what a Ghost Hours entry is. These protocols answer the
harder question: how do you get a real one logged at the end of every session
without the measurement contaminating itself? The answers are procedural —
silent agent scoring, one question per message, seal-before-surfacing, verbatim
notes, honesty tags on delegated fills — and they are the part most worth
copying. Pollock 2026.
