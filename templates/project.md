# {Project Name}

Persistent project knowledge that the Requirements Scorer reads during discuss to contextualize its scoring and coaching. Seeded by `/oneshot:new-project` (auto-populated from GSD artifacts when present, otherwise blank) and updated as patterns emerge.

See DESIGN.md §"Global State Directory → project.md".

---

## Tech stack

<!--
Languages, frameworks, build tools, runtime. One-liner per item.
Example:
- Language: Rust (edition 2021)
- Build: Cargo workspaces
- Tests: cargo test + insta snapshots
- CI: GitHub Actions
-->

(to be filled)

## Architectural conventions

<!--
Patterns that are non-negotiable in this codebase. Layering rules, naming
conventions, forbidden patterns. The scorer uses these to flag requirements
that would violate project norms.

Example:
- All public APIs live in `src/public/`; internal modules are private.
- Error types use `thiserror`; never `Box<dyn Error>`.
- No `unwrap()` in non-test code.
-->

(to be filled)

## Common gotchas

<!--
Things that have bitten us before. Worth their weight in gold for the scorer
and the implementation agent.

Example:
- The config loader caches aggressively; tests need to force a reset.
- The integration test suite requires a live Postgres; skip on CI without it.
-->

(to be filled)

## Known-difficult areas

<!--
Subsystems where requirements quality matters extra because the implementation
is tricky. The scorer uses these to be harder on specifications that touch
these areas.

Example:
- The tokenizer — precision matters, edge cases are many.
- The scheduler — concurrency invariants are subtle.
-->

(to be filled)

## Coding standards

<!--
Linting, formatting, testing expectations.

Example:
- rustfmt enforced in CI
- clippy with `-D warnings` in CI
- Minimum coverage: 80% on new modules
-->

(to be filled)

## Historical failure patterns

<!--
Patterns the scorer's calibration has identified over time. This section is
updated automatically as calibration.md accumulates entries.

Example:
- #vague-error-contracts — requirements that don't pin down error semantics
  have cost an average of 18 points on actual correctness.
-->

(to be filled — will accumulate from calibration.md)
