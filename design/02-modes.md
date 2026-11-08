# 02 — Modes

Status: decided.

## Goal and scope

Mode registry with a single active mode object; TDM, Domination, Kill Confirmed.

## Decisions

Inherited from `00-core.md`:

- A mode owns everything inside `LIVE`. Contract: `MODE:Start()`, `MODE:Cleanup()`, `PW.Match.Finish(result)` (core decision 3).
- Rounds are provided by the abstract base mode `round_base` (core decision 4).

Inherited from `01-extensibility.md`:

- Modes are entities of the kind `modes/` with the class table `MODE` (decisions 8, 16).
- A mode is the default answer for question hooks such as `PW_CanRespawn` (decision 9).
- Mode settings are declared in `MODE.Settings` (decision 17).

### Configurability

1. **Two ways to set up a match.**
   - **Custom:** the host picks one mode and one map and edits Game Setup by hand (CoD private match).
   - **Playlist:** the host picks a ready-made playlist curated by an addon author (for example "Shipment 24/7" from a map pack, "Hardcore" from a mode pack); nothing to configure.
   - Rationale: players get both "configure it yourself" and curated experiences from addon authors.

2. **Playlists are a kind `playlists/` (data only).**

   ```lua
   -- lua/privatewar/playlists/shipment_247.lua
   PLAYLIST.Name  = "Shipment 24/7"
   PLAYLIST.Modes = { tdm = 1, dom = 1, kc = 1 }       -- mode id → weight
   PLAYLIST.Maps  = { "pw_shipment" }                  -- map pool; nil = every map that supports the mode
   PLAYLIST.Settings = {                                -- match-scope overrides, full setting ids
       ["tdm.scorelimit"] = 100,
       ["bots.count"]     = 11,
   }
   ```

   - A "preset" is just a playlist with one mode (for example Hardcore TDM = `Modes = { tdm = 1 }`, `Settings = { ["health.hardcore"] = true }`). No separate preset concept.
   - In "rotation with vote" (core decision 2) the vote offers several map + mode pairs sampled from the active playlist by weight.

3. **Host-saved playlists.** "Save as…" in the lobby stores the current Custom setup as a playlist in JSON under `data/privatewar/playlists/`. The loader reads them alongside Lua playlists; same fields, same validation.

4. **`maxplayers` cannot be changed from Lua** (`../notes/17-lobby-and-join-flow.md`, fact 5). A playlist's player count can only mean "fill with bots up to N". If the server was started with fewer slots, the lobby shows a warning ("playlist expects 24 players, server has 16").

5a. **Bot fill instead of a player-count field.** The bots module setting is `bots.fill` ("fill with bots up to N players in total"), not a fixed bot count. In Custom the host sets it in Game Setup; a playlist sets it through `Settings = { ["bots.fill"] = 24 }`. Capped by `maxplayers` (decision 4). No separate playlist field. Clarified with the user on 2026-11-07: `bots` is one module that owns the bot settings; the `bots_*` modules of `07-bots.md` d.3 are its sub-modules.
5b. **Vote size** is a `server` setting `vote.options` (default 3), not a playlist field.

### Scope

5. **MVP modes: TDM, FFA, Domination, Kill Confirmed.**
   - Together they exercise teams and no-teams, zones on the map and pickup objects, which is enough to test the extensibility foundation.
   - S&D (with `round_base`) is the first mode after MVP; the `MODE` interface is designed with it in mind so the API does not break later.
   - Gun Game and Gunfight come later; good candidates to test writing a mode as a third-party pack.

### Teams

6. **The team API supports N teams; MVP is tested only with 0 (FFA) and 2.**
   - A mode declares its team count: `MODE.Teams = N` (`0` = FFA).
   - Modules work with the list `PW.Teams.GetActive()` and never assume exactly two teams. There are no `TEAM_A` / `TEAM_B` constants in the public API.
   - **Enemy check only through `PW.IsEnemy(a, b)`**, a question hook (`hook.Call("PW_IsEnemy", PW.ActiveMode, a, b)`). Team-based default: `a:Team() ~= b:Team()`; FFA: `a ~= b`. Modules (damage, HUD, bots, minimap) never compare `Team()` directly; otherwise FFA breaks in every module separately.
   - Team assignment, balancing, late-join placement and the per-team bot target are done by a `teams` module, not by the core or the mode. `round_base` swaps sides through that module's functions.
   - Team names and colours are cosmetic; MVP has defaults; "factions" may become a kind later.
   - Rationale: keeps the door open for modes with many teams (for example a Plunder-like squads mode) without a breaking API change later; writing modules as loops over teams costs almost nothing when done from the start.
   - Known cost for N > 2 when such a mode appears: dynamic spawning instead of per-team spawn zones (`03-mapdata`), N-team scoreboard and HUD, N-owner capture in Domination-like modes.
   - Decided by the user on 2026-11-06 (T-1.16): team assignment balances all players evenly and does not keep humans together against bots. Friends may end up on opposite teams. There is no setting for this.

### MODE interface

7. **Fields and methods of `MODE`.**

   | Field | Required | Meaning |
   | --- | --- | --- |
   | `Name` | Yes | Display name (localisation key) |
   | `Teams` | Yes | Team count (`0` = FFA), decision 6 |
   | `Description`, `Icon` | No | Lobby and vote |
   | `Base`, `Abstract` | No | Inheritance; hidden from lists |
   | `Settings`, `SettingDefaults` | No | `01-extensibility.md` decision 17 |

   - Lifecycle: `MODE:Start()`, `MODE:Cleanup()` (core decision 3).
   - `MODE:Think()`, optional: called by the core every tick during `LIVE` through `PW.Call` (pcall + profiler, core decision 6). A mode does not add its own `Think` hooks.
   - Default answers and reactions: the mode defines methods named like `PW_*` hooks; they are called last for every `PW_*` hook while the mode is active (`01-extensibility.md` decisions 9 and 18):

     ```lua
     function MODE:PW_CanRespawn(ply) return true end
     function MODE:PW_RespawnDelay(ply) return self:Setting("respawndelay") end
     function MODE:PW_SelectSpawn(ply) ... end
     function MODE:PW_IsEnemy(a, b) return a:Team() ~= b:Team() end
     function MODE:PW_PlayerKilled(victim, attacker, dmg) ... end   -- scoring
     ```

   - The full list of `PW_*` hooks a mode may answer is defined together with the subsystems that fire them (spawn: `03-mapdata`, loadout: `05-loadout`, bots: `07-bots`).

### Additional modes: user-approved revision (2026-11-08)

8. **Search and Destroy first; independent Hardpoint/Infection preparation in parallel.** The user renewed
   implementation authorization; this does not pass the outstanding player/weapon HUD visual checkpoint.
   Shared API changes still require orchestrator review/freeze before implementation.

   - **S&D:** two authored sites on `gm_construct`, one bomb, one life per round; 120 s round, 5 s plant,
     7.5 s defuse, 45 s fuse; first to 6 round wins; swap sides every 3 completed rounds. Select a random
     attacking carrier. Interactions hold E continuously with no partial progress. A planted bomb keeps the
     round alive beyond the ordinary deadline even if every attacker is dead. Explosion resolves the round
     without damaging players. Join in progress spectates until the next round.
     Before plant: no attackers means defender win, no defenders means attacker win, both absent means draw.
     Plant must complete strictly before the round deadline, defuse strictly before the fuse; equality loses
     to the deadline. Damage alone does not cancel held use; release/range/death do. Carrier death/disconnect
     drops once; invalid out-of-world/unreachable drops recover at the authored point. Reconnect grants no
     second life, spectators see only their own team, bot quota replacements occur between rounds.
      Intermission has no combat; clear grenades/active effects but keep unused earned streak inventory.
      Carrier and dropped-bomb markers are visible only to attackers; planted bomb and fuse timer are visible
      to both teams. Defenders can see the dropped physical bomb by ordinary sight, never hidden bot coordinates.
      Actor death cancels an unfinished interaction; a completed plant survives carrier death. Exact deadline
      equality loses to the deadline.
   - **Hardpoint:** two teams, one rotating authored zone, first authored map `gm_construct`; 60 s per zone,
     1 point per second, score limit 250, match limit 10 minutes, tied scores draw. Only exclusive living
     occupancy scores; empty and contested zones score zero regardless of unequal counts. No additional
     personal rewards. Bots pursue the active zone, without pre-rotation.
   - **Infection:** a separate optional addon, not mandatory built-in content; default 3 rounds, configurable
      including 1. Reseed initial infected each round, preferring no repeat where possible. User-approved
      playtest revision (2026-11-08): the first valid native-fist hit by a living infected immediately converts
      a living current-roster survivor without death, respawn or teleport. Cancel that hit's damage, including
      lethal damage; preserve position, momentum and control. Validate attack provenance, enemy roles and
      current lives, not merely holding fists; world, team, other-weapon, blast, non-hit, duplicate or stale
      events cannot trigger contact conversion or credit. Survivor bots escape/maintain distance and fire
      when legally possible rather than approach for melee; infected bots still pursue with native fists.
      Both use ordinary perceived contacts, local navigation and normal aim/input, never hidden positions
      or difficulty cheats. Each round lasts 120 s, with one random initial infected; infected respawn after
      3 s, new joiners wait for the next round. Survivor death still converts, including world death/suicide
      without a reward. All converted means infected win; at time expiry remaining survivors
     win. No new XP/money events. Infected have 400 health, walk and run speeds multiplied by 1.15 over
     ordinary player values, GMod's built-in fists and the HL2 zombie player skin; jump and fist damage
     are unchanged. Apply identically to humans/bots and fully restore ordinary state outside Infection.
     Verify the built-in fists weapon class and valid player model in the engine; no substitute crowbar.
     At least two participants means humans or bots (one host plus one bot is valid). Last infected
     disconnect gives survivors the round; no survivors gives infected the round; a pending infected respawn
      still counts as present. Deadline wins over equal-time hit or death; contact conversion must occur
      strictly before expiry and the last conversion resolves once. Personal round wins go to surviving
     survivors at expiry or the initial seed on infected victory; converted players never inherit a win.
     Final match standings use personal round wins (`teams = false`), shared top is a draw; infection counts
     are informational statistics only. Infected receive no perks/grenades/streaks; revoke them on conversion.
     Each round has a fresh roster/classes; reconnect must not bypass role/life restrictions.

   Shared lifecycle/role APIs remain generic: two-phase round preparation, synchronous team transition,
   post-base spawn notification and optional terminal result transform. These interface approvals do not
   change existing ordinary modes or grant new XP/money events.

## Interfaces

TBD.

## Performance budget

TBD.

## Security

TBD.

## Open questions

1. ~~Playlist fields~~ Closed: decisions 5a and 5b; per-mode settings inside a multi-mode playlist use full ids (`tdm.scorelimit`).
2. ~~How a mode declares which maps it supports~~ Closed: `03-mapdata.md` decision 6 (`MODE.MapData`, `MODE:ValidateMapData`).
3. ~~The `MODE` interface~~ Closed: decision 7 (hook list grows with the subsystems that fire the hooks).
4. ~~Team model~~ Closed: decision 6. Open detail: verify the engine limit on team count if a mode ever needs more than 8–16 teams.
5. ~~MVP mode list~~ Closed: decision 5.
