# Bots API: blackboard, `PW_Bot*` hooks, goal API, stimuli, kinds, scheduler

Status: frozen on 2026-11-07, changes only through the orchestrator. Extended on 2026-11-07 after T-5.1, T-5.2,
T-5.3, T-5.5, T-5.6, T-5.7, T-5.8, T-5.9, T-5.10 and T-5.12: the items that the code decided are closed in "Open in design" and the sections below;
**the code wins over any description here**. Two items are orchestrator decisions that wait for the user's
confirmation (items 1 and 2).

Contract for the `bots` lane and its sub-lanes (T-5.1 to T-5.13). It sits on top of `core.md` (kinds, settings,
hook dispatch, `PW.Call`, profiling), `modes.md` ("`BotObjectives`"), `adapter.md` ("Bot input rules"), `teams.md`
(`PW.IsEnemy`) and `map.md` (`PW.Map.GetNavAreas`) and does not repeat them. Sources: `design/07-bots.md`
(cited as `07 d.N`), `design/01-extensibility.md`, `design/02-modes.md` d.5a. Research (`notes/14`)
explains why; it is not a decision.

**The design is deliberately thin here.** `07 d.16` moved the blackboard contract to this file, and the design gives
only the layer diagram, the names of the groups (intents, contacts, goal, orders) and a few examples. A column
"Source" marks every name: `design` means the design states it, `research` means it is taken from the note the
design points to for values, `contract` means this file introduces the name because a layer boundary needs one (the
orchestrator's choice, frozen here). Everything the design leaves undecided is **not** invented: it is listed in
"Open in design" with the task it blocks.

## Ownership

One module `bots` owns the bot settings (`bots.fill`, `bots.difficulty`, `bots.tickbudget`, ...; full id
`<owner>.<key>`, `01-extensibility.md` d.17); the `bots_*` modules are its sub-modules (`07 d.3`, clarified on
2026-11-07). Each layer is a module that talks to the others only through the blackboard and the `PW_Bot*` hooks
(`07 d.3`, `01-extensibility.md` d.16), so any layer can be replaced by a module with the same contract.

| Module (`lua/privatewar/modules/<id>/`) | Sub-lane | Task | Layer and rate (`07 d.3`) | Writes (see "Blackboard") | Reads |
| --- | --- | --- | --- | --- | --- |
| `bots` | manager (settings file); placeholder written by the modes lane (T-2.6), the bots lane owns it since T-5.1 (item 11) | T-5.1 | Settings only: `bots.fill`, `bots.difficulty`, `bots.tickbudget`, `bots.classes`, `bots.classrepick` (declared) | none | none |
| `bots_manager` | manager | T-5.1 | Quota, create and kick, reconciliation after `changelevel`, Singleplayer refusal; the team is placed by `teams`, the manager only mirrors it | `bot`, `team` (`personality` and `difficulty` wait for T-5.12) | `bots.fill` |
| `bots_scheduler` | scheduler | T-5.3 | Millisecond budget per tick, random phase per bot, global FIFO, counters (`PW.BotScheduler`) | none today: the phase is read with `PW.BotScheduler.GetPhase(id)`, not from the board | none |
| `bots_debug` | debug | T-5.4 | Overlay data behind the server ConVar `pw_bot_debug` and its drawing (`PW.BotDebug`, "Debug overlay") | none | `behavior`, `target`, `goal`, `path`, the scheduler counters |
| `bots_input` | input | T-5.2 | Every tick: `GM:StartCommand` writes `CUserCmd` from the intents, adapter `GetInputRules` | none (consumes `intent`) | `intent`, adapter rules |
| `bots_nav` | nav | T-5.5 | Budgeted: time-sliced A*, cost layers (`PW.BotNav`) | none (a path service) | path requests |
| `bots_goal` | nav | T-5.6 | Goal wrapper (`SetGoal`), navmesh projection, blacklist, path follower (10 Hz scheduler tick per bot with a goal), stuck ladder, doors; dev command `pw_bot_goto` | `goal`, `path`, `intent.move`, `intent.view` (not while the aim owns the view; always on a ladder), its own `IN_*` bits of `intent.buttons` | `target`, `intent`, the path service |
| `bots_perception` | perception | T-5.7 | 10 Hz, random phase per bot: FOV, multi-point LOS, reaction queue, hearing, contact memory | `contacts`, `memory`, `debug.perception` | `team`, `difficulty`, contacts of others (sharing) |
| `bots_aim` | aim | T-5.8 | Every tick: spring-damper, focus error, lead, recoil compensation, fire-when-steady | `intent.view`, `intent.buttons` (attack part), `debug.aim` | `contacts`, `target`, `intent.target`, `difficulty` |
| `bots_brain` | brain | T-5.9 (T-5.10 to T-5.13 add behaviours and data) | 10 Hz, random phase per bot: dual-utility over `bot_behaviors/`, Action stack | `behavior`, `target`, `intent` (movement, stance, buttons) | `contacts`, `order`, `goal` status |
| `bots_tactics` | brain | T-5.10a | Survival and combat helpers: the facts of a bot at 5 Hz (`board.tactics`), the budgeted cover search, the damage hook (`PW.BotTactics`) | `tactics` | `contacts`, `difficulty`, `personality`, the weapon adapter |
| `bots_objectives` | brain | T-5.10b | Objective, roam and camp helpers: facts per brain tick (`PW.BotObjectives.Facts`), the fallback derivation of objectives, hot spots, roam and camp points | none (a facts accessor; keeps the recent deaths of each team) | `MODE:BotObjectives`, `memory`, `personality`, `difficulty`, `order` |
| `bots_loadouts` | brain data (loadout lane contract) | T-5.13 | Gives each bot a class from a pool (presets and the players' classes) through `PW.Loadout.SetClass`; pure rules in `shared.lua`, glue in `init.lua` (`PW.BotLoadouts`) | none (reads `board.personality.class_weights` through `PW.BotLoadouts.WeightsOf`) | `personality`, `bots.classes`, `bots.classrepick` |
| `bots_commander` | brain (task table of `TASKS.md`; the design names the module only) | T-5.11 | Per team at 1 Hz: objectives, assignment, rebalance, hunt slots | `order`, `hunt` | `MODE:BotObjectives`, `contacts` |

- Kind files `bot_behaviors`, `bot_personalities` and `bot_difficulties` (`lua/privatewar/kinds/`) belong to the core
  lane: the orchestrator added them before T-5.9 and T-5.12 (`TASKS.md`, "Lanes and ownership"). The entity folders
  `lua/privatewar/bot_behaviors|bot_personalities|bot_difficulties/` belong to the `bots` lane.
- `design/01-extensibility.md` d.17 lists only `bot_behaviors/` (class table `BEHAVIOR`) in its kind table; the class
  tables of the other two kinds are `DIFFICULTY` and `PERSONALITY` (decided in code, item 6).
- A sub-lane never writes a field of another sub-lane's module. Cross-layer needs go through a contract change.

## Blackboard

A per-bot table with documented fields (`07 d.3`: "intents, contacts, goal, orders"). Realm: server only. The
layers read and write it directly; a writer is the **only** module that assigns its fields. Access:
`PW.Bot.Get(bot) -> PW.BotBoard?` (contract; `nil` for a player that is not a managed bot, a human included).
The table is created when the bot is created by `bots_manager` and dropped when it is kicked; a surviving bot keeps
its Lua state across a map change only by re-creation (`00-core.md` d.9: "re-create Lua state for surviving bots").

Written by the manager (T-5.1, decided in code): the board is `{ bot = <Player> }` when the bot is created; the
manager's step (once a second) refreshes `team` from `Player:Team()` while that is an active team (`1..n`), else `nil`
(FFA, spectators). The manager never sets a team: the teams module places the bot. A bot without a board (the engine
`bot` command, other test groups) is not managed: `PW.Bot.Get` returns `nil` and no layer drives it. `difficulty` and
`personality` are given once (T-5.12, see "Profiles"): the manager copies a tier of the setting `bots.difficulty` (a
tier per bot for `mix`) at creation, and a personality as soon as the bot's team is known. The boards live in the weak-keyed `PW._BotsManager.boards`; `PW.Bot.Get(bot)` returns
`PW._BotsManager.boards[bot]`.

| Field | Type | Writer | Readers | Source |
| --- | --- | --- | --- | --- |
| `bot` | `Player` | manager | all | contract |
| `team` | integer? | manager (through `teams`) | commander, perception, brain | design (`07 d.3`: "team via teams") |
| `personality` | plain copy of a `PW.BotPersonality` file (`PW.BotProfiles.Snapshot`: `ClassName`, `Name`, every data field) | manager, once, when the team is known (4:1 rule, "Profiles") | tactics, objectives (`camp` needs `type == "stationary"`), commander | design (`07 d.10`) |
| `difficulty` | plain copy of a `PW.BotDifficulty` tier file (`PW.BotProfiles.Snapshot`) | manager, once, at creation | perception, aim, brain, tactics, objectives | design (`07 d.10`) |
| `tactics` | `PW.BotCombatFacts` (health, magazine, last damage, lethal count, the last cover, `profile`) | `bots_tactics` (scheduler job, period 0.2 s) | `fight`, `take_cover`, `reload_cover`, `retaliate`, `search`, `third_party`, `throw_equipment` | contract (T-5.10a; the shared facts of the survival and combat behaviours) |
| `phase` | number (random offset in seconds) | scheduler | brain, perception | design (`07 d.3`: "random phase per bot"). **Not written to the board**: the scheduler keeps the phase of each registered id, read with `PW.BotScheduler.GetPhase(id)` ("Scheduler budget") |
| `intent` | `PW.BotIntent` (see "Intent") | brain (movement, stance, goal request, target), aim (view, attack button) | input | design (`07 d.3`: "intents") |
| `goal` | `PW.BotGoal?` | `bots_goal` (status and projection); the request is written through `SetGoal` | nav, brain, debug | design (`07 d.6`) |
| `path` | `PW.BotPath?` | `bots_goal` | input (next waypoint), debug | design (`07 d.6`: path) |
| `contacts` | `PW.BotContact[]` | perception | aim, brain, commander | design (`07 d.3`, `07 d.7`) |
| `memory` | `table<Entity, PW.BotContact>` | perception | brain (`search`, `hunt`) | design (`07 d.7`: contact memory 12 s) |
| `target` | `Entity?` | brain | aim, input, debug | design (`07 d.3`: "target") |
| `order` | `PW.BotOrder?` | commander | brain | design (`07 d.3`: "orders") |
| `hunt` | `PW.BotHuntSlot?` | commander | brain (`hunt`, through `PW.BotCommander.HuntView`) | design (`07 d.9`); shape decided in code (T-5.11), "Commander" |
| `behavior` | `{ id: string, reason: string }?` | brain | debug | design (`07 d.5`, `07 d.11`: reason strings feed the overlay) |
| `danger` | per-area cost table reference | nav (baked about once per second) | nav | design (`07 d.6`). **Not on the board**: the baked table is one per navigation service, shared by all bots (`service.GetCostTable()`, "Goal API") |
| `debug` | table (counters, ms per layer) | every writer adds its own counters | overlay | design (`07 d.11`). Written today: `debug.perception = { candidates, traces }`, `debug.aim = { focus, err, tolerance, fire, part, blockedSince }` |

### Tactics relationship reset

The `bots_tactics` owner consumes `PW_PlayerTeamChanging`, `PW_PlayerTeamChanged`, `PW_RoundPreparing`
and `PW_RoundPrepared`, and clears the same owned state on `PW_MatchEnd`.
Each notification synchronously forgets its own hurt/attacker history and
cached `board.tactics` for **all managed bots**, including when a human changes team. Repeated reset
is harmless; it does not produce contacts, start goals, change roles or write another layer's fields.
Scheduler registrations remain intact, and ordinary ticks rebuild fresh facts normally.

Queued cover searches carry unique request tokens. Reset invalidates them without removing another
owner's FIFO jobs. An obsolete callback cannot trace old threat positions, restore cached cover,
consume a newer pending request or write to a replaced board/facts generation. Only the matching live
request writes its owner's `tactics.cover`. This is not a bot teleport or an alternative damage path.
Tests: `bots_tactics_reset.lua`; no optional addon is required for these cases.

Types (the field lists of the rows marked "contract"; names the design does not give are in "Open in design"):

```lua
---@class PW.BotContact
---@field ent Entity         -- the enemy (as decided by PW.IsEnemy)
---@field pos Vector         -- last seen or heard position
---@field vel Vector         -- last known velocity (07 d.7)
---@field time number        -- CurTime() of the last sighting or stimulus
---@field visible boolean    -- currently seen through the reaction queue
---@field source string      -- "sight", "sound", "damage", "shared" or a stimulus kind

---@class PW.BotOrder        -- the commander's order: one objective of MODE:BotObjectives plus the assignment
---@field objective table    -- the objective as returned by MODE:BotObjectives (see "Mode objectives")
---@field type string        -- the objective's action: "capture", "defend", "collect", "deny", "hold"
---@field id string         -- the objective's id (contract addition, T-5.11: the key of the anti-dither rules)
---@field priority number   -- the objective's weight at the last pass, 0..1 (contract addition, T-5.11)
---@field since number       -- CurTime() of the assignment; kept while the bot stays on the same objective and action

---@class PW.BotHuntSlot     -- the commander's hunt slot (T-5.11)
---@field target? Player     -- the human this bot hunts; nil = the bot holds no slot
---@field since number       -- CurTime() the slot was given (or of the pass that wrote "no slot")
```

- `PW.BotContact.dir` (optional unit `Vector`): set by the `damage` stimulus, the direction from the victim to the
  attacker (T-5.7).
- `PW.BotOrder.type` is the `action` of `modes.md` "`BotObjectives`" (an order is the objective a bot was assigned,
  `07 d.14`). A hunt assignment is carried by the `hunt` slot, not by `order` ("Commander"). A bot with an `order` never holds a hunt slot.
- Everything not in this table is private to its module. A module that needs a field another module owns asks
  through a contract change, not by reading its internals.

## Intent

The brain and the aim controller write intents, the input writer turns them into `CUserCmd` every tick. The design
fixes only the content of the intent line of its diagram: "`SetGoal(point, radius, priority)`, target, stance,
buttons" (`07 d.3`), the two separate channels ("target/aim and legs/movement are independent controllers writing
different `CUserCmd` fields", `07 d.5`) and the fairness rule (`07 d.2`: a bot acts only through `CUserCmd`: view,
movement, buttons; no `SetPos`, no damage, health, ammo or spread change).

```lua
---@class PW.BotIntent                     -- shape: contract; the groups are from 07 d.3 and 07 d.5
---@field goal? PW.BotGoalRequest          -- legs channel: written only through bot:SetGoal (see "Goal API")
---@field target? Entity                   -- aim channel: who to look at and shoot
---@field stance? "stand"|"crouch"         -- "crouch" holds IN_DUCK; nil or "stand" does not (T-5.2)
---@field buttons integer                  -- IN_* mask the brain wants held this tick (not view, not movement)
---@field view? Angle                      -- aim channel output (aim controller), the wanted view angles
---@field viewTarget? Angle                -- legs channel: walking view target; bots_input turns the view toward it per tick
---@field viewSpeed? number                 -- legs channel: max degrees per second toward viewTarget (turn_max_speed)
---@field move? Vector                     -- legs channel output (path follower): forward, side, up, as CUserCmd
---@field weapon? string                   -- class to select (T-5.2); nil keeps the active weapon
---@field sprint? boolean                  -- legs channel (T-11.6): IN_SPEED while moving forward; no attack while set
---@field drive? Vector                    -- legs channel (T-11.6): forward, side move used when `move` is nil
---@field slideAt? number                  -- legs channel (T-11.6): CurTime() of a Quick Slide request
```

Rules the input writer follows (the core rules are in `adapter.md` "Bot input rules" and are not repeated):

1. The only output is `CUserCmd`: `SetViewAngles`, `SetForwardMove`, `SetSideMove`, `SetUpMove`, `SetButtons`,
   `SelectWeapon` (`07 d.2`, `adapter.md`). Button bits are written, not only the move values.
2. The input writer runs in `GM:StartCommand` through `PW.HookFor`, for bots only (`IsBot()`), every tick.
3. The adapter of the bot's weapon decides per-base quirks through `ADAPTER:GetInputRules(wep)`, `GetFireInfo(wep)` and
   `BotAction(ply, wep, action, arg)` (`adapter.md`); the writer never branches on a weapon base.
4. The AI uses the core's own PRNG, not `math.random` (`adapter.md` "Bot input rules", rule 4).
5. The intent of a tick is final once `StartCommand` runs: a module changing it later has no effect.

Decided in code (T-5.2, `bots_input`; the values are the lane agent's decisions, to be confirmed):

1. Fields: `stance` is `"stand"` or `"crouch"`; `weapon` is the class to select (the field is new, not in the design).
   ADS is `IN_ATTACK2` in `buttons`. A `nil` `view` keeps the current eye angles, a `nil` `move` is `0, 0, 0`.
2. An intent of `nil` (a managed bot whose brain wrote nothing) makes the bot stand still: no buttons, no movement,
   the current eye angles.
3. Button bits of the move values are added (`IN_FORWARD`, `IN_BACK`, `IN_MOVELEFT`, `IN_MOVERIGHT`).
4. Besides `SetViewAngles` the writer also calls `SetEyeAngles` with the same angles: a bot moves along the
   `CUserCmd` view, but its eye angles (what weapons aim along) otherwise keep the spawn angles (verified in game).
5. Weapon select: the class is sent every tick until it is active when the adapter rule `reselectEveryTick` is set,
   else once per request.
6. Which bots the writer drives: a bot with a scripted intent (`PW.BotInput.SetScripted`, the dev command) or with a
   board (`PW.Bot.Get`); the scripted intent wins. Other bots are left alone.
7. Dev command `pw_bot_intent <bot name|*> clear | stop | [forward=N] [side=N] [up=N] [pitch=N] [yaw=N]
   [weapon=<class>] [attack] [attack2] [reload] [jump] [crouch] [sprint] [walk] [use]` scripts an intent; `clear`
   drops the scripted one. The name is a case-insensitive substring. Privilege `pw.bots.debug` (default
   `superadmin`); the server console may always use it.

Decided in code (T-11.6, combat movement; see "Combat movement"):

1. `sprint`, `drive` and `slideAt` are written by the behaviours (the brain) and belong to the top frame of the
   stack: when another behaviour becomes the top, the brain clears all three (brain decision 10), so a sprint or a
   strafe never outlives the behaviour that set it.
2. Merge rule for `move` (closes the `move` part of item 3): the path follower's `move` wins; `drive` is used only
   while the follower writes no move (no active goal). A behaviour that strafes or rushes with `drive` clears its goal
   first.
3. `sprint` adds `IN_SPEED` only while the forward move is above 0 and removes `IN_ATTACK` and `IN_ATTACK2`: a running
   bot does not shoot (CoD rule). A sprinting behaviour drops the aim target (`PW.BotTactics.Run`), so the follower
   owns the view and the bot runs facing its path.
4. `slideAt` is ignored unless the Quick Slide addon was detected (`PW.BotQuickSlide.Available()`). With it, the
   writer holds `IN_DUCK` for the addon's slide duration after `slideAt` and adds `IN_SPEED` (and removes the attack)
   during the first `PW.BotInput.SlideStart` (0.15) seconds: the addon starts a slide on duck plus sprint.

Closed in part (T-5.6, T-5.8): the view ownership rule, see "View ownership". Still open (item 3): how `move` is merged when several
writers want it, the intent for equipment and streak use.

## Goal API

`bot:SetGoal(point, radius, priority)` (`07 d.6`). `bot` is a managed bot (`Player` method, installed by
`bots_nav`; `PW.Bot.SetGoal(bot, point, radius, priority)` is the same call without the metatable).

| Argument | Type | Meaning |
| --- | --- | --- |
| `point` | `Vector` | Where to go |
| `radius` | number | Arrival radius, in units |
| `priority` | string | `"hunt"` < `"guard"` < `"objective"` < `"tactical"` < `"critical"` |

- **Built in T-5.6** (`bots_goal`, a sub-module of the nav sub-lane; the contract named `bots_nav`, but `bots_nav`
  stayed the pure path service `PW.BotNav`, below). `PW.Bot.SetGoal(bot, point, radius, priority) -> accepted, status`,
  `bot:SetGoal(...)` (the same call) and `PW.Bot.ClearGoal(bot)`. `SetGoal` returns `false, nil` for a bot without a
  board; an unknown priority is an assertion error.
- Arbitration (decided in code; closes item 4 in part): a goal of a lower priority is refused (`false`, the status of the
  running goal); at an equal or higher priority the new goal replaces the running one, except that a request for the
  same point (within 32 units) with the same radius and an equal priority is "same" and keeps the running path
  (`true`, the running status). A finished goal (`arrived`, `failed`, `unreachable`) never blocks: any priority replaces it.
- Projection: the point is projected on the navmesh (an area within 256 units, `PW.BotGoal.Project`). No area:
  the goal ends at once as `unreachable`, reason `"off navmesh"`, and the request returns `true, "unreachable"`.
- Blacklist: per bot, 64-unit cells of the projected point for 30 s. A goal that ends `unreachable` by a proof or by
  retries, or `failed` as stuck, adds its cell; a request for a blacklisted cell returns `false, "unreachable"` (an
  active goal stays; a finished one is replaced by an `unreachable` goal with reason `"blacklisted"`).
- Status, `board.goal.status` (`PW.BotGoalStatus`): `"moving"` (searching or following), `"arrived"` (within `radius`
  of the projected point), `"failed"`, `"unreachable"`. `board.goal.reason` explains the last two: `"stuck"` (the stuck
  ladder gave up), `"died"`, `"no navmesh"`, `"off navmesh"`, `"no path"` (the path service proved it), `"retries"`
  (four path requests without a path), `"blacklisted"`.
- `board.goal` is `{ point, radius, priority, status, since, projected?, reason?, repaths? }` (`PW.BotGoal`);
  `board.path` is `{ points, index, partial }` (`PW.BotPath`): waypoints, the one the bot walks to, and whether the
  search ended short of the goal (a partial path ends at the closest expanded area, then the follower asks again).
  `bots_goal` is their only writer. A dead bot (death hook) ends its goal as `failed`, `"died"`; a disconnect drops the state.
- Follower: one scheduler job per bot with an active goal (period 0.1 s). It writes `intent.move`, `intent.viewTarget` and
  `intent.viewSpeed` (the view toward a point 160 units ahead on the path and the turn speed; `bots_input` steps the
  view toward it on every StartCommand tick by at most `viewSpeed` x tick interval, then stores the result in
  `intent.view`; not written while `PW.BotAim.OwnsView` is true, the aim then clears both, see "View ownership") and its own `IN_*` bits of
  `intent.buttons` (removed again when the goal ends). The stuck ladder, in the order of `07 d.6`: jump, crouch, back
  off, side step, repath, give up; one rung per 1 s window in which the remaining path length dropped by less than 24
  units. Doors (`prop_door_rotating`, `func_door`, `func_door_rotating`) within 72 units of the eyes ahead: `+use`
  once, wait 0.75 s, again after 1.5 s. Ladders are not planned over (the graph of `PW.BotNav` has no ladder links);
  a bot already on a ladder looks toward the next waypoint and walks forward (the follower then writes `intent.view`
  itself, unstepped, even while the aim owns it).
- Dev command `pw_bot_goto <bot name|*> here | <x> <y> <z> | clear | status [radius] [hunt|guard|objective|tactical|critical]`:
  `here` is the point under the caller's crosshair (a player is needed), radius defaults to 64 and priority to
  `critical`. The name is a case-insensitive substring. `status` prints the goal, reason and waypoint and draws the
  remaining path for 5 s (`debugoverlay`, `developer 1`). Privilege `pw.bots.debug` (default `superadmin`); the server
  console may always use it. Priorities rank `hunt` 1 to `critical` 5 (`PW.BotGoal.Priorities`).
- Navmesh data: `PW.Map.GetNavAreas()` (`map.md`); on a map without a navmesh no bot is created (`map.md` "Open in
  design", item 10).
- The engine `Path("Follow")` fallback of `07 d.6` is not used.

Cost layers (`07 d.6`): modules register path cost terms that are baked into a per-area table about once per second;
the A* inner loop never calls hooks. Decided in code (T-5.5, `bots_nav`):

```lua
PW.BotNav.RegisterCostLayer(id, layer)    -- layer: fun(node, graph) -> extra cost in distance units
PW.BotNav.UnregisterCostLayer(id)         -- returns boolean
```

- `node` is the navigation area id (an integer; `CNavArea` userdata are not stable keys), `graph` the `PW.NavGraph` of
  the service (`Position(node)` gives the area centre). A negative or non-number answer counts as 0 (the heuristic
  stays admissible); an erroring layer counts as 0 and is counted in `layerErrors`. Registering an existing `id`
  replaces the layer.
- Layers are baked into one table node to extra cost, 256 nodes per tick, about every 1 s or at once after a layer
  changed; the finished table replaces the old one. The step cost is `graph.Cost(from, to) + baked[to]`. That table is
  one per service, shared by all bots (the contract's `danger` field is therefore not per bot).
- The sample layer `danger` (recent deaths, falls off with distance and age, decays in 120 s) is registered by the
  module itself; `PW.BotNav.Danger` holds it.
- Path requests: `PW.BotNav.RequestPath(fromPos, toPos, callback?)` returns a `PW.NavHandle`, or `nil` without a
  navmesh or an area near a point. A request is asynchronous: a handle (`status` `"queued"`, `"running"`, `"found"`,
  `"partial"`, `"unreachable"` or `"cancelled"`, `path` as area ids, `positions`, `done`) and an optional callback when
  done; `PW.BotNav.Cancel(handle)`.
- A search expands at most 4000 nodes, then ends `"partial"` with the path to the expanded node closest to the goal.
  Only a search that exhausted its open set is `"unreachable"` and fills the cache of unreachable pairs (30 s). A
  slice is at most 150 expansions or 1 ms; each slice is one job of the scheduler FIFO.
- Removing the layers of a disabled module automatically is not done: the module calls `UnregisterCostLayer`
  (item 5, remainder).

## Aim API

Module `bots_aim` (T-5.8): a spring-damper over the view angles, a focus error that shrinks while the aim is steady, target
lead, the headshot gate, recoil compensation and the fire decision. The aim step runs for every bot with a target in the
`Tick` hook (every server tick, `07 d.3`); the result goes into the intent that the input writer uses.

| Function | Contract |
| --- | --- |
| `PW.BotAim.SetTarget(bot, target, tier?)` | Server. Dev and test override: aims `bot` at an `Entity` (fires at it) or a `Vector` (look-at point, never fires); `nil` clears it. `tier` (`recruit`, `regular`, `hardened`, `veteran`) replaces the bot's difficulty for the aim until the override is cleared. The override wins over `intent.target` and `board.target` |
| `PW.BotAim.GetState(bot) -> PW.BotAimState?` | The aim state (`p`, `y`, `focus`, `err`, `tolerance`, `part`, `fire`, `blockedSince`, ...), `nil` while the bot has no target |
| `PW.BotAim.OwnsView(bot) -> boolean` | `true` while the aim drives the bot's view (it has a target and a state) |

- Target (decided in code): the override, else `intent.target`, else `board.target`. A brain target is aimed only while
  perception knows it (`board.contacts`): a visible contact at its live body part and with fire allowed, a remembered one at
  the contact position without fire (no wallhack, `07 d.2`). An override target perception does not know is aimed at
  directly and may be fired at (a debug tool).
- Output: `intent.view` and the `IN_ATTACK` bit of `intent.buttons`, written while there is a target. On release (no
  target, dead target, dead bot) the aim clears `IN_ATTACK` once and forgets its state; the view stays where it was.
  A bot driven by nothing gets a scripted intent from the aim for the duration of an override.
- Fire gate: the view within the tolerance for 0.05 s, the attack
  delay of the tier since acquisition passed, a target seen now, and one `MASK_SHOT` line-of-fire trace clear (the target
  or another enemy; the world or a teammate blocks). A blocked shot shows as `blockedSince` set.
  The tolerance (0.4 to 12 degrees) is the angle of the CS fire half size at the target's range (`Config.fireHalfSize` 32
  units, `fireHalfSizeSniper` 16 for a sniper rifle) plus `Config.focusTolerance` (0.15) times the current focus error. The
  view is compared with the goal, which carries the focus error.
  - Settle hysteresis: once the view is settled (`settledSince` set), the bot keeps the fire permission until the error
    exceeds `Config.holdTolerance` (2) times the tolerance (capped at `maxTolerance`). Without it the spring, which lags the
    wandering goal by a few degrees after each re-roll, chattered the gate open and closed and delayed the first shot by up
    to 2 s. Leaving the hold band clears `settledSince` and `blockedSince`.
  - Line of fire: the trace runs from the eye through the aimed point, `Config.traceSlack` units past it
    (`lib.FireRayEnd(eye, point)`, pure), not along the current view direction, so a view that still lags does not make the
    trace miss or hit cover beside the target.
  - Focus is not reset when the sight toggles: when `canFire` changes between two steps (the target is lost or seen
    again), the aim point jumps between the remembered and the seen position, but the target did not move. The step skips
    the movement measure for that tick (`s.sighted` remembers the last `canFire`), so the focus error does not reset to its
    initial value; the spring still turns the view. `Acquire` clears `sighted`.
  - A flicker of the perception sight (a contact seen and lost on alternate ticks) therefore no longer resets the aim
    focus or the settle state.
- Tier: the bot's `board.difficulty` (T-5.12 data, read with `PW.BotProfiles.Pick`; the fields are declared with
  `PW.BotProfiles.Reads("difficulty", "aim", ...)`); a board without one reads the regular tier. The values are the files in
  `bot_difficulties/` (the table is in the local manual checklist (not published), section 7, item 21).
- Debug: `board.debug.aim = { focus, err, tolerance, fire, part, blockedSince }`, refreshed each aim tick.
- Dev command `pw_bot_aim <bot name|*> <player name|me> [recruit|regular|hardened|veteran] | clear | status`: `me` is the
  caller; `clear` drops the override; `status` prints `part`, `focus`, `err`, `tol`, `fire` and `blocked` per bot (or "has
  no target"). Privilege `pw.bots.debug`; the server console may always use it.

Engagement latency (regression test `lua/tests/privatewar/bots_engagement.lua`):

- `PW.BotTactics.Config.fightGrace` = 1 s: a running `fight` keeps its target through a sight gap this short (a turn, a
  strafe behind a post) instead of ending as lost.
- The brain wakes on a new visible enemy: a visible contact that was not visible on the previous tick drops every cached
  evaluation, so the behaviours re-rank in the same tick, not after their interval. Losing sight is no event.
- `third_party` looks toward the heard fight the whole time (a `Vector` look-at target of the aim, never fired at), and
  clears a vector target when it ends.
- The path follower's view is limited to the difficulty's `turn_max_speed`: `PW.BotGoal.TurnToward(from, to, maxSpeed, dt) ->
  Angle` turns each of pitch and yaw by at most `maxSpeed * dt` toward the wanted angles (pure, shared).
- Perception never skips a reaction snapshot: a tick recognises the latest snapshot that is old enough plus every enemy of
  the snapshots that became old enough since the previous tick (`state.recognisedTo`, perception decision 10).

## View ownership

Closes the view part of item 3. `intent.view` has two writers: the path follower (`bots_goal`, legs channel) and the aim
(`bots_aim`, aim channel). **Rule: the aim owns the view while it has a target; otherwise the path follower does** (the
move then follows the current view, so a bot can walk a path while looking at an enemy).

Implemented (T-5.9): the follower asks `PW.BotGoal.FollowerOwnsView(aim, bot)` (true when the aim module is missing or
`PW.BotAim.OwnsView(bot)` is not true) and skips writing `intent.view` while it is false. A target set through the
brain (`board.target`, `intent.target`) or through `PW.BotAim.SetTarget` (`pw_bot_aim`) owns the view the same way. The
walking direction is computed from the view in force (`intent.view`), so the legs keep following the path. **Exception:
on a ladder (`MOVETYPE_LADDER`) the follower always writes the view** (toward the next waypoint, pitched 70 degrees up or
down), because climbing needs it.

## Walking view smoothing

The path follower runs at 10 Hz but `bots_input` runs every server tick, so the walking view is stepped per tick instead
of snapped (a snap of up to 170 degrees in one follower tick turned bots away from an enemy before perception could see
it).

- The follower writes `intent.viewTarget` (an `Angle`: the view toward a point 160 units ahead on the path) and
  `intent.viewSpeed` (the difficulty's `turn_max_speed`, degrees per second: 180 recruit, 360 regular, 720 veteran). When
  it has no target angle it writes both as `nil`.
- `PW.BotInput.StepView(eye, target, speed, dt) -> Angle` (pure): moves pitch and yaw of `eye` toward `target` by at most
  `speed * dt` degrees on each axis (shortest way round, normalized, roll 0).
- In `StartCommand` the writer uses `StepView` with `dt = engine.TickInterval()` when `viewTarget`, `viewSpeed` and `dt`
  are all present; otherwise it uses `intent.view`, else the current eye angles. After the step it stores the result in
  `intent.view`, so when the target goes away the bot keeps looking where it looked.
- The aim owns the view while it has a target: on every write it sets `intent.view` and clears `viewTarget` and
  `viewSpeed` (see "View ownership"). On a ladder the follower writes `intent.view` itself, unstepped.

## Stimuli

`PW.Bot.AddStimulus(botOrTeam, kind, data)` (`07 d.7`). Modules feed contacts through it: for example the UAV streak
reveals enemies to a team's bots exactly as the radar shows them to humans.

| Argument | Type | Meaning |
| --- | --- | --- |
| `botOrTeam` | `Player` (a bot) or integer (a team index) | Who gets the stimulus |
| `kind` | string | The kind of stimulus, see the list below |
| `data` | table | `{ ent, pos, vel?, time?, dir? }` (below) |

- Perception (`bots_perception`, T-5.7) receives it and adds it to the contact memory of the target bot or of every
  bot of the team (`PW.BotContact.source` = the kind).
- Named stimulus sources in the design: gunfire (`EntityFireBullets`, suppressors respected), footsteps of sprinting
  players, explosions (`EntityEmitSound`), damage taken (the attacker's direction), team sharing with `share_delay`
  (`07 d.7`). Never map-wide hearing.
- Must tolerate a team index with no bots and an invalid bot (no error).

Decided in code (T-5.7, `bots_perception`):

- Kinds: `"gunfire"`, `"gunfire_suppressed"`, `"footstep"` (sprinting players only), `"explosion"`: sounds, the
  listener hears them only within the hearing range below; `"damage"`: the direction of the attacker (the stimulus
  reveals a point at most 800 units from the victim's eyes along that direction, `dir` is set); `"shared"`: team
  sharing; any other string a module chooses (for example `"radar"` for a UAV) is stored as the contact's `source` and
  is not filtered by range.
- `data`: `ent` (the enemy it is about; required, memory is keyed by entity) and `pos` (a `Vector`; required); `vel`,
  `time` (default `CurTime()`) and `dir` are optional. A stimulus about an entity that is not an enemy of the bot
  (`PW.IsEnemy`) is dropped. A sound position is moved by an error of up to a tenth of the distance.
- `PW.Bot.AddStimulus` returns the number of bots that took the stimulus (`0` for bad input; it never errors). A table
  in place of `kind` is the stimulus itself with its kind in the field `kind`.
- Hearing ranges, in units: gunfire 2500, suppressed 500, sprint footsteps 450, explosion 3500. A kind not listed is
  never heard. Sprint footsteps need a horizontal speed above 150.
- Other numbers: field of view 110 degrees, sight range 4500, memory 12 s (fixed by `07 d.7`; `contact_memory` of a
  difficulty is ignored), at most 6 line-of-sight traces per bot per tick (head, chest, feet), reaction delay and
  sharing per tier as in the table below.
- Sharing: a sighting recognised through the reaction queue is offered once a second per enemy to teammates; the
  receiver gets it after its own `share_delay`, within its `share_radius` of the sender, as a position (`source`
  `"shared"`, not visible).
- `contacts` is every memory entry, the seen first, then the newest. The search plan is not a field:
  `PW.Bot.GetSearchPlan(bot, ent?)` returns the 5 points (last seen, ahead, left, right, far ahead; offsets 350, 300,
  800 units, snapped to the navmesh) or `nil`, from the given lost contact or the freshest lost one.

| Tier | `reaction_mean` | `reaction_floor` | `reaction_jitter` | `share_delay` | `share_radius` |
| --- | --- | --- | --- | --- | --- |
| recruit | 0.60 | 0.25 | 0.35 | 2.0 | 800 |
| regular | 0.45 | 0.20 | 0.30 | 1.5 | 1200 |
| hardened | 0.32 | 0.18 | 0.25 | 1.0 | 1575 |
| veteran | 0.22 | 0.15 | 0.20 | 0.5 | unlimited |

The tier is the bot's `board.difficulty`; the table repeats the data files in `bot_difficulties/` (T-5.12), which win.

## Kinds

Entity files of three kinds, all data or Action classes, loaded by the core loader (`core.md` "Kinds"). Per-entity
enable ConVars exist as for any entity (`core.md` "Enable ConVars"). The kind declaration files are written by the
orchestrator (see "Ownership").

### `bot_behaviors` (class table `BEHAVIOR`, `01-extensibility.md` d.17; `07 d.5`)

```lua
BEHAVIOR.Modes    = { "dom" }                 -- nil = every mode
BEHAVIOR.Interval = 0.5                       -- re-evaluation interval, s

function BEHAVIOR:Rank(bot, ctx)   end        -- hard priority bucket
function BEHAVIOR:Weight(bot, ctx) end        -- nuance
function BEHAVIOR:OnStart(bot, ctx) end
function BEHAVIOR:Update(bot, ctx) end        -- returns Continue / ChangeTo / SuspendFor / Done(reason)
function BEHAVIOR:OnEnd(bot, ctx) end
function BEHAVIOR:OnSuspend(bot, ctx) end
function BEHAVIOR:OnResume(bot, ctx) end
```

- Fields and methods as in `07 d.5`; the rest of this subsection is the behaviour of the brain (`07 d.4`).
- Dual-utility: every behaviour has a rank (hard bucket) and a weight (nuance). Options much worse than the best are
  screened out; among the rest the choice is weighted-random; a lower difficulty widens the screen
  (`decision_screen`). The current behaviour gets a commitment bonus, a minimum run time and cooldowns. A behaviour
  may declare its own re-evaluation interval (default 1000 ms, minimum 100 ms).
- Action stack (`07 d.5`): a behaviour can be suspended by an urgent one and resumed. Transitions are return values
  (`PW.Bot.Continue()`, and the other three), so addons cannot force each other's state. Reason strings feed the debug
  overlay.
- The 11 MVP behaviours (`07 d.13`): `fight`, `take_cover`, `reload_cover`, `retaliate`, `search`, `hunt`,
  `objective`, `third_party`, `use_streak`, `throw_equipment`, `camp`. Domination and Kill Confirmed need no
  dedicated behaviour: `objective` performs the order from `MODE:BotObjectives` (`07 d.13`, `07 d.14`). The folder also
  has `idle` (T-5.9), the roam-bucket fallback.
- Decided in code (T-5.9, `bots_brain`): the bucket order is `survival` 40 > `combat` 30 > `objective` 20 > `roam` 10
  (`PW.BotBrain.Buckets`; closes item 1 in code). `Rank` returns a bucket name or a number greater than 0; `nil`, `false`
  or a value of 0 or less means "not a candidate now". The transition constructors are `PW.Bot.Continue()`,
  `PW.Bot.ChangeTo(id, reason?)`, `PW.Bot.SuspendFor(id, reason?)` and `PW.Bot.Done(reason?)` (also on `PW.BotBrain`);
  `Update` returning nothing counts as `Done`. Optional fields: `Modes`, `Interval` (default 1 s, minimum 0.1 s),
  `MinRun`, `Cooldown`. The brain runs at 10 Hz per bot with a random phase (scheduler id `"brain:<UserID>"`), on
  `CurTime()`; a dead bot ends its whole stack.
- `ctx` (closes the `ctx` part of item 3): `bot`, `board`, `now`, `running` (id of the running behaviour), `state` (the
  frame's per-run table, set only inside the lifecycle methods), `order`, `contacts`, `memory`, `goal`, `target`, and the
  helpers `ctx:Intent()`, `ctx:SetGoal(point, radius, priority)`, `ctx:ClearGoal()`, `ctx:GoalStatus()`,
  `ctx:SetTarget(ent)` (writes `board.target` and `intent.target`; a `Vector` is a look-at point that is never fired
  at), `ctx:Contact(ent)` and `ctx:SearchPlan(ent?)`. The helpers of the other modules cache extra fields on it
  (`facts`, `recent`, `checked`, `lastObjective`).

Built-in behaviours (T-5.9, T-5.10a, T-5.10b; the numbers are the lane agents' decisions, to confirm; all use `Modes = nil`).
The bucket is the rank a behaviour returns; `take_cover` and `reload_cover` return different buckets by situation.

| Id | Bucket | Weight | `Interval` / `MinRun` / `Cooldown`, s | Runs when |
| --- | --- | --- | --- | --- |
| `retaliate` | survival | 1.2 | 0.1 / 0.3 / 0.5 | damaged by an attacker it does not see (damage within 1.5 s); makes the attacker the aim target; ends when seen or after 2.5 s |
| `take_cover` | survival, combat | survival 0.6 + 0.4 x (1 - health share), +0.1 outnumbered; combat 0.3 + `cover_chance`, at least 1 while running | 0.25 / 1.5 / 3 | `PW.BotTactics.CoverWanted` (T-11.6): a threat is known and a fresh cover with a peek point exists (a running take_cover keeps its own). Survival: health below 0.5, or damage within 2.5 s or two or more enemies in sight while the threat is at least 250 units away. Combat: the bot sees the enemy (or already takes cover), the enemy is farther than 500 units and `cover_chance` > 0; fight also hands over to it (ChangeTo) by `cover_chance` after 1.5 s of fighting. Runs to the cover (a sprint, aim released, when under pressure and farther than 150), then hide (crouched) and peek (stand up, or step out with a Quick Slide), at most 3 cycles |
| `reload_cover` | survival, roam | survival 0.9 (empty magazine) or 0.7; 0.5 while flanking back; roam 0.5 | 0.2 / 0.5 / 1 | survival: a threat is known (8 s) and the magazine is at or below 25 %; goes to cover when one exists and the threat is farther than 400, reloads crouched, then flanks toward the threat. Roam: no threat and the magazine at or below 50 % (a calm reload in place) |
| `fight` | combat | 1 | 0.25 / 0.5 / none | an enemy is visible; strafe (a direct sideways `drive`, the other side when the navmesh ends) or crouch by the profile in legs of 0.35 to 1.45 s (shorter for a higher `mobility`), approaches when farther than `engage_range` (a sprint by `mobility`), steps aside when blocked for 0.4 s; a fresh hit while strafing may be dodged with a Quick Slide; without a melee weapon a target within 110 units gets the adapter's `BotAction(ply, wep, "melee")` every 0.8 s (T-11.6) |
| `melee` | combat | 1.6 | 0.2 / 0.4 / 0.5 | T-11.6: a visible enemy within 110 units (about 2 m), or within 350 while the gun is dry (empty magazine, no reserve), and the bot carries a melee weapon (catalogue `Kind` `"melee"`, else a melee hold type): selects it (`intent.weapon`), runs straight at the target (`drive`; a Quick Slide from 150 to 450 units) and lets the aim swing; ends when the target is lost or farther than 220 units with a gun that can shoot, then selects the previous weapon again. `reload_cover` yields to it |
| `search` | combat | 0.3 to 0.7 (falls with the age of the contact) | 0.5 / 1 / 2 | an enemy was seen and lost (not a fight sound) within 12 s; walks the 5 search points of perception, 0.6 s pause at each, gives up after 20 s |
| `third_party` | combat | 0.5 + 0.3 x `aggression` | 0.5 / 1 / 3 | gunfire or an explosion of an enemy was heard within 6 s and 3000 units and no enemy is visible; waits `third_party_delay`, flanks, then closes in; gives up after 15 s |
| `throw_equipment` | combat | 1 | 0.5 / 0.5 / 12 | an enemy seen within 4 s is lost, 300 to 1800 units away, and the bot has lethal equipment (`PW.Equipment.Count`); looks at the remembered position (the aim never fires at a remembered contact), waits 0.6 s for the turn (gives up waiting after 2 s when the aim error stays above 8 degrees), then uses the lethal slot through `PW.Equipment.Use`. Works since T-4.5 (the equipment module, `equipment.md`); without the module the bot has no lethal and the behaviour never runs |
| `objective` | objective | order: (0.55 + 0.45 x objective weight) x (0.5 + 0.5 x `teamwork`); local pick: 0.3 + 0.6 x score | 0.5 / 2 / none | there is an objective (the order, else `PW.BotObjectives.Resolve` over the derived objectives, see "Mode objectives"); `capture` and `hold` drift inside the zone, `defend` guards around it, `collect` and `deny` walk onto the tag |
| `use_streak` | objective | 0.9 | 0.5 / none / 3 | `PW.BotObjectives.Facts(ctx).streak` is set; wired by T-4.6: `PW.BotObjectives.ReadyStreak(bot)` calls `PW.Streaks.Ready` (the first inventory streak whose `STREAK:BotShouldUse` agrees), `UseStreak(ctx, id)` calls `PW.Streaks.Use`; both return nothing and `false` without the streaks module (`streaks.md`) |
| `hunt` | roam | hot spot 0.3 + 0.5 x score; roaming 0.25 | 1 / none / none | always when a hot spot (an enemy heard or lost within 20 s, a teammate's death within 45 s) or a roam point exists; otherwise roams the navmesh and sometimes pauses to look around |
| `camp` | roam | 0.6 | 1 / none / 8 | `personality.type == "stationary"` only; holds a spot crouched for 25 to 45 s and watches two entrances |
| `idle` | roam | 0.01 | 1 / none / none | the fallback, so some behaviour always runs: releases the buttons and stands |

- `STREAK:BotShouldUse(bot)` and `EQUIPMENT:OnUse` are owned by the loadout lane (`05-loadout.md`); the behaviour
  `use_streak` calls them through `PW.Streaks` (`ReadyStreak` to `Ready`, `UseStreak` to `Use`, T-4.6).

### `bot_personalities` (`07 d.10`)

One data file per personality in `lua/privatewar/bot_personalities/` (`run_and_gun`, `cqb`, `camper`), class table
`PERSONALITY`, registry `PW.BotPersonalities`. Decided in code (T-5.12; closes the personality part of item 6):

- Kind: `KIND.Folder = "bot_personalities"`, `KIND.Global = "PERSONALITY"`, `KIND.Subscribe = "never"`,
  `KIND.Required = { Name = "string", type = "string" }`. Per-entry ConVar `pw_personality_<id>_enabled`.
- Fields (all numbers except `type`; the reader is the module that declared it):

| Field | Meaning | Reader |
| --- | --- | --- |
| `Name`, `Description` | display name and text (meta, not profile data) | UI |
| `type` | `"active"` or `"stationary"`; only a `stationary` personality runs `camp` | `bots_objectives`, `bots_manager` (the 4:1 rule) |
| `crouch_chance` | chance to crouch when a fight leg stops | `bots_tactics` |
| `aggression` | 0..1, raises the weight of `third_party` | `bots_tactics` |
| `engage_range` | units; a target farther away is approached | `bots_tactics` |
| `cover_chance` | 0..1, the weight of a combat-bucket `take_cover` | `bots_tactics` |
| `flank_radius` | units; sideways offset of flank points | `bots_tactics` |
| `third_party_delay` | seconds before a heard fight is flanked | `bots_tactics` |
| `mobility` | 0..1 (T-11.6): shorter strafe legs (jitter) and the chance to sprint a long leg (hunt, objective, fight approach) | `bots_tactics` |
| `class_weights` | table (not a number): category of the primary weapon to weight; unlisted weighs 1, `0` removes | `bots_loadouts` |

- Values: `run_and_gun` (active) 0.1 / 0.8 / 1500 / 0.3 / 450 / 0.5, `cqb` (active) 0.25 / 0.65 / 900 / 0.5 / 300 / 1,
  `camper` (stationary) 0.6 / 0.2 / 2500 / 0.8 / 600 / 3, in the order `crouch_chance`, `aggression`, `engage_range`,
  `cover_chance`, `flank_radius`, `third_party_delay` (the data files win: `run_and_gun` has `cover_chance` 0.3).
  `mobility` (T-11.6): `run_and_gun` 0.9, `cqb` 0.7, `camper` 0.3.
- Default ratio per team: 4 active : 1 stationary (`07 d.10`), see "Profiles". A `stationary` personality is the
  only one that runs `camp` (`07 d.9`, `07 d.13`, `07 d.14`). Preferring `defend` objectives is the commander's part
  (T-5.11); `camp` itself picks a spot near a defended objective when there is one.

### `bot_difficulties` (`07 d.10`, `07 d.15`)

One data file per tier in `lua/privatewar/bot_difficulties/` (`recruit`, `regular`, `hardened`, `veteran`), class table
`DIFFICULTY`, registry `PW.BotDifficulties`. Decided in code (T-5.12; closes the difficulty part of item 6):

- Kind: `KIND.Folder = "bot_difficulties"`, `KIND.Global = "DIFFICULTY"`, `KIND.Subscribe = "never"`,
  `KIND.Required = { Name = "string" }`. Per-entry ConVar `pw_difficulty_<id>_enabled`.
- Fields: 25 per tier besides `Name` and `Description`, all numbers except `headshot_allowed` (`"no"`, `"rifles"`,
  `"yes"`). Every field is read by a module that declared it with `PW.BotProfiles.Reads`; a field nobody reads, or a
  declared field a file lacks, fails the T-5.12 test.

| Reader | Fields |
| --- | --- |
| `bots_aim` | `look_stiffness`, `look_damping`, `look_max_accel`, `turn_max_speed`, `aim_focus_initial`, `aim_focus_decay`, `aim_focus_floor`, `aim_focus_reset_deg`, `aim_reroll_interval`, `aim_offset_scale`, `attack_delay`, `lead_target`, `headshot_allowed`, `headshot_chance`, `recoil_comp_gain` |
| `bots_perception` | `reaction_mean`, `reaction_floor`, `reaction_jitter`, `share_delay`, `share_radius`, `fov` |
| `bots_brain` | `decision_screen`, `commitment_bonus` |
| `bots_objectives` | `teamwork` (how likely a bot follows an order; scales the weight of `objective` with an order) |
| `bots_tactics` | `strafe_chance`, `slide_chance` (T-11.6; 07 d.15: 0 / 0.2 / 0.4 / 0.6) |

- Values: the table of the local manual checklist (not published) section 7, items 18, 21 and 29. They are starting points, tuned in game
  without code changes. Fairness (`07 d.2`): difficulty changes only human parameters; a dynamic adjustment may only
  nerf bots.
- Fields of `notes/14-industry-bot-ai.md` that no module reads are **not** in the data: `flick_overshoot`, `burst_len`,
  `danger_memory`, `contact_memory` (`07 d.7` fixes the memory at 12 s), `target_persistence`, and the manoeuvre chances
  dive and corner fire (the slide chance is `slide_chance` since T-11.6). A module that wants one declares it and adds it to every file. "Sight time" (item 6) has
  no field.
- The setting `bots.difficulty` is the four tier ids plus `mix` (`modes.md`, "`bots.fill` and `bots.difficulty`"); see
  "Profiles".

## Profiles

`PW.BotProfiles` (T-5.12; `modules/bots/sh_profiles.lua`, shared, loaded by `bots` before the other `bots_*` modules so
that they can declare their reads at load time). Pure glue around the two data kinds.

| Function | Contract |
| --- | --- |
| `PW.BotProfiles.Reads(kind, consumer, fields)` | A consumer declares the fields it reads: `kind` is `"difficulty"` or `"personality"`, `consumer` an id (`"aim"`, `"perception"`, `"brain"`, `"objectives"`, `"tactics"`), `fields` a list of data field names. Called at load time; a second call by the same consumer replaces the first. The declarations survive a reload |
| `PW.BotProfiles.Pick(fields, difficulty?, tier?) -> table` | The values of the listed fields: from `difficulty` (a board's difficulty copy) when it has a field of the same type, else from the tier `tier` (`PW.BotProfiles.Tier`, the `regular` tier for `nil` or an unknown id). Consumers read their data only through it |
| `PW.BotProfiles.Audit(kind, entities) -> string[]` | The problems of a set of files against the declared reads: `<id>.<field> is read by nobody` and `<id> lacks <field> (read by <consumers>)`; empty when they agree. The T-5.12 test calls it |
| `PW.BotProfiles.Readers(kind)`, `Fields(entity)`, `Entities(kind)`, `Tier(id)`, `TierExists(id)` | Declared field to its consumers; the sorted data fields of an entity (without `ClassName`, `BaseClass`, `Base`, `Abstract`, `Name`, `Description`, functions and `_` names); the enabled entities of a kind; the tier entity |
| `PW.BotProfiles.Snapshot(entity)` | A plain copy (`ClassName`, `Name` and the data fields): what the board holds |
| `PW.BotProfiles.ResolveTier(value, roll)` | The tier id for a `bots.difficulty` value; `mix` picks by `MixWeights` with `roll` in [0, 1); an unknown value is `regular` |
| `PW.BotProfiles.NextType(active, stationary)`, `PickPersonality(type, roll)` | The 4:1 rule and the personality of a type chosen by `roll` (sorted by id) |

- Constants: `Fallback = "regular"`, `Mix = "mix"`, `MixWeights = { recruit = 1, regular = 2, hardened = 2, veteran = 1 }`,
  `Ratio = { active = 4, stationary = 1 }`.
- The manager (`bots_manager`) assigns the profiles once per bot: `board.difficulty` at creation (`ResolveTier` of the
  setting; each bot rolls its own tier for `mix`), `board.personality` as soon as `board.team` is known (at once when the
  match has no teams). Per team (all bots together without teams) the 4:1 rule is kept: the fifth bot of five is
  `stationary`. Neither changes during the life of the bot; both are plain copies, so editing a data file later does not
  change a bot that exists.
- A board without a difficulty (tests, a bot the manager does not own yet) reads the `regular` tier.

## Bot names

T-11.9, `design/06-progression.md` d.7. The manager passes a human-like name to `player.CreateNextBot` instead of
`Bot <n>`: `PW.BotsManager._PickName(PW.BotsManager.NamePool, taken, roll)` picks a pool name that no connected player
has (compared without case; `taken` from `_TakenNames(entries)`, every `PW.BotsEntry` carries `name = Nick()`; names
created in the same step are added). When every pool name is taken, the first pool entry in its existing order gets the
lowest unused numeric suffix starting at 2 (`"Mike 2"`). This fallback never draws RNG: identical `pool` and `taken`
produce the same result regardless of `roll`. An empty pool uses `"Operator"` as the base, with the same suffix rule.

Names are reserved by the current connected-player snapshot, not a permanent used-name set. A kicked bot still
connected reserves its name; after it leaves, its name can be reused by the next creation step. Human names are
reserved in the same way. The pool is the data file `modules/bots_manager/sh_name_pool.lua` (about 100 original first
names, surnames and callsigns; no empty entries or case-insensitive duplicates, editable). The personality is not used
as a hint: it is assigned after the team is known, later than the name. Killfeed, scoreboard and postmatch read `Nick()`.
Bot operators (models) are in `operators.md`.

## Combat movement

T-11.6 (`07 d.13`, revision 2026-11-07). Pure rules in `modules/bots_tactics/sh_moves.lua` (`PW.BotTactics`), the
keys in `bots_input`, the optional addon support in `modules/bots_input/sh_quickslide.lua` (`PW.BotQuickSlide`).

- Why cover was rarely used before (found in the code and measured on the Deck): the combat-bucket `take_cover`
  weighed 0.6 to 1.1 against a running `fight` at 1 x 1.15 commitment, so it never replaced a running fight; its own
  evaluation dropped it again once its cover was older than 3 s; and a cover was only usable with a traced peek
  point, which the 8 traced candidates often lacked. In a 40 s TDM sample on `gm_construct` (11 bots) `take_cover`
  was the top behaviour in 20 of about 800 bot samples on `main` and in 210 to 218 with this change.
- Cover: `CoverWanted(input) -> rank, weight` (see the behaviour table). `PickCover` gives a cover without a traced peek
  a side step of `Config.peekStep` (80) units across the line to the threat (`cover.guessed`).
- Strafe: `LegLength(profile, roll)` = 0.35 + 0.6 x (1 - `mobility`) + 0.5 x roll seconds; the strafe point must be on
  the navmesh (`Walkable`, one `navmesh.GetNavArea` per leg).
- Sprint: `SprintWanted(dist, profile, roll)`: a leg of at least 300 units and roll < `mobility`; `Travel(ctx, point)`
  applies it (hunt, objective approach). `take_cover` and `reload_cover` sprint to a cover farther than 150 units.
- Melee: `MeleeWanted(dist, facts)`; facts `melee` (the class of a carried melee weapon) and `active` are refreshed by
  the facts tick with `speed`, `runSpeed`, `onGround`, `crouching`. `Bash(ctx)` calls the adapter's `BotAction` with
  `"melee"` (the default answers `false`). ARC9 implements it with its own bash (`adapter.md`, "Bot actions"): it
  answers `false` until a player, NPC or nextbot is along the aim within `BashRange` (64 units from the eye in the
  installed packs, about 80 units between the feet), so between that and `meleeRange` (110) `fight` asks again every
  0.8 s and keeps shooting meanwhile; `meleeRange` stays one value for every base.
- Quick Slide (third-party Workshop addon 2416989205; only its public surface is read): a slide starts when duck and
  sprint are held together on the ground, standing, faster than half the run speed, and lasts while duck is held, at
  most `sv_qslide_duration` (0.75). `PW.BotQuickSlide.Detect(probe)` is true when `Player:GetSliding` exists and the
  ConVar or the addon's `SetupMove` hook does; `Available()` probes once and caches (one log line "Quick Slide for
  bots: addon found|not found"). `SlideWanted(kind, facts)`: the addon, not cooling down (3 s), on the ground, not
  crouched, speed above half the run speed, roll < `slide_chance`, then `peek` (a step-out peek of at least 64
  units), `dodge` (hurt within 0.5 s, while strafing) or `close` (150 to 450 units before melee).
- Budget: no new per-tick trace. The facts tick (5 Hz) reads the weapons of the bot; fight does one navmesh lookup
  per strafe leg; the cover search keeps its rate (1.5 s) and caps. Measured in the same TDM sample: 4.0 % of
  scheduler ticks over 2 ms (max 3.6 ms) against 3.3 % (max 17.9 ms) on `main`.

## Hooks

Notifications and questions use the core dispatch (`core.md` "Hook dispatch": `PW.Ask`, `PW.Notify`); the sub-modules
listen to them as auto-subscribed `PW_*` methods or with `hook.Add`. `07 d.3` says only that layers talk through "`PW_Bot*`
hooks" and the extension table says "React to bot events: `PW_Bot*` hooks". **The design names no hook, no
arguments and no order**, so the list is open (item 8); nothing is frozen here except the naming rule below.

- Naming rule: `PW_Bot<Event>` for hooks of this lane (`PW_Bot` prefix, `07 d.3`).
- Questions return a value through `PW.Ask`; notifications do not (`core.md`).
- Hooks the design does mention that other lanes own: `PW_IsEnemy(a, b)` (question, `teams.md`: every bot check of
  an enemy goes through `PW.IsEnemy`, `02-modes.md` d.6), `STREAK:BotShouldUse(bot)`, `EQUIPMENT:OnUse` and
  `PW_WeaponsLoaded` (notification, `core.md`: consumers such as bots wait for it before reading `PW.Weapons`).

## Scheduler budget

`bots_scheduler` (T-5.3). Source: `07 d.3`, `01-extensibility.md` d.17, `design/07-bots.md` "Performance budget".

| Item | Contract | Source |
| --- | --- | --- |
| Setting | `bots.tickbudget`, scope `server`, type `float`, ms per tick, default 2, range 0.5..10; declared in `modules/bots` | design (`01-extensibility.md` d.17 example), declared in code (T-5.3) |
| Rates | Commander 1 Hz; brain and perception 10 Hz with a random phase per bot; aim and input every tick; navigation budgeted | design (`07 d.3`) |
| Global FIFO | Expensive jobs (cover search, long A*) go through one global FIFO, one job per tick | design (`07 d.3`) |
| Rule | No `ents.Find*` in hot loops | design (performance budget) |
| Counters | Traces, A* expansions, ms per layer, through the profiler (`PW.Profile`, `core.md`) | design (`07 d.11`) |
| Overlay | Debug data is produced only when `pw_bot_debug` is on | decided in code (T-5.4), "Debug overlay" |

Decided in code (T-5.3, `bots_scheduler`; global `PW.BotScheduler`; the default scheduler ticks in `Think`):

| Function | Contract |
| --- | --- |
| `PW.BotScheduler.Register(id, fn, opts?)` | Registers a per-bot tick function under any non-nil `id`; `fn(id, now)` is called every `opts.period` seconds (default 0.1). A random phase in `[0, period)` spreads the bots. Registering an existing `id` replaces `fn` and `period` and keeps the phase. Perception uses the id `"perception:<UserID>"` |
| `PW.BotScheduler.Unregister(id)` | Removes it; returns `false` when unknown |
| `PW.BotScheduler.Enqueue(job)` | Appends a function to the global FIFO; every tick runs at most one job, first, and counts it in the budget. A long job slices itself and enqueues the rest (A* does) |
| `PW.BotScheduler.GetCounters()` | Copy of `{ ticks, lastTickMs, maxTickMs, brainRuns, jobsRun, errors, maxLateness, deferred, stretchedTicks, overBudgetTicks, bots, queued }` |
| `PW.BotScheduler.ResetCounters()` | Zeroes the counters except `bots` and `queued` |
| `PW.BotScheduler.GetPhase(id)` | The random phase of an id, or `nil` (this is the contract's `phase`, not a board field) |
| `PW.BotScheduler.New(opts?)` | An independent scheduler with the same functions and `Tick()`; `opts` is `{ budget, clock, random, onError, state }`. `PW.BotScheduler.Default` is the one the module ticks |

- A due bot is skipped when its predicted cost (its own last cost; the longest cost seen for a bot not measured yet)
  does not fit the rest of the budget; the first due bot of a tick always runs. The skipped bots wait for the next
  tick, most overdue first: the period stretches under overload, the cost does not. A bot more than one period behind
  restarts from now instead of catching up with a burst.
- A failing tick function or job is caught with `pcall`, counted in `errors` and reported with `ErrorNoHalt`; the
  others keep running.
- The budget is read from `bots.tickbudget` at most once a second. The state of the default scheduler survives a reload
  (`PW._BotSchedulerState`).
- The mandatory test cases (T-5.3: never exceeds the budget with 24 fake bots; every bot gets its brain tick within the
  period; the FIFO runs one job per tick) fix the behaviour.

## Mode objectives

Bots read what a mode wants through `MODE:BotObjectives(team)` (`modes.md` "`BotObjectives`"), not through any other
mode field. The commander calls it through `PW.Call` at 1 Hz per team and stores the assignment as `order`.

```lua
{
    id     = "flag_B",
    pos    = Vector(...),
    radius = 160,
    action = "capture",   -- "capture" | "defend" | "collect" | "deny" | "hold" ("plant", "defuse" later)
    weight = 0.8,         -- 0..1, importance for this team now
    want   = 2,           -- desired number of bots
}
```

- The answer is an array; a mode without the method means no objectives (TDM, FFA: bots are driven by `hunt`).
- The commander assigns with `weight`, `want`, distance and personality (`07 d.9`, `07 d.14`); bots may ignore an
  order to survive (`teamwork`, `07 d.9`).
- The `team` argument for FFA (`Teams = 0`) and the empty answer (`nil` or `{}`) are open (`modes.md` item 12); the
  commander must treat both `nil` and `{}` as "no objectives" until that is decided.
- `dom` and `kc` implement `BotObjectives` (T-5.11, `modes.md`): `dom` answers `PW.BotObjectives.DomObjectives` over
  the match's flags and `kc` answers `PW.BotObjectives.KCObjectives` over the tags on the ground, both for the given team.
- Fallback when a mode has no answer (T-5.10b, decided in code; the commander also goes through it): `PW.BotObjectives.Derive(mode, own, flags, tags, team)`
  returns the objectives of a bot's team: `own` (the mode's `BotObjectives` answer, `{}` for an answer that is not a
  table) when it is not `nil`, else `PW.BotObjectives.DomObjectives(flags, team)` for `dom` and
  `PW.BotObjectives.KCObjectives(tags, team)` for `kc`, else `{}` (TDM, FFA: hunt only). The `objective` behaviour then
  picks one itself (`PickObjective`: weight x closeness, x0.35 when `want` teammates are already near, x1.3 for the
  current one) unless `board.order` is set; an order wins and `Resolve` returns it with `ordered = true`.
  Dom derivation: an enemy or neutral flag is `capture` (weight 0.6, the middle flag of an odd count 0.8, `want` 2); a
  flag of the team that is not fully held (value below 95 of 100) is `capture` 0.9 (`want` 2); a fully held flag is
  `defend` 0.3 (`want` 1). KC derivation: an enemy tag is `collect` 0.6, a tag of the team's own dead `deny` 0.5
  (`want` 1 each; radius 24). Flag radius 160.

### Eligible objective actions extension (frozen, implemented)

Orchestrator-approved extension (2026-11-08); tests precede implementation. The six existing objective fields,
legacy callers and Domination behavior stay valid; no additional engine scans or secret information are introduced.

| Field/signature | Meaning |
| --- | --- |
| `PW.BotObjective.eligible?: table<integer, boolean>` | Server-only allow-set keyed by current `Player:UserID()`. Absent = all eligible; empty = none. Only positive integer keys with value exactly `true` survive sanitization. A malformed present allow-set rejects the objective, never becomes unrestricted. The mode supplies only role/roster/carrier eligibility, not hidden enemy facts. |
| `PW.BotObjective.revision?: integer` | Nonnegative generation of this objective visit/state. Absent keeps legacy identity. A changed revision invalidates the previous order and interaction immediately, even inside a sticky capture/hold; stable id/action/revision keeps existing anti-dither behavior. Round/visit ids must not be reused within a match. |
| `action = "plant" or "defuse"` | `pos` is a reachable interaction point, `radius` the authoritative maximum use distance, not a loose nav arrival radius. Require `eligible`, `revision`, finite position and positive finite radius for these new actions. No duration/progress field: the mode alone owns hold validation, clock and verdict. |
| `PW.BotCommander.Sanitize(raw: any) -> PW.BotObjective[]` | Promote the existing private sanitizer to a pure shared function; copy only documented fields, including a copied allow-set/revision; no callbacks, roles, entity references, enemy positions or arbitrary metadata. Reject malformed new fields and duplicate ids; never mutate the source. Legacy actions keep their existing behavior/defaults. |
| `PW.BotCommander.Eligible(objective: PW.BotObjective, botId: integer) -> boolean` | Shared pure allow-set predicate used before every assignment/retention and local fallback choice, and rechecked by the behavior before holding use. Missing module must fail closed for restricted/new actions, not make them unrestricted. |
| `PW.BotObjective.zone?: PW.BotObjectiveZone` | Optional authoritative cylinder `{ pos: Vector, radius: number, above: number, below: number }`, finite position/dimensions, positive radius, nonnegative vertical bounds. Whitelist and copy it through sanitizer/fallback. Actual and projected nav arrival must be inside this cylinder; never trust a projected `arrived` flag alone. |
| `PW.BotCommander.ArrivalFits(objective, projected, radius) -> boolean` | Shared pure helper: the entire horizontal arrival disc and projected height must fit the authoritative cylinder. The objective behavior validates immediately after `SetGoal`, clearing an invalid projected goal synchronously, and separately checks actual position/height before holding. Legacy objectives without a cylinder keep their existing behavior. |
| `PW_PlayerTeamChanging(ply, from, to, reason)` | Synchronous server notification before team mutation; brain stops its stack. Humans and bots both trigger invalidation because every bot's relationships may change. |
| `PW_PlayerTeamChanged(ply, from, to, reason)` | Synchronous server notification after team/manager-board mirror update. Commander clears orders/hunt and its retained assignment state for all managed bots; each other owner clears only its own state. |
| `PW_ObjectiveInvalidated(id: string, revision: integer)` | Server notification invalidating one old objective visit. Commander calls its own `InvalidateObjective(id, revision)` helper, releasing matching orders and goals through public `PW.Bot.ClearGoal`. Other revisions/objectives are untouched. The mode invalidates before publishing the next visit. |

Eligibility overrides all assignment passes, including active capture/hold and hysteresis. Ineligible retained
orders release immediately, even with the same id/action/revision. For local fallback, filter before ranking;
an ineligible best candidate must not hide an eligible second candidate. Preserve approved fields through
`PW.BotObjectives.Resolve`, including its fallback. Re-resolve current generation/eligibility before
interaction rather than trusting a one-second-old commander order. No new defend-cap bypass is proposed.

For plant/defuse the behavior approaches through `SetGoal`, verifies actual distance (not only projected nav
arrival), stops locomotion/sprint, looks at the public interaction point and holds `IN_USE` through ordinary
`intent.buttons`/`StartCommand`. It never calls plant/defuse or modifies objective progress directly. Existing
input conflict rules still forbid use with attack. Release objective-owned use on suspend/end, invalid actor,
changed id/action/revision, lost eligibility or leaving range; resume must revalidate. Mode-side validation
remains authoritative on every input tick. Capture/hold drift, collect/deny and Domination caps stay unchanged.

Tests-first cases in `tests/privatewar/bots_snd.lua`: carrier-only assignment despite a nearer ineligible
bot; eligibility removes even sticky holds; revision releases a hold immediately; sanitizer copies eligibility
and rejects malformed restrictions without forwarding secret fields. `snd_input.lua` additionally exercises
held-use cleanup, actual StartCommand plant/defuse input and travel from an authored spawn through planting and
guarding. The behavior records `ctx.state.id` / `revision`; matching `PW_ObjectiveInvalidated` synchronously ends
running/suspended objective frames through the brain owner and normal OnEnd cleanup. Test evidence does not pass
the human bot-quality or visual checkpoint.

**Narrow ownership request before implementation:** the S&D agent also needs
`modules/bots_objectives/shared.lua`, only `PickObjective`/`Resolve`, to preserve/validate these fields and filter
the local fallback. Their optional bot-id parameter and copied metadata must preserve all existing callers.
Without that serialized grant, commander-only changes would leave a bypass and lose the interaction fields.
This narrow ownership and the unified team/round notifications are now approved. Commander also clears all
its orders/hunt/retained state on `PW_RoundPrepared`; it never accesses another layer's private stores.

## Commander

Module `bots_commander` (T-5.11; `07 d.3`, `07 d.9`, `07 d.14`), global `PW.BotCommander`. Server only; one pass every
`Config.interval` (1 s) in `Think`. The assignment and the hunt slots are pure functions over plain data (`shared.lua`,
`sh_hunt.lua`); the glue (`init.lua`) reads the engine.

A pass: per team, the objectives (`MODE:BotObjectives(team)` through `PW.Call`, else `PW.BotObjectives.Derive`),
`Assign` over the alive bots and their current orders, and `board.order` written (`nil` for a bot without one and for a
dead bot); then `Hunt` over the alive humans and `board.hunt` written on every managed bot. Bots without a team (FFA) get
no objectives and no order.

| Field | Shape | Meaning |
| --- | --- | --- |
| `board.order` | `{ objective, type, id, priority, since }` | `objective` is the objective as returned by the mode, `type` its `action`, `id` its id, `priority` its `weight`, `since` the `CurTime()` of the assignment (kept while the bot stays on the same objective and action) |
| `board.hunt` | `{ target?, since }` | `target` is the human this bot hunts; `nil` means the bot holds no hunt slot. Written on every managed bot while the commander runs; a dead bot gets `{ since = now }` and no order |

`Assign(bots, objectives, orders, now, opts) -> table<id, PW.BotOrder>`, three passes over the bots sorted by id:

1. An active capture (the order is `capture` or `hold` of an objective that still has that action) of a bot standing
   inside the radius is kept, whatever the want says.
2. Any other order of an objective that still exists with the same action is kept for `Config.hold` seconds after its
   `since`, while the objective has a free slot and, for `defend`, the defender cap allows. A changed action or a gone
   objective frees the bot at once.
3. The free bots and the free slots are paired greedily by `weight x closeness x factors` (`sticky` for the current
   objective, `stationaryDefend` for a stationary personality on a `defend`); ties go to the smaller objective id, then
   the smaller bot id. A bot that gets no slot has no order.

Defenders (action `defend`, all objectives together) are at most `floor(team size x defendShare)`; the team size counts
every managed bot of the team, dead ones included. Objectives with `weight <= 0` or `want <= 0` get nobody.

`Hunt(state, humans, bots, now, opts) -> table<bot id, human id>`: at most `huntMax` bots hunt one human; the budget
of each human (1 to `huntMax`) is re-rolled every `rerollMin` to `rerollMax` seconds. Candidates are the enemies of the
human (another team, or no team in FFA) without an order, one human per bot; the closest free bot gets a free slot (true
positions: the commander only picks who hunts, the hunter goes to its own contact memory). A hunter that makes no
progress (closer by `huntProgress` units, or a contact with the human in the last `huntContact` seconds) for `huntStall`
seconds is replaced and is not picked for that human again for `huntStall` seconds.

`HuntView(board, memory, deaths, isHuman) -> memory, deaths`: the view the `hunt` behaviour reads. Without `board.hunt`
nothing is filtered. With a slot, contacts of humans other than `target` are dropped (bot enemies stay). Without a
target the teammates' death spots are dropped too (in solo every death spot is the human's), so such a bot chases bot
enemies and roams.

`PW.BotCommander.Config` (a plain table, not ConVars; `huntMax` is a config value):

| Key | Default | Meaning |
| --- | --- | --- |
| `interval` | 1 | seconds between passes |
| `hold` | 30 | seconds an order is kept (`07 d.14`: 30 to 45) |
| `defendShare` | 1/3 | share of the team that may defend |
| `sticky` | 1.25 | score factor for the current objective |
| `stationaryDefend` | 1.5 | score factor of `defend` for a stationary bot |
| `falloff` | 1200 | closeness = `1 / (1 + distance / falloff)` |
| `huntMax` | 2 | hunt slots per human |
| `huntStall` | 20 | seconds without progress before a hunter is replaced |
| `huntProgress` | 150 | units closer that count as progress |
| `huntContact` | 3 | seconds a contact counts as progress |
| `rerollMin`, `rerollMax` | 30, 60 | seconds between budget re-rolls |

## Debug overlay

Module `bots_debug` (T-5.4; `07 d.11`), global `PW.BotDebug`. The server ConVar `pw_bot_debug` (default 0, range 0..1,
`FCVAR_DONTRECORD`) switches it: only the server console, rcon and the listen-server host can change it. While it is 0
nothing is collected, built or sent. While it is 1, up to 4 times a second (`PW.BotDebug.Interval` 0.25 s), the server
sends the message `pw_bot_debug` to the clients that hold the privilege `pw.bots.debug` (default `superadmin`, shared with
`pw_bot_aim` and `pw_bot_goto`); a client without it receives nothing.

Wire format of `pw_bot_debug` (server to clients, explicit writes):

```text
string perf line; uint8 bot count (max 64);
per bot: uint13 entity index, string name, string behaviour, string reason, string target, bool hasGoal,
  [int16 x, int16 y, int16 z, string status], uint6 waypoint count (max 24), int16 x, y, z per waypoint
```

Strings are cut to 32 characters; coordinates are rounded to integers. The path holds the remaining waypoints from
the one the bot walks to, at most `MaxPath` (24). The perf line comes from the scheduler counters (bots, tick ms, runs,
deferred, queued, over-budget ticks, errors). The client draws, for each bot in view (within 2000 units), a label (name,
`behaviour: reason`, `target ...`), a goal marker with the goal status and the path polyline, plus the perf line in the
top-left corner; when no message arrived for 2 seconds the overlay disappears.

## Mandatory behaviour of every layer

- Fairness (`07 d.2`): no layer moves, heals, arms or buffs a bot except through `CUserCmd`; no layer reads an
  enemy position that perception has not made known (no wallhacks).
- Bots are real players (`player.CreateNextBot` plus `StartCommand`, `07` decisions) and count as loaded immediately
  (`00-core.md` d.9). A kicked bot is removed with `Player:Kick`, never `Entity:Remove`.
- Bot creation is paused while the navmesh is generated (`map.md` "Open in design", item 10), in Singleplayer and
  during a GLuaTest run: the gate of the manager, decided in code (item 10 below).
- Bots exist from `PREMATCH` through `VOTE` and are kicked on entering `LOBBY` (T-5.1).
- Debug overlay from day one (`07 d.11`): behaviour name and reason, target, goal and path above each bot, plus
  perf counters.

## Open in design

The design does not decide these. They are **not** part of the contract; a task that needs one asks the user (or the
orchestrator records the decision here) before its code is written. "Blocks" names the first task that cannot be
finished without the answer.

Status on 2026-11-07: items 2, 6, 7, 9 (except the overlay ConVar), 10 and 11 are closed by code; items 1, 3, 4 and 5
are closed in part; items 1 and 2 also carry an orchestrator decision that waits for the user's confirmation. Items 8,
12, 13 and 14 are still open.

Contradictions inside `design/07-bots.md` (not chosen, reported):

1. **Rank buckets.** `07 d.4` names three buckets in order: "self-preservation > objective > roam". The table of
   `07 d.13` uses four names: "combat", "survival", "objective", "roam", and gives no order between "combat" and the
   others. `07 d.5` shows `Rank` returning numbers (`20`, `10`), `07 d.4` calls the rank a "hard priority bucket".
   Open: the bucket list and order (and whether "survival" is "self-preservation"), and whether `Rank` returns a name
   or a number. Blocks T-5.9 (brain) and T-5.10 (behaviours); T-5.12 reads it for the data.
   **Orchestrator decision, pending the user's confirmation (2026-11-07):** four buckets in the order survival >
   combat > objective > roam ("survival" is the "self-preservation" of `07 d.4`; `combat` is added from the table of
   `07 d.13`).
   **Closed by code (T-5.9), to be confirmed:** `PW.BotBrain.Buckets` is survival 40, combat 30, objective 20, roam 10;
   `Rank` returns a bucket name or a number greater than 0 (`07 d.5` shows numbers), and `nil`, `false` or 0 or less
   means "not a candidate". The built-in behaviours return names ("Blackboard"/"Kinds", behaviour table).
2. **`bots.count` versus `bots.fill`.** `07 d.3` lists "`bots.fill`, `bots.count`, ..." as the settings; `01-extensibility.md`
   d.17 declares `count`; `02-modes.md` d.5a replaced the count with `fill` ("not a fixed bot count") and the code has
   `fill`. Open: whether `bots.count` exists, and the full settings list of `bots` (`bots.tickbudget` is in the d.17
   example only). Blocks T-5.1 (manager quota) and T-5.3 (the budget setting).
   **Closed by code (T-5.1, T-5.3):** the module `bots` declares `fill` (scope `match`, int, default 12, 0..128),
   `difficulty` (scope `match`, enum) and `tickbudget` (scope `server`, float, default 2, 0.5..10); there is no
   `bots.count`. **Orchestrator decision, pending the user's confirmation:** `bots.fill` is the canonical setting
   (total players including humans, capped by `maxplayers` with one slot always left free, so fill 12 on 12 slots gives
   11 players); `bots.count` is not added.

Gaps (the design is silent; no contradiction):

3. **Blackboard field shapes.** `07 d.16` defers to this document, so the design gives no shapes. This file fixed the
   groups and writers from `07 d.3`, but the following are not decided: the full `PW.BotIntent` (stance value set,
   weapon choice, ADS, equipment and streak use, merge rule when several writers want `view` or `move`), the shape
   of the hunt slot, the fields of `ctx` given to `Rank`, `Weight` and `Update`, the Action transition constructors
   (`Continue`, `ChangeTo`, `SuspendFor`, `Done(reason)`: arguments), min-run-time and cooldown field names.
   Blocks T-5.2 (input writer), T-5.9, T-5.10, T-5.11.
   **Closed in part by code (T-5.2, T-5.6, T-5.8, T-5.9):** the stance value set (`"stand"`, `"crouch"`), the weapon
   choice (field `weapon`) and ADS (`IN_ATTACK2`); see "Intent". The merge rule for `view`: the aim owns it while it has a
   target, the follower otherwise and always on a ladder ("View ownership"). The `ctx` fields, the four transition
   constructors and the names `MinRun` and `Cooldown` ("Kinds", `bot_behaviors`). Still open: the merge rule for `move`
   (the follower is the only writer today), streak use (streak use is closed by T-4.6: `use_streak` goes through
   `PW.BotObjectives.ReadyStreak` and `UseStreak` to `PW.Streaks.Ready` and `Use`; equipment use is closed by T-4.5: `throw_equipment` works through
   `PW.Equipment.Use`), the hunt slot.
   **Hunt slot closed by code (T-5.11):** `board.hunt = { target?, since }`, "Commander".
4. **Goal API details.** Behaviour for an equal priority; the status string values; what happens to a goal when the
   bot dies, when the mode changes the order, or when `SetGoal` is called with a point off the navmesh and no
   projection. Blocks T-5.6.
   **Closed by code (T-5.6), to be confirmed:** equal priority: the newer request wins; statuses and reasons: see "Goal API";
   death: `failed`, `"died"`; off the navmesh: `unreachable`, `"off navmesh"`. A mode changing an order is the
   commander's case (T-5.11) and stays open.
5. **Stimulus and cost-layer API.** The set of stimulus kinds and the `data` shape per kind; the signature to register
   a cost layer and how a layer is removed on module disable. Blocks T-5.7 and T-5.5.
   **Closed in part by code (T-5.5, T-5.7):** the stimulus kinds and the `data` shape ("Stimuli") and the cost layer
   signature `RegisterCostLayer(id, fn(node, graph) -> extra)` ("Goal API"). Still open: removal of a layer when its
   module is disabled (today the module calls `UnregisterCostLayer`).
6. **Kind declarations for `bot_personalities` and `bot_difficulties`.** `01-extensibility.md` d.17 lists only
   `bot_behaviors/` (`BEHAVIOR`); the class table names, `Required` fields, `Subscribe` value, the field identifiers of
   the personality, the identifiers of the manoeuvre chances and "sight time" (no row in `notes/14`) are open.
   Blocks T-5.12, and the orchestrator's kind files before T-5.9.
   **Closed by code (T-5.9, T-5.12), to be confirmed:** class tables `BEHAVIOR`, `DIFFICULTY`, `PERSONALITY`;
   `Subscribe = "never"` for all three; `Required` is `Rank`, `Weight`, `Update` for behaviours, `Name` for a difficulty,
   `Name` and `type` for a personality; the field identifiers are those of "Kinds" (`crouch_chance`, `aggression`,
   `engage_range`, `cover_chance`, `flank_radius`, `third_party_delay`; the manoeuvre chance is `strafe_chance`).
   Still unnamed because no module needs them: slide, dive and corner-fire chances, and "sight time".
7. **Difficulty selection.** `07 d.10`: "`bots.difficulty` picks a tier (or a mix)": the mix is undefined, and the
   setting is a temporary enum (`modes.md`) that must come from the kind. Blocks T-5.12 and the lobby form for it.
   **Closed by code (T-5.12), to be confirmed:** the setting is the four tier ids plus `mix`; `mix` gives every bot a
   tier of its own with the weights recruit 1, regular 2, hardened 2, veteran 1 ("Profiles"). The enum is still
   declared in the settings file (it does not read the kind), so a new tier file needs its id added to the options.
8. **`PW_Bot*` hooks.** No event, no arguments, no order are named anywhere in the design (only the prefix and the
   mentions in `07 d.3` and the extension-point table). Blocks T-5.0 itself as "hooks list"; the sub-lanes meanwhile
   use the blackboard only, and add hooks only after the orchestrator records them here.
9. **Scheduler API names.** The functions of the budget (acquire, queue a job, report), the unit of the FIFO job, and
   the ownership of `pw_bot_debug` (ConVar flags, scope). Blocks T-5.3 and T-5.4.
   **Closed by code (T-5.3):** the names are those of `PW.BotScheduler` ("Scheduler budget"); the FIFO unit is a
   function. `pw_bot_debug` **closed by code (T-5.4):** a server ConVar, "Debug overlay".
10. **Bot creation pause during navmesh generation.** A switch the bots module reads (`map.md` item 10). `navgen` kicks
    the bots; the pause is not designed. Blocks T-5.1 and CP-2 item 5 only if bots exist then.
    **Closed by code (T-5.1):** the manager is idle (creates and kicks nothing) in Singleplayer (one log line), while
    `PW.NavGen.IsGenerating()` is true (`navmesh.IsGenerating()` without the `navgen` module), during a GLuaTest run
    (`GLuaTest_StartedTestRun` pauses it; `GLuaTest_Finished` resumes it at once in `LOBBY` or on the next entry to
    `LOBBY`) and outside `PREMATCH`, `LIVE`, `POSTMATCH` and `VOTE`. Entering `LOBBY` kicks every bot, and so does a
    map that starts in `LOBBY`. A human joining kicks the newest bot of `PW.Teams.Smallest()` (else the newest bot of the
    largest team that has one). A join-in-progress spectator (NW2 bool `pw_spectating`, `modes.md` "Join in progress") is not a human
    of the quota: the humans count of the step skips them, so their joining kicks no bot and they do not reduce the
    bot target until they play. `core.md` writes the bot target of `pending_match.json` from
    `PW.BotsManager.PendingTarget(settings)`.
11. **Ownership of the `bots` module file.** The placeholder is the modes lane's (T-2.6, `modes.md`); the sub-lane
    that adds `bots.tickbudget` and other settings is not named (`TASKS.md` says the `bots` lane owns `modules/bots_*`,
    not `modules/bots`). Blocks T-5.1.
    **Closed by code (T-5.1, T-5.3):** the bots lane owns `modules/bots` (the settings file) as well as `modules/bots_*`;
    the scheduler lane added `bots.tickbudget` there.
12. **`MODE:BotObjectives(team)` for FFA** (`modes.md` item 12): the argument and the empty answer. Does not block the
    MVP; blocks T-5.11 detail.
13. **Bot loadout contract.** `05-loadout.md` d.14 puts the selection inside the brain and names the setting
    `bots.classes` (type `set`: `preset`, `players`); the interface to the loadout lane (how a bot receives a class)
    is not defined here. Blocks T-5.13.
    **Closed by code (T-5.13):** module `bots_loadouts` (`05-loadout.md` d.14).
    - Pool: the sources of `bots.classes` (`set`, default both): `preset` (the `classes/` kind) and `players` (the
      available custom classes of every human of the session, taken whenever a pool is built and when a human leaves,
      kept until the map changes). Every class passes `PW.Loadout.Validate` under the current match settings (budget,
      bans, `PW_ValidateLoadout`), never progression. An empty set or nothing valid gives an empty pool: the bot keeps
      the default loadout.
    - Weights: the personality field `class_weights` maps the category of a class's primary weapon to a weight (an
      unlisted category weighs 1, `0` removes it; all zero falls back to an even draw). Values: `cqb` shotgun 3, smg 2,
      sniper 0.25; `run_and_gun` smg 3, ar 1.5, sniper 0.5; `camper` sniper 3, lmg 2, ar 1.5, shotgun 0.5. Every class
      weighs the same otherwise, so a player with many classes is picked more often.
    - Setting `bots.classrepick` (float 0..1, default 0.25): the chance that a bot picks a new class on respawn.
    - Timing: the class is set before the `PlayerSpawn` listeners of equipment and streaks run. On `PW_PhaseChange` to
      `LIVE` every bot gets a fresh class (before `PW_MatchStart` spawns everybody; chance 1); on `PostPlayerDeath` in
      `LIVE` the class for the next life is re-picked by `bots.classrepick`; a bot that joins during `LIVE` is assigned
      in `PlayerInitialSpawn`, and `PlayerSpawn` is a fallback for a bot without a class. Classes are dropped on
      `LOBBY` and `PREMATCH`. A mode's `PW_PlayerLoadout` still wins over the class.
    - Pause: like the bots manager, the module is paused during a GLuaTest run (`GLuaTest_StartedTestRun` to
      `GLuaTest_Finished`), because other groups' in-game cases expect a bot with the default loadout; the T-5.13 smoke
      unpauses it for its own match.
14. **Interfaces and security sections of `07-bots.md`** say "TBD". This file is the interface; the security question
    (what a client can send about bots) is not designed. Bots send no net messages; a human cannot call a bot API
    because the API is server only. Not blocking.
