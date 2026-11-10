# AGENTS.md

Entry point for coding agents. Read the rules before changing files; a skill is implementation guidance, not authorization.

## Read in this order

1. `CLAUDE.md`: project rules, repository layout, platform facts, third-party code rules.
2. `TASKS.md`: section "How to continue (handover)" (orchestration loop, gates, Deck rules), then "Phase 11" at the end (current queue).
3. `DESIGN.md` and `design/NN-*.md`: decisions, cited as `<file> d.<n>`.
4. `.claude/commands/orchestrate.md`: the orchestration rules and brief template, valid for any agent.
5. [Agent workflow](docs/agent-workflow.md): concrete TDD, verification, failure and reporting steps. Then load the relevant skill below and its API contracts.

## Coding skills

| Task | Load this skill |
| --- | --- |
| Add/change an internal game mode, rounds, map objectives | [privatewar-mode](.opencode/skills/privatewar-mode/SKILL.md) |
| Add/change a weapon-base integration or adapter | [privatewar-weapon-adapter](.opencode/skills/privatewar-weapon-adapter/SKILL.md) |
| Add/change a perk, passive stat or owner-local event effect | [privatewar-perk](.opencode/skills/privatewar-perk/SKILL.md) |
| Add/change a Pick X wildcard or slot-rule modifier | [privatewar-wildcard](.opencode/skills/privatewar-wildcard/SKILL.md) |

OpenCode discovers `.opencode/skills/<id>/SKILL.md`; invoke by exact id with the skill tool or `@<id>`.
Other harnesses can read the linked file directly; no duplicated skill copies or harness-specific API guesses are needed.
Read [API index](docs/api/README.md) and [mandatory test map](docs/agent-test-map.md) for the task's seams.
Validate guidance with `nix develop --command bash scripts/check/agent-guides.sh` (also in `make check`).

## Core rules

1. Decided means decided: do not change `design/` without the user's approval; open questions go to the user.
2. English in the repository (code, commits, docs); Russian in chat with the user. Public text is English only.
   Private content, including the local manual checklist listed in `scripts/export/local-only.txt`, must stay outside the public repository and any published tree. Export tooling is optional (see `docs/publishing.md`).
3. TDD with GLuaTest: tests first in `addons/privatewar/lua/tests/privatewar/*.lua`; the cases in `TASKS.md` "Mandatory test cases" are obligatory.
4. Gates before every merge: `nix develop --command make check` and `nix develop --command make test` (with `pipefail`). Lint, type and test tools only through `nix develop --command`; run ordinary git commands directly in your own worktree.
5. Commits: `git commit --signoff`, semantic message, the trailer `Assisted-by: LLM` and nothing else naming a product or model. Never `--no-verify`; never disable a lint or type rule without the user's approval.
6. Develop directly in this canonical repository (`kitsunoff/privatewar`), on feature branches. Never commit or merge locally on `main`; use reviewed PRs, draft by default. Push only with the user's authorization. Show the PR title and body and obtain approval before creating it. Merge only with separate explicit user approval, using `gh pr merge --squash --delete-branch`.
7. Steam Deck: obtain explicit permission and confirmation that it is free before any access; use only the locked `scripts/deck/*.sh`. Never run `cp1.sh` unless asked. Without permission, report game tests skipped and the merge gate incomplete.
8. Licence: GPL-3.0-or-later (`LICENSE`). Vendor third-party code only under a GPL-compatible licence and add its notice to `THIRD_PARTY_NOTICES.md` in the same change (`CLAUDE.md`, "Third-party code").
