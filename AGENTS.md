# AGENTS.md

Entry point for Codex and other coding agents. The full rules live in the files below; this page only points to them.

## Read in this order

1. `CLAUDE.md`: project rules, repository layout, platform facts, third-party code rules.
2. `TASKS.md`: section "How to continue (handover)" (orchestration loop, gates, Deck rules), then "Phase 11" at the end (current queue).
3. `DESIGN.md` and `design/NN-*.md`: decisions, cited as `<file> d.<n>`.
4. `.claude/commands/orchestrate.md`: the orchestration rules and brief template, valid for any agent.

## Core rules

1. Decided means decided: do not change `design/` without the user's approval; open questions go to the user.
2. English in the repository (code, commits, docs); Russian in chat with the user. Public text is English only.
   The local manual checklist (a `docs/` file listed in `scripts/export/local-only.txt`) is local only and never published; publish only through `scripts/export/public.sh` (see `docs/publishing.md`).
3. TDD with GLuaTest: tests first in `addons/privatewar/lua/tests/privatewar/*.lua`; the cases in `TASKS.md` "Mandatory test cases" are obligatory.
4. Gates before every merge: `nix develop --command make check` and `nix develop --command make test` (with `pipefail`). Tools only through `nix develop --command`.
5. Commits: `git commit --signoff`, semantic message, the trailer `Assisted-by: LLM` and nothing else naming a product or model. Never `--no-verify`; never disable a lint or type rule without the user's approval.
6. Feature branches and local `--no-ff --signoff` merges; no remote, no pushes. Never commit on `main`.
7. Steam Deck: only through the locked `scripts/deck/*.sh`; never run `cp1.sh` unless asked.
8. Licence: GPL-3.0-or-later (`LICENSE`). Vendor third-party code only under a GPL-compatible licence and add its notice to `THIRD_PARTY_NOTICES.md` in the same change (`CLAUDE.md`, "Third-party code").
