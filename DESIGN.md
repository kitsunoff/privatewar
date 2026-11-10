# Private War — design (index)

Status: draft. Each subsystem is designed in its own file under `design/`. The implementation plan is `TASKS.md`; UI image prompts are in `design/visual-prompts/`.

## Goal

**Private War** (folder `privatewar`, Lua prefix `PW`): a casual "CoD in Garry's Mod":

- solo with bots, or with friends on a player-hosted listen server (Steam P2P);
- a CoD-style pre-match lobby inside the game.

Motivation: modern CoD cannot be played offline with bots (the last option is MWR). The primary use case is therefore **solo or with a few friends against bots that feel alive**. Bot quality is a core feature, not a filler.

## Philosophy

Suckless:

1. Small core; everything else is a module.
2. Few dependencies.
3. Performance by design, verified by measurement.

## Structure

See `design/01-extensibility.md` (decisions 8 and 16). SWEP-style folders, no manifests. The paths below are inside the gamemode addon, which is `addons/privatewar/` in the repository; each integration addon is its own `addons/<name>/` folder, and the dev-only bridge is `addons/privatewar-dev/`:

```text
lua/privatewar/
  kinds/<kind>.lua            KIND declarations (folder, class table name, required fields)
  modules/<id>/               subsystem code: shared.lua, init.lua, cl_init.lua (MODULE table)
  <kind folder>/<id>.lua      entities: modes/, streaks/, hud/, weapon_adapters/, ...
  <kind folder>/<id>/         or the folder form: shared.lua, init.lua, cl_init.lua

gamemodes/privatewar/gamemode/
  core: loader, the two built-in kinds (kinds, modules), match phases, net helpers

Built-in content (modules, kinds, modes, fallback SWEP adapter) ships under lua/privatewar/ inside the
gamemode's own Workshop addon. See notes/09-lua-file-shadowing.md.

Separate Workshop addons (integrations), same layout:
  privatewar-arc9      ARC9 adapter
  privatewar-mwbase    MW Base (mg_base) adapter
  privatewar-tfa       TFA adapter
```

## Global rules

1. Modules talk only through `PW_*` hooks, registries and small public APIs. They never wrap or overwrite another module's functions.
2. A disabled or missing module never breaks the core or other modules.
3. Size limits: a file stays under ~500 lines, a function under ~60 lines.
4. No `net.WriteTable`. Every client → server message is validated: permission, state, rate and values.
5. **Everything is typed with annotations** (EmmyLua / LuaCATS: `---@class`, `---@field`, `---@param`, `---@return`, `---@meta`) so the language server gives completion and type errors. Every public function, hook, class table (`MODE`, `PERK`, ...), settings schema and blackboard field is annotated. Type definitions for the `PW` API and every kind ship in `lua/privatewar/types/` (`---@meta` files) so addon authors get the same completion. Tooling: LuaLS with GMod annotations (`TASKS.md`, "Toolchain").
6. **Linters and the type checker are mandatory gates** (`glualint`, `lua-language-server --check` with warnings as errors, `markdownlint-cli2` for docs), provided by `flake.nix` and enforced by git hooks and an agent hook; rules are never disabled to get a change through.
7. **Optimisation first** (user decision 2026-11-07). The Steam Deck is the target hardware: the gamemode is designed to be playable on the Steam Deck. Every integration and every costly option defaults to performance; visual or simulation quality is opt-in through a setting the host can change. First instance: the ARC9 performance profile (`design/04-weapons.md` d.7).
   - Narrow user-approved exception (2026-11-10): the optional combat-movement layer defaults on, with its enable switch applied at the next match. Its hull/ground traces must be bounded and its cost measured on the Deck. This exception does not change the performance-first defaults of other features.

## Performance rules

1. **Server:** a per-tick budget for bots and heavy searches, spread across frames; no `ents.Find*` in hot loops; a quantized ring buffer for killcam.
2. **Net:** bit-packed payloads, deltas only, and only the data a client needs. Never send enemy positions that are not deliberately revealed.
3. **Client:**
   - no allocations in `HUDPaint`;
   - fonts, materials and colors are cached;
   - one `HUDPaint` iterates the HUD element registry;
   - one owner for `CalcView`.
4. **Profiler module:** per-module timings (`SysTime()` wrappers), toggled by a ConVar.

## Decided

- Bots are real players (`player.CreateNextBot` + `StartCommand`), not NextBot entities that imitate players.
- Hosting is player-hosted listen servers with Steam P2P; no backend for the MVP.
- Progression is local per player, sent to the host on join, and forgeable (accepted).
- One gamemode with internal modules, plus weapon base integrations as separate addons.
- UI is Lua only: a small in-house widget kit and immediate-mode HUD. No DHTML, no npm toolchain. UI is verified in game (hot reload + screenshot).

## Subsystems

| # | Subsystem | File | Status |
| --- | --- | --- | --- |
| 00 | Core | `design/00-core.md` | decided |
| 01 | Extensibility | `design/01-extensibility.md` | decided |
| 02 | Modes | `design/02-modes.md` | decided |
| 03 | Map data | `design/03-mapdata.md` | decided |
| 04 | Weapons (adapters) | `design/04-weapons.md` | decided |
| 05 | Loadout | `design/05-loadout.md` | decided |
| 06 | Progression | `design/06-progression.md` | decided |
| 07 | Bots | `design/07-bots.md` | decided |
| 08 | Lobby and hosting | `design/08-lobby.md` | decided |
| 09 | HUD | `design/09-hud.md` | decided |
| 10 | Frontend | `design/10-frontend.md` | decided (font files: follow-up now that D4 is decided) |
| 11 | Camera and killcam | `design/11-camera.md` | draft |
| 12 | Audio | `design/12-audio.md` | draft |

Each subsystem file follows one template: status, goal and scope, decisions, interfaces (events emitted and consumed, public API), performance budget, security, open questions, research links.

Status values: `draft` → `in-review` → `decided`. A subsystem is `decided` only when its open questions list is empty.
