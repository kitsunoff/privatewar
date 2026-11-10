---
name: privatewar-mode
description: Implement or change a Private War internal game mode, MODE lifecycle, rounds, map objectives, mode settings or bot objectives. Use for requests such as a new team/FFA/round mode, not for weapon adapters, perks or wildcards alone.
---

# Private War game modes

Read [shared workflow](../../../docs/agent-workflow.md) before edits and
[mode contracts](../../../docs/api/modes.md), [map contracts](../../../docs/api/map.md),
[role policy](../../../docs/api/role-policy.md). Decisions: `design/02-modes.md` d.6–8,
`design/00-core.md` d.3–4, `design/01-extensibility.md` d.8–18. Do not redesign approved modes.

## Ownership

Default content: `addons/privatewar/lua/privatewar/modes/<unique_id>.lua` or folder form, plus task-specific
`addons/privatewar/lua/tests/privatewar/mode_<topic>.lua` and `addons/privatewar/lua/privatewar/types/match_rules.lua`.
Inspect `addons/privatewar/lua/privatewar/kinds/modes.lua`, `modes/tdm.lua`, `modes/ffa.lua`, `modes/round_base.lua`
(all under `addons/privatewar/lua/privatewar/`). Integration content may live in a separately approved addon.
`addons/privatewar-infection/` is optional content, not a template to copy into mandatory built-ins.
Map files, score events, mode-specific modules/HUD and shared round/bot/core seams need explicit task ownership;
coordinate before touching `addons/privatewar/lua/privatewar/maps/gm_construct.lua` or another lane's files.

## Workflow

1. Record git state/base and task status via the shared workflow. Inspect current mode/type/test implementations,
   not historical queue hashes. Classify continuous versus `round_base`, map-data needs, team/FFA and optional dependencies.
2. Declare owned paths, non-goals and observable rules (limits/ties, exact deadline precedence, admission, rewards,
   public versus private information). Use already approved rules; decide routine engineering details yourself.
3. Map mandatory cases using [test map](../../../docs/agent-test-map.md); write new tests first with pure state
   reducers and thin engine wrappers. Preserve existing suites. Native scenarios start through `PW.Match.Start`.
4. Implement through `MODE` methods below. Keep per-match state on `self`, cleanup idempotent, no independent Think
   hook. Add types and generated settings/UI model tests; implement mode HUD with the existing HUD owner.
5. Run `nix develop --command make check`; game RED/GREEN and `nix develop --command make test` only with explicit
   permission/free Deck. Inspect actual diff, reload/failure behavior and eventual authorized client screenshots.
6. Report exact cases, commands/counts, commits, skipped checks and pending human mode/feel/P2P/controller/perf checkpoints.

## Implementation contract

- Kind requires `Name: string`, `Teams: number`; `0` means FFA. `Base` is resolved before required validation.
  Registry `PW.Modes`, `Subscribe = "never"`; mode `PW_*` methods run last through `PW.ActiveMode`, not auto-hooks.
- `MODE:Start()`, `MODE:Think()`, `MODE:Cleanup()` are server lifecycle calls through `PW.Call`; finish with
  `PW.Match.Finish(result)` where result follows `PW.MatchResult` in `types/match_rules.lua`. Never set phase/NW2
  internals or assign `PW.ActiveMode` to start a real match. Active mode errors abort to LOBBY.
- `MODE.Settings` is match-only; read `self:Setting(key)`. Inherited defaults override per key. `SettingDefaults`
  uses full module setting ids. Check generated Game Setup controls; do not bypass settings validation/snapshot.
- Use `PW.IsEnemy(a, b)`, `PW.Teams` and `PW.Score.Award(ply, eventId, ctx?)`, not direct cross-module state edits.
  Mode loadout overrides (`PW_PlayerLoadout(ply)`) are trusted and not validated by Resolve: construct legal data.
- Map objectives: `MapData = true`, `ValidateMapData(data) -> true | false, reason`, `PW.Map.GetModeData(modeId)`.
  The getter reads the current map and walks the mode's Base chain. Structural validation must reject
  nonfinite coordinates/dimensions; current-map activation also checks geometry/reachability. Hide invalid layouts.
- `MODE:BotObjectives(team) -> PW.BotObjective[]` is requested at 1 Hz/team. Return stable ids, positions, radii,
  registered action ids, weights and wants; use `types/bots_objectives.lua` and current
  `addons/privatewar/lua/privatewar/modules/bots_commander/sh_contracts.lua`. Declare all required action ids in
  `Dependencies.objective_actions` and runner `Dependencies.modules = { "bots_objectives", ... }` plus required
  mode modules. Missing/disabled/failed required entries abort even in human-only matches. Do not bake action logic
  into the generic commander or reveal hidden enemy positions. Existing action handlers use normal bot inputs.
- Round modes inherit `round_base`; use `PrepareRound(round, swapped)` before playable spawns, not `PW_RoundStart`
  to create roles. `RoundWinner(timedOut)` returns team/false/nil and optional exactly-true timeout deferral.
  Explicit terminal verdict wins; fixed `RoundLimit` counts draws and differs from `RoundsToWin`.
  Keep `PW_RoundEnd` → intermission/swap → preparation → spawn → `PW_RoundStart` ordering. Route controlled spawns
  through `PW.MatchRules.Spawn(ply)`; use generic admission/team-transition/player-overrides owners for roles.

## Minimal example (inspected, not executed here)

Complete inherited-mode declaration for an approved TDM variant; no new lifecycle code needed. Write it only when
that variant is requested. Repository destination: `addons/privatewar/lua/privatewar/modes/example_tdm.lua`.
Setup: core plus built-in `tdm`/`match_rules`; loader supplies `MODE` on both realms.

```lua
MODE.Base = "tdm"
MODE.Name = "Example TDM"
MODE.Short = "EX"
MODE.Settings = { scorelimit = { default = 50 } }
```

Expected: `PW.Modes.Get("example_tdm")` has inherited `Teams = 2`, lifecycle and limit 50 in its schema;
Game Setup lists the setting, while the base TDM remains 75. Add a registration/inheritance GLuaTest and run
the authorized full `make test` command above; inspect `modes_tdm_ffa.lua` for win/time/tie fixtures.
Do not present registration success as proof that a brand-new objective mode is playable.

## Tests first

Preserve T-2.2–T-2.5 and relevant T-1.12/T-2.9/T-5.2/T-5.7/T-5.11/T-8.4 in the test map. New mode tests must cover
limit, time equality, draw, once-only terminal actions, late join/reconnect, owner cleanup on abort/failure/reload,
disabled/missing dependencies, invalid map and empty/tiny teams; round changes preserve
`round_objective_lifecycle.lua` and `round_initial_spawn.lua`. Verify server/client safe snapshots and no hidden
coordinates separately from ordinary bot travel/input smoke. Applicable named T-11.12–T-11.14 cases remain mandatory.

## Stop conditions

Stop for a decided-rule conflict, missing public seam/permission, required cross-lane or frozen-contract edit not
assigned, impossible mandatory case, or environment failure after two attempts. No design edits, AI rewrite,
enemy-knowledge shortcut, direct SetTeam/foreign store writes, automatic Deck access or automatic publication.
