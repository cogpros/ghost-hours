# Closing-Time Scoring Constants — Single Source of Truth

Shared by `closing-time`, `closing-time-autofill`, and `closing-time-fleet`.
Extracted to end copy-paste drift between the variants.
**Rule: no closing-time SKILL.md re-types these values. They cite this file and Read it at
Phase 3 (or Phase 4 for the fleet variant).** Change the values here, nowhere else.

## FW-C Anchor Chart (Felt Weight of Completion, 1–10)

- 1 = Checked a box. Wouldn't remember it happened.
- 3 = Plumbing. Had to happen. No emotional weight.
- 5 = Solid work. Moved things forward. Meaningful.
- 7 = The compound is working. System building on itself.
- 8 = Capability milestone. First time doing something real.
- 10 = New altitude. The trajectory changed.

## Drift States (4)

- **Stayed on intent** — work shipped matches the first message's ask
- **Adjacent** — related but expanded scope
- **Pivoted** — different work than the intent suggested
- **Snowballed** — started small, ended large

Exception: pivots the operator named out loud during the session are direction changes, not drift.

## GH Type Ceilings (sanity check)

Replaces a universal 25x cap. If `gh_mins / hugr_mins` exceeds the ceiling,
surface it ("That's [N]x for [type]. Ceiling is [Y]x. Does that feel right?") — the
operator decides; never enforce.

| Type | Ceiling |
|---|---|
| Speed | 10x HH |
| Restoration | 15x HH |
| Bypass | 50x HH |
| Augmentation | no universal cap (elapsed-with-team frame) |

## GH Counterfactual Frames (Step 5 prompts, by type)

- **Speed:** "If you did this alone, no AI, how long?" (single human person-hours)
- **Restoration:** "If you tried alone now without restored capability, how long including frustration?" (person-hours with pain multiplier)
- **Bypass:** "Your time scoping + briefing + reviewing, plus the freelancer's time and wait between sync calls" (solo + hire-and-coordinate)
- **Augmentation:** "Your time scoping + briefing, plus team-elapsed wall-clock including hiring, sync calls, revisions, business-hours response" (solo + team-elapsed)

## Version

v1.0. Scoring values live only here; the SKILL.md files cite this file.
