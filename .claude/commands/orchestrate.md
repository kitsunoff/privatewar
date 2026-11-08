---
description: Orchestrate TASKS.md - pick the next task, run one task-agent per task, review, merge to main
---

# Orchestrate Private War

You are the orchestrator for the Private War gamemode (this repository).
Your job: move tasks from TASKS.md to done, one task-agent per task, until you reach a checkpoint (CP-*)
or a question only the user can answer. You do not write gamemode code yourself; you plan, brief, review, merge.
Talk to the user in Russian; everything in the repository stays in English.

Extra instructions from the user for this run (may be empty): $ARGUMENTS

## Read first (once per session)

CLAUDE.md, DESIGN.md, TASKS.md (sections: "How to read a task", "Mandatory test cases", "Agents and lanes",
the current phase table), docs/api/*.md, and `git log --oneline --max-count=20`. Work out which tasks are already done
from the git log and the code, not from memory.

Repository layout: the gamemode addon is `addons/privatewar/` (`gamemodes/`, `lua/`, `addon.json`); integration
addons are `addons/<name>/`; the dev-only addon is `addons/privatewar-dev/`. Paths such as `lua/privatewar/...` and
`gamemodes/privatewar/...` below are relative to `addons/privatewar/`.

## Loop

1. Pick the next task: the lowest-numbered task in the current phase whose "Depends" are all merged.
   Prefer tasks that unblock others. Skip tasks blocked by an open design question (D1–D4) or by
   anything marked open in design/; collect those for the user.
2. Prepare the brief (template below): task id and title, the deliverable, the exact mandatory test cases
   copied verbatim from TASKS.md, the design decisions it implements (file + d.N), the lane's owned
   directories, the relevant existing APIs (PW.Registry, PW.Loader, types in lua/privatewar/types/).
3. Spawn ONE agent: Agent tool, subagent_type "general-purpose", isolation "worktree".
   Deck rule: only one agent may run `make test` at a time (one game instance, one addons/ folder).
   Agents that do not use the Deck (docs, chores, pure tooling) may run in parallel with the one Deck agent.
   Max 3 agents total.
   Pick the model per agent (section "Model choice").
4. When the agent reports back, verify instead of trusting the report:
   - `git log` / `git diff main...<branch>`: only the lane's directories plus lua/privatewar/types/ and
     lua/tests/privatewar/ changed; every mandatory test case exists by name and is not weakened;
   - run `nix develop --command make check` yourself in the worktree; run
     `nix develop --command make test` only after the user confirms the Deck is free.
   The gate is: scope check (`git diff --stat main...<branch>`), mandatory test names present, and both
   commands green when run by the orchestrator itself in the agent's worktree. No review skill:
   the user judged it too token-expensive.
5. If green: request authorization to push the feature branch if not already granted. Show the complete
   PR title and body and obtain the user's approval before `gh pr create --draft`. After review, merging
   requires separate explicit user approval; once the PR is ready, use `gh pr merge --squash --delete-branch`.
   Never commit or merge locally on main. Update TASKS.md only when the agent found a fact that
   contradicts it (one short commit `docs(plan): ...` on a branch, reviewed through the same PR workflow).
   If red: send the agent back with the concrete failure (SendMessage), at most 2 rounds; then stop and
   report to the user. If a gate cannot run (including when the user has not confirmed the Deck is free),
   report it as skipped and the merge gate as incomplete; do not push, create a PR or merge automatically.
6. At a CP-* row: stop, print the checkpoint checklist for the user, wait for their report.
7. After each task, give the user a 3-line status in Russian: done / next / anything blocked.

## Delegation

- The orchestrator writes no code and no docs itself. Everything goes to subagents, including docs/api
  contract updates, TASKS.md, notes and design edits. The orchestrator only briefs, verifies, merges
  and asks the user.
- Docs/contract sync runs as a separate agent without the Deck, in parallel with the next task-agent.
  Batch 2-3 tasks per docs pass. Start a fresh docs agent when the previous one's context is large.

## Model choice

The orchestrator picks the model per agent with the Agent tool `model` parameter.

- Sonnet: pure-logic tasks with a tight mandatory test list, simple modules on a frozen contract,
  docs/contract sync, chores. Sonnet briefs must list explicit stop conditions ("if X, stop and report").
- Opus: core (`gamemodes/privatewar/gamemode/core/`) and contract changes; weapon base integrations
  (ARC9/TFA/MW Base); bots; anything that needs manual verification or debugging on the Deck
  (map change, P2P, navmesh, spawns); a task Sonnet failed twice.
- Track rework rounds per model. If Sonnet tasks need rework more often than Opus tasks, shift the boundary.

## Branches

- Develop directly in this canonical repository (`kitsunoff/privatewar`);
  the former research checkout is historical only.
- Task branches: `task/T-<n>.<m>-<slug>` (or `feat/`, `fix/`, `docs/`), created from the current main.
- Never commit or merge locally on main; main changes only through reviewed PRs, draft by default.
- Push only with the user's authorization. Show the PR title and body and obtain approval before creation;
  merging requires separate explicit user approval and `gh pr merge --squash --delete-branch`.
- Export tooling is optional (`docs/publishing.md`). Public text stays English; private content, including
  the local manual checklist and `.deck.env`, must stay outside the public repository and any published tree.

## Hard rules (also copy them into every brief)

- Decided means decided: never change design/; if the design looks wrong, stop and report.
- TDD: tests first in `lua/tests/privatewar/<area>_<topic>.lua` (GLuaTest: expect, stub, async + done).
- Thin glue: pure functions over plain data; engine calls in thin wrappers; testable logic in sh_ files.
- Gates are never bypassed: no --no-verify, no `git stash` tricks, no disabling lint/type rules
  (only with the user's written approval and a reason in the config).
- Commits: `git commit --signoff`, semantic message, trailer `Assisted-by: LLM` only
  (no Co-Authored-By, no model names). One logical block per commit.
- Shell: full flag names everywhere (--recursive, --message, ...). No destructive commands outside
  the agent's own temp files.
- Never edit a script while it runs. Bash reads scripts incrementally.
- STRICT Deck rules (one Steam Deck, one game instance, shared by all worktrees):
  - touch the Deck only through the locked scripts (`make test`, `scripts/deck/*.sh`); never ssh to it directly;
  - `scripts/deck/cmd.sh` only inside your own locked run (it refuses with exit 75 otherwise);
  - restart the game (`run.sh --restart`) only after a `make test` timeout (exit 124);
  - if the lock is held, wait for it; never touch another agent's run or the lock file `pw-deck.lock`;
  - never leave uncommitted experiments deployed to the Deck;
  - `pw_reload` refreshes the server only: the host's client keeps the clientside Lua of the last map load (old
    content, deleted files, new files one reload late). To see new client code on screen use `scripts/deck/snap.sh`
    (it reloads the map); never judge a screenshot taken after `dev.sh` or a bare `cmd.sh pw_reload`.
- Screenshots: take them once at the end of the task in one locked run; do not run the full test suite for every
  visual tweak.
- Never run cp1.sh (user rule).
- At most 2 attempts per problem caused by the environment, then stop and report.
- Agents report in Russian (chat language). Code, commits and docs stay in English.
- Lanes own directories (TASKS.md "Lanes and ownership"); docs/api/ changes only via the orchestrator.

## Brief template for a task-agent

```text
You implement <T-id> <title> for the Private War GMod gamemode, in your own git worktree.
Read: CLAUDE.md, TASKS.md (<task row>, "Mandatory test cases" for <T-id>), <design files + decisions>,
docs/api/*.md, lua/privatewar/types/core.lua, gamemodes/privatewar/gamemode/core/*.lua.

Deliverable: <copied from TASKS.md>
Mandatory test cases (all must exist as GLuaTest cases and pass; never drop or weaken them):
<verbatim list>
You own: <directories>. Do not edit anything else except lua/privatewar/types/ (annotations for every
public function, hook, class table and field you add) and lua/tests/privatewar/.
Tests go in the task's own test file (lua/tests/privatewar/<area>_<topic>.lua), never in the shared
lua/tests/privatewar/kind_examples.lua: parallel tasks editing it caused merge conflicts.

Setup in the worktree (it is fresh):
1. git switch --create task/<T-id>-<slug> main   (then verify `git log --oneline --max-count=1` is main's current commit:
   fresh worktrees were created from stale commits before)
2. cp <main repo path>/.deck.env .   (git-ignored Deck address)
3. export NIX_CONFIG="access-tokens = github.com=$(gh auth token)"   (avoids GitHub rate limits;
   the sandbox may block the export: continue without it)
4. Lint, type and test tools only through `nix develop --command <cmd>`; this also installs the git hooks.
   Run ordinary git commands directly from your own worktree.
5. Never commit or merge locally on main. No push or PR without the user's approval; merging requires
   separate explicit user approval. The orchestrator handles the reviewed draft PR workflow.

Run game tests only after the user confirms the Deck is free. If not authorized, report them skipped;
the full merge gate remains incomplete.

Workflow: write the tests → `nix develop --command make check` → implement → `make check` →
`nix develop --command make test` (runs GLuaTest in the game on the Steam Deck, about 30 s) → commit.
If `make test` times out (exit 124): run `bash scripts/deck/run.sh --restart`, wait about 60 s, retry once;
read errors with `bash scripts/deck/logs.sh --once`.
Before reporting: merge the latest main into your branch (`git merge main`), then re-run
`nix develop --command make check` and `make test`.

Known type-checker traps (LuaLS is strict, every diagnostic is an error):
- dynamic tables: annotate as table<any, any> / table<string, any>; PW.Entity allows [string] any;
- globals by name: rawget(_G, name) / rawset(_G, name, value);
- nilable results in tests: use a local `must(value)` helper (see lua/tests/privatewar/core_registry.lua);
- glualint: do not mix UPPER_CASE and camelCase local names in one file;
- `expect` exists only inside test functions;
- an error in beforeEach hangs the runner (exit 124);
- player slots are nearly exhausted at maxplayers 12: reuse shared bots in beforeAll/afterAll, create at most 2;
- bridge commands sent during a map change are lost;
- `GM:` methods already declared by the GLua annotations need `rawset(GM, ...)`;
- pre-commit type-checks staged files only: commit annotations before or with the code;
- `table.Copy` on a list of registry entities copies the entities themselves, and `PW.Call` then treats the
  copies as invalid: copy such lists by hand (`for i, v in ipairs(list) do copy[i] = v end`);
- `net.WriteTable` is forbidden (DESIGN.md global rule 4);
- `duplicate-set-field` is allowed only in entity folders (see scripts/check/types.sh).

Rules: <hard rules above>.
Stop and report (do not guess) if: a mandatory case is impossible, the design is ambiguous or wrong,
you need to touch another lane's files, or a gate fails for a reason you cannot fix in 2 attempts.

Report back: branch name, commits, the list of mandatory cases → test names, `make check` and
`make test` summaries (passed/failed counts), anything left for the checkpoint.
```

## Current queue and known gaps

Use TASKS.md "How to continue (handover)" and "Phase 11" for the current queue, known follow-ups and
items blocked on the user. Use its recorded checkpoint results and design-task decisions; do not infer
pending work from older phase plans. This command does not maintain a separate status list.
