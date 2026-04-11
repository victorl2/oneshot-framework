# Scoring Model

The conceptual core of Oneshot's calibration loop. Used by both the Requirements Scorer (pre-dispatch, during discuss) and the PR Reviewer (post-dispatch, after CI green).

See DESIGN.md §"Scoring Model" for the canonical specification.

---

## Dimensions

Five dimensions for requirements scoring, four for PR review (ambiguity doesn't apply post-implementation).

| Dimension        | Requirements question                                 | PR review question                       |
|------------------|--------------------------------------------------------|--------------------------------------------|
| **Correctness**  | Is what's being asked for clearly specified?         | Does the code do what was asked?           |
| **Quality**      | Are standards / conventions / constraints pinned down? | Does the code meet them?               |
| **Completeness** | Are all cases (edge, error, empty) spelled out?       | Are all cases handled?                    |
| **Robustness**   | Are failure modes and invariants called out?         | Does it hold up under them?               |
| **Ambiguity**    | How many unresolved interpretations remain?          | *(requirements only — N/A at review time)* |

**Why same dimensions both ways:** the delta between predicted (requirements) and actual (PR review) is the signal that makes calibration more than theater. If dimensions don't match, you can't compute a delta.

## Display format

Per turn, during discuss, scores are shown to the human with turn-over-turn deltas:

```
correctness 72 (+3) · quality 80 (±0) · completeness 55 (+8)
robustness 61 (+1) · ambiguity 70 (-2) → overall 68 (+2)
```

**The delta is the whole point** — it tells the human whether their last answer moved the needle. The per-dimension view tells them *where* to aim next.

## Thresholds (v1 starting points)

Defaults — calibrate over time from `calibration.md`.

| Threshold            | Default | Effect                                                             |
|----------------------|---------|--------------------------------------------------------------------|
| Soft gate (overall)  | 75      | Dispatch without friction at or above this                        |
| Below soft gate      | —       | Dispatch requires explicit `--force`                              |
| Plateau window       | 3 turns | Turns over which plateau is detected                              |
| Plateau delta        | 5       | Minimum overall movement across window — less triggers coaching |

All configurable in `config.yml`.

## Calibration file format

`calibration.md` is append-only. Each entry:

```markdown
## run-2026-04-10-143022
- Predicted: correctness 82, quality 78, completeness 80, robustness 75, ambiguity 85 → 80
- Actual:    correctness 64, quality 81, completeness 58, robustness 70           → 68
- Delta:     correctness -18, quality +3, completeness -22, robustness -5 → -12
- Root cause: requirements pinned down happy path but left error semantics vague.
  Scorer flagged ambiguity at turn 4, discuss asked, human gave "handle it
  sensibly" — shipped anyway.
- Pattern tag: #vague-error-contracts
```

The scorer reads recent entries as few-shot examples. Pattern tags accumulate over time into the scorer's understanding of *this project's* specific failure modes.

## Cold start

Early in project life, `calibration.md` is empty. The scorer coaches from general principles only. This degrades gracefully — less sharp, not broken. It sharpens automatically as runs accumulate, no bootstrap dataset required.

## Open signals not yet in the tuple

Two signals are candidates for inclusion in future calibration tuples (see DESIGN.md open questions):

- **Fix attempts** — a run that passed CI on the first try is meaningfully different from one that needed 3 fix cycles, even if both end at `completed`. Likely worth a column.
- **Subagent token ratio** — the ratio of subagent tokens to total tokens is probably a quality signal. Runs with healthy delegation probably land better.

Both would need to be validated against real run data before being promoted from "open question" to "required column."
