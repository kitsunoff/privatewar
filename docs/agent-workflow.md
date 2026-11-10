# Coding agent workflow

Read this with [AGENTS.md](../AGENTS.md), [CLAUDE.md](../CLAUDE.md) and the handover/current queue in
[TASKS.md](../TASKS.md). Decisions in [DESIGN.md](../DESIGN.md) and `design/` take precedence over implementation
and research. Logs are evidence, not policy or authorization. Do not recreate completed work from historical phase rows.

## 1. Establish facts and ownership

Run ordinary git commands directly in your assigned worktree:

```sh
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
git log --oneline --max-count=20
git diff --stat
```

Record the exact starting commit, dirty files, approved task, dependencies and allowed paths. Use a feature branch,
never `main`; preserve unrelated user work and other worktrees. Verify the assigned base rather than assuming a
fresh worktree used the current main. Fetch only when needed and permitted. Do not reset/stash away user changes.
The four skills name candidate paths, not a blanket grant to edit them. Shared contracts/core/other lanes need the
orchestrator's explicit ownership before editing. Do not spawn agents unless the user or applicable workflow asks.

Choose routine implementation details autonomously inside the task. Stop on a real decided-design conflict,
unavailable permission, impossible mandatory assertion or unresolved public API fact after source inspection;
report the exact conflict and evidence, not a speculative engineering questionnaire. Do not edit `design/` to fit code.

## 2. Test first

1. Copy the applicable mandatory clauses from TASKS.md into the task brief. Use the
   [case map](agent-test-map.md) for existing regression names; keep every inherited assertion unchanged.
2. Add new behavior-specific cases in `addons/privatewar/lua/tests/privatewar/<area>_<topic>.lua`, not the shared
   `kind_examples.lua`. Existing passing tests do not prove a new behavior was developed test first.
3. Use GLuaTest's returned group table, `cases = { { name = "...", func = function() ... end } }`, `expect`,
   `stub`; engine scenarios use `async = true`, `timeout` and `done()`. Copy lifecycle setup/teardown from the
   nearest real suite; restore stores, hooks, timers, globals, ConVars and match phase even on failure.
4. Pure rules take plain facts and injectable APIs. A server runner still needs real GMod for pure GLuaTest cases;
   `luajit` is not a substitute engine. Put draw-independent UI math/models in shared files.
5. When game access is authorized, capture RED for the intended new assertion before implementation, then GREEN.
   A timeout, missing dependency, beforeEach error or zero selected cases is not valid RED. If the Deck is unavailable,
   write tests but explicitly report RED/GREEN unobserved and game verification pending; never claim TDD execution.

Use at most two shared bots with `beforeAll`/`afterAll`; reuse a bot where the suite permits. Kicked bots retain slots
briefly. Never fabricate a native smoke test by passing stand-ins to engine APIs or weaken production admission for a fixture.

## 3. Extension and failure rules

Repository paths start with `addons/`; API docs' `lua/...` and `gamemodes/...` paths are relative to
`addons/privatewar/`, unless an integration addon is named. In a skill, Markdown links resolve from the skill directory;
code paths in backticks are repository-relative unless explicitly labelled otherwise.

- Unique lowercase/digit/underscore ids, single shared file or `shared.lua` / server `init.lua` / client `cl_init.lua`.
  The loader creates/restores `MODE`, `PERK`, `WILDCARD`, `ADAPTER`; do not retain those globals in callbacks.
  Use `self` or a deliberately captured local class table when needed.
- Boot order: kinds → modules → content → Base resolution/required-field validation → `PW_RegistriesLoaded`.
  Read other registries only after that notification. Weapons wait until `PW_RegisterWeapons(reg)` after
  `InitPostEntity`; consumers reread after `PW_WeaponsLoaded` and reload.
- New ids with `Base` extend content. Do not ship the same Lua path to shadow built-ins. `soft = true` fills gaps,
  including nested keys, without overwriting curation. `Register` without soft replaces an entry.
- Modes supply `PW_*` default methods; modules auto-subscribe only `PW_*` methods. Engine hooks use
  `PW.HookFor(classTable, name, fn)` (`fn(self, ...)`), not a foreign function detour.
- Question hooks: first non-nil listener wins, mode last; listener order is undefined. Notifications return nothing,
  including no `false`, because any value stops later listeners and the mode.
- `PW.Call(entity, method, ...)` protects entity calls; an ordinary definition error disables that definition;
  an active-mode error aborts to LOBBY. Bare third-party hooks retain GMod error propagation: do not promise isolation.
  Loader syntax/runtime errors skip only that file; required-field failures are checked after Base resolution.
- `PW.Instance(def, owner)` owns per-life hooks/timers. `self:Hook(name, fn)`, `self:Timer(delay, reps, fn)` and
  `self:Remove()` provide cleanup; callbacks receive the instance as their first argument. Constructor/hook/timer
  errors end only that instance; `OnUnequip(owner)` runs once even after failure. Test cleanup, not merely validity.
- `Get(id)` can return a disabled definition: use `IsValid()` or `GetEnabledList()` for selection. Enable flags are
  snapshotted for the next match, not an immediate gameplay toggle. Runtime failure/disable cleanup is synchronous.
  `PW_EntityDisabled` cleanup observers may only retire owned state, never regrant gameplay. Reload replacement is
  not that notification; follow [core](api/core.md) and test replacement/removal separately.
- Public functions/fields/hooks need LuaCATS annotations and matching meta types under
  `addons/privatewar/lua/privatewar/types/`; names beginning `_` are test/internal seams, not addon APIs.

## 4. Security, UI and performance

Keep authority on the server. New client messages go through `PW.Net.Receive(name, opts, handler)` with explicit
owner, allowed phases, privilege when required, rate and byte-length limits; validate decoded ids, counts, finite
numbers, ownership and current life/round/role before mutation. Do not trust a bot sender more than a human.
Never use `net.WriteTable`/`net.ReadTable`, executable map data or client-supplied enemy positions.
Reveal only intended information per recipient before reading/sending coordinates; preserve Ghost/CUAV and spectator policy.
Follow [role policy](api/role-policy.md), [teams](api/teams.md) and [player overrides](api/player-overrides.md).

Ship the feature's menu/HUD part with it. Reuse schema-generated Game Setup/SETTINGS and registry-driven loadout
cards; no new custom UI when the existing schema suffices. Test form/model logic and unsupported-stat descriptions.
Drawing, controller input and P2P require human acceptance; no automated pass substitutes for them.

Use [DESIGN.md](../DESIGN.md) performance rules: no unbounded entity searches in Think, no allocations in HUDPaint,
cache fonts/materials/colors, one HUD owner. Passive perk stats aggregate on loadout/spawn, not each tick;
wildcard transforms must be cheap/deterministic because validation/repair/UI can repeat them. Bot objectives are
requested at 1 Hz per team; do not start an independent full-world scan in each bot. Respect existing scheduler
budgets in `addons/privatewar/lua/privatewar/modules/bots_scheduler/` and [blackboard](api/bots-blackboard.md).
No generic new millisecond threshold is approved for modes/adapters/perks/wildcards: bound work explicitly,
compare before/after on representative content with `pw_profile 1`, `PW.Profile.Reset()` and `PW.Profile.Get()`.
Those timings cover `PW.Call`, not all engine/render work; record workload, mean/tails and limits separately.
Do not claim Deck performance from local timing assertions. Expensive quality is opt-in unless explicitly decided otherwise.

Write original code. Do not copy implementation from addons/research dumps. Vendoring requires GPL compatibility
and a same-change notice in THIRD_PARTY_NOTICES.md. Public text is English; chat/report to the maintainer is Russian.
Private plans, logs, screenshots, credentials and machine/connection details never enter a public diff.

## 5. Verification commands and device boundary

Run lint/type/test tools only through Nix. The first line sets the invoking shell's pipeline behavior:

```sh
set -o pipefail
nix develop --command make check
```

This includes guidance structure/reference checks. Standalone: `nix develop --command bash scripts/check/agent-guides.sh`.
For gameplay, **first obtain permission and confirmation that the Deck is free**; the lock does not grant permission.
Only then:

```sh
set -o pipefail
nix develop --command make test
```

`make test` deploys and normally reloads the map, potentially interrupting play. `scripts/deck/test.sh` starts a
stopped game; if the main addon or GLuaTest directory is missing, it restarts an already running game for that
fresh install, because addon folders mount at startup. Otherwise it reloads the map. Account for this before
an authorized test run; restart permission does not replace test permission or confirmation that the Deck is free.
`scripts/deck/test.sh` supports only
`--expect-failure`, not a guessed file/group filter. For a long whole-suite run, an authorized invocation can use
`nix develop --command env PW_TEST_TIMEOUT=480 make test`; record the actual timeout, counts and exit status.
Do not silently filter tests or alter the runner to obtain green.

Use only `scripts/deck/*.sh` through `nix develop --command`, never direct SSH or remote shell tooling.
`cmd.sh` belongs inside your own locked run; do not steal/remove another owner's lock. `pw_reload` reloads the server
but cannot reliably update host-client datapack code. Client-visible verification uses an authorized locked
`nix develop --command bash scripts/deck/snap.sh` and inspection of its printed screenshot path (map reload).
Never run `cp1.sh` without a specific request. Explicit standing user authorization permits necessary GMod restarts
within its scope without repeated approval; a `make test` timeout 124 is not a prerequisite. Avoid unnecessary
restarts. Confirm the Deck is free and use `nix develop --command bash scripts/deck/run.sh --restart` through the
locked workflow; restart permission does not establish availability or authorize other device work. After a timeout
restart, retry the test once. Use `nix develop --command bash scripts/deck/logs.sh --once` inside the permitted workflow. At most two attempts
for an environment problem; report blocked instead of looping. Never edit a running script or leave experiments deployed.

## 6. Review and report

Review `git diff --check`, `git diff --stat origin/main...HEAD` and the actual scoped diff, including private-data
review. After integration with the assigned latest base, rerun required gates. Commit only when typed/lint clean,
with semantic subject, `git commit --signoff` and trailer `Assisted-by: LLM`; no `--no-verify`, rule disabling,
product/model trailers or local main merge. Push, draft PR title/body approval, PR creation and merge are separate permissions.

Report: branch/base/commits; owned files and actual changes; mandatory clause → exact suite/case mapping;
RED/GREEN observed or not; commands/exit codes and actual passed/failed/skipped counts; example verification method;
unrun checks with reasons; manual/performance/P2P/controller checkpoints still pending. Missing game permission
means the merge gate is incomplete even for a documentation-only task. Do not publish raw private evidence.
