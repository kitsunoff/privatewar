# 38 - Search and Destroy bot behaviour: site choice, routes, corner checks, empty grenade

Research for [the change record](../changes/planned/snd-bot-behaviour.md). It reports code inspection
on `main` (2026-11-22) and external reading only. No Deck, in-game, GLuaTest or performance run was made. Research
explains why; it is not a decision. When this note and `design/` disagree, `design/` wins.

Paths below are relative to `addons/privatewar/lua/privatewar/` unless they start with `addons/` or `notes/`.

## 1. Playtest observations (maintainer, 2026-11-22)

Bots play reasonably in respawn modes. In Search and Destroy (S&D):

1. Attackers always plant at the same site.
2. Bots take the identical route every round.
3. Bots do not check corners or angles.
4. A bot stands holding a grenade with zero ammo, aiming and trying to fire.

## 2. Site choice (problem 1)

Confirmed root cause. The attacker objective list is built from the first authored site only:

- `modules/snd/sh_objectives.lua:49`: `if team == 1 then return { objective(state, team, state.map.sites[1],
  "plant", 1) } end`. The plant objective is the only objective attackers get while the bomb is carried.
- `modules/snd/sh_objectives.lua:12` and `:28`: plant eligibility is the carrier only, so non-carrier attackers get
  no objective and fall back to `hunt` (roam), see `bot_behaviors/hunt.lua:90-105`.
- `modules/snd/shared.lua:72-83` (`NewRound`) stores no per-round attack target; `modes/snd.lua:64-77`
  (`PrepareRound`) draws only a random carrier (`modes/snd.lua:72`, `02-modes.md` d.8 "Select a random attacking
  carrier").
- Nothing downstream can vary the site: the commander's greedy fill (`modules/bots_commander/shared.lua:196-211`)
  and the local pick (`modules/bots_objectives/shared.lua:124-135`) only choose among the objectives they are given.
- `changes/planned/snd-de-autodetect.md` already records "Consider that existing bots attack the first site".

Side observation (not reported, same code): defenders get one `hold` objective per site with `want = 128`
(`sh_objectives.lua:52`). The crowding factor never triggers at that `want`, and both the commander score
(`bots_commander/shared.lua:157-165`) and the local score (`bots_objectives/shared.lua:116-122`) are
`weight x closeness`, so each defender holds the site nearest to its spawn every round. That is a second source of
round-to-round sameness; it is listed as an open question in the record, not as a reported problem.

No core seeded PRNG exists yet (`modules/bots_perception/init.lua:15`, `modules/bots_brain/init.lua:9`: "math.random
until the core has its own AI PRNG"). `notes/08-weapon-adapters.md` section 3.5 records that MW Base reseeds the
global `math.random`, so determinism must come from injected random functions or a pure hash, not `math.randomseed`.

## 3. Route sameness (problem 2)

Confirmed root cause: the whole pipeline is deterministic for a fixed start and goal.

- `modules/bots_nav/init.lua:41-42`: step cost and heuristic are distances between area centres.
- `modules/bots_nav/sh_service.lua:248-249`: step cost adds the baked cost table; the only registered layer is
  `danger` (`bots_nav/init.lua:48-51`), which is non-zero only near deaths in the last 120 s.
- `modules/bots_nav/shared.lua:69-82`: A* relaxes with `<` only; ties resolve by heap order, which is stable for the
  same inputs.
- `modules/bots_goal/init.lua:114-129` (`waypoints`) and `modules/bots_goal/sh_follow.lua:62-76`: each waypoint is
  the closest point of the next area to the previous centre, pulled 16 units in. Same path, same waypoints.
- S&D spawns, the bomb point and the site approach (`sh_objectives.lua:26`, goal `objective_actions/plant.lua:18`)
  are fixed per map. With the same start area, the same goal area and an empty danger layer, every round produces
  the same path.
- `07-bots.md` d.6 already decides "penalty for areas used by teammates (natural flanks and spread, Killzone)" as a
  cost term. It is not implemented: no such layer is registered. It would spread teammates in one round, but by
  itself it does not vary routes between rounds.
- The baked table is global (`sh_service.lua:241-249`), so a cost layer cannot differ per bot without an API change.

### Options considered

- **A. Portal offset.** A seeded point along the shared edge of two path areas instead of the closest point.
  Varies per bot and per round ("a bit left, a bit right"). Cost: O(path) pure math once per path, 2 extent reads
  per step. Fits the current API inside `bots_goal`.
- **B. Per-round noise cost layer** `hash(seed, area) x amplitude`. Varies per round, same for every bot. Cost: one
  hash per area per bake (the bake already runs at about 1 Hz). Fits as a cost layer (d.6 framework).
- **C. Per-request cost noise inside A\*.** Varies per bot. Cost: one hash per relaxation and more expansions.
  Does not fit: `RequestPath` and `NewSearch` change.
- **D. Via-point lanes** (`start -> via -> goal`, via among lateral nav areas). Varies per bot, large detours. Cost:
  two searches per path. Fits inside `bots_goal` or the objective action.
- **E. k near-optimal paths** by the penalty method, one picked at random. Varies per bot. Cost: k searches per
  path. Fits, but multiplies the A\* budget by k.

Option E is the textbook way to produce distinct alternatives (penalty method; Bader, Dees, Geisberger, Sanders,
"Alternative Route Graphs in Road Networks", 2011). On a Steam Deck with an iteration cap of 4000 per search
(`bots_nav/shared.lua:36`) it multiplies the most expensive bot job, so it is not recommended as a default.
A + B give visible lateral variety and different corridors between rounds for almost no cost. D is the cheap
substitute for E when a map has clearly separate lanes.

Hash note for implementers: LuaJIT `bit` operations work on 32-bit values, but `a * b` of two 32-bit integers loses
precision above 2^53. A hash must split multiplications into 16-bit halves (or use a small-modulus LCG with
Schrage's method) to stay exact and identical on every platform.

## 4. Corner checks (problem 3)

Confirmed root cause: while travelling without a target, the bot always looks along its path.

- `modules/bots_goal/init.lua:24` (`lookAhead = 160`) and `:246-256` (`legsFor`): the walking view target is the
  path point 160 units ahead (`sh_follow.lua:20-30`), unless the aim owns the view.
- The aim owns the view only while it has a target (`modules/bots_aim/init.lua:1-11`, `:243-246`). A `Vector` target
  is a supported look-at point that is never fired at (`bots_aim/init.lua:11`, `:140`).
- Travelling code clears look points: `objective_actions/movement.lua:26` (`LookAt(ctx, nil)` on every leg),
  `bot_behaviors/hunt.lua:65,70`, and `modules/bots_tactics/sh_moves.lua:117-121` (`Run(ctx, true)` drops any target).
  `docs/api/bots-blackboard.md` "Intent" rule 3 documents that a sprinting bot runs facing its path.
- `modules/bots_tactics/sh_moves.lua:56-58,123-128`: long legs (at least 300 units) are sprinted with chance
  `mobility`, so bots often sprint into a site.
- Perception sees only inside a 110 degree cone (`bot_difficulties/*.lua:34`, `bots_perception/shared.lua:68-78`).
  A doorway or side corridor at 90 degrees to the path is outside the cone until the bot has passed it.
- Only stationary moments look around: `hunt.lua:124` after arriving, `movement.lua:39-45` (guard), `camp.lua:69`.
- The follower already moves relative to the current eye yaw (`bots_goal/init.lua:257-259`, `sh_follow.lua:41-46`)
  and turns the view at most `turn_max_speed` per second (`bots_goal/init.lua:190-197`). Looking sideways while
  walking along the path is therefore already mechanically possible; nothing chooses where to look.

### Industry practice

- Counter-Strike bot (ReGameDLL_CS reimplementation, `regamedll/dlls/bot/cs_bot_vision.cpp`, `UpdateLookAround`):
  while moving and not safe, the bot glances at encounter spots along its current path segment, a little ahead of
  its progress (`leadCheckRange = 50`), at most 8 candidates, skipping spots checked in the last 10 s, choosing one
  at random; the interval between glances grows as skill falls (`(1 - skill)^4 x 10..30 s`). `UpdatePeripheralVision`
  (about every 0.29 s) marks spots already visible in the FOV as checked, so the bot does not look at what it already
  sees. When stationary it looks at precomputed approach points. `notes/14-industry-bot-ai.md` lines 65 and 202-203
  record the same and the CS rule "do not look at spots closer than 100 units" (erratic rotation).
  Source: <https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/bot/cs_bot_vision.cpp>.
- Killzone 3 (Game AI Pro 1 ch.29) and "Dynamic tactical position evaluation" (AI Game Programming Wisdom 3): threat
  prediction picks the most likely hiding waypoints of a lost enemy and scans them; position queries use cheap
  candidate sets (waypoints, hiding spots) with cheap filters first and raycasts last (`notes/14`, reading list 1, 5).
- F.E.A.R. (Orkin, "Three States and a Plan", GDC 2006): squad behaviour is legible because agents announce and
  face what they do; for us the cheap equivalent is "face the next opening before entering it".
- GMod navmesh exposes hiding spots (`CNavArea:GetHidingSpots`, already used in `modules/bots_tactics/init.lua:157`)
  and adjacency (`bots_nav/init.lua:31-40`) but not CS encounter spots. Off-path neighbour areas of the path are the
  cheap stand-in for "openings" (doorways, side corridors).

### Proposed technique (cheap)

1. When a path arrives, derive up to N watch points from it: centres of neighbour areas that are not on the path,
   plus at most one or two hiding spots per path area, each tagged with the path index it belongs to. No traces.
2. Corner pre-aim ("slicing the pie"): when the path turns by more than about 45 degrees within the next 200-300
   units, look at a point beyond the turn on the next segment before reaching the corner.
3. Each follower tick (10 Hz), when not sprinting and the aim has no target: pick the best unchecked watch point near
   the current path index (side angle 30-120 degrees, distance 100-1200 units), glance at it for a short time, mark it
   checked; else look along the path. Skill controls the glance frequency, as in CS.
4. Walk instead of sprint near likely contact (inside a radius around an S&D site, or while the next segment has
   openings), so the glance is possible (`Run(ctx, true)` drops look targets by contract).

## 5. Empty grenade (problem 4)

Code facts:

- Bots can never fire the grenade SWEP:
  `addons/privatewar/gamemodes/privatewar/entities/weapons/weapon_pw_grenade.lua:96-100`
  returns from `PrimaryAttack` when `owner:IsBot()`. A bot that holds the grenade SWEP for any reason is stuck: the
  aim keeps pressing attack (`bots_aim/init.lua:1-4`) and nothing happens, with or without ammo.
- Bot throw path (`modules/equipment/sv_grenades.lua:81-98`, `_BotThrow`): `SelectWeapon(grenade)`, `_Spend`
  immediately (the projectile does not need the SWEP to be deployed), then one `timer.Simple(BotHold = 0.3)`
  (`sh_grenades.lua:20`) that returns only if the active weapon is a grenade at that instant (`sv_grenades.lua:94-95`).
  The human path's switch back (`_AfterThrow`, `sv_grenades.lua:73-79`) is not used by bots.
- `_ReturnTo` (`sv_grenades.lua:40-61`) prefers the remembered or previous weapon, then any non-grenade.
- No code anywhere switches a bot away from an unusable active weapon. Weapon selection writers are only
  `bots_input` (`intent.weapon`, `bots_input/shared.lua:125-136`, sent through `bots_input/init.lua:93-96`),
  `bot_behaviors/melee.lua` and the equipment module.
- `intent.weapon` is sticky: the brain clears only `sprint`, `drive` and `slideAt` on a frame change
  (`docs/api/bots-blackboard.md` "Intent" rule 1); `board.intent` is reset only on `PW_RoundPrepared`, team change and
  match end (`bots_brain/init.lua:95-107`).
- ARC9 (the main supported base) defers weapon switches: `Holster` waits for its holster time and ARC9's own
  `StartCommand` hook re-selects the target weapon later (`notes/08-weapon-adapters.md` section 2, row
  "Weapon switch (`A/sh_deploy.lua:233-291`)"; the ARC9 adapter reads `GetHolsterTime()` at
  `addons/privatewar-arc9/lua/privatewar/weapon_adapters/arc9/init.lua:144`).
- The only automated bot-throw test switches from `weapon_crowbar`
  (`lua/tests/privatewar/grenades_inventory.lua:229-249`),
  which holsters instantly, so a deferred switch is never exercised.

Paths that leave the grenade in hand:

1. **Hypothesis H4a (most likely, ARC9 deferred holster).** The bot holds an ARC9 gun; `_BotThrow` asks for the
   grenade; ARC9 starts its holster animation; `_Spend` throws at once; at 0.3 s the active weapon is still the
   holstering ARC9 gun, so the return timer does nothing; ARC9 then completes the switch to the grenade, now with
   zero ammo when it was the last one. Nothing ever switches back. Confirm in game: log the active class at the
   `BotHold` timer and again 1 s later for a bot holding an ARC9 rifle; or run the existing bot-throw case from an
   ARC9 weapon.
2. **H4b (code-confirmed path, needs a timing coincidence).** `melee.lua:50` stores `st.previous = f.active`, where
   `f.active` is the 5 Hz tactics fact (`bots_tactics/init.lua:85-94`, tick 0.2 s, `:13`). If melee starts within the
   throw window (0.3 s hold plus up to 0.2 s staleness), `previous` is the grenade class; `melee.lua:78` writes it into
   the sticky `intent.weapon`, and `bots_input` re-selects the grenade for the rest of the round. With ARC9
   `reselectEveryTick = true` (`privatewar-arc9/.../arc9/shared.lua:349`) it is re-sent every tick.
3. **H4c (minor).** `_ReturnTo` returns `nil` when the bot owns no non-grenade weapon (`sh_grenades.lua:61-72`);
   unlikely in normal loadouts.

Why it shows in S&D: one life per round keeps the stuck bot alive for minutes; in respawn modes the next death
resets the loadout. S&D also produces many "lost contact behind a corner" moments that trigger `throw_equipment`.

## 6. Ownership

| Area | Files | Lane (`TASKS.md` "Lanes and ownership") |
| --- | --- | --- |
| Attack site per round | `modules/snd/*`, `modes/snd.lua` | `modes` (`snd` not listed; orchestrator confirms) |
| Routes, watch points | `bots_nav`, `bots_goal`, `bots_tactics`, `objective_actions/`, behaviours | `bots` |
| Usable-weapon guard, melee | `bots_tactics`, `bot_behaviors/melee.lua`, `bots_input` | `bots` |
| Bot throw return | `modules/equipment/*` | `loadout` (by analogy with `throwables`) |

Note: `objective_actions/`, `modules/snd/` and `modules/equipment/` are not listed in the lane table; the
orchestrator confirms their owners.

## 7. Sources

- ReGameDLL_CS, `cs_bot_vision.cpp` (`UpdateLookAround`, `UpdatePeripheralVision`, `SetLookAt`):
  <https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/bot/cs_bot_vision.cpp>
- Straatman et al., "Hierarchical AI for Multiplayer Bots in Killzone 3", Game AI Pro 1 ch.29:
  <http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter29_Hierarchical_AI_for_Multiplayer_Bots_in_Killzone_3.pdf>
- Jack, "Tactical Position Selection", Game AI Pro 1 ch.26:
  <http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter26_Tactical_Position_Selection.pdf>
- Orkin, "Three States and a Plan: The AI of F.E.A.R.", GDC 2006:
  <https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf>
- Bader, Dees, Geisberger, Sanders, "Alternative Route Graphs in Road Networks" (2011), KIT record:
  <https://publikationen.bibliothek.kit.edu/1000097648>; "Defining and Computing Alternative Routes in Road
  Networks" (arXiv 1002.4330, full text not opened in this session): <https://arxiv.org/abs/1002.4330>
- Internal: `notes/14-industry-bot-ai.md`, `notes/08-weapon-adapters.md`, `notes/24-search-and-destroy-research.md`.
