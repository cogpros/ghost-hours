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
  work session ends
        |
        v
  closing-time  (or a variant)
        |
        |  Phase 0-2: silent agent FW-C, background repo sweep,
        |             fact-sheet extraction, capture, clarify, assay
        v
  Phase 3: Measure  <-- this IS the Ghost Hours measurement
        |             (type, subtype, GH estimate, backlog, FW-C, note)
        v
  scripts/adapters/log-leverage.sh
        |
        |-- upstream writer, if you have one (CLOSING_TIME_UPSTREAM_DIR)
        '-- local fallback: ~/.closing-time/leverage-log.jsonl
        |
        v
  rows in the ghost-hours log --> /ghost-hours report, retro, share
        |
        v
  Phase 4-5: record creative work, push gate, seal
```

Every close produces exactly one thing the root framework cares about: a
Ghost Hours row with honest provenance (who scored the felt weight, and
whether the agent's blind estimate stayed blind).

## The three variants

| Skill | When | Who fills the operator fields |
|---|---|---|
| [`closing-time/`](closing-time/SKILL.md) | Default. Operator present at session end. | Operator, one question at a time |
| [`closing-time-autofill/`](closing-time-autofill/SKILL.md) | Operator delegates the whole close ("close out while I sleep"). | The agent, with every estimate honesty-tagged (`fwc_source`, `operator-override-fill`) |
| [`closing-time-fleet/`](closing-time-fleet/SKILL.md) | A Discord fleet of agents needs closing as one unit, not N sessions. | Read off the stack; FW-C stays operator-confirmed |

The three variants share one implementation: `closing-time/scripts/`,
`closing-time/config/`, and `closing-time/references/scoring-constants.md`.
The autofill variant ships no scripts of its own. The fleet variant adds one
helper (`discord-stack-facts.sh`) and reuses the rest.

## What's configurable

- **State** defaults to `~/.closing-time/` (override root with `CLOSING_TIME_STATE`).
- **Adapters** (`closing-time/scripts/adapters/`) route log writes, bus events,
  and notifications to your stack via `CLOSING_TIME_UPSTREAM_DIR`, with local
  JSONL fallbacks so the protocol runs identically on a bare machine.
- **Sweep whitelist** and **secret-scan patterns** live in
  `closing-time/config/` — both ship as examples; populate your own.
- **Fleet identities** (operator id, home channel, agent sources) live in
  `~/.closing-time/fleet.conf` — nothing is hardcoded.

## Why publish the collection layer

The root skill defines what a Ghost Hours entry is. These protocols answer the
harder question: how do you get a real one logged at the end of every session
without the measurement contaminating itself? The answers are procedural —
silent agent scoring, one question per message, seal-before-surfacing, verbatim
notes, honesty tags on delegated fills — and they are the part most worth
copying. Pollock 2026.
