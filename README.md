# Oneshot Framework

A standalone framework for running **isolated, single-shot implementation agents** in sandboxed containers on a remote server over SSH.

The human operator drives requirements gathering locally, with a silent scoring agent measuring requirements quality in real time. Once requirements clear a quality bar, the task is dispatched to a sandboxed container on the server, where an agent attempts a one-shot implementation, opens a PR, and **drives it through CI until all required checks pass**. After the PR lands CI-green, a reviewer agent scores it and drafts targeted feedback questions for the human.

Full design spec: [`DESIGN.md`](./DESIGN.md)

## Status

**v0 — scaffolding only.** This repository currently contains:
- Full framework design ([`DESIGN.md`](./DESIGN.md))
- Stub slash commands (`commands/`)
- Stub agent definitions (`agents/`)
- Starter templates (`templates/`)
- Reference documentation (`references/`)
- Sandbox runtime stub (`sandbox/`)

No executable dispatcher, runtime, or agent logic yet — the stubs define the contracts and responsibilities for each component per the design.

## Repository layout

```
oneshot-framework/
├── DESIGN.md              # full framework specification
├── VERSION                # semver
├── README.md              # this file
├── install.sh             # installer stub (TODO)
├── commands/              # slash command definitions
│   ├── new-project.md     # /oneshot:new-project
│   ├── start.md           # /oneshot start
│   ├── status.md          # /oneshot status
│   ├── watch.md           # /oneshot watch
│   ├── logs.md            # /oneshot logs
│   ├── cancel.md          # /oneshot cancel
│   └── iterate.md         # /oneshot iterate
├── agents/                # agent definitions
│   ├── oneshot-discuss.md
│   ├── oneshot-scorer.md
│   ├── oneshot-implementer.md
│   ├── oneshot-reviewer.md
│   └── oneshot-ci-fixer.md
├── templates/             # starter files for projects
│   ├── config.yml
│   ├── project.md
│   └── requirements.md
├── references/            # cross-cutting reference docs
│   └── scoring-model.md
└── sandbox/               # sandbox runtime source
    └── Dockerfile
```

## Key concepts

- **Requirements scorer (silent coach)** — measures requirements quality in real time during discuss; coaches the discuss-agent when progress stalls. See DESIGN §1.
- **Discussion sandbox** — a live remote sandbox the discuss-agent uses during requirements gathering to verify capabilities and enrich context with real data. See DESIGN §2.
- **Dispatch bundle** — sealed requirements + project snapshot + exploration artifacts + sandbox config, shipped to the server. See DESIGN §3.
- **Sandbox runtime** — Docker-based isolated execution with CPU/RAM/GPU limits and skill/MCP carryover. Two modes: discussion (long-lived) and implementation (ephemeral). See DESIGN §4.
- **Progress tracker** — file-based event stream (`status.jsonl` semantic events + compact `heartbeats.jsonl` telemetry) that survives container death. See DESIGN §5.
- **CI Gate** — enforces that "done" means PR open *and* required CI green. Detach-and-reattach pattern with automatic fix sandboxes. See DESIGN §6.
- **PR Reviewer** — scores the CI-green PR on the same dimensions as the requirements scorer, computes calibration delta. See DESIGN §7.
- **Iterate loop** — restart the cycle with an existing PR + review + human feedback as context. See DESIGN §8.

## Command surface

| Command                    | Purpose                                                                  |
|----------------------------|--------------------------------------------------------------------------|
| `/oneshot:new-project`     | Initialize a new Oneshot project; auto-detects and seeds from GSD artifacts |
| `/oneshot start <task>`    | Begin a run — discuss, score, dispatch                                   |
| `/oneshot status [run_id]` | Table of active runs, or detail view for one                             |
| `/oneshot watch <run_id>`  | Live tail of a run's event stream                                        |
| `/oneshot logs <run_id>`   | Stream `agent.log` for debugging                                         |
| `/oneshot cancel <run_id>` | Abort a running agent                                                    |
| `/oneshot iterate <PR>`    | Restart the cycle for an existing PR                                     |

## License

See [`LICENSE`](./LICENSE).
