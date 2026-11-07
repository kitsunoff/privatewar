# Private War — implementation plan

Status: draft, built from `DESIGN.md` and `design/*.md` as of 2026-11-06. Handover for a new agent: "How to continue (handover)" below; current queue: "Phase 11" at the end.

This file is the single task list for building the gamemode. It defines:

1. phases and tasks with dependencies;
2. **human checkpoints** (`CP-*`): moments when the user runs the game and tests by hand; the next phase does not start until the checkpoint passes;
3. **parallel lanes** and which agent owns which lane.

Repository paths: `lua/...` and `gamemodes/...` in this file, in `DESIGN.md`, `design/` and `docs/` are relative to the gamemode addon folder `addons/privatewar/` (the same paths GMod sees in the game). The other addons are `addons/privatewar-arc9/` (ARC9 integration) and `addons/privatewar-dev/` (dev-only bridge, never shipped).

## How to read a task

```text
T-<phase>.<n>  Title                                  lane · agent · depends on
  Deliverable: what exists when the task is done
  Tests first: what is written before the code (TDD); the full list is in "Mandatory test cases"
  Design: the decisions it implements
```

- **Tests first** is mandatory (global rule: TDD). The test framework is **GLuaTest** (`CFC-Servers/GLuaTest`): tests live in `lua/tests/privatewar/*.lua`, run inside a real GMod server (pure logic and engine behaviour alike), with `expect`, `stub`, async cases (timers, hooks, bots via `player.CreateNextBot`). See "Testing" below. Checkpoints cover what automated tests cannot (P2P, feel, visuals).
- In the task tables, "Pure:" means a fast GLuaTest case with no engine state (stubs only); "In-game:" means a GLuaTest case that uses real entities, hooks, timers or bots (usually `async = true`).
- A task is done when: tests pass, `glualint`, the type checker (`lua-language-server --check`) and the `rules` gate are clean (warnings as errors, including type errors), **every public function, hook, class table and field it adds is annotated and the matching `---@meta` definitions in `lua/privatewar/types/` are updated**, the module loads with `pw_reload`, **its screen part exists if the feature has UI**, the commit is made with `--signoff`.

## How to continue (handover)

For an agent that picks the work up in the middle (for example Codex after Claude): everything needed is in this repository. Read `CLAUDE.md` (project rules), `AGENTS.md` (short entry point), this file, then "Phase 11" at the end for the current queue. Task status is not stored per row in the older phase tables; inspect current code and task branches alongside "Phase 11". Pre-snapshot merge hashes and branch references are historical, not instructions to recreate implemented work.

### Publishing

Develop directly in this canonical repository (`kitsunoff/privatewar`), on feature branches and through reviewed PRs, draft by default. The former research checkout is historical only. Push only with the user's authorization; show the PR title and body and obtain approval before creating it. Merging requires separate explicit user approval. Public text is English only; private content must stay outside the public repository and any published tree. `scripts/export/public.sh` remains optional tooling for a filtered snapshot, not a required development step. See `docs/publishing.md`.

### Current state (2026-11-07 evening)

- The initial public snapshot has one root commit, `2d71b09`. Older merge hashes and running-branch/worktree references below are historical, not a current queue. Inspect the current code and task branches before continuing; do not recreate implemented features from old status entries.
- T-11.8 is implemented in the initial public snapshot, including all mandatory cases; penetration was measured and kept on.
- T-11.9 is implemented in the initial public snapshot; the independently verified correction from `task/T-11.9-operators-names-fix` is included in the current change set (required request rejection, first-stock default, deterministic overflow names and expanded mandatory tests).
- T-11.10 has an initial implementation in the public snapshot; follow-up is required to reconcile mandatory cases and existing contracts: non-positive map-change delay versus the minimum requirement, popup expiry after its deadline, the shared initial/postmatch lobby path and test, and measured popup padding.
- The Deck must be free (the user is not playing) before `make test`, because the tests reload the map.
- User decisions still open: the DOM flag tiles moving up to y about 20; the lobby leave dialog default button (CANCEL recommended); the XP curve (item 46: about 3M XP in total now; options: keep, divide by 10, custom).

### Orchestration loop

1. One agent per task, each in its own git worktree and branch (`task/T-<n>.<m>-<slug>`, `feat/<slug>`, `fix/<slug>`, `docs/<slug>`), created from the current `main`. At most 3 agents at once; only one of them may use the Deck at a time (the lock handles waiting).
2. Task order: lowest-numbered task whose dependencies are merged; skip anything blocked by an open design question (`D1`-`D4`) or marked "pending confirmation"; collect those for the user. The full orchestration rules (briefs, model choice, hard rules) are in `.claude/commands/orchestrate.md`; they apply to any agent.
3. The merge gate, run in the agent's worktree after merging the latest `main` into the branch: `nix develop --command make check` and `nix develop --command make test`, both green (run them with `set -o pipefail` so a failure inside a pipe is not hidden). Plus: scope check with `git diff --stat main...<branch>` (only the lane's directories, `lua/privatewar/types/`, `lua/tests/privatewar/`), and every mandatory test case below exists by name and is not weakened.
4. Copy the git-ignored `.deck.env` (Deck address) from the main checkout into every new worktree.
5. Never commit or merge locally on `main`. After review and green gates, request authorization to push the feature branch if not already granted. Show the draft PR title and body and obtain the user's approval before `gh pr create --draft`. Merge only with separate explicit user approval, using `gh pr merge --squash --delete-branch` after the PR is ready. No push, PR creation or merge is automatic.
6. Commits: `git commit --signoff`, semantic message, trailer `Assisted-by: LLM` only. Never `--no-verify`.

### Steam Deck rules

1. Touch the Deck only through the locked scripts (`make test`, `scripts/deck/*.sh`); never `ssh` to it directly. `scripts/deck/lock.sh` needs GNU coreutils: always run the Deck scripts through `nix develop --command`.
2. For any client-visible change, look at the result with `scripts/deck/snap.sh` (it reloads the map so the host's client runs the new files) and read the printed screenshot path. `pw_reload` alone does not refresh the host's client.
3. Never run `scripts/deck/cp1.sh` unless the user asks for it. Restart the game (`run.sh --restart`) only after a `make test` timeout (exit 124).
4. Never leave uncommitted experiments deployed to the Deck.

### Manual checks and pending decisions

The local manual checklist (not published; its path is listed in `scripts/export/local-only.txt` and it must stay outside the public repository and any published tree) is the place for everything a human must check in the game and for decisions taken by recommendation (its section 7). It may be written in the maintainer's language, but nothing from it is ever published; public text is English only. When a decision is marked "pending confirmation" here or in `design/`, implement the recommendation and add an item there; the user confirms or corrects it later. Do not stop the run for it.

## Toolchain

Lint, type and test tools come from `flake.nix` (`nix develop`, or direnv `use flake`). Agents run these commands through `nix develop --command <cmd>` because their shells are non-interactive. Run ordinary git commands directly in your own worktree.

**Rule: nothing is built from source.** A tool missing from nixpkgs is packaged from its **release binary** under the nixpkgs naming convention `<name>-bin`.

| Tool | Source | Notes |
| --- | --- | --- |
| `lua-language-server` (LuaLS) | nixpkgs (3.17.1) | Language server and **type checker** (`--check`) on every platform |
| `markdownlint-cli2` | nixpkgs (0.21.0) | Docs |
| `luajit` | nixpkgs | Same Lua as GMod for quick scripts |
| `glualint-bin` | Release binary `FPtje/GLuaFixer` 1.30.0 | Assets: `OSX-x86_64` (runs through Rosetta on Apple Silicon), `x86_64-linux`; no native arm64 macOS build |
| `glua-ls-bin` (optional, editor only) | Release binary `Pollux12/gmod-glua-ls` | Only `glua_ls` has macOS builds (`darwin-arm64-experimental`); `glua_check` ships for linux-x64 and win32 only, so it is **not** the gate |
| GMod annotations | Pinned non-flake input `luttje/glua-api-snippets` (data, not built) | Fed to LuaLS via `.luarc.json` |
| GLuaTest | Pinned non-flake input `CFC-Servers/GLuaTest` | Docker runner script; Docker itself (Colima) stays in nix-darwin |
| Git hooks | `cachix/git-hooks.nix` (Apache-2.0) | Installed by the devShell; all four `pre-commit` fast checks; no automatic `pre-push` tests (user decision 2026-11-08). Manual `make check` / `make test` acceptance/merge gates remain mandatory |
| CI (later) | `nix flake check` | Same checks as the hooks |

Outside the flake (system level): Colima/Docker, Garry's Mod itself.

## Dev loop on the Steam Deck

Code is written on the Mac; Garry's Mod runs on a Steam Deck in the local network.

```text
scripts/deck/
  deploy.sh   rsync the addons under addons/ to the Deck over SSH (changed files only)
  cmd.sh      send a console command to the running game ("pw_reload", "map gm_construct", "screenshot", run tests)
  run.sh      start GMod on the Deck with dev args (-condebug, +maxplayers 12, +gamemode privatewar, +map ...)
  logs.sh     tail garrysmod/console.log over SSH, filtered: Lua errors, [PW] lines, GLuaTest results
  dev.sh      deploy → pw_reload → logs (one command for agents)
```

0. **Deck lock:** `deploy.sh`, `test.sh`, `run.sh`, `stop.sh`, `cp1.sh` and `dev.sh` take a lock shared by all worktrees (a symlink in the git common dir, `scripts/deck/lock.sh`), so parallel lane agents may all run `make test`: they wait in turn (message every 30 s, timeout `PW_DECK_LOCK_TIMEOUT`, default 1800 s, exit 75), a dead owner's lock is taken over, nested scripts re-enter. `cmd.sh` and `logs.sh` stay lock-free. Self-test: `scripts/check/deck-lock-selftest.sh` (part of `make check`).
1. **Connection:** `DECK_HOST` (for example `steamdeck.local`) and `DECK_USER` (default `deck`) from environment variables; authentication by SSH key installed once with `ssh-copy-id`. **No passwords or hosts in the repository.**
2. **Install detection** (the user is not sure whether GMod runs natively or through Proton): read `~/.local/share/Steam/steamapps/libraryfolders.vdf` to find the library holding app 4000 (internal storage or SD card); native build if `GarrysMod/hl2.sh` / `hl2_linux` exists, Proton if `GarrysMod/*.exe` and `steamapps/compatdata/4000/` exist. In both cases `addons/` and `console.log` live under `steamapps/common/GarrysMod/garrysmod/`. Launch arguments differ only in how Steam is asked to start the game (`steam -applaunch 4000 <args>`).
3. **Reload:** on Linux (native) Lua auto-refresh works for changed files; new files need `pw_reload`. Under Proton auto-refresh is expected to work like on Windows (to verify). `dev.sh` always sends `pw_reload` after deploying, so both cases are covered on the server. **The host's client is not covered** (measured 2026-11-07): it runs clientside Lua from the server's datapack filled at map load, so after `pw_reload` it keeps the old content of changed files, still runs deleted files and finds a new file only one `pw_reload` later. To see new client code on screen, reload the map: `snap.sh` does it (map reload with the GLuaTest run skipped, then waits for the host's client).
4. **Command bridge:** a listen server has no convenient remote console, so the dev-only module `pw_devbridge` polls `data/privatewar_dev/cmd.txt` once per second while `pw_dev` is 1 (default), runs the command on the server, and clears the file. It is excluded from Workshop packages.
5. **Screenshots:** `cmd.sh screenshot`, then `scp` the newest file from `garrysmod/screenshots/` to the Mac for review.
6. **Verified on the user's Deck (2026-11-06, over SSH):**

   | Fact | Value |
   | --- | --- |
   | OS | SteamOS 3.7.19, `x86_64` |
   | SSH | `sshd` running, key login works |
   | Library | Internal storage, `/home/deck/.local/share/Steam` |
   | Game dir | `/home/deck/.local/share/Steam/steamapps/common/GarrysMod/garrysmod/` |
   | Build | **Windows build through Proton**: forced compatibility tool `proton_10` (Proton 10.0, prefix `10.1000-105`), `gmod.exe` present |
   | Branch | `x86-64` (both `bin/win64` and `bin/linux64` present) |
   | Launch options | None set |
   | `addons/` | Empty |
   | `console.log` | Absent (no `-condebug` yet) |

7. **Verified while writing `scripts/deck/` (2026-11-06):**
   - `steam -applaunch 4000 <args>` from SSH works when run in the foreground with `DISPLAY=:0` and `XDG_RUNTIME_DIR=/run/user/<uid>`; a detached background call was silently lost. Steam showed no confirmation dialog.
   - `-condebug` writes `garrysmod/console.log` under Proton; it appends across runs, so `run.sh` moves the old log to `console.log.prev` before each launch.
   - `+pw_dev 1` on the command line is lost ("Unknown command"): launch arguments run before Lua creates the ConVar. The bridge ConVar therefore defaults to 1.
   - `game.ConsoleCommand` blocks `echo`, `lua_run` and similar commands. The bridge has prefixes: `lua <code>` runs Lua through `RunString`, `client <cmd>` runs a command on the host's client (`client jpeg` for screenshots).
   - **Lua auto-refresh did not trigger under Proton** for a changed addon autorun file within 15 s. Reloads go through the bridge (`pw_reload` once it exists); a change to the bridge itself needs `run.sh --restart`. Re-test auto-refresh for gamemode files when they exist.
   - The game process under Proton is `S:\common\GarrysMod\bin\win64\gmod.exe` (plus its CEF subprocesses); the scripts match `bin.win(32|64).gmod\.exe|hl2_linux`.
   - The Deck has the user's own Workshop addons subscribed (ARC9 and others); they load in every dev session and appear in the log.

8. **Script reference:**

   | Script | Use |
   | --- | --- |
   | `detect.sh` | Print `proton`/`native` and the `garrysmod/` path |
   | `deploy.sh [--no-dev]` | Copy changed files of every addon under `addons/` (the dev addon is deployed as `addons/privatewar_dev` on the Deck) |
   | `run.sh [--restart]` | Launch (or relaunch) the game; `PW_GAMEMODE`, `PW_MAP`, `PW_MAXPLAYERS`, `PW_EXTRA_ARGS` |
   | `stop.sh` | Stop the game |
   | `cmd.sh <line>...` | Queue bridge lines (`map ...`, `pw_reload`, `lua <code>`, `client <cmd>`) |
   | `logs.sh [--all] [--from-start] [--once]` | Filtered log; `--once` prints and exits (use this in agents) |
   | `shot.sh [dir]` | Screenshot on the Deck, copied to `.deck-shots/` on the Mac (git-ignored); prints the path |
   | `dev.sh` | `deploy.sh` → `cmd.sh pw_reload` → `logs.sh` |

9. **Test start gate:** GLuaTest stays installed in `addons/` and runs on every map load. On a listen server the dev addon (`pw_testgate.lua`) delays the run until the listen host's client has finished loading: the host's first usercmd that is not forced (`StartCommand`), plus 2 s; fallback: 60 s without a host. Bots created by tests therefore never take player slot 1, and the host keeps `superadmin` for dev bridge commands such as `pw_reload`. Starting earlier (at `PlayerInitialSpawn`) was too early: test groups swapped the module stores while the host's client was still loading, its first `pw_lobby_request` was lost and the lobby screen stayed empty. The gate prints `[PW] testgate: host <name> loaded` on every map load and skips one run when `data/privatewar_dev/skip_tests.txt` exists (a one-shot flag written by `snap.sh` before its map reload; `test.sh` removes a stale one).

## Testing

| What | Tool | Notes |
| --- | --- | --- |
| Unit and integration tests | **GLuaTest** (`CFC-Servers/GLuaTest`, GPL-3.0, active) | RSpec/Jest-like syntax, `expect`, `stub`, async cases; runs in a real server, so engine APIs, hooks, timers and bots are testable |
| Local loop | GLuaTest in the dev server's `addons/` | Tests run on server start; re-run with `pw_reload` / restart |
| Headless run | GLuaTest Docker runner (`run_local.sh`) | Same runner as CI; needs Docker compose (Colima `nerdctl compose`); x86 server image on Apple Silicon is unverified |
| CI (optional) | GLuaTest reusable workflow on pull requests | `requirements.txt` can pull dependencies (for example weapon bases) |
| Lint and types (mandatory) | `glualint` (linter) + `lua-language-server --check` (type checker, GMod annotations from `luttje/glua-api-snippets`, warnings as errors) + `markdownlint-cli2` for docs + `rules` (`scripts/check/rules.sh`, below) | Enforced by `pre-commit` and the Claude Code `PostToolUse` hook (T-0.7); `make check` runs lint, types, markdown and rules; type and lint errors fail the build; disabling a rule inline or in config needs the user's approval with a written reason |
| Rules gate (mandatory) | `make rules` (`scripts/check/rules.sh`, also a `nix flake check` and a `pre-commit` hook) | No `net.WriteTable` / `net.ReadTable` outside tests (DESIGN.md global rule 4); a Lua file at most 500 lines and a function at most 60 lines under `gamemodes/`, `lua/privatewar/` and the integration addons (global rule 3), function length measured from the `luajit -bl` prototype listing; `lua/tests/` and `addons/privatewar-dev/` are exempt |
| Not automatable | Checkpoints (`CP-*`) | P2P, listen-server specifics, feel, visuals |

The local manual checklist (not published) is the single list of manual checks; every task appends its checkpoint items there.

### Coverage strategy

**Thin glue rule:** logic is written as pure functions that take plain data (positions, numbers, tables); engine calls (`ents.Find*`, traces, `draw.*`, `net.*`, `SetPos`) live in thin wrappers around them. Shared (`sh_`) logic also loads on the server, so even client-side logic (what the HUD shows, timer formatting, settings form generation) is testable in the server-only runner. Only drawing itself is left to checkpoints.

| Area | Expected depth | Covered by tests | Left to checkpoints |
| --- | --- | --- | --- |
| Core and extensibility | High | Registries, `Base`, `soft`, `PreRegister`, settings clamp/inheritance, hook dispatch and auto-subscription, `PW.Call`, instances (no leaked hooks/timers), phases, NW2 values, `pending_match.json` validity | The `changelevel` itself (restarts the server) |
| Net | Medium | A bot is a player: call `PW.Net.Receive` handlers directly with a bot as sender to test privilege, phase, rate and length checks | Real client ↔ server traffic |
| Modes and map | High | Win conditions, capture math, KC tags, rounds, spawn scoring, map filter, vote selection | Feel |
| Weapons | Medium–high | With the GLuaTest Workshop `collection` mounting ARC9/TFA/MW Base and packs: catalogue, `Apply` on a bot's weapon, customization lock, server side of stat modifiers | Client prediction (timings the player sees) |
| Loadout and progression | High | Pick X budget, wildcards, class repair, perk stacking, streak counting, XP curves, date-seeded store rotation | — |
| Bots | Medium | Math: A* on a synthetic graph, reaction queue, aim spring, dual-utility selection, commander assignment. A **few** smoke scenarios: spawn a bot, give a goal, check position / not stuck after N ticks, with generous timeouts (scenarios tend to be flaky) | Believability, behaviour quality, difficulty balance |
| HUD and frontend | Low | Logic split from drawing (formatting, layout maths, form generation from schemas) | Drawing and look (screenshots) |
| Lobby and P2P | Low | Bot quota, join in progress (via bots) | P2P, Steam "Join Game", listen-host specifics |

Runner notes: select the gamemode and map (`--gamemode privatewar --map gm_construct`); mount weapon bases through a Workshop collection; on Apple Silicon use `--branch x86-64` (the default 32-bit server crashes under emulation) and a higher `--timeout`.

- Licence: GLuaTest is a development tool and is never shipped, so its GPL-3.0 does not affect the gamemode's licence (D4). Tests live in `lua/tests/privatewar/` and are excluded from Workshop packages (T-10.2).
- Listen-server-only behaviour (P2P, host privileges as listen host) is covered by checkpoints, not by the Docker runner (dedicated server).
- Known issue: GLuaTest runs leave archived test ConVars (for example `pw_module_test_subscribe_boot_enabled`) in the Deck's `cfg/server.vdf`. They are harmless but accumulate; tests should prefer non-archived ConVars for test kinds.
- Player slots: the suite runs with `maxplayers 12`, and kicked bots hold their slot for a while. The existing tests already use about 10 slots, so new in-game tests reuse shared bots (`beforeAll`/`afterAll`) instead of creating more.

## Mandatory test cases

**A task is not done until every case listed for it below exists as a GLuaTest case and passes.** The reviewer checks this list against the branch. Agents may add more cases; they may not drop or weaken these. If a case turns out impossible, the agent stops and raises it with the orchestrator instead of skipping it. "Pure" and "In-game" have the meaning given in "How to read a task".

### Phase 0

- **T-0.3**: `nix develop` provides every tool on a clean machine (aarch64-darwin and x86_64-linux); a deliberately mistyped call (wrong argument type to an annotated function) makes `nix flake check` fail; a lint error makes it fail too.
- **T-0.8**: **Cancelled by the user on 2026-11-07: the Deck scripts are dev tooling and are not tested.** The block below is kept for the record and is not mandatory.
  - detection prints the install type (native or Proton) and the `garrysmod/` path, both for an internal-storage and an SD-card library (`libraryfolders.vdf`);
  - `deploy.sh` copies only changed files and never touches other addons; running it twice copies nothing the second time;
  - a command written by `cmd.sh` is executed exactly once by `pw_devbridge` and the file is cleared; the bridge does nothing when `pw_dev 0` (default 1: the addon only exists on dev machines, and a `+pw_dev` launch argument would be lost because it runs before the ConVar exists);
  - `logs.sh` shows a deliberately broken Lua file's error within a few seconds of `dev.sh`;
  - no password or host is stored in the repository (environment variables and SSH keys only).
- **T-0.7**: a commit with a lint error, a type error, a markdown error or a rules violation is refused by `pre-commit`; pushing does not run GLuaTest or require Deck access (user decision 2026-11-08, replacing the former full-test `pre-push` requirement); a fresh worktree entering the devShell has all four `pre-commit` hooks installed; an agent edit introducing a type error gets the diagnostic from the `PostToolUse` hook. Manual acceptance/merge gates remain unchanged.
- **T-0.4**
  - a trivial case passes in the dev server and in the Docker runner;
  - a deliberately failing case makes `make test` exit non-zero.

### Phase 1 — core

- **T-1.1 Kind loader**
  - single-file form and folder form (`shared.lua`, `init.lua`, `cl_init.lua`) both register;
  - the global class table (`MODE`, ...) is cleared after each file;
  - a file with a syntax error and a file that errors at runtime are skipped with one log line each, and the next file still loads;
  - a missing required field skips the entity with a readable error; a mistyped field (wrong type) too;
  - a kind declared in `kinds/` by a fixture addon path is scanned without any core change.
- **T-1.2 Registries**
  - `Base` resolves regardless of registration order (child before parent, parent before child);
  - multi-level `Base` chain; missing base gives a clear error, not a crash;
  - `Abstract` entities are absent from `GetList` but usable as a base;
  - re-registering the same id replaces the entry;
  - late registration (after the main load) resolves `Base` immediately;
  - `soft = true` fills only missing fields, merges nested tables per key (`Attachments.optic_acog.Unlock` kept, missing `Cost` filled), never overwrites.
- **T-1.3 `PW_PreRegister`**
  - returning `false` vetoes registration;
  - field edits in the hook are applied;
  - one listener matching an id prefix patches many entities;
  - runs for late (programmatic) registrations too.
- **T-1.4 Enable ConVars**
  - every entity gets `pw_<lowercase Global>_<id>_enabled`;
  - a disabled entity is absent from lists after the next `LOBBY → PREMATCH`;
  - changing the ConVar during `LIVE` does not change the current match's snapshot.
- **T-1.5 Settings**
  - each type (`int`, `float`, `bool`, `enum`, `set`): valid value accepted, out-of-range clamped, wrong type rejected, unknown enum option rejected;
  - inherited settings and overridden defaults through `Base`;
  - `MODE.SettingDefaults` overrides a module's `match` default;
  - full ids (`tdm.scorelimit`) resolve; unknown id is reported;
  - `match` snapshot is taken on `LOBBY → PREMATCH` and is immutable during the match;
  - a non-privileged sender cannot change `match` or `server` settings.
- **T-1.6 Hook dispatch**
  - the active mode's method is called after listeners; a listener's non-nil answer wins over the mode for a question hook;
  - for a notification hook, a listener returning a value triggers the debug warning;
  - after switching modes, the old mode's methods are no longer called.
- **T-1.7 Auto-subscription**
  - only `PW_*` methods are subscribed (a method named `Think` is not);
  - `KIND.Subscribe = "never"` entities are not subscribed;
  - disabling an entity (ConVar or error) removes its subscriptions (`IsValid` false).
- **T-1.8 `PW.Call`**
  - an erroring entity method returns safely, logs once, and the entity is disabled until map change;
  - the active mode erroring ends the match and returns to `LOBBY` with the error message;
  - with `pw_profile 1` time is accumulated per entity id; with `0` nothing is recorded.
- **T-1.9 `PW.Instance`**
  - `self:Hook` and `self:Timer` work while valid;
  - after `Remove()` no hook or timer of the instance remains (`hook.GetTable`, `timer.Exists`);
  - `OnUnequip` is called exactly once;
  - all live instances end on `PW_MatchEnd`;
  - an error inside an instance callback disables only that instance.
- **T-1.10 Privileges**
  - without CAMI: `superadmin` default passes for a superadmin bot, fails for a normal bot;
  - with a stubbed `CAMI` global: privilege is registered and the check goes through CAMI.
- **T-1.11 `PW.Net.Receive`**
  - with a bot as sender: wrong privilege, wrong phase, over-rate, over-length messages are dropped before the handler;
  - a valid message reaches the handler;
  - rejection logging is throttled (one line per N seconds per player).
- **T-1.12 Phase machine**
  - every transition in the table fires and no other transition is possible;
  - `PREMATCH → LIVE` on "all ready" and on timeout;
  - `PW.Match.Finish` moves to `POSTMATCH`; host abort returns to `LOBBY` from any phase;
  - after-match setting: lobby vs rotation path;
  - `MODE:Start`, `MODE:Cleanup` called exactly once per match; `MODE:Think` called only in `LIVE`.
- **T-1.13 Phase networking**
  - NW2 values are written in the order end → phase → seq on every transition;
  - `seq` increases by exactly one per transition.
- **T-1.14 Map change**
  - `pending_match.json` written before the command; contents round-trip;
  - validity: wrong map, wrong map-change count, file older than 120 s, unknown version → each rejected, falls back to `LOBBY`;
  - same target map → no `changelevel`, straight to `PREMATCH`;
  - double start request does not call `changelevel` twice (guard);
  - client-ready handshake: repeated ready messages are idempotent; `PREMATCH` waits for humans only.
- **T-1.15 `pw_reload`**: a new kind file added after load is picked up; a changed file replaces its entry.
- **T-1.16 `teams`**
  - assignment and balance for 2 teams and for N = 3, 4;
  - `PW.IsEnemy`: team mode vs FFA (`a ~= b`);
  - late joiner goes to the smaller team.
- **T-1.17 Weapon registration phase**: `PW_RegisterWeapons` runs after SWEPs exist, then `PW_WeaponsLoaded`; a weapon registered in the phase is visible to `PW_WeaponsLoaded` listeners.
- **T-1.18 Fixtures**: one minimal valid entity per built-in kind registers; one invalid variant per kind is rejected.
- **T-1.19 Lobby v0 and kit**: settings form generation produces one control per setting of the right type (logic only; drawing is a checkpoint); Start button handler requires the privilege; the enable-flag message is rejected without the privilege and accepted from a superadmin who is not the host.

### Phase 2 — modes and map

- **T-2.1 Score**: `Award` adds points and fires `PW_ScoreEvent` with points, XP and weapon; `PW_ScoreValue` overrides the value; unknown event id is rejected.
- **T-2.2 TDM, FFA**: win by score limit; win by time limit; tie handling; FFA winner is the top player.
- **T-2.3 `round_base`**: round loop until `RoundsToWin`; side swap every `SwapSidesEvery`; `PW_RoundStart/End` order; abstract mode not in lists.
- **T-2.4 Domination**: capture scalar moves by `rate × min(diff, 3)` and stops at ±100; contested point does not move; scoring per held point; `ValidateMapData` rejects < 2 flags; mode hidden on a map without data.
- **T-2.5 Kill Confirmed**: tag spawns at victim; enemy pickup confirms and scores; teammate pickup denies; tag is removed after pickup.
- **T-2.6 Playlists**: weighted sampling respects weights over many draws; host-saved JSON loads and validates like Lua playlists; invalid JSON is rejected with a message.
- **T-2.7 Map data**: entity class → team mapping for CS:S, HL2DM, TF2 spawn classes; `GetModeData` walks the `Base` chain.
- **T-2.8 Navmesh fallback**: sampled points are on walkable areas and respect the size/water/slope filters (synthetic area data).
- **T-2.9 Spawns**: scoring prefers far-from-enemy, penalises enemy line of sight, rewards nearby teammates only in team modes; a recently used point is penalised; hull-blocked point is never chosen.
- **T-2.10 `pw_mark`**: output line parses back into a valid map-data entry; requires the privilege.
- **T-2.11 Map list**: union of data maps, prefixes and whitelist; junk patterns always excluded.
- **T-2.12 Navmesh generation**: marker validation (success, failure, stale marker); seeds generated for every spawn entity class; no generation without the privilege or outside `LOBBY`.
- **T-2.13 Vote**: options sampled from the playlist; last two maps excluded unless the playlist has < 3 maps; repeat excluded unless allowed; early end when all humans voted; bots never vote; vote change replaces the previous vote; tie broken at random among tied options.

### Phase 3 — weapons

- **T-3.1 Adapter lookup**: highest `Priority` claiming adapter wins; adapters with `IsAvailable() == false` are skipped; every optional method has a working default.
- **T-3.2 Fallback adapter**: claims a plain SWEP; stats defaults from `Primary.*`.
- **T-3.3 Catalogue**: declarative entry beats programmatic `soft` entry per field; per-weapon ConVar hides a weapon; curation fields (`Attachments`, `Camos`) survive merge.
- **T-3.4 Ammo**: default ammo suppressed; the core gives the configured magazines.
- **T-3.5 Stat mods**: `SetStatMods` writes NW2 values and bumps the revision once; refresh is called once per revision per weapon; removal resets to 1.0.
- **T-3.6–T-3.8 Integrations** (each with the Workshop collection mounted):
  - catalogue lists the pack's weapons with categories;
  - `Apply` on a bot's weapon returns the applied build; a conflicting build returns what stuck;
  - customization lock is active (the base's own customization path refuses);
  - stat mods change the server-side value of at least reload time;
  - `PrepareForBot` runs without errors; two bots with different builds of the same class keep different builds (ARC9 instance tables risk).

### Phase 4 — loadout, progression, economy

- **T-4.1 Slots**: a module-declared slot appears; wrong kind in a slot rejected; filter respected; `PW_PlayerLoadout` from the mode replaces the class.
- **T-4.2 Pick X**: budget sum; budget 0 = unlimited; cosmetic attachments free; `PW_LoadoutCost` override; `maxattachments`; banned weapon/attachment rejected.
- **T-4.3 Wildcards**: `ModifySlots` effects (extra perk, extra attachment) and their cost.
- **T-4.4 Perks**: group rule; `PW.Stat` multiplies perk, wildcard and mode multipliers; recomputed on spawn and loadout change only; event methods called only for the owner; instance cleanup on death.
- **T-4.5 Equipment**: slot key triggers `OnUse` on the instance; count decreases and refills on spawn; bot path `PW.Equipment.Use` works.
- **T-4.6 Streaks**: earning by kills and by score; reset on death; unused streaks kept; `streaks.persist`; streak kills do not chain unless enabled; activation creates an instance that ends after `Duration`.
- **T-4.7 Classes**: repair removes unavailable items and keeps the rest; size-limited upload rejects oversized payload; class marked unavailable when a playlist lowers the budget.
- **T-4.8 Gunsmith flow**: validation on save; partial application repairs the class and sends one message.
- **T-4.9 Progression**: XP curve values at levels 1, 10, 55; weapon XP only from events with a weapon; unlock by curation vs unlock by count; `unlockall`.
- **T-4.10 Storage**: delta batching every 10 s; client-side apply is additive and idempotent per batch id; sanity check rejects negative or absurd values.
- **T-4.11 Medals**: each MVP detector fires exactly when it should (double/triple kill windows, revenge, first blood, 5-streak, saviour) and not otherwise.
- **T-4.12 Economy**: currency from events; purchase deducts and unlocks; insufficient funds refused; rotation is identical for the same date and different for another date.

### Phase 5 — bots

- **T-5.1 Manager**: quota arithmetic (humans join/leave, `maxplayers` cap); a human joining replaces a bot of the smaller team; reconciliation after a simulated map change (extra kicked, missing created, `NULL` from `CreateNextBot` handled); refusal in Singleplayer.
- **T-5.2 Input writer**: a scripted intent produces the expected `CUserCmd` buttons and move values; adapter input rules (release between semi shots, TFA reload tap, no `IN_USE` with attack) are respected.
- **T-5.3 Scheduler**: never exceeds the per-tick budget with 24 fake bots; every bot gets its brain tick within the expected period; FIFO runs one expensive job per tick.
- **T-5.4 Debug overlay**: debug data (behaviour, reason, goal) is produced only when `pw_bot_debug` is on (logic only; drawing is a checkpoint).
- **T-5.5 A***: shortest path on a synthetic graph; time slicing yields and resumes to the same result; partial path on iteration cap; unreachable pair cached; cost layers change the chosen path.
- **T-5.6 Goals and following**: higher priority goal overrides lower; unreachable goal blacklisted; stuck ladder escalates in order. Smoke scenario on `gm_construct`: a bot reaches a goal 20 m away within the timeout.
- **T-5.7 Perception**: target outside FOV not seen; reaction queue delays recognition by the configured time; contact memory decays after 12 s; search plan yields 5 points; damage reveals attacker direction; hearing range respected (no map-wide hearing); stimulus from `PW.Bot.AddStimulus` enters memory.
- **T-5.8 Aim**: spring-damper converges without exceeding the acceleration clamp; focus error shrinks while steady and resets on large moves; no fire before settle; line-of-fire gate blocks firing at an occluded target.
- **T-5.9 Brain**: dual-utility picks the highest rank bucket; weighted-random among near-best only (screen threshold); commitment bonus prevents flip-flopping; per-behaviour interval respected; Action stack suspend/resume order.
- **T-5.10 Behaviours**: each of the 11 behaviours has at least one case for "chosen when it should be" and one for "not chosen when it should not be".
- **T-5.11 Commander**: assignment respects `want` and `weight`; Domination defenders ≤ team / 3; anti-dither (no reassignment off an active capture); hunt slots ≤ 2 per human and replacement of a stalled hunter.
- **T-5.12 Profiles**: every field of every difficulty and personality file is read somewhere (unused field fails the test); team personality ratio 4:1.
- **T-5.13 Bot loadouts**: pool from presets and players; a player's class used by a bot is checked against match settings, not progression.

### Phase 6–8 — HUD, frontend, lobby (logic only; visuals are checkpoints)

- **T-6.1** element registry order and visibility by phase; an erroring element is disabled without breaking others.
- **T-6.2** timer formatting from `pw_phase_end`; victory/defeat decision.
- **T-6.4** score popup queue (ordering, merge of rapid events, expiry).
- **T-6.6** radar visibility rules: teammates always; enemies only during UAV; Counter-UAV hides enemies.
- **T-7.2** settings forms: one control per setting, correct widget per type, values written back through the validated path.
- **T-7.4–T-7.7** each screen's data model (what to show) built from registries without drawing.
- **T-8.2** maxplayers warning appears when `bots.fill` exceeds slots.
- **T-8.4** join in progress on/off: spectate vs play.

UI rework (D1; added 2026-11-07 from `notes/16-frontend-d1-proposal.md` §5; they sit next to, and never replace, the cases above; pure unless marked):

- **U-1 tokens, fonts, scaling** (T-7.1): every token named in `design/10-frontend.md` d.5 exists in `PW.UI.Style` and is a colour; font ladder sizes at 1280×800 are at least 14 px; every font name is at most 31 characters; scale `S` for 1920×1080, 1280×800, 2560×1440 and 3440×1440; fallback scale when `PW.HUD` is nil; font families come from `PW.UI.Style` only (one place to switch to Fira).
- **U-2 layout, focus, input** (T-7.1): column rectangles at the four resolutions (anchored left and right, the centre fills); focus: down and up in a vertical list, stop at the ends, wrap in the tab bar, skip disabled, stop on locked, cross to the neighbour group by geometry, restore the group's last node, no candidate keeps focus; input: every action has a keyboard key and a controller code, the device switches on the last input, the `pw_ui_hints` override wins.
- **U-3 router and root** (T-7.1): Push, Pop and Replace; Back at a tab root in `LOBBY` stays; a tab switch keeps each tab's stack; a locked tab cannot be entered; a screen whose build errors is skipped through `PW.Call` and the others work.
- **U-4 components v1** (T-7.1): the expanded card is the selected one; pager maths (`page`, `pages`, rows per page from height); player list model: humans listed, bots collapsed to "+N", host first, team sections from `PREMATCH`, one PARTY section in `LOBBY`; tab model: locked and "NEW" (seen-set); form controls: the T-7.2 cases still pass (one control per setting, widget per type, values through the validated path).
- **U-5 hub and custom game** (T-8.1, T-8.2): hub model from playlist state, lobby state and players: a guest sees Start, Mode and Map, Game Setup locked with a reason, the host sees them enabled; summary is the mode name plus the map; the maxplayers warning appears when `bots.fill` exceeds slots (the T-8.2 case); "NEW" badge from the seen-set; the existing `lobby_ui.lua` cases still pass; mode badge text: `MODE.Short` if set, else the initials of `Name`.
- **U-6 map picker** (T-8.2): the map list is the maps that fit the mode; the selection is kept when it still fits, else the first; pager position for the focused row; thumbnail path from the map name; mode cycling with Q / E.
- **U-7 vote restyle** (T-7.7): one card per option, own vote marked, votes, turnout; timer formatting; `canPick` hides the "Pick myself" action; the existing `vote.lua` cases still pass.
- **U-8 HUD match status** (T-6.2): timer formatting from `pw_phase_end` and the victory/defeat decision (the T-6.2 cases); score order: own team first, leader second, FFA uses frags.
- **U-9 operator scene** (T-7.3): framing distance from bounds and FOV; model fallback when the model path is invalid (`models/error.mdl` is rejected).

Phase 11 — playtest follow-ups (added 2026-11-07; pure unless marked; the cases sit next to, and never replace, the cases above):

- **T-11.1 ARC9 finish** (T-3.6): ARC9's own HUD is hidden while the gamemode HUD is active and restored when the gamemode unloads; the stutter profile compares ARC9 against HL2 weapons and the result is written into `docs/perf-report.md` (a measurement, not a case); bots on `de_dust2_classic` get a navmesh (navgen result is loaded or generated) and in-game a bot leaves its spawn within the timeout.
- **T-11.2 Killstreak squares** (T-6.6/T-4.6 HUD): one square per streak in the set, ordered by cost; the bar fill fraction from kills or score against the streak costs; a square is lit exactly when the bar reaches its cost and not before; the selected streak is highlighted; key or gamepad hint only on ready streaks; an empty set draws nothing.
- **T-11.3 XP bar and level-up popup**: bar fraction from XP and the level curve; eased fill converges to the target and never overshoots; on level-up the fill goes to full and restarts for the new level; the LEVEL UP popup enters the same queue as medals and never overlaps a medal popup (order, expiry); the old LVL element is not registered.
- **T-11.4 Grenades as inventory items** (T-4.5): the built-in `frag` and `flash` give a grenade SWEP to the owner on spawn; count equals the SWEP ammo and refills on spawn; the slot key switches to the grenade and does not throw at once; holding attack cooks, the cook time is capped at about 3 s; throwing the last grenade returns to the previous weapon; dying while cooking drops the live grenade at the body with the remaining fuse (never below the minimum) and the thrower as the attacker (in-game); a bot switches to the grenade and throws it (in-game, smoke-level); a perk or wildcard that changes the equipment count changes the ammo.
- **T-11.5 Scoreboard rework** (U-8/T-6.2): own team first; per-team bar fraction is score / score limit, clamped to 1; the L-shaped outline length equals the full bar; FFA lists you and the leader, and you and second place when you lead; the timer is formatted from `pw_phase_end` (the existing T-6.2 cases still pass); Domination flag tiles are unchanged.
- **T-11.6 Bot combat movement** (T-5.10): under fire a bot chooses `take_cover` and alternates hide and peek; while firing at a visible target it strafes (intent contains lateral movement); between covers it runs (sprint intent); at close range it chooses melee and not a firearm; Quick Slide support is used only when the addon is detected and never when it is absent (stubbed detection, both branches); the slide intents fire for peek, dodge and closing distance only under their own conditions; in-game smoke: a bot under fire reaches a cover point within the timeout.
- **T-11.7 Stat-based unlock levels** (T-3.6, T-4.9): the power score is monotonic in each stat in the right direction (more damage and rate of fire raise it, more recoil and spread lower it); ranking within a category is stable and ties are broken deterministically; levels spread over 1..55 with 1-2 weapons per category open at level 1; attachment levels spread over 1..30 within a slot; an attachment without numeric stats gets the middle level of its slot and is counted in the report; the cache file is keyed by the weapon set and is reused when the set is unchanged and recomputed when it changes; registration is `soft`, so a hand-curated `Unlock` wins option by option; the host setting off falls back to unlock by count.
- **T-11.8 ARC9 performance profile**: the profile table maps `deck` to exactly the client values (tpik_others 0, lod_distance 0.4, cheapscopes 1, fx_rtvm 0, muzzle_others 0, eject_fx 0) and server values (`arc9_bullet_physics 0`, `arc9_ricochet 0`), and `off` to an empty table; `arc9.perf` defaults to `deck`; apply saves the original value of every touched ConVar before changing it and restore puts each back; crash safety: when the data file with saved originals exists at start (no clean ShutDown), the next start restores the saved values first and then applies the profile; a clean ShutDown deletes the file; applying twice does not overwrite the saved originals with profile values; a missing ConVar (ARC9 not installed) is skipped without error; the precache ConVars stay set after restore; the settings schema accepts an optional `description` and rejects a non-string one; a setting without `description` still validates; the SETTINGS screen model exposes the description when present (pure part).
- **T-11.9 Operator skin and bot names**: the skin list holds stock models, valid Workshop models (`player_manager.AllValidModels`) and owned economy `models`; locked entries carry their price and are not selectable; the default is `cl_playermodel` when valid, otherwise the first stock model; the net message validator rejects a non-string, an unknown model and a model not owned; a valid choice is stored and applied in `PlayerSetModel`; in team modes the player colour is set from the team (`SetPlayerColor`), in FFA it is not forced; a player with no choice gets the default; a bot gets a valid model and the choice differs between sessions (seeded random stub); bot names come from the pool of about 100 names, are unique within the game, never match `Bot%d+`, the pool file has no duplicates and no empty entries, and when the pool is exhausted a deterministic fallback keeps names unique; a name is released when a bot leaves and can be reused.
- **T-11.10 Match end and lobby flow**: (a) REGRESSION first: the postmatch results phase lasts `pw_postmatch_time` and does not advance to the lobby earlier (written and seen failing before the fix); after it, the next phase is VOTE or the lobby according to the aftermatch setting; (b) entering the post-match lobby hides or unspawns every player and bot body exactly as the first lobby does (same function, both paths tested); the operator panel stays available; (c) the START MATCH button label model returns a countdown string from the remaining seconds, clamps below zero and never shows the old "match starts from" text; the same formatter serves a pending map change; (d) map change: the server announces map, mode and end time; the clients' popup model holds the map's nice name and the mode, is visible until the end time and not after; the map changes only after the configured delay (`pw_mapchange_delay`, default about 5 s), not at once; a zero or negative delay is clamped to a minimum; announce and change use the same end time; (e) LEVEL UP popup clipping: the computed popup box contains the full text width at the maximum scale, at every scale step of the scale-in animation, and at 1280x720, 1280x800 and 1920x1080 (the box is computed from the measured text width plus padding, not from a fixed size).
- **T-11.11 Player vitals and weapon HUD** (user-approved 2026-11-08, `09` revision): health fractions at zero/half/full, clamp/out-of-range and invalid maximum; exactly three bounded continuous 50-armor segments at 0/25/50/75/100/125/150, overflow and negative; nickname above armor above health; on-screen left vitals/right weapon at 1280x720, 1280x800 and 1920x1080 without XP/equipment overlap; only LIVE/alive/non-spectating local-player data, never stale player/weapon snapshots; live name/clip/reserve, switch/empty/zero, invalid weapon, melee/no primary ammo and clipless finite reserve; localized and long UTF-8 names fit without byte splitting; hide only corresponding native panels while their replacement is active and successfully drawing, restore vanilla on HUD/module/element off, missing or error, preserve crosshair/killfeed. Existing T-6.1, T-6.4, T-11.3 and T-11.5 suites remain mandatory and unchanged. Mapping: `hud_vitals.lua` cases "Health fraction: zero half full clamp out-of-range and invalid maximum are safe", "Armor: exactly three bounded continuous segments at 0 25 50 75 100 125 150 overflow and negative", "Layout: nickname above armor above health; left/right anchors clear XP and equipment", "Lifecycle: only LIVE alive valid non-spectating local players show vitals or weapon" and all three "Native panels:" cases; `hud_weapon.lua` cases "Weapon: live name clip reserve update switch empty clip and zero reserve without stale data", "Weapon: melee no primary ammo clipless reserve and invalid counts never invent ammo", "Weapon: player replacement death spectator and weapon switch never reuse another snapshot", "Weapon: adapter display name and engine PrintName fallback are localized" and "Names: long localized UTF-8 nicknames and weapon names fit without byte splitting". Manual visuals require Deck screenshots and then user confirmation; automated success never passes the user's checkpoint.

## Agents and lanes

### Agent roles

| Role | Who | Responsibilities |
| --- | --- | --- |
| Orchestrator | Main Claude session with the user | Picks tasks, freezes contracts, spawns lane agents, merges, runs reviews, prepares checkpoints |
| Lane agent | `general-purpose` subagent, `isolation: worktree`, one per lane | Implements tasks of one lane on its own branch, TDD, only touches the lane's directories |
| Research agent | `general-purpose` subagent, background | Answers fact questions that appear during implementation, writes `notes/NN-*.md` |
| Reviewer | the orchestrator: scope check, mandatory test names, `make check` and `make test` re-run in the worktree; no review skill (user decision 2026-11-06) | Reviews every lane branch before merge |
| User | Human | Runs checkpoints in GMod, decides on design questions, approves PRs and pushes |

### Lanes and ownership

Each lane owns directories. A lane agent never edits another lane's files; cross-lane needs go through a contract change done by the orchestrator.

| Lane | Owns | Notes |
| --- | --- | --- |
| `core` | `gamemodes/privatewar/gamemode/core/`, `lua/privatewar/kinds/` (core kinds), test harness | Must land first; other lanes build on its contracts |
| `modes` | `lua/privatewar/modes/`, `lua/privatewar/playlists/`, `lua/privatewar/modules/teams/`, `modules/score/`, `modules/vote/` | |
| `map` | `lua/privatewar/maps/`, `modules/mapdata/`, `modules/spawns/`, `modules/navgen/` | |
| `weapons` | `lua/privatewar/weapon_adapters/`, `lua/privatewar/weapons/`, `modules/weapons_*`, integration addons `privatewar-arc9`, `privatewar-tfa`, `privatewar-mwbase` | |
| `loadout` | `modules/loadout/`, `modules/perks/`, `modules/throwables/`, `modules/streaks/`, `lua/privatewar/perks\|equipment\|streaks\|wildcards\|classes/` | |
| `progression` | `modules/progression/`, `modules/economy/`, `modules/medals/`, `lua/privatewar/score_events\|bundles\|models\|cards/` | |
| `bots` | `modules/bots_*`, `lua/privatewar/bot_behaviors\|bot_personalities\|bot_difficulties/` | Internally splits into sub-lanes (see Phase 5) |
| `ui` | `modules/ui_kit/`, `modules/hud/`, `lua/privatewar/hud/`, `lua/privatewar/screens/`, `modules/lobby_ui/` | Owns the widget kit, style and polish; runs in parallel from CP-1. Feature lanes build their own screen parts with the kit |

### Parallelism rules

1. **Contracts before parallel work.** Before lanes start in parallel, the orchestrator writes the API doc stubs of the contracts they share (`docs/api/*.md`: hook names and arguments, class table fields, blackboard fields). Changing a frozen contract needs the orchestrator.
2. **At most 3 lane agents at once.** More agents cost more than they save and make merges harder.
3. **One worktree branch per lane task**, merged to `main` through a PR after review. Never commit to `main` directly.
4. **Checkpoints are barriers.** All lanes stop at a checkpoint until the user reports the result.
5. **Research questions do not block lanes:** the lane continues with a stub plus a failing test documenting the expected behaviour, and a research agent answers in the background.

### Dependency graph (phases)

```text
P0 setup ──► P1 core (+ lobby v0) ──► CP-1 ──┬─► P2 modes+map ──► CP-2 ──────────────┐
                                           ├─► P3 weapons ─────► CP-3 ──┐           │
                                           │                            ├─► P4 loadout+progression ─► CP-4
                                           │                            │                              │
                                           │                            └──────────► P5 bots ─► CP-5a..CP-5e
                                           │
                                           └─► ui lane (parallel): style/polish of screens that features ship;
                                                 each feature lane builds its own screen part (lobby v0 from P1)
                                                                                             │
                                                                                 CP-6 ◄──────┘ (needs P5 too)
                                                                                    ▼
                                                                   P9 camera/audio ─► P10 release

D1..D4 design tasks: anytime; each blocks the phase it names.
```

**UI grows together with features:**

1. **Lobby v0 in Phase 1** (T-1.19): a minimal widget kit and a lobby screen to pick map and mode and start the match.
2. **Every feature task ships its own screen part.** Definition of done of a feature includes its UI: playlists add the playlist list, Game Setup is generated from settings schemas, loadout adds the class editor, weapons add the gunsmith, economy adds the store, and so on. There is no separate "UI later" phase and no throwaway debug UI.
3. **Style and polish** (D1 decisions, colour tokens, fonts, operator scene, animations) run in the `ui` lane in parallel and are applied to existing screens as they land.

## Design tasks still open

These are not implementation tasks. Each one blocks the phase named.

| Id | Topic | Blocks | Where |
| --- | --- | --- | --- |
| ~~D1~~ | Frontend: widget kit, fonts (open licence), operator scene, input (mouse/keyboard/gamepad). Decided 2026-11-07, see `design/10-frontend.md`; font files pending D4 | — | `design/10-frontend.md` d.3–d.13 |
| D2 | Camera and killcam: single `CalcView` owner, camera stack, killcam recording on the server | P9 | `design/11-camera.md` |
| D3 | Audio: announcer, music states, UI sounds, asset licensing | P9 | `design/12-audio.md` |
| ~~D4~~ | Licence of the gamemode: **GPL-3.0-or-later**. Decided 2026-11-07. Vendoring is allowed only for code under a GPL-compatible licence, with its notice in `THIRD_PARTY_NOTICES.md` | — | `LICENSE`, `THIRD_PARTY_NOTICES.md` |
| ~~D5~~ | Gamemode name: **Private War**, folder `privatewar`, Lua prefix `PW` (hooks `PW_*`, ConVars `pw_*`). Decided 2026-11-06 | — | — |

---

## Phase 0 — Setup

| Task | Lane · agent | Depends |
| --- | --- | --- |
| T-0.1 Git repository, branch policy, `.gitattributes` (vendored libs, research dumps as `linguist-vendored`/`linguist-documentation`), `.gitignore` for raw `.gma`/downloads | core · orchestrator | — |
| T-0.2 Repository layout: `gamemodes/privatewar/`, `lua/privatewar/`, integration addon folders, `docs/api/`, `tests/` | core · orchestrator | T-0.1 |
| T-0.3 `flake.nix` toolchain (see "Toolchain"): devShell with every tool; `-bin` packages for tools missing from nixpkgs, from release binaries only; GMod annotations and GLuaTest as pinned non-flake inputs; `nix flake check` runs lint + types + markdown; `.envrc` with `use flake`; editor setup doc | core · lane agent | T-0.2 |
| T-0.7 Quality gates that cannot be skipped, defined in the flake with `cachix/git-hooks.nix`: strict configs (`.glualint.json` all checks on, `.luarc.json` with type diagnostics as errors); `pre-commit` over the whole project = `glualint` + `lua-language-server --check` + `markdownlint-cli2` + `rules`; no automatic `pre-push` tests (user decision 2026-11-08); manual `make check` / `make test` acceptance/merge gates unchanged; hooks installed by the devShell, so every worktree gets them; a Claude Code `PostToolUse` hook on `Edit`/`Write` of `*.lua` running lint + type check on the changed file | core · lane agent | T-0.3, T-0.4 |
| T-0.6 Type definitions skeleton: `lua/privatewar/types/*.lua` `---@meta` files declaring the `PW` namespace and one class per kind (`PW.Mode`, `PW.Perk`, ...) plus the global class tables (`MODE`, `PERK`, ...) typed as those classes; grown by every task that adds API | core · lane agent | T-0.3 |
| T-0.8 Steam Deck dev loop (see "Dev loop on the Steam Deck"): `scripts/deck/` (`deploy.sh`, `cmd.sh`, `run.sh`, `logs.sh`, `dev.sh`), auto-detection of the GMod install (native Linux vs Proton, library on internal storage or SD card), dev-only `pw_devbridge` module (file command bridge, excluded from Workshop) | core · lane agent | T-0.2, T-0.3 |
| T-0.4 Test harness: GLuaTest. Local loop 1: GLuaTest addon in the dev server's `addons/`, tests run on server start / `pw_reload`. Local loop 2: `make test` = GLuaTest Docker runner (`docker/run_local.sh`, via Colima `nerdctl compose`; verify it runs on Apple Silicon). Optional CI later: GLuaTest reusable workflow on PRs | core · lane agent | T-0.2 |
| T-0.5 Dev loop doc: how to run a listen server with `maxplayers 12`, `lua_refresh_file`, `pw_reload`, screenshots | core · orchestrator | T-0.2 |

- Deliverable: empty gamemode that loads; `make lint test` green (GLuaTest runs at least one trivial case).

### CP-0 — gamemode loads

1. Start GMod → New Game → the gamemode, Max Players 12, P2P on.
2. Console shows the gamemode boot line, no Lua errors.
3. `make lint test` passes locally.

---

## Phase 1 — Core and extensibility

All tasks in lane `core`. One lane agent, sequential; the orchestrator freezes `docs/api/core.md` after T-1.3.

| Task | Depends | Tests first | Design |
| --- | --- | --- | --- |
| T-1.1 Kind loader: built-in kinds `kinds/` and `modules/`, SWEP-style global class tables, single-file and folder forms, `pcall` include, required fields check | T-0.4 | Pure: field validation, form detection on a fake file list | `01` d.8, d.15, d.16 |
| T-1.2 Registries: `Register/Get/GetStored/GetList`, deferred `Base` resolution, `Abstract`, replace on re-register, late registration with immediate `Base`, `soft = true` deep merge | T-1.1 | Pure: inheritance order independence, soft merge per nested key | `01` d.8, d.12; `04` d.3 |
| T-1.3 `PW_PreRegister` hook (patch / veto) for every registration | T-1.2 | Pure: veto, field patch, prefix bulk patch | `01` d.10 |
| T-1.4 Per-entity enable ConVars, snapshot on `LOBBY → PREMATCH` | T-1.2 | In-game self-test | `01` d.11 |
| T-1.5 Settings schema: types `int/float/bool/enum/set`, scopes `match/server/client`, full ids, inheritance, `SettingDefaults`, server clamp, match snapshot | T-1.2 | Pure: clamp, enum, set validation, inheritance | `01` d.17 |
| T-1.6 Hook dispatch: all `PW_*` via `hook.Call(name, PW.ActiveMode, ...)`; debug warning when a notification listener returns a value | T-1.2 | In-game self-test | `01` d.9 |
| T-1.7 Auto-subscription of `PW_*` methods with `IsValid`; `KIND.Subscribe` | T-1.6 | In-game self-test: disabled entity loses hooks | `01` d.18 |
| T-1.8 `PW.Call`: pcall, disable-until-map-change, profiler timings under `pw_profile` | T-1.2 | Pure: disable after error | `00` d.6; `01` d.15 |
| T-1.9 `PW.Instance`: `Hook`, `Timer`, `Remove`, end all on `PW_MatchEnd` | T-1.7, T-1.8 | In-game self-test: no leaked hooks/timers | `00` d.11 |
| T-1.10 Privileges + optional CAMI | T-0.4 | Pure: fallback to usergroup | `00` d.7 |
| T-1.11 `PW.Net.Receive` wrapper: privilege, phase, rate, length, log throttling | T-1.10 | Pure: rate limiter; in-game: rejected message logged once | `00` d.8 |
| T-1.12 Phase machine `LOBBY → PREMATCH → LIVE → POSTMATCH → VOTE`, transitions table, host abort, mode contract `Start/Cleanup/Think`, `PW.Match.Finish` | T-1.6, T-1.8 | Pure: transition table | `00` d.1–5; `02` d.7 |
| T-1.13 Phase networking: NW2 `pw_phase`, `pw_phase_end`, `pw_phase_seq`, client `PW_PhaseChanged`, local countdown | T-1.12 | In-game: late joiner sees phase | `00` d.10 |
| T-1.14 Map change: `pending_match.json`, validity checks, failed-changelevel fallback, client ready handshake with retry, bot reconciliation hook point | T-1.12 | Pure: validity rules | `00` d.9 |
| T-1.15 `pw_reload` (rescan kinds on server and clients), `GM:OnReloaded` | T-1.2 | In-game | `01` d.12 |
| T-1.16 `teams` module: `MODE.Teams = N`, `PW.Teams.GetActive`, `PW.IsEnemy`, assignment, balance, late join placement | T-1.12 | Pure: balance arithmetic, N teams | `02` d.6; `08` d.4 |
| T-1.17 Weapon registration phase: `PW_RegisterWeapons` → `PW_WeaponsLoaded` in `InitPostEntity` | T-1.2 | In-game | `04` d.3 |
| T-1.18 Kind fixtures as GLuaTest cases: one minimal entity per built-in kind, registered and validated in tests (also serve as documentation examples) | T-1.1 | — | `01` d.15 idea |
| T-1.19 Widget kit v0 (panel, button, list, generated settings form) and **lobby screen v0**: pick map and mode, Start; toggle the enable flags of entities, for the host and superadmins (`01` d.11), through a `PW.Net.Receive` message behind a privilege, not a console command. Match and server settings are changed only through the existing `pw_settings_match` (LOBBY only) and `pw_settings_server` messages. Known gap: the match settings snapshot (and the host's pending match values) is not replicated to clients yet, so a client's `PW.Setting` returns defaults for match settings. This is the first real screen, not a throwaway debug UI; later features extend it | T-1.4, T-1.5, T-1.11, T-1.12 | In-game | `08` d.3; `10` d.2; `01` d.11, d.17 |

### CP-1 — core works in the real game

How to run (dev addon `addons/privatewar-dev/` installed):

- Dev dummy mode `pw_dummy`: a match that does nothing and finishes itself; start it with the dev console command `pw_dev_start [map]` (dev addon only; the steps are listed in `pw_devstart.lua`).
- Lobby screen: opens in `LOBBY`; F1 or the console command `pw_lobby` closes and reopens it.
- Shorter timers: set the ConVars `pw_countdown` (PREMATCH countdown, default 10 s) and `pw_postmatch_time` (POSTMATCH, default 15 s), and restore them afterwards.
- Automated run: `nix develop --command ./scripts/deck/cp1.sh` runs every CP-1 check that needs no second human and prints PASS, FAIL or MANUAL for each item, then a summary. Evidence (log excerpts, screenshots, the summary) goes to `.deck-shots/cp1-<timestamp>/`.
  - `--no-restart` reloads the map instead of restarting the game; shadowing test 2 then becomes MANUAL, because a new legacy addon folder is mounted only at game start.
  - The script restores the ConVars it changed before its map change: archived ConVars are written to `cfg/server.vdf` only on a map change or a clean game exit, and `host_writeconfig` is blocked through the bridge.
  - MANUAL items (need a second human, an admin mod or real Workshop items): P2P guest follows `changelevel`, guest lobby without Start and toggles, late joiner, guest `pw_reload`, ULX/SAM privileges, shadowing tests with real Workshop items, and shadowing test 4 on a dedicated server with `sv_allowcslua 0`.

Checklist:

1. Load the gamemode with GLuaTest installed; all test groups pass in the server console.
2. Dummy mode cycles through all phases; countdown visible from `pw_phase_end`.
3. Change the map from the lobby: the new map comes up in `PREMATCH` (`notes/10` "To verify in game").
4. **P2P guest follows `changelevel`, and a new guest can join after it** (`notes/10` item 2, garrysmod-issues #6832). If it fails: apply the fallback in `00-core.md` d.9 and tell the orchestrator.
5. File shadowing tests from `notes/09-lua-file-shadowing.md` "To verify in game" (at least tests 1, 2 and 4).
6. Late joiner sees the correct phase and timer.

Passed on 2026-11-07 (user report: all items ok, including the P2P guest after changelevel; the map change fallback of 00-core.md d.9 is not needed).

---

## Phase 2 — Modes and map data

Two lanes in parallel: `modes` and `map`. Contract to freeze first: `docs/api/modes.md` (`MODE` fields, `BotObjectives` format), `docs/api/map.md` (`MAP` table, `PW.Map.GetModeData`, `PW.Spawns.Pick` opts).

| Task | Lane | Depends | Tests first | Design |
| --- | --- | --- | --- | --- |
| T-2.1 `score` module: `score_events/` kind, `PW.Score.Award`, `PW_ScoreEvent`, `PW_ScoreValue` | modes | CP-1 | Pure: value override | `06` d.3 |
| T-2.2 TDM and FFA modes. Note (found in T-1.16): `GM.TeamBased = true` in `shared.lua` makes the base `GM:PlayerSpawn` spawn a player without a team as a spectator; in FFA the teams module assigns no team, so FFA must handle spawning (here or in T-2.9) | modes | T-2.1 | Pure: win conditions | `02` d.5, d.7 |
| T-2.3 `round_base` abstract mode (rounds, side swap, `PW_RoundStart/End`) | modes | T-2.2 | Pure: round loop | `00` d.4 |
| T-2.4 Domination: flags, capture math (signed scalar), `MODE.MapData`, `ValidateMapData` | modes | T-2.2, T-2.7 | Pure: capture math | `02`; `03` d.6; README "worth stealing" |
| T-2.5 Kill Confirmed: tag entity (data-only, `TRANSMIT_ALWAYS`), pickup, confirm/deny | modes | T-2.2 | In-game | `02`; README |
| T-2.6 Playlists kind, host-saved JSON playlists, Custom, `bots.fill` setting placeholder | modes | T-2.2 | Pure: weighted sampling | `02` d.1–5b |
| T-2.7 `maps/` kind, `PW.Map.GetModeData`, auto-detect spawn entities (CS:S, HL2DM, TF2) | map | CP-1 | Pure: entity class mapping | `03` d.2–3 |
| T-2.8 Navmesh fallback: sample ~200 points at load, cache areas | map | T-2.7 | In-game | `03` d.3 |
| T-2.9 `spawns` module: candidates, scoring, hull check, spawn protection. Note (found in T-1.16): `GM.TeamBased = true` in `shared.lua` makes the base `GM:PlayerSpawn` spawn a player without a team as a spectator; in FFA the teams module assigns no team, so FFA must handle spawning (here or in T-2.2) | map | T-2.7, T-1.16 | Pure: scoring with fake enemies | `03` d.7 |
| T-2.10 `pw_mark` command | map | T-2.7 | — | `03` d.5 |
| T-2.11 Map list (data maps, PvP prefixes, host whitelist, junk filter) | map | T-2.7 | Pure: filter | `03` d.9 |
| T-2.12 Navmesh generation flow (seeds, marker file, fast mode, post-reload result) | map | T-2.8 | Pure: marker validation | `03` d.8; `notes/11` |
| T-2.13 Vote module (options from playlist, early end, no repeat, recent maps, host pick) | modes | T-2.6, T-2.11 | Pure: candidate selection | `08` d.5 |

### CP-2 — modes playable by humans

Use the lobby screen: lobby v0 with the generated Game Setup form (T-1.19) plus the playlist part shipped by T-2.6.

1. TDM and FFA with one friend (no bots) on a CS:S map and on `gm_construct`.
2. Domination on a map with a Lua data file made with `pw_mark`; Domination hidden on a map without data.
3. Kill Confirmed: tags spawn, confirm and deny score.
4. Spawns feel safe; no spawning inside players.
5. Navmesh generation on a map without `.nav` (`notes/11` "To verify in game", at least the basic run and the post-reload check).
6. Vote after a match; rotation and back-to-lobby both work.

---

## Phase 3 — Weapons

Lane `weapons`. Can run in parallel with Phase 2. Contract to freeze first: `docs/api/adapter.md` (from `notes/08` §5 plus stat-mod methods).

| Task | Depends | Tests first | Design |
| --- | --- | --- | --- |
| T-3.1 `weapon_adapters/` kind, adapter lookup by class (`Claims`, `Priority`), defaults for every optional method | CP-1 | Pure: priority resolution | `04` d.1 |
| T-3.2 Fallback adapter for plain SWEPs and HL2 weapons | T-3.1 | Pure | `04` |
| T-3.3 `weapons/` kind usage: declarative entries, `soft` programmatic registration, per-weapon ConVars, attachment/camo curation fields | T-3.1, T-1.17 | Pure: curation merge | `04` d.3; `06` d.2 |
| T-3.4 Ammo owned by the core (`SuppressDefaultAmmo`, `GetAmmoType`) | T-3.1 | In-game | `notes/08` §5 |
| T-3.5 Stat modifiers: `PW.SetStatMods`, `PW.GetStatMod`, revision refresh loop | T-3.1 | Pure: revision logic | `04` d.6 |
| T-3.6 ARC9 integration addon (module + adapter): lock customization, `nocustomize`, catalogue, `Apply`, stat mods, bot shims | T-3.3–T-3.5 | In-game | `04` d.2, d.4, d.6; `notes/08` §2, §6.2 |
| T-3.7 TFA integration addon | T-3.3–T-3.5 | In-game | `notes/08` §4, §6.4; `notes/12` |
| T-3.8 MW Base integration addon | T-3.3–T-3.5 | In-game | `notes/08` §3, §6.3; `notes/12` |

- T-3.6, T-3.7 and T-3.8 can run as three parallel worktrees (still at most 3 agents total).

### CP-3 — weapons in real packs

1. One real pack per base installed; catalogue lists their weapons with categories.
2. A build with attachments applies on spawn; native customization menus are blocked.
3. Stat modifiers (reload, draw, ADS) visibly change timings on all three bases (`notes/12` §8).
4. Risks from `notes/08` §7: two bots with different builds of the same ARC9 class; TFA client restore blocked; bot viewmodel on TFA.

---

## Phase 4 — Loadout, progression, economy

Lanes `loadout` and `progression` in parallel after CP-3 (loadout needs adapters).

| Task | Lane | Depends | Tests first | Design |
| --- | --- | --- | --- | --- |
| T-4.1 Slot declarations, loadout table, validation, `PW_ValidateLoadout`, `PW_PlayerLoadout` | loadout | CP-3 | Pure | `05` d.1 |
| T-4.2 Pick X budget, `Cost`, `PW_LoadoutCost`, `maxattachments`, bans (`set` settings) | loadout | T-4.1 | Pure: budget arithmetic | `05` d.2–3, d.7 |
| T-4.3 Wildcards kind, `ModifySlots` | loadout | T-4.2 | Pure | `05` d.5 |
| T-4.4 Perks: groups, `PERK.Stats`, `PW.Stat`, events, instances | loadout | T-4.1, T-1.9 | Pure: stat multiplication | `05` d.4, d.8 |
| T-4.5 Equipment: slot keys, `OnUse`, `throwables` module (`PW.Throw`), frag/flash sample items | loadout | T-4.1 | In-game | `05` d.11 |
| T-4.6 Killstreaks: earning by kills/score, inventory, activation instances; UAV, Counter-UAV, airstrike; `PW.Reveal` | loadout | T-4.1, T-2.1 | Pure: streak counting rules | `05` d.9–10 |
| T-4.7 Classes: client `classes.json`, upload on join, repair, presets kind | loadout | T-4.1 | Pure: repair | `05` d.12–13 |
| T-4.8 Gunsmith server flow (validate on save, apply on spawn, repair on conflict) | loadout | T-4.7, CP-3 | In-game | `05` d.15 |
| T-4.9 Progression: XP from score events, weapon XP, curves, unlock rules (curated or by count), `unlockall` | progression | T-2.1 | Pure: curves, unlock by count | `06` d.1–2, d.4 |
| T-4.10 Progression storage and 10 s deltas, postmatch summary data | progression | T-4.9 | Pure: delta apply | `06` d.5 |
| T-4.11 Medals module (double/triple kill, revenge, first blood, 5-streak, saviour) | progression | T-2.1 | Pure: detectors | `06` d.3 |
| T-4.12 Economy: currency, `Price`, purchases, bundles kind, date-seeded rotation, `models/` and `cards/` kinds | progression | T-4.9 | Pure: deterministic rotation | `06` d.6 |

### CP-4 — a full human match loop

Use the class editor, gunsmith and store screens shipped by the Phase 4 tasks.

1. Edit a class (Pick 10), save, spawn with it; a playlist with a lower budget marks the class unavailable.
2. Perks work (one stat perk, one event perk, one custom-hook perk); no leaks after death (instances).
3. Equipment keys throw grenades; UAV reveals on radar; airstrike hits.
4. XP and weapon XP grow; levels unlock items; `unlockall` works; store purchase unlocks an item early.
5. Rejoin: classes and progression came back from the client files.

---

## Phase 5 — Bots

Lane `bots`, split into sub-lanes that can run in parallel once the blackboard contract (`docs/api/bots-blackboard.md`, `07` d.16) is frozen. At most 3 sub-lane agents at once.

| Task | Sub-lane | Depends | Tests first | Design |
| --- | --- | --- | --- | --- |
| T-5.0 Blackboard contract doc, `PW_Bot*` hooks list | orchestrator | CP-1 | — | `07` d.3, d.16 |
| T-5.1 Manager: quota `bots.fill`, create/kick, team via `teams`, reconciliation after `changelevel`, Singleplayer refusal | manager | T-5.0 | Pure: quota arithmetic | `07` d.3; `00` d.9 |
| T-5.2 Input writer in `GM:StartCommand`: intents → `CUserCmd`, adapter `GetInputRules`, weapon select | input | T-5.0, CP-3 | In-game scripted intents | `07` d.3; `notes/08` §6 |
| T-5.3 Scheduler: ms budget, random phase, global FIFO, perf counters | scheduler | T-5.0 | Pure: budget slicing | `07` d.3 |
| T-5.4 Debug overlay (behaviour, reason, target, goal, path) | scheduler | T-5.3 | — | `07` d.11 |
| T-5.5 Navigation: vendored `binaryheap.lua`, time-sliced A*, partial paths, unreachable cache, cost layers baked per second | nav | T-5.3 | Pure: A* on a synthetic graph | `07` d.6 |
| T-5.6 Goal API `SetGoal(point, radius, priority)`, goal wrapper, path follower, stuck ladder, doors and ladders | nav | T-5.5, T-5.2 | Pure: priority arbitration | `07` d.6 |
| T-5.7 Perception: FOV, multi-point LOS, reaction queue, hearing, contact memory + 5-point search, damage awareness, team sharing, `PW.Bot.AddStimulus` | perception | T-5.3 | Pure: reaction queue, memory decay | `07` d.7 |
| T-5.8 Aim controller: spring-damper, focus error, lead, headshot gating, recoil gain, fire-when-steady, line-of-fire gate | aim | T-5.2 | Pure: controller math | `07` d.8 |
| T-5.9 Brain: dual-utility selection, Action stack, commitment, intervals | brain | T-5.0 | Pure: selection and screening | `07` d.4–5 |
| T-5.10 MVP behaviours (11) | brain | T-5.9, T-5.6–T-5.8 | Pure where possible | `07` d.13 |
| T-5.11 Commander: objectives from `MODE:BotObjectives`, assignment, rebalance, hunt slots | brain | T-5.9, T-2.4, T-2.5 | Pure: assignment | `07` d.9, d.14 |
| T-5.12 Personalities and difficulty kinds, default tiers | brain | T-5.9 | Pure: table completeness (every field read) | `07` d.10, d.15 |
| T-5.13 Bot loadouts (presets + players' pool), streak and equipment use | brain | T-4.6, T-4.7, T-5.10 | Pure: class pool | `05` d.14 |

### Bot checkpoints

| Checkpoint | After | What the user checks |
| --- | --- | --- |
| CP-5a | T-5.1–T-5.4 | Bots join, take slots, get kicked when humans join; scripted bot walks, aims, fires, reloads with ARC9/TFA/MW weapons |
| CP-5b | T-5.5–T-5.6 | Bots navigate a CS:S map and `gm_construct` without getting stuck for long; debug overlay shows paths |
| CP-5c | T-5.7–T-5.8 | Bots notice, react with a delay, track and hit believably; no wallhacks; difficulty tiers feel different |
| CP-5d | T-5.9–T-5.12 | Full TDM/FFA vs bots solo: bots take cover, search, flank, third-party; at most 1–2 hunt the solo player |
| CP-5e | T-5.11, T-5.13 | Domination and Kill Confirmed vs bots: objective play; bots use streaks and grenades; load test 16–24 bots within budget (profiler) |

---

## Phase 6 — HUD

Lane `ui`. T-6.1–T-6.3 can start right after CP-1 (P6a), the rest after their data sources exist.

| Task | Depends | Design |
| --- | --- | --- |
| T-6.1 `hud/` kind, single `HUDPaint` over the registry via `PW.Call`, 1920×1080 scaling | CP-1 | `09` d.3 |
| T-6.2 Match status (scores, local timer), phase messages, victory/defeat | T-6.1 | `09` d.2 |
| T-6.3 Hitmarker | T-6.1 | `09` d.2 |
| T-6.4 Score popups and medals | T-6.1, T-2.1, T-4.11 | `09` d.2 |
| T-6.5 Domination points element (in the mode) | T-6.1, T-2.4 | `09` d.2 |
| T-6.6 Radar with UAV/Counter-UAV states | T-6.1, T-4.6 | `09` d.2 |

---

## Phase 7 — Frontend (`ui` lane, parallel from CP-1; needs D1)

Visual reference: `design/visual-prompts/`. Not a final phase. Each screen below is built **inside the feature task that produces its data** (by that lane's agent, with the `ui` kit); the `ui` lane owns the kit, style and polish. The table lists where each screen belongs.

| Task | Depends | Design |
| --- | --- | --- |
| T-7.1 Widget kit, colour tokens, fonts, scaling, router | CP-1, D1 | `10` d.2 + D1 |
| T-7.2 Settings forms generated from schemas (Game Setup, host settings, client settings) | T-7.1, T-1.5 | `01` d.17 |
| T-7.3 Operator/weapon scene (lobby, class editor, gunsmith, store) | T-7.1, CP-3 | D1 |
| T-7.4 Classes and gunsmith screens | T-7.3, T-4.8 | `05` |
| T-7.5 Store, bundle details, progress screens | T-7.3, T-4.12 | `06` |
| T-7.6 Death class picker, pause menu | T-7.1, T-4.7 | `10` d.1 |
| T-7.7 Postmatch summary and vote screens | T-7.1, T-4.10, T-2.13 | `08` d.5 |

### UI rework (D1 decided; plan from `notes/16-frontend-d1-proposal.md` §5)

Lane `ui`. Order: kit v1 (U-1..U-4) → CP-UI1 → screens. Each `U-n` is a slice of an existing task, not a new phase. Tests first; drawing is checked at checkpoints. The `screens/` kind file (`lua/privatewar/kinds/screens.lua`) belongs to the core lane: the orchestrator adds it before U-3.

| Task | Slice of | Deliverable | Depends | Design |
| --- | --- | --- | --- | --- |
| U-1 Tokens, fonts, scaling | T-7.1 | `PW.UI.Style` v1 with every palette token; font families in one place (built-in GMod fonts until D4, then Fira); `PW.HUD.Font` with a family argument and `extended = true`; font ladder; fallback chain | CP-1 | `10` d.4, d.5, d.13 |
| U-2 Layout, focus, input | T-7.1 | `PW.UI.Layout.Columns`, `PW.UI.Focus`, `PW.UI.Input` (pure, shared) | U-1 | `10` d.3, d.7 |
| U-3 Router and root | T-7.1 | `PWRoot` popup, tab stacks, Back, `OnPauseMenuShow` suppression while open, `screens/` kind | U-2 | `10` d.3, d.8 |
| U-4 Components v1 | T-7.1 | Title, tab bar, status line, card list and cards, info cards, summary, player list, hint bar, button v1, pager, form controls v1, warning chip, backdrop, dialog, timer (note 16 §3, items 1–3, 5–15, 18–20) with models | U-3 | `10` d.3, d.5, d.9, d.10 |
| U-5 Hub and custom game | T-8.1 | `lobby_ui` hub (PLAY / LOADOUT / PROGRESS / STORE) and Custom game screens on the kit; v0 frame removed | CP-UI1, U-4, U-9 (placeholder until T-7.3) | `10` d.8, d.9 |
| U-6 Map picker | T-8.2 | Map picker screen with the pager and mode cycling | U-5 | `10` d.3 |
| U-7 Vote restyle | T-7.7 | Vote screen on vote cards; "Pick myself" opens the picker in pick mode | CP-UI1, U-4, U-6 | `10` d.3 |
| U-8 HUD match status | T-6.2 | `hud/match_status.lua` and phase messages replacing `phase_label.lua` | T-6.1, U-1 | `09` d.2 |
| U-9 Operator scene | T-7.3 | `PWOperator` with our own lights and idle pose; weapon after CP-3 | U-4 | `10` d.6 |

### CP-UI1 — the kit on the Deck

Barrier after U-1..U-4, before the screens are rewritten (U-5..U-7). Stop all `ui` lane work; the user looks at the kit in GMod and reports.

1. The kit demo screen on the Steam Deck at 1280×800 and at 1920×1080: nothing is clipped or distorted, the smallest text (22 design units) is readable on the 7-inch screen.
2. Keyboard focus navigation: arrows and W A S D move the focus, Enter activates, Esc goes back, Q / E switch tabs, PgUp / PgDn page lists; one highlight only (hover and keyboard share it); locked items are focusable and explain themselves.
3. Button hints: the hint bar shows the right actions, follows the last used device, and the `pw_ui_hints` override works; native gamepad (if any) is noted, not required.
4. Palette and contrast: all tokens as decided in `design/10-frontend.md` d.5; `text_muted` readable over a bright map with the scrim on; states (normal, focused, selected, disabled, locked) distinguishable.
5. Scaling: layout at 1920×1080, 1280×800 and an ultrawide if available; the fonts are the built-in ones through the family indirection (Fira files wait for D4).

## Phase 8 — Lobby UI (`ui` lane, parallel)

| Task | Depends | Design |
| --- | --- | --- |
| T-8.1 Lobby hub screen (operator, party list, playlist chip, start/ready) | T-7.3 | `08` d.3 |
| T-8.2 Play screen and Game Setup (playlists, Custom), maxplayers warnings | T-7.2, T-2.6 | `08` d.2; `02` d.4 |
| T-8.3 Entry hints (Singleplayer screen, P2P hint), recommended `.cfg` | T-7.1 | `08` d.2 |
| T-8.4 Join in progress / spectate setting | T-1.16 | `08` d.4 |

### CP-6 — the "real game" checkpoint

1. Solo: start New Game with 12 slots → lobby → pick a playlist → match vs bots → postmatch → vote → next match.
2. With a friend over P2P: join from Steam, join in progress, leave mid-match (bot replaces).
3. Screenshots of every screen compared with the visual prompts.

---

## Phase 9 — Camera and audio (after D2, D3)

Tasks are written when D2 and D3 are decided. Expected scope: single `CalcView` owner with a camera stack, lobby orbit, intro, spectate, killcam (server-side ring buffer); announcer queue, music states, UI sounds.

### CP-7 — juice

Killcam plays after death; announcer lines and music transitions in the right moments.

## Phase 10 — Release

| Task | Depends |
| --- | --- |
| T-10.1 Licence file (D4), third-party notices (`binaryheap.lua` MIT). Done 2026-11-07 (branch `chore/license-gpl`): `LICENSE` (GPL-3.0-or-later), `THIRD_PARTY_NOTICES.md`, both shipped in every Workshop addon | D4 |
| T-10.2 Workshop packaging: gamemode addon with `lua/privatewar/` built-in content; integration addons per weapon base; **exclude `lua/tests/`, `lua/privatewar_fixtures/` (test fixtures and examples) and the whole dev addon `addons/privatewar-dev/` (devbridge, testgate, dummy mode, `pw_dev_start`), not only `pw_devbridge`** (tests are not shipped; GLuaTest is a dev-only tool); the examples in `lua/privatewar_fixtures/examples/` may be published separately as author docs; ship `lua/privatewar/types/` for addon authors (or publish it separately) | all |
| T-10.3 Player docs: how to start solo with bots, how to host for friends, how to write a mode/perk/behaviour (docs from the API stubs) | all |
| T-10.4 Final load test and profiler pass | CP-6 |

### CP-8 — release candidate

Fresh Steam account subscribes from the Workshop, starts solo with bots following only the in-game hints, and plays a full match without errors.

## Phase 11 — Playtest follow-ups (2026-11-07)

Source: the first playtest of the game loop on 2026-11-07 ("it plays"), decisions approved by the user in chat. Decisions are in `design/05-loadout.md` d.11 (revision), `design/06-progression.md` d.2 (revision), `design/07-bots.md` d.13 (revision) and `design/09-hud.md` (revision); the details first taken by recommendation (the local manual checklist (not published) section 7, items 64-67) were confirmed by the user on 2026-11-07, with one change: dying while cooking drops the live grenade (item 66.3). Older branch and merge references record pre-snapshot history. Current implementation and follow-up status for T-11.8 to T-11.10 is recorded below; inspect current code and task branches before starting work.

| Task | Lane | Depends | Tests first | Source decision | Status |
| --- | --- | --- | --- | --- | --- |
| T-11.1 ARC9 finish: hide ARC9's HUD, profile the periodic stutter (ARC9 vs HL2 weapons), fix bots standing still on `de_dust2_classic` (navmesh/navgen). Branch `task/T-3.6-arc9-finish` (from `task/T-3.6-arc9` and `main`) | `weapons` (navgen part: `map`) | T-3.6 | Pure + In-game | playtest 2026-11-07; `04` d.2 | done (merged `6d0afad`) |
| T-11.2 Killstreak HUD squares. Branch `feat/hud-streaks-squares` | `ui` | T-6.6, T-4.6 | Pure | `09` revision 1 | done (merged `c24cb42`) |
| T-11.3 XP bar and LEVEL UP popup (old LVL element removed). Branch `feat/hud-xpbar-levelup` | `ui` | T-6.4, T-4.9 | Pure | `09` revision 2 | done (merged `73b43c3`) |
| T-11.4 Grenades as inventory items (SWEPs); G and 4 switch to the grenade, hold attack to cook, count = ammo; bots switch and throw | `loadout` (bot use: `bots`) | T-4.5, T-5.13 | Pure + In-game | `05` d.11 revision (details confirmed 2026-11-07; death drop added) | done (merged `f09c2eb`) |
| T-11.5 Scoreboard rework: match status top left under the radar, team bars with L-shaped outline, FFA leader | `ui` | T-11.2, T-11.3 (same HUD area; avoid merge conflicts) | Pure | `09` revision 3 | done (merged `44c7d69`) |
| T-11.6 Bot combat movement: cover under fire and peeking, strafing, running between covers, melee at close range, optional Quick Slide support (public API only, off when absent) | `bots` | T-5.10 | Pure + In-game smoke | `07` d.13 revision (numbers confirmed 2026-11-07) | done (merged `fcedf95`) |
| T-11.7 Stat-based default unlock levels (weapons 1..55, attachments 1..30), cached per map, registered `soft`, host switch; starting with ARC9 | `weapons` / `progression` | T-11.1 merged | Pure | `06` d.2 revision (formula weights confirmed 2026-11-07) | done (merged `ed225db`) |
| T-11.8 ARC9 performance profile ("optimisation first": the Steam Deck is the target hardware, integrations default to performance, quality is opt-in). Setting `arc9.perf` = `deck` (default) or `off`. `deck` sets the client visual ConVars from `docs/perf-report.md` (`arc9_tpik_others 0`, `arc9_lod_distance 0.4`, `arc9_cheapscopes 1`, `arc9_fx_rtvm 0`, `arc9_muzzle_others 0`, `arc9_eject_fx 0`; check the exact ConVar names in the ARC9 install) and the server ConVars `arc9_bullet_physics 0` (hitscan) and `arc9_ricochet 0`. Penetration (`arc9_mod_penetration`): measure on the Deck (TDM, about 9 bots, 120 s with it on vs off, through the profiler); turn it off in the profile only if it adds more than 0.5 ms to the average server Lua time or raises p99/max noticeably, and write the numbers into `docs/perf-report.md`. The profile applies while the mode runs and is restored on ShutDown; crash-safe: the original values are saved in a data file and restored at the next start if no clean ShutDown happened. The precache ConVars stay set. The settings schema gets an optional `description` field shown on the SETTINGS screen (approved). Original branch: `feat/arc9-perf-profile` | `weapons` (schema and SETTINGS screen part: `ui`/`core`) | T-3.6, T-11.1 | Pure + Deck measurement | "Optimisation first" principle (user, 2026-11-07) | implemented in initial public snapshot; all mandatory cases exist; penetration measured and kept on |
| T-11.9 Operator skin and bot names. Today no player model is set, so everyone is the base grey model. One global operator skin per player: the list holds stock models, Workshop models (`player_manager.AllValidModels`) and owned economy `models`; locked ones show their price; the default is `cl_playermodel` if valid; it is a client setting plus a picker with a preview; a validated net message sends it; the server checks valid and owned and applies it in `PlayerSetModel` with the team colour (`SetPlayerColor`) in team modes. Bots get a random valid model per session. Bots get human-like names from a pool of about 100 original names (no real people, no copyrighted characters), unique in the game, never "BotNN"; the pool lives in a data file. Original branch: `feat/operators-bot-names` | `loadout` / `ui` (bot names and models: `bots`) | T-4.12, T-7.5 | Pure + In-game smoke | playtest 2026-11-07 | implemented in initial public snapshot; independently verified correction included in current change set (`task/T-11.9-operators-names-fix`) |
| T-11.10 Match end and lobby flow. (a) BUG: the postmatch results screen jumps to the lobby instantly; it must stay for `pw_postmatch_time`, then go to VOTE or the lobby per the aftermatch setting; a test reproduces the bug first. (b) In the post-match lobby unspawn or hide all player and bot bodies, identical to the first lobby; the lobby operator panel stays. (c) Replace the "match starts from ..." text with a countdown on the START MATCH button (green text, dark button background); the same countdown is used for a pending map change. (d) A map change is not instant: show a popup "MAP CHANGE" with the map's nice name and the mode for a configurable time (default about 5 s), then change the map; the server announces map, mode and end time to clients. (e) The LEVEL UP popup renders clipped, so the text does not fully fit; the code is `lua/privatewar/hud/popups.lua` and `modules/hud/sh_popups.lua` / `sh_xpbar.lua` with a scale-in animation; the Deck runs at 1280x720. The whole text must fit at every scale step and at 1280x720, 1280x800 and 1920x1080. Original branch: `fix/match-flow-lobby` | `core` / `ui` | T-7.7, U-5 | Pure + In-game | playtest 2026-11-07 | initial implementation in public snapshot; follow-up required: reconcile mandatory cases and existing contracts |
| T-11.11 Player vitals and active weapon HUD: bottom-left nickname / three armor segments / health; bottom-right localized weapon name and clip / reserve; replace native health/ammo only while custom elements are active; preserve XP and grenade equipment. Branch `task/T-11.11-player-weapon-hud` | `ui` | T-6.1, T-11.3, T-11.4, T-11.5 | Pure + Deck visual + user checkpoint | user-approved `09` revision 2026-11-08 | automated: retrospective tests-only red 0/13/0, target green 13/0/0, full green 1395/0/0 (passed/failed/skipped); 1280x720 screenshots reviewed, 1920x1080 capture blocked by the engine video-command restriction; user visual checkpoint pending |

### Known follow-ups (not scheduled; some need a user decision)

1. Remaining hot spots of `docs/perf-report.md`:
   - the bot class pool costs 14-26 ms per bot death: needs a contract change in `docs/api/bots-blackboard.md` item 13 (orchestrator);
   - scheduler tasks reach 15-20 ms per call;
   - allocations in `HUDPaint` (client, 50-95 KB/s).
2. Airstrike kills give weapon XP to the weapon in hand. Needs a decision.
3. There is no localisation file for medal and score event names. Needs a decision.
4. Lobby leave dialog: the default button is LEAVE GAME now (Esc then Enter disconnects); CANCEL is recommended. Default button: pending confirmation.
5. `testgate` backs up the match ConVars (`pw_prematch_timeout`, `pw_countdown`, `pw_postmatch_time`, since T-11.8 also `pw_aftermatch` and `pw_vote_time`) when a run starts and restores them at the end of every run (T-11.8) and on the next map load after an interrupted run (done in `chore/phase11-sync`).
6. `scripts/deck/lock.sh` needs GNU coreutils: run the Deck scripts through `nix develop --command` (also noted in the handover section).
7. Prewarm bot weapons in PREMATCH to avoid ARC9 first-`Give` hitches (needs a user decision).
8. DOM flag tiles may move up to y≈20 now that the top centre is free (needs a user decision).
9. Done (`fix/client-include-errors`): "Couldn't include file" on the client at every map load. Five bot modules (`bots_brain`, `bots_nav` with its `binaryheap.lua`, `bots_objectives`, `bots_commander`, `bots_perception`) included `sh_` files from `shared.lua` without `AddCSLuaFile`. Fixed, and `scripts/check/rules.sh` rule 4 now fails a top-level include in a shared file that has no matching `AddCSLuaFile`.
10. Vendor Fira Sans (OFL 1.1, GPL-compatible as a font) now that D4 is decided: the font files, `resource.AddFile` / `AddWorkshop`, the family names in `PW.UI.Style` (`design/10-frontend.md` d.4) and an entry in `THIRD_PARTY_NOTICES.md`. Not started.

### Done (historical pre-snapshot record, 2026-11-07)

- Phase 4: T-4.3 (wildcards), T-4.4 (perks), T-4.6 (killstreaks), T-4.8 (gunsmith flow), T-4.9 (progression), T-4.10 (storage and deltas), T-4.11 (medals), T-4.12 (economy).
- Phase 5: T-5.13 (bot loadouts).
- Phase 6: T-6.4 (score popups and medals), T-6.5 (Domination points), T-6.6 (radar).
- Phase 7: T-7.2 (settings screen), T-7.4 (classes and gunsmith screens), T-7.5 (store and progress screens), T-7.6 (death class picker, pause menu), T-7.7 (postmatch summary).
- Phase 10: T-10.1 (licence GPL-3.0-or-later and third-party notices, branch `chore/license-gpl`), T-10.2 (packaging), T-10.3 (player docs), T-10.4 (load test, profiler, `docs/perf-report.md`).
- Phase 11: T-11.1 (ARC9 finish), T-11.2 (streak squares), T-11.3 (XP bar and LEVEL UP), T-11.4 (grenades as inventory SWEPs), T-11.5 (score bars). Also done: T-11.6 (bot combat moves, `fcedf95`), T-11.7 (stat-based unlocks, `ed225db`), the ARC9 bot bash with model precache at map load (`58b51b9`) and the cooked frag drop on death (`3066b27`). T-11.8 (ARC9 perf profile) is implemented in the initial public snapshot. T-11.9 and T-11.10 also have initial implementations there; see their Phase 11 rows for the verified T-11.9 correction in the current change set and the required T-11.10 follow-up.
- Fixes merged: bot respawn in FFA, `classes.json` digit-only slot keys, Deck client reload through `snap.sh`, dev profiler probes; also the lobby Esc leave dialog and gamepad d-pad for streaks and equipment.

### Blocked on the user

- T-3.7 TFA and T-3.8 MW Base integrations: the weapon bases are not installed on the Deck.
