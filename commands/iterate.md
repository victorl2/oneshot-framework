---
name: oneshot:iterate
description: Restart the Oneshot cycle for an existing PR with review + feedback as context
argument-hint: "<pr_url_or_number>"
allowed-tools:
  - Read
  - Bash
  - Write
  - Task
  - AskUserQuestion
---

<objective>
Restart the Oneshot cycle for an existing PR. Unlike `/oneshot start`, iterate re-enters the discuss loop with the PR diff, the reviewer's scores and questions, and the human's answers to those questions all attached as context. On the next pass, the agent updates the **same PR branch** rather than opening a new one.

**When to use:**
- The reviewer scored the PR below threshold on some dimension.
- The human round surfaced gaps or concerns that need fixing.
- The requirements need refinement and a second implementation pass.

**When NOT to use:**
- The PR is already merged.
- The CI is currently failing (that's the CI Gate's fix loop, not iterate).
- The fix is a one-line trivial change (just push it manually).
</objective>

<execution_context>
@~/.claude/oneshot/references/scoring-model.md
@~/.claude/oneshot/references/discussion-sandbox.md
</execution_context>

<process>
See DESIGN.md §8 (Iterate Loop).

**NOT YET IMPLEMENTED** — this stub documents the intended behavior.

1. Resolve the PR URL or number to a local `runs/{timestamp}/` directory via `pr_opened` events.
2. Gather context: PR diff, `pr-review.md`, `human-feedback.md`, original `requirements.md`.
3. Enter the discuss loop with all of the above attached as prior context.
4. The scorer starts from the existing requirements as baseline, not from scratch.
5. On re-seal, dispatch a new run — but the agent pushes commits to the same branch, updating the existing PR.
6. Re-run the CI Gate and reviewer on the updated PR.
</process>
