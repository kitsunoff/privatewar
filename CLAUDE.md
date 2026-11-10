# Private War

A casual "modern CoD in Garry's Mod" gamemode: solo or with a few friends against bots that feel alive, on player-hosted listen servers. Folder `privatewar`, Lua prefix `PW` (hooks `PW_*`, ConVars `pw_*`).

## Read in this order

1. `DESIGN.md`: goal, philosophy, global rules, subsystem table with statuses.
2. `design/NN-*.md`: one file per subsystem. Decisions are numbered; cite them as `<file> d.<n>` (for example `01-extensibility.md` d.16).
3. `TASKS.md`: the implementation plan: phases, tasks, human checkpoints (`CP-*`), lanes and agent roles, open design tasks (`D1`–`D4`; `D1`, `D4` and `D5` are decided).
4. `notes/NN-*.md`: research. Research explains *why*; it is not a decision. When research and `design/` disagree, `design/` wins.

Superseded material (do not follow): the DHTML recommendation in `notes/20-ui-tooling.md`.

Handover for a new agent (including Codex): `AGENTS.md`, then `TASKS.md` "How to continue (handover)" and "Phase 11" (current queue).
Practical coding workflows: `AGENTS.md` "Coding skills" and `docs/agent-workflow.md`; exact regression references:
`docs/agent-test-map.md`. Skills guide implementation but do not authorize code, device access or publication.

## Repository layout

- `addons/privatewar/`: the gamemode addon (`gamemodes/privatewar/`, `lua/privatewar/`, `lua/tests/`, `lua/privatewar_fixtures/`, `addon.json`). Paths such as `lua/privatewar/...` in `DESIGN.md`, `design/`, `docs/` and `TASKS.md` are relative to this folder, the same paths GMod sees in the game.
- `addons/privatewar-arc9/`: the ARC9 weapon integration. Other `addons/<name>/` folders may be optional content
  (for example Infection), integrations or development tooling; inspect each addon's purpose before copying it.
- `addons/privatewar-dev/`: the dev-only bridge addon (never shipped; deployed to the Deck as `addons/privatewar_dev`).
- Tooling: `scripts/` (gates, Deck loop, packaging), `tests/gates/` (gate fixtures), `nix/`, `flake.nix`, `Makefile`, `cfg/`.

## Working rules

1. **Decided means decided.** Do not change a decision in `design/` without the user's explicit approval. If implementation shows a decision is wrong, stop and raise it.
2. **Open design questions go to the user.** Do not invent answers for `D1`–`D4` or for anything marked open; ask.
3. **TDD with GLuaTest; the cases in `TASKS.md` "Mandatory test cases" are obligatory** (a task is not done without them; never drop or weaken them). Tests first, in `addons/privatewar/lua/tests/privatewar/*.lua`, using GLuaTest (`CFC-Servers/GLuaTest`): `expect`, `stub`, async cases. Tests run in a real GMod server (dev server `addons/` or the Docker runner). What tests cannot cover goes to checkpoints. See `TASKS.md`, "Testing".
4. **Thin glue.** Write logic as pure functions over plain data; keep engine calls (`ents.Find*`, traces, `draw.*`, `net.*`) in thin wrappers. Put testable client logic in `sh_` files so the server-only test runner covers it. Bot scenario tests: few, smoke-level, generous timeouts. Coverage targets per area: `TASKS.md`, "Coverage strategy".
5. **Checkpoints are barriers.** At a `CP-*`, stop all lanes and hand the checklist to the user; the user tests in GMod and reports.
6. **Lanes own directories** (`TASKS.md`, "Lanes and ownership"). A lane agent never edits another lane's files; shared contracts in `docs/api/` change only through the orchestrator.
7. **At most 3 parallel lane agents**, each in its own git worktree branch; merge to `main` only through a reviewed PR.
8. **Every feature ships its own UI part** (`TASKS.md`, "UI grows together with features").
9. **Linters and type checker are mandatory, never bypassed.** Tools come only from `flake.nix`; run them as `nix develop --command <cmd>` (agent shells are non-interactive, direnv may not load). `pre-commit` runs `glualint`, `lua-language-server --check`, `markdownlint-cli2` and `rules` over the whole project; a Claude Code hook checks every `.lua` edit. By user decision (2026-11-08), no automatic `pre-push` GLuaTest hook is installed: pushing must not require Deck access. Manual `make check` and `make test` gates before acceptance/merge remain mandatory. Never commit or push with `--no-verify`, never disable a rule inline or in config without the user's approval and a written reason; fix the code instead. Never build tools from source: a tool missing from nixpkgs is a `<name>-bin` package from its release binary (`TASKS.md`, "Toolchain"). **Typed and lint clean before commit.**
10. **Publishing and language.** Public text (code, comments, docs, commits) is English only. Private content, including the local manual checklist listed in `scripts/export/local-only.txt`, must stay outside the public repository and any published tree; the checklist may be written in the maintainer's language. The export tooling is optional, not the development workflow (`docs/publishing.md`).
11. **Canonical development repository:** this repository (`kitsunoff/privatewar`). Develop directly here on feature branches; never commit or merge locally on `main`. Changes reach `main` only through reviewed PRs, draft by default. Push only with the user's authorization. Show the PR title and body and obtain approval before creating it; merging needs separate explicit user approval and `gh pr merge --squash --delete-branch`. Commits: `git commit --signoff`, semantic messages with the trailer `Assisted-by: LLM`. Code and docs stay in English (chat with the maintainer may use another language).

## Third-party code

1. Write original project implementations from the design; do not copy third-party addon/research implementations.
   Deliberately vendored libraries/assets are the narrow exception governed by the compatibility/notice rule below.
2. The gamemode is licensed under GPL-3.0-or-later (`LICENSE`; `D4`, decided 2026-11-07). Vendoring (copying a library into the tree) is allowed only for code under a GPL-compatible licence, and its copyright and licence notice must be added to `THIRD_PARTY_NOTICES.md` in the same change. Vendored so far: `Tieske/binaryheap.lua` (MIT).
3. Font files (for example Fira Sans, OFL 1.1, GPL-compatible as a font) follow the same rule. Vendoring Fira Sans is a follow-up in `TASKS.md`; until it is done the UI uses built-in GMod fonts through the family indirection in `PW.UI.Style` (`design/10-frontend.md` d.4).
4. Integrations with other addons (weapon bases such as ARC9) use only their public API and live in their own integration addon under `addons/`.

## Platform facts that bite

- The game runs on a **Steam Deck** (Linux; native build or Proton, detected by the scripts), code is written on the Mac. Use `scripts/deck/dev.sh` (deploy → `pw_reload` → filtered logs); see `TASKS.md`, "Dev loop on the Steam Deck". Connection comes from `DECK_HOST` / `DECK_USER` and an SSH key; never write passwords or hosts into the repository.
- On the Deck the game runs through Proton and Lua auto-refresh was not observed: reload through the bridge (`scripts/deck/cmd.sh pw_reload`). In agents use `logs.sh --once`, not the following mode. `game.ConsoleCommand` blocks `lua_run`/`echo`: use the bridge prefix `lua <code>`. Screenshots: `scripts/deck/shot.sh`, then read the printed file.
- Bots need a listen server with `maxplayers > 1`; Singleplayer cannot create them.
- SWEPs load after the gamemode: weapon registration happens in `PW_RegisterWeapons` after `InitPostEntity`.
