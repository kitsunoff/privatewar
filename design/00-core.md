# 00 — Core

Status: decided (in-game verification steps in `../notes/10-changelevel-and-phase-sync.md`).

## Goal and scope

After `01-extensibility.md` decision 16 the core is minimal:

- the loader and the two built-in kinds (`kinds`, `modules`) — specified in `01-extensibility.md`;
- the match phase state machine;
- net helpers.

Not in the core: the event bus (rejected, plain hooks are used), the weapon adapter registry (it is the `weapon_adapters` kind), HUD, bots, lobby UI (modules).

## Decisions

### Match flow

1. **Phase cycle (draft):**

   ```text
   LOBBY ──start──> [changelevel if map differs] ──> PREMATCH ──> LIVE ──> POSTMATCH ──> VOTE ──> LOBBY or PREMATCH
   ```

   | Phase | What happens |
   | --- | --- |
   | `LOBBY` | Lobby screen: the host picks mode, map and bot count; players edit loadouts and ready up. |
   | `PREMATCH` | Wait until every player has loaded (players reconnect after `changelevel`), then a countdown. |
   | `LIVE` | The match is running. |
   | `POSTMATCH` | Winner, final killcam, scoreboard, XP summary. |
   | `VOTE` | Vote for the next map and mode. |

2. **After the match: host setting.** In the lobby the host chooses between:
   - **back to lobby** (CoD private match style): after `POSTMATCH` the server returns to `LOBBY`; `VOTE` is skipped;
   - **rotation with vote** (CoD public match style): `POSTMATCH → VOTE → PREMATCH` on the voted map and mode; the server returns to `LOBBY` only when the host asks for it.
   - Rationale: almost no extra code (the setting only picks the transition after `POSTMATCH`/`VOTE`); covers both play styles (friends prefer the lobby, solo with bots prefers rotation).

3. **The core owns only the outer cycle; everything inside `LIVE` belongs to the mode.**

   ```text
   core:   LOBBY → PREMATCH → LIVE → POSTMATCH → VOTE → ...
                                │
   mode:                        └─ MODE:Start() ... PW.Match.Finish(result)
                                   (rounds, sides, overtime: the mode's own business)
   ```

   - Contract between core and mode:
     - the core calls `MODE:Start()` on entering `LIVE` and `MODE:Cleanup()` on leaving it;
     - the mode calls `PW.Match.Finish(result)` when the match is over (`result`: winner and summary);
     - the core fires notification hooks `PW_MatchStart` and `PW_MatchEnd`. That is all other modules know about the match lifecycle from the core.
   - `PREMATCH` and `POSTMATCH` stay in the core: waiting for players after `changelevel` and the end-of-match screen are needed by every mode. A mode may tune them (for example durations) but does not own them.
   - Rationale: the core does not need to know what happens inside a mode (user's point: the bootstrapper only hooks start and end).

4. **Rounds are not a core concept.** They live in an abstract base mode `modes/round_base.lua`:
   - it implements the round loop, side swaps and the notification hooks `PW_RoundStart` / `PW_RoundEnd` (documented by `round_base`, not by the core);
   - round-based modes inherit it with `MODE.Base = "round_base"` and only set parameters (for example `MODE.RoundsToWin = 4`);
   - `MODE.Abstract = true` keeps a base mode out of the vote and all lists. This flag is generic for every kind;
   - modules that care about rounds (killcam, bots) listen to `PW_RoundStart` / `PW_RoundEnd`; in non-round modes these hooks never fire.
   - Rationale: no round code in the core, no duplicated round loop across modes (reuse through `Base`, `01-extensibility.md` decision 8).

5. **Phase transitions.**

   | Transition | Trigger |
   | --- | --- |
   | `LOBBY → PREMATCH` | The host presses Start. If the map differs, `changelevel` first. |
   | `PREMATCH → LIVE` | Every player has loaded, or a timeout (60 s) expires; then a countdown (10 s). |
   | `LIVE → POSTMATCH` | The mode calls `PW.Match.Finish`. |
   | `POSTMATCH → VOTE` or `LOBBY` | Timer (15 s); direction from the host setting (decision 2). |
   | `VOTE → PREMATCH` | Timer (15 s); a tie is broken at random. |
   | any → `LOBBY` | Host command "abort and return to lobby". |

   - All durations are ConVars.
   - The match time limit belongs to the mode, which calls `Finish` itself (decision 3).
   - "No humans left" is not handled: on a listen server the host is always present, and the server closes when the host leaves. Dedicated servers are not a target.
   - Ready flags in the lobby are informational only; the host can start at any time (CoD private match). Requiring everyone ready would let one AFK player block the game.

### Profiling

6. **Measurement point in the core, display in a module.**
   - The core provides one function `PW.Call(entity, method, ...)`. The core and modules use it to call entity methods; it already carries the `pcall` and the disable-on-error logic from `01-extensibility.md` decision 15.
   - With `pw_profile 1`, `PW.Call` also measures `SysTime()` and accumulates time per entity id. With `pw_profile 0`, the cost is one `if` check.
   - The `profiler` module only displays the data (screen overlay or console dump).
   - Rationale: the hot call sites live in the core; a profiler module would otherwise need to detour core functions, which global rule 1 forbids. About 10 lines in the core.

### Permissions and net

7. **Named privileges, with CAMI when present.**
   - Fact: on a listen server the host gets the `superadmin` usergroup automatically (`garrysmod/lua/includes/extensions/player_auth.lua:109` in the public `Facepunch/garrysmod` repository).
   - A module declares a privilege as a string with a default usergroup: `PW.Privilege("pw.match.start", "superadmin")`. Privileges are declared by modules, not hardcoded in the core (`01-extensibility.md` decision 16).
   - Check: `PW.Can(ply, "pw.match.start")`.
   - If the `CAMI` global exists (an admin mod such as ULX or SAM is installed), privileges are registered in CAMI and checked through it, so the host can delegate them. The core does not ship CAMI itself.
   - Without CAMI the check falls back to the default usergroup (`IsSuperAdmin()` for `"superadmin"`).
   - Privileged actions (initial list): start match; change mode, map, bot count, match settings; enable/disable entities (`01-extensibility.md` decision 11); abort to lobby; `pw_reload`; profiler.
   - Not privileges: "a player edits only their own loadout", "one vote per player". These are checked by the handler of that action.
   - Deferred (YAGNI): an in-game co-host / party-leader handover. If needed, it becomes another source of rights on top of `PW.Can`.
   - About 20 lines in the core.

8. **One wrapper for every client → server message.**

   ```lua
   PW.Net.Receive("pw_loadout_set", {
       who    = "any",            -- "any" or a privilege name, for example "pw.match.start"
       phases = { "LOBBY", "LIVE" },
       rate   = 2,                -- max messages per second per player; extra ones are dropped
       maxLen = 256,              -- bytes
   }, function(ply, len)
       -- values are validated here by the handler
   end)
   ```

   - The core calls `util.AddNetworkString` itself.
   - Privilege, phase, rate and length are checked **before** the handler runs. A rejected message is dropped and logged, at most once per N seconds per player.
   - Values are validated by the handler; no extra validation helpers (`math.Clamp` and a registry lookup are one line each).
   - Debug mode warns about `net.Receive` registrations that bypass the wrapper.
   - No bit-packing helpers: `net.WriteUInt(x, bits)` already writes bits (YAGNI).
   - Rationale: global rule 4 enforced in one place, so no module can forget it. About 40 lines.

### Map change

9. **`changelevel` with the next match persisted as JSON in `data/`.**
   - Before `changelevel` the server writes `data/privatewar/pending_match.json`: map, mode or playlist, `match` settings snapshot, bot count, team assignment by SteamID64, `createdAt`, `game.GetMapChangeCount()`, format version. The file is written **before** the command, not in `ShutDown`, so a failed `changelevel` loses nothing.
   - `changelevel` is called only if the target map differs from the current one; otherwise the core goes straight to `PREMATCH`. A `PW.mapChanging` guard prevents a double call.
   - On the new map the server reads the file, deletes it, and accepts it only if: the map matches; `game.GetMapChangeCount()` grew by exactly 1 (rejects a stale file after a crash); the file is younger than 120 s; the format version is known. Valid → `PREMATCH`; otherwise → `LOBBY`.
   - If `changelevel` fails (for example the map is missing) and the server is still on the old map after 10 s, it returns to `LOBBY` and shows the host an error.
   - **Bots are reconciled, never assumed:** on the new map compare `player.GetBots()` with the target; re-create Lua state for surviving bots, create missing ones with `player.CreateNextBot` (handle a `NULL` return), kick extras (`Player:Kick`, never `Entity:Remove`). Bots count as loaded immediately.
   - **Client loaded detection:** the client sends `pw_client_ready` from `InitPostEntity` every 2 s until the server acknowledges (covers lost messages, garrysmod-issues #5081). `PREMATCH` waits for every human to be ready or 60 s (decision 5).
   - Evidence: `../notes/10-changelevel-and-phase-sync.md`.
   - Risk (not blocking): a 2026 comment on garrysmod-issues #6832 reports that nobody can join a P2P server after `changelevel`. Probably a temporary regression of the spring 2026 netcode update; tracked as an early in-game test in `08-lobby.md`. Fallback only if confirmed: forbid map changes from the lobby (matches always on the host's start map).

### Phase networking

10. **NW2 globals as the single source of truth; timers computed locally.**
    - Three NW2 globals: `pw_phase` (string), `pw_phase_end` (`CurTime()` at which the phase ends, `-1` if none), `pw_phase_seq` (change counter). Only `PW.SetPhase` writes them, always in the order end → phase → seq, in or after server `InitPostEntity`.
    - Late joiners receive them automatically.
    - **No countdown traffic.** Clients compute the remaining time locally every frame as `pw_phase_end - CurTime()`. The server never sends timer ticks.
    - Clients get one `Entity(0):SetNW2VarProxy("pw_phase_seq", ...)` that fires the client hook `PW_PhaseChanged`. Handlers must be idempotent (the proxy fires before the value is stored and repeats on full updates); they read other keys from `newval` or one frame later. After registering the proxy in `InitPostEntity`, the handler runs once with the current values.
    - Data that must arrive together with a phase change (for example the end-of-match scoreboard) is sent as a separate net message carrying its own `seq`; the client applies it when the seq matches. The same transition is never duplicated through a net message.
    - Evidence: `../notes/10-changelevel-and-phase-sync.md` §5, R4.

### Instances

11. **`PW.Instance(def, owner)`: per-owner instances with automatic cleanup.**

    ```lua
    -- perks/ghost.lua
    function PERK:OnEquip(owner)                 -- instance created
        self:Hook("Think", function()            -- any hook, auto-removed
            self.still = owner:GetVelocity():LengthSqr() < 100
        end)
        self:Timer(1, 0, function() end)         -- any timer, auto-removed
    end
    function PERK:OnUnequip(owner) end           -- optional: own cleanup
    ```

    - An instance is a table inheriting from its definition (`self` is the instance, so per-owner state lives on it), with an `IsValid` method.
    - `self:Hook(name, fn)` = `hook.Add(name, self, fn)`: the same `IsValid` mechanism as `01-extensibility.md` decision 18; GMod drops the hooks once the instance is invalid.
    - `self:Timer(delay, reps, fn)` creates a uniquely named timer tracked by the instance; the core removes it on cleanup.
    - `self:Remove()` ends the instance: calls `OnUnequip` (through `PW.Call`), marks it invalid, removes its timers. The owning module decides when (for example perks: on death, loadout change, match end; a streak: when its duration ends).
    - The core also ends every live instance on `PW_MatchEnd`, so nothing leaks into the next match.
    - Errors inside instance callbacks disable that instance only (`PW.Call`, `01-extensibility.md` decision 15).
    - Used by perks, killstreaks, equipment, field upgrades and anything else that needs per-player state with hooks.
    - Rationale: lets content authors write unusual effects with any hook, without having to remember cleanup. About 30 lines.

## Interfaces

TBD.

## Performance budget

- Profiler: per-entity timings in `PW.Call` when `pw_profile 1`; one `if` check otherwise (decision 6).

## Security

TBD.

## Open questions

1. ~~Rounds~~ Closed: decisions 3 and 4.
2. ~~Transition rules~~ Closed: decision 5.
3. ~~Persisting match state across `changelevel`~~ Closed: decision 9.
4. ~~Phase networking~~ Closed: decision 10.
5. ~~Net helpers~~ Closed: decisions 7 and 8.
6. ~~Profiler~~ Closed: decision 6.

## Research

- `../notes/17-lobby-and-join-flow.md` (lobby phase, changelevel, hosting)
- `../notes/10-changelevel-and-phase-sync.md` (changelevel, state persistence, client loaded detection, phase networking)
