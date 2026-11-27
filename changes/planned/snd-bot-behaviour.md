# Search and Destroy bot behaviour: site choice, route variety, corner checks, empty grenade

Status: `planned`

Recorded: 2026-11-22

## Goal and scope

Fix four bot problems the maintainer observed in Search and Destroy (S&D) playtests on 2026-11-22. Bots play
reasonably in respawn modes; in S&D:

1. Attackers always plant at the same site.
2. Bots take the identical route every round.
3. Bots do not check corners and angles.
4. A bot stands holding a grenade with zero ammo, aiming and trying to fire.

The record splits the work into four independent steps. Step 1 (grenade) and step 2 (site choice) are small fixes
and ship first; step 3 (routes) and step 4 (corner checks) are larger and need Deck measurement. Out of scope:
escort roles for non-carrier attackers, defender distribution between sites (open question 5), a core AI PRNG, and
any change to S&D rules (`02-modes.md` d.8).

Research and evidence: [notes/38](../../notes/38-snd-bot-behaviour-research.md). It reports code inspection and
external reading only: no Deck, in-game, GLuaTest or performance runs. Hypotheses are marked as such. This record is
tracking, not authorization to implement, access the Deck or publish.

Paths are relative to `addons/privatewar/lua/privatewar/` unless they start with `addons/`, `docs/` or `design/`.

## Decisions and prerequisites

- [ ] Maintainer answers the open questions below (each has a recommended default). Steps 1 and 2 need only
  questions 1-3; steps 3 and 4 need questions 4 and 6-8.
- [ ] No `design/` change is proposed. If the maintainer wants per-bot path cost noise inside A* (step 3 option C),
  or a new difficulty/personality field (question 7), the `07-bots.md` d.6 / d.10 text and `docs/api/` contracts
  change only with explicit user approval through the orchestrator.
- [ ] Orchestrator confirms lane ownership where `TASKS.md` "Lanes and ownership" is silent: `modules/snd/`
  (proposed `modes`), `modules/equipment/` (proposed `loadout`), `objective_actions/` (proposed `bots`).
- [ ] Contract changes listed per step ("Frozen/public APIs touched") are frozen by the orchestrator before the lane
  agent starts.
- [ ] Obtain explicit permission and confirmation that the Steam Deck is free before any game access or tests.

## Step 1: never stay on an unusable weapon (problem 4, ship first)

### Step 1: Root cause

Bots can never fire the grenade SWEP: `PrimaryAttack` returns for bots
(`addons/privatewar/gamemodes/privatewar/entities/weapons/weapon_pw_grenade.lua:96-100`). Any path that leaves a bot
holding it makes the bot aim and press attack forever. Nothing in the bot stack restores a usable weapon; the only
switch back is one timer in the bot throw path.

1. **Hypothesis H4a (most likely; confirm in game).** `_BotThrow` (`modules/equipment/sv_grenades.lua:81-98`) calls
   `SelectWeapon(grenade)`, throws at once through `_Spend`, and schedules one check after `BotHold = 0.3` s
   (`modules/equipment/sh_grenades.lua:20`) that returns only if the grenade is active at that instant
   (`sv_grenades.lua:94-95`). ARC9 defers switches until its holster animation ends and re-selects from its own
   `StartCommand` hook (`notes/08-weapon-adapters.md` section 2, "Weapon switch"; the adapter reads
   `GetHolsterTime()`, `addons/privatewar-arc9/lua/privatewar/weapon_adapters/arc9/init.lua:144`). With a holster
   time above 0.3 s the check sees the ARC9 gun, does nothing, and ARC9 then completes the switch to the now-empty
   grenade. The only bot-throw test switches from `weapon_crowbar`
   (`lua/tests/privatewar/grenades_inventory.lua:229-249`),
   which never exercises a deferred switch. How to confirm: on the Deck, log the bot's active class at the
   `BotHold` timer and 1 s later after `PW.Equipment.Use(bot, "lethal")` from an ARC9 rifle.
2. **H4b (code-confirmed path).** `bot_behaviors/melee.lua:50` stores `st.previous = f.active` from the 5 Hz tactics
   facts (`modules/bots_tactics/init.lua:85-94`); inside the throw window this is the grenade class. `melee.lua:78`
   writes it into `intent.weapon`, which is sticky (only `sprint`, `drive`, `slideAt` are cleared per frame,
   `docs/api/bots-blackboard.md` "Intent" rule 1; `board.intent` resets only on round prepare / team change / match
   end, `modules/bots_brain/init.lua:95-107`). `bots_input` then re-selects the grenade
   (`modules/bots_input/shared.lua:125-136`; ARC9 `reselectEveryTick = true`,
   `addons/privatewar-arc9/lua/privatewar/weapon_adapters/arc9/shared.lua:349`).
3. **H4c (minor).** `_ReturnWeapon` returns `nil` when no non-grenade weapon is owned (`sh_grenades.lua:61-72`).

### Step 1: Steps

- [ ] 1a. Pure picker in `modules/bots_tactics/sh_weapons.lua` (new `sh_` file, keeps `init.lua` small):
  `PW.BotTactics.UsableWeapon(facts) -> class?` over plain data
  `{ active = class?, weapons = { { class, kind, grenade, clip, capacity, reserve } }, previous = class?,
  throwingUntil = number?, now = number }`. Returns `nil` when the active weapon is usable or a bot throw is still in
  its window; otherwise the class to select: `previous` if usable, else the first gun with ammo (clip or reserve),
  else melee, else `nil`. A grenade SWEP (`PWGrenade`) or `kind == "throwable"` is never usable for bots.
- [ ] 1b. Glue in `modules/bots_tactics/init.lua` (5 Hz facts tick, existing): gather the plain list from
  `bot:GetWeapons()` through the adapters already used in `weaponFacts` (`init.lua:50-60`); when `UsableWeapon`
  returns a class, write `intent.weapon = class` and remember it was a guard write (`f.guardWeapon`); once the class
  is active, clear `intent.weapon` only if it still equals the guard write. Never touch an `intent.weapon` owned by
  a running melee behaviour (`ctx.running == "melee"` check through the board, or a marker set by melee).
- [ ] 1c. `bot_behaviors/melee.lua`: never record a grenade/throwable as `previous`; in `OnEnd` resolve the weapon
  through `UsableWeapon` instead of restoring a stale class, and clear `intent.weapon` once that weapon is active
  (no sticky selection after melee).
- [ ] 1d. `modules/equipment/sv_grenades.lua` (loadout lane, separate small PR or same PR after orchestrator
  approval): replace the single `BotHold` check by a bounded poll (for example every 0.25 s up to 3 s) that returns
  as soon as a grenade is active after the throw, and expose the throw window (`PW.Equipment.BotThrowing(ply, now)`
  or a field the tactics facts read) so 1b does not fight the throw. Alternative (question 2): bots do not select the
  grenade at all and only pass the SWEP entity for inflictor credit.
- [ ] 1e. Treat the bot as "dry" for `MeleeWanted` when the active weapon is a grenade (`sh_moves.lua:60-67`), so a
  stuck frame with a close enemy still produces a reaction until 1b switches.

### Step 1: Files owned

`modules/bots_tactics/sh_weapons.lua` (new), `modules/bots_tactics/init.lua`, `modules/bots_tactics/shared.lua`
(include line only), `bot_behaviors/melee.lua`, `modules/equipment/sv_grenades.lua`,
`modules/equipment/sh_grenades.lua`,
tests `lua/tests/privatewar/bots_usable_weapon.lua` (new), `lua/tests/privatewar/grenades_inventory.lua`.

### Step 1: Frozen/public APIs touched

- `docs/api/bots-blackboard.md`: `bots_tactics` becomes a writer of `intent.weapon` (guard only); document that
  `intent.weapon` is cleared by its writer after the selection is reached.
- `docs/api/equipment.md`: `Use` "returns to the previous weapon after `BotHold`" becomes "returns once the switch has
  happened, within a bounded wait"; any new `BotThrowing` accessor.

### Step 1: Mandatory test cases (write first)

- `UsableWeapon`: active grenade with zero ammo returns the previous gun; active grenade with ammo left also returns a
  gun (bots never fire grenade SWEPs); during the throw window returns `nil`; previous that is itself a grenade is
  skipped; a dry gun with reserve 0 and another gun with ammo returns the other gun; only melee left returns melee;
  nothing usable returns `nil`; a usable active weapon returns `nil`.
- Guard glue (fake facts): a guard write is cleared after the class becomes active; a melee-owned `intent.weapon` is
  never overwritten or cleared by the guard.
- Melee: `OnStart` with `f.active` = grenade class does not store it; `OnEnd` leaves no sticky `intent.weapon` once
  the restored weapon is active.
- Equipment bot path with a fake deferred switch (store with injectable engine calls, `_NewStore`): the switch to the
  grenade completes after `BotHold`; the bot still ends on the previous weapon; the poll stops after its bound.
- Keep the existing "Mandatory: in a LIVE match the bot gets the grenade SWEPs ..." case green.

### Step 1: Deck/in-game smoke checks

- With an ARC9 rifle: `PW.Equipment.Use(bot, "lethal")` with the last frag; within 3 s the bot holds a gun.
- Log the active class at `BotHold` and 1 s later before the fix to confirm or reject H4a (record the result here).

## Step 2: choose the attack site per round (problem 1, ship first)

### Step 2: Root cause (confirmed)

`modules/snd/sh_objectives.lua:49` returns the plant objective for `state.map.sites[1]` only. The round state has no
attack target (`modules/snd/shared.lua:72-83`); `modes/snd.lua:64-77` randomizes only the carrier. The commander and
the local pick choose only among the objectives they receive (`modules/bots_commander/shared.lua:196-211`,
`modules/bots_objectives/shared.lua:124-135`).

### Step 2: Steps

- [ ] 2a. Pure `PW.SND.PickAttackSite(sites, random, previous?) -> site id` in `modules/snd/shared.lua` (or a new
  `sh_` file if the 500-line rule needs it): weighted random over the sites, the previous round's site weighted
  down (question 1 default 0.35), deterministic for an injected `random`.
- [ ] 2b. `modes/snd.lua` `PrepareRound`: pass the chosen id into `NewRound` (new optional argument `attackSite`,
  default `sites[1].id` so existing callers and tests keep working); store `state.attackSite`; remember the previous
  site on the mode (`self._SNDLastSite`).
- [ ] 2c. `sh_objectives.lua:49`: build the plant objective from `state.attackSite`. Keep the same site after a
  bomb drop and pickup in the same round (question 3 default).
- [ ] 2d. Information safety: `attackSite` stays server-only. `lib.Snapshot` (`modules/snd/sh_round.lua:121-126`)
  copies explicit fields, so it is not sent; add a test that proves it. Defender objectives keep listing both sites.

### Step 2: Files owned

`modules/snd/shared.lua`, `modules/snd/sh_objectives.lua`, `modes/snd.lua`, tests `lua/tests/privatewar/mode_snd.lua`,
`lua/tests/privatewar/bots_snd.lua`.

### Step 2: Frozen/public APIs touched

`docs/api/modes.md` S&D section: `PW.SND.NewRound` gains an optional `attackSite`; new `PW.SND.PickAttackSite`.
`changes/planned/snd-de-autodetect.md` item "Consider that existing bots attack the first site" is then covered
here; link both records when this one moves.

### Step 2: Mandatory test cases (write first)

- `PickAttackSite`: with a scripted random sequence both sites are chosen; the previous site is chosen less often
  over 1000 seeded draws (bounded ratio, deterministic); a single valid site always returns it.
- `Objectives(state, 1)` while carried uses `state.attackSite`, not `sites[1]`; after drop and pickup the site is the
  same; `NewRound` without `attackSite` keeps the old behaviour.
- `Snapshot` for both teams never contains `attackSite`; defenders' objectives are identical for either attack site.
- Keep all T-11.12 cases in `docs/agent-test-map.md` green, including "SND bots: sole attacker carries plants and
  guards through shared input rules".

### Step 2: Deck/in-game smoke checks

- Ten rounds on `gm_construct` with bots only: plants happen at both sites (count in the log).

## Step 3: route variety between rounds and between bots (problem 2)

### Step 3: Root cause (confirmed)

Paths are deterministic for a fixed start and goal: centre-to-centre distance cost and heuristic
(`modules/bots_nav/init.lua:41-42`), only the `danger` layer (`bots_nav/init.lua:48-51`), stable tie handling
(`modules/bots_nav/shared.lua:69-82`), and waypoints at the closest point of each next area
(`modules/bots_goal/init.lua:114-129`, `modules/bots_goal/sh_follow.lua:62-76`). S&D spawns and site approaches are
fixed, so each round repeats the same path. The decided teammate-occupancy cost term of `07-bots.md` d.6 is not
implemented. Options and trade-offs: notes/38 section 3.

### Step 3: Steps

- [ ] 3a. Seeded hash (pure, `modules/bots_nav/shared.lua`): `PW.BotNav.Hash01(seed, key) -> [0, 1)`, exact on
  LuaJIT (16-bit split multiplication; no `math.randomseed`, see notes/38). The round seed is drawn once on
  `PW_RoundPrepared` and on match start (respawn modes: once per match, question 6) and stored in the nav store;
  tests inject it.
- [ ] 3b. Option A, portal offsets (per bot, cheap): pure `PW.BotGoal.PortalPoint(edgeFrom, edgeTo, t)` and
  `PW.BotGoal.SharedEdge(extentA, extentB)` (axis-aligned rectangles from `CNavArea:GetExtentInfo` or `GetCorner`)
  in `sh_follow.lua`; `waypoints()` picks `t = 0.2 + 0.6 x Hash01(seed + userId, areaId)` along the shared edge
  instead of the closest point, clamped at least one hull half-width (16 units) from the edge ends. Fallback to the
  current point when the edge is shorter than 48 units or on a ladder/drop link.
- [ ] 3c. Option B, per-round noise layer (between rounds): register cost layer `round_noise` =
  `amplitude x Hash01(roundSeed, areaId) x areaSpan` (non-negative, so the heuristic stays admissible); default
  amplitude 0.25 (question 4). Global for all bots, so it changes the corridor per round, not per bot.
- [ ] 3d. Optional (question 4): via-point lanes for attackers in S&D: at round start the objective action chooses
  one of up to three lateral via areas between spawn and site and routes in two legs. Only if 3b + 3c are not enough
  in the human checkpoint.
- [ ] 3e. Do not implement A\* per-request noise or k-path search (options C, E) without a measured need and user
  approval (C changes the `RequestPath` contract; E multiplies the A\* budget).

### Step 3: Files owned

`modules/bots_nav/shared.lua`, `modules/bots_nav/sh_service.lua` (only if a seed accessor is needed),
`modules/bots_nav/init.lua`, `modules/bots_goal/sh_follow.lua`, `modules/bots_goal/init.lua`, tests
`lua/tests/privatewar/bots_nav.lua`, `lua/tests/privatewar/bots_goal.lua` (existing) or a new
`bots_route_variety.lua`.

### Step 3: Frozen/public APIs touched

`docs/api/bots-blackboard.md` "Goal API" and `bots_nav` rows: new cost layer id `round_noise`, waypoint rule change,
new pure helpers. No change to `RequestPath`.

### Step 3: Mandatory test cases (write first)

- `Hash01` is deterministic for the same seed and key, differs across seeds, stays in `[0, 1)`, and has a roughly
  uniform histogram over 10 000 keys (bounded buckets).
- Synthetic graph with two equal-length corridors: with `round_noise` and two different seeds the chosen corridor
  differs; with the same seed it is identical; the layer never returns a negative cost (existing T-5.5 "cost layers
  change the chosen path" stays green).
- `SharedEdge` of two touching rectangles returns the overlap segment; non-touching rectangles return `nil`;
  `PortalPoint` stays inside the segment minus the margin for `t` in `[0, 1]`; two bot seeds give different points.
- `Waypoints` keeps the final point and the step count unchanged with offsets enabled.

### Step 3: Deck cost

- 3b: one shared-edge computation per path step when a path arrives (2 extent reads per step, about 30-80 steps per
  path). No per-tick cost.
- 3c: one hash per nav area per bake; the bake already runs about once per second in chunks of 256 areas per tick
  (`sh_service.lua:238`, `:260-263`). Possible cost: more A* expansions because the noise loosens the heuristic.
  Measure `PW.BotNav` counters (`GetCounters`: `iterations`, `partial`) over ten S&D rounds before and after; accept
  if mean iterations per found path rise by at most 30 % and the partial rate does not rise (question 4).

### Step 3: Deck/in-game smoke checks

- Ten bot-only rounds: the carrier's path (debug overlay `pw_bot_debug`) differs between at least some rounds; no new
  stuck reports; nav counters recorded in this record.

## Step 4: look at likely threats while moving (problem 3)

### Step 4: Root cause (confirmed)

Without an aim target the walking view always looks 160 units ahead along the path (`modules/bots_goal/init.lua:24`,
`:246-256`; `sh_follow.lua:20-30`). Travelling code clears look points on every leg
(`objective_actions/movement.lua:26`, `bot_behaviors/hunt.lua:65,70`), and sprinting drops any target by contract
(`modules/bots_tactics/sh_moves.lua:117-121`; `docs/api/bots-blackboard.md` "Intent" rule 3). Legs of 300+ units are
sprinted with chance `mobility` (`sh_moves.lua:56-58,123-128`). Perception sees a 110 degree cone
(`bot_difficulties/*.lua:34`), so side openings stay unseen until passed. The follower already moves relative to the
eye yaw (`bots_goal/init.lua:257-259`), so looking sideways while walking needs no input change.

### Step 4: Steps

- [ ] 4a. Pure module `modules/bots_goal/sh_watch.lua`:
  - `WatchPoints(pathAreas, neighbours, centres, hidingSpots, opts) -> { { pos, index } }`: centres of neighbour
    areas not on the path plus at most `opts.spotsPerArea` (default 1) hiding spots per path area, capped at
    `opts.max` (default 24), each tagged with the path index.
  - `CornerPreaim(points, index, pos, opts) -> Vector?`: when the path turns by more than `opts.turn` (45 degrees)
    within `opts.ahead` (250 units), a point `opts.beyond` (200 units) past the turn on the next segment, at eye height.
  - `PickGlance(watch, pos, forward, index, checked, now, opts) -> pos?`: unchecked points near the current index,
    side angle 30-120 degrees, distance 100-1200 units (CS "not closer than 100"), best by angle and distance, ties by
    an injected random; `checked` keyed by rounded position with a 10 s memory.
- [ ] 4b. Glue in `bots_goal/init.lua` (stay under the 500-line rule; move helpers to a new `sv_watch.lua` if
  needed): compute watch points once in `onPath` using the nav graph adjacency (expose a read-only
  `PW.BotNav.Neighbours(id)` from the cached `AreaGraph`) and `GetHidingSpots`; in `legsFor`, when the follower owns
  the view and the intent is not sprinting, use in order: corner pre-aim, an active glance (0.4-0.8 s), a new glance
  chosen at most every `glanceEvery` seconds, else the look-ahead point. Mark a watch point checked when it was the
  glance target or when it was inside the FOV cone for one follower tick (cheap stand-in for CS peripheral vision;
  no trace).
- [ ] 4c. Walk near likely contact: `PW.BotTactics.Travel` does not sprint when the travel target is inside an
  objective zone radius plus 900 units for S&D attackers and defenders, or (question 8) always when the next 400
  units of path have watch points. This keeps the existing sprint contract: sprinting still faces the path.
- [ ] 4d. Glance frequency by difficulty, without new data fields by default: derive `glanceEvery` from the existing
  `turn_max_speed` tier (recruit slow, veteran fast). A new `corner_check` field needs approval (question 7) and a
  T-5.12 update (every field must be read).

### Step 4: Files owned

`modules/bots_goal/sh_watch.lua` (new), `modules/bots_goal/shared.lua` (include line), `modules/bots_goal/init.lua`,
optional `modules/bots_goal/sv_watch.lua`, `modules/bots_nav/init.lua` (read-only `Neighbours`),
`modules/bots_tactics/sh_moves.lua`, tests `lua/tests/privatewar/bots_watch.lua` (new).

### Step 4: Frozen/public APIs touched

`docs/api/bots-blackboard.md`: `board.path` gains `watch` (plain vectors with indices); the `bots_goal` row's
"walking view target" description changes from "160 units ahead" to "ahead, a corner pre-aim or a glance";
`PW.BotNav.Neighbours`. "Intent" rule 3 (sprint faces the path) is kept.

### Step 4: Mandatory test cases (write first)

- `WatchPoints`: an L-shaped corridor with one side doorway yields the doorway centre and no on-path area; the cap
  and `spotsPerArea` are respected; indices match path positions.
- `CornerPreaim`: a straight path returns `nil`; a 90 degree turn 150 units ahead returns a point on the next segment
  beyond the turn; a turn farther than `ahead` returns `nil`.
- `PickGlance`: points behind the bot, closer than 100 units or checked within 10 s are rejected; the best side point
  wins; identical input and random give identical output.
- Follower view (fake board): sprinting keeps the look-ahead view; an aim target suppresses glances; with a watch
  point the walking view target turns toward it and returns to the path afterwards.
- `Travel` does not sprint inside the S&D site radius rule; sprints as before elsewhere (existing T-11.6 cases green).

### Step 4: Deck cost

- Once per path: neighbour lookup (already cached by `AreaGraph`) and `GetHidingSpots` for path areas, at most about
  80 areas; output capped at 24 points.
- Per follower tick (10 Hz per moving bot): at most 24 vector dot products and distance checks. No traces by
  default. If LOS filtering is added later: at most 1 trace per glance, at most 2 per second per bot.
- Measure with the scheduler and profiler counters (`07-bots.md` d.11) for 10 bots; accept if the bot share of the
  per-tick budget does not exceed the current measurement by more than 10 %.

### Step 4: Deck/in-game smoke checks

- `pw_bot_debug` on, one attacker bot entering a site: the view visibly turns toward side doorways and around corners
  before the bot reaches them; no view jitter (spots closer than 100 units are never targets).

## Human checkpoint (maintainer verifies in game)

1. Grenade: over several S&D rounds with ARC9 weapons, no bot ever stands holding a grenade; after throwing its last
   grenade a bot is back on a gun within about 1 s and fights normally.
2. Site choice: over about ten rounds attackers plant at both sites, without an obvious repeating pattern.
3. Routes: the carrier and escorts do not trace the exact same line every round; within a round bots do not walk in
   a single file on one line; nobody gets stuck more than before.
4. Corner checks: walking bots look into side doorways and pre-aim corners before entering sites; they walk (not
   sprint) near sites; the view turning looks human (not twitchy); bots react to an enemy around a corner more often
   than before.
5. Performance: the Deck frame rate with the usual bot count is not noticeably worse than before.

The checkpoint items go to the local manual checklist (private) when work starts.

## Risks

- Step 1: the guard can fight a legitimate selection (melee, a future device or streak weapon). Mitigation: the
  guard only acts when the active weapon is a grenade/throwable or dry, and only clears its own write.
- Step 1: H4a is a hypothesis; if the in-game log rejects it, 1b still fixes the symptom, but 1d may be unnecessary.
- Step 2: a random site can pick an unreachable site on a bad map; `PW.SND.Validate` and the map readiness checks
  already require reachable approaches, so only authored or detected valid sites are candidates.
- Step 3: noise can produce visibly longer detours or more partial paths on large maps; amplitude is a tunable and
  measured. Portal offsets near ledges can make bots clip corners; keep the hull margin and fall back on short edges.
- Step 4: glances slow target acquisition straight ahead if overdone; skill-based frequency and the FOV "already
  seen" rule limit it. More walking makes rounds slower; question 8 controls the radius.
- Lines and functions must stay within the rules gate (500 lines per file, 60 per function); `bots_goal/init.lua`
  is already 439 lines.

## Open questions for the maintainer

1. Site choice weights: should the previous round's site be less likely? Recommended default: yes, weight 0.35 for
   the previous site, 1 for the other.
2. Grenade bot path: keep switching to the grenade SWEP for the throw (visible to players, needs 1d) or throw
   without switching (no race at all, but other players never see a bot holding a grenade)? Recommended default:
   keep the switch and fix the return (1d), plus the guard (1b) as a safety net.
3. If the carrier dies and another attacker picks up the bomb, keep the round's site or re-pick? Recommended
   default: keep it.
4. Route variety strength: portal offsets plus per-round noise with amplitude 0.25 and the 30 % A* budget limit, and
   via-point lanes only if that is not enough? Recommended default: yes.
5. Defenders currently each hold the site nearest their spawn every round (notes/38 section 2). Should this record
   also split defenders between sites (for example at least one per site when the team has two or more bots)?
   Recommended default: yes, as a separate small step after step 2, because it also reduces round-to-round sameness.
6. Respawn modes: route noise seed per match or per life? Recommended default: per round in round modes, per match
   in respawn modes (the danger layer already varies routes there).
7. Corner-check frequency: derive from existing difficulty fields, or add a new `corner_check` difficulty field
   (needs approval and a T-5.12 update)? Recommended default: derive from existing fields.
8. Walking near sites: no sprint within the site radius plus 900 units for both teams in S&D, or also whenever the
   path ahead has openings in every mode? Recommended default: S&D site rule only.

## Evidence

Research: [notes/38-snd-bot-behaviour-research.md](../../notes/38-snd-bot-behaviour-research.md), code inspection of
`main` at 2026-11-22 only. No implementation, test run, Deck access or human acceptance is claimed.
