# Freestyle Reproduction: Testing Kasparov's Freestyle Finding in Knowledge Work

**Status: pre-registered, not yet run.** Designed 2026-07-10; volunteer-arm protocol added 2026-07-18. This document is published before any task runs; the predictions below are fixed as of the publication commit's date.

**One-line claim under test:** "Weak human + machine + better process was superior to … a strong human + machine + inferior process" (Kasparov, 2010, on the 2005 Playchess.com freestyle tournament). Reproduced outside chess, in real knowledge work, with the process variable being the operator's cognitive-prosthetic architecture ("hugr": the human-AI pair as the working unit).

## Hypothesis

H1: An operator with a clinically documented cognitive deficit profile (neuropsychological assessment on file; executive function, working memory, prospective memory), paired with an LLM through the full prosthetic binding (persistent memory, skills, session protocols, ambient triggering), produces task outcomes superior or equal to a high-achieving operator paired with the same model through a bare chat interface.

H0: The bare pair matches or beats the prosthetic pair. The result must be allowed to land either way; a one-way bet is theatre. A null or reversed result publishes with the same prominence.

## Design

Between-pairs comparison. Two systems, one task battery, blind grading.

| | System A (prosthetic pair) | System B (bare pair) |
|---|---|---|
| Human | The author (documented deficit profile; the "weak human" is clinically measured, not assumed) | Consenting high-achieving volunteer, no known deficits |
| Machine | Same model as B | Same model as A. **Non-negotiable; unequal models void the run** |
| Process | Full prosthetic stack | Bare chat under the written gate below |

### The bare-chat gate (written config, not plan-tier assumption)

System B's "plain chat" is defined by configuration, verified at task time, not inferred from subscription tier (feature availability by tier changes and would silently change the arm):

- Memory features OFF
- No projects / workspaces
- No custom instructions or styles
- Fresh conversation per task
- A funded seat on the same model System A uses, so model parity is a receipt and rate limits never fragment System B's sessions into an unregistered process difference

### The adaptation clause (pre-registered)

System B's operator is gated on tooling, **never on learning**. Across the battery the volunteer is expected to improvise and improve their own prompting process, and this is treated as data, not contamination. The claim under test is therefore the strong form: an engineered, persistent process versus the best process a high-achieving human can improvise in real time against the same model. The volunteer's self-described process notes per task are collected as a qualitative record of that improvisation.

### Volunteer status and disclosure

A candidate volunteer has been identified (professional background in psychology and teaching); consent is pending and precedes any task. The volunteer is personally known to the author — selection is convenient and disclosed, not blind. Grading is blind; selection does not need to be for a demonstration of this size. The volunteer receives a per-completed-task honorarium and may elect to be named or remain anonymous in the publication.

## Task battery

- 10 to 20 tasks, real work, not puzzles. Mixed classes: research + synthesis, multi-step build, document production, planning under constraints, cold-start recovery on a half-finished artifact (the class the prosthetic stack should win hardest).
- Each task specified as a brief with a deliverable and a time box. Same brief verbatim to both systems.
- Tasks drawn/adapted from actual backlog items so ecological validity holds, then genericized so System B's participant can run them.
- Task order randomized to mitigate learning effects.

## Measurement

1. **Primary: blind-graded outcomes.** Graders who do not know which system produced which deliverable score each on a fixed rubric (completeness, correctness, usability of the artifact). This is the scoreboard chess had for free.
2. **Instrumented layer: Ghost Hours on both sides.** Same schema, same protocol, `participant_id` per the export schema. Both participants log `human_mins`, `gh_mins` (shared estimation protocol or external estimation; self-estimates are NOT comparable across participants), type/subtype, FW-C.
3. **Condition tagging:** every session tagged `condition:hugr` / `condition:bare` in the GH `tags` array (see the condition-tagging convention in SPEC.md). No schema change required.

## Predictions (pre-registered before any task runs)

- P1 (the law): A ≥ B on blind-graded outcomes, despite the documented deficit asymmetry.
- P2: A's advantage concentrates in cold-start recovery and multi-session continuity tasks; B may match or beat A on single-shot, self-contained tasks. (The binding is memory + initiation; tasks that don't need it shouldn't show the effect. If A wins everything including tasks the process can't touch, suspect confound, not triumph.)
- P3: A's GH data shows unlock-class sessions; B's shows only speed-class. The taxonomy separates the pairs even where raw outcomes tie.
- P4 (adaptation): B's per-task outcomes improve across the battery as the volunteer's improvised process matures; A's stay flat (the engineered process is already built). If B's curve closes the gap entirely, that is the finding.

## Known confounds and limits (stated up front)

- n = 2 humans. This is a demonstration in the Kasparov sense (his data point was one tournament), not a population claim.
- No blinding of participants; only grading is blind.
- Skill-with-AI is a hidden variable: the author has years of pair practice; the volunteer starts fresh. This partially IS the process variable (the amateurs' "coaching" skill was Kasparov's point) but is named here, not hidden. The adaptation clause turns part of it into a measured curve.
- The volunteer is personally known to the author (disclosed above).
- Learning effects across the battery; mitigated by task-order randomization and measured by P4.
- Grader rubric quality bounds everything. Rubric publishes to this directory before task one.

## Blockers to first task

1. Volunteer consent (candidate identified; ask in progress)
2. Task battery not yet written (publishes here before use)
3. Grading rubric not yet written (publishes here before use)
