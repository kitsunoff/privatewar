# 07 — Bots

Status: decided (values tuned in game).

## Goal and scope

Bots that fill empty slots: manager, brain, navigation, input control.

## Decisions

- Bots are real players (`player.CreateNextBot` + `StartCommand`), not NextBot entities that imitate players.

1. **Quality target: bots that feel alive.** The main use case is playing modern-CoD-style matches offline, solo or with a few friends, against bots (`../DESIGN.md`, Goal). Bots make mistakes, have personality, play objectives and move believably. At the highest difficulty they are a serious challenge without cheating (no wallhacks, no instant reactions, no speed above human).

2. **Fairness: a bot is a virtual gamepad.**
   - Bots act only through `CUserCmd` (view, movement, buttons). No `SetPos`, no damage/health/ammo/spread bonuses, no knowledge of positions through walls. (Killzone 3, Valve.)
   - Difficulty changes only human parameters: reaction, accuracy, turn speed, decision quality, knowledge sharing.
   - Any dynamic adjustment may only nerf bots, never buff them (players notice AI doing better than normal, `../notes/14-industry-bot-ai.md`).

3. **Layered architecture; every layer is a separate module.**

   ```text
   team commander (1 Hz)       objectives from MODE:BotObjectives(team): weight + desired bot count
      │                        attacker/defender rebalance, hunt slots, personality ratio
      ▼ orders
   brain (10 Hz)               dual-utility over bot_behaviors/ → active Action (OnStart/Update/OnEnd/...)
      │  intents               SetGoal(point, radius, priority), target, stance, buttons
      ▼
   perception (10 Hz)          FOV + multi-point LOS, reaction queue, hearing, contact memory
   aim (every tick)            spring-damper, focus error, lead, recoil comp, fire-when-steady
   navigation (budgeted)       own time-sliced A* (binaryheap, MIT), danger costs, stuck recovery
   input (every tick)          GM:StartCommand writes CUserCmd, adapter GetInputRules
   scheduler                   ms budget per tick, random phase per bot, global FIFO for expensive jobs
   ```

   - Layers are modules (`modules/bots_manager`, `bots_input`, `bots_scheduler`, `bots_nav`, `bots_perception`, `bots_aim`, `bots_brain`, `bots_commander`) that talk only through a per-bot blackboard with documented fields (intents, contacts, goal, orders) and `PW_Bot*` hooks. Any layer can be replaced by another module with the same contract (global rule 1, `01-extensibility.md` decision 16).
   - Clarified with the user on 2026-11-07: one module `bots` owns the bot settings (`bots.fill`, `bots.count`, ...; full id `<owner>.<key>`, `01-extensibility.md` decision 17). The `bots_*` modules above are its sub-modules.
   - Rates: commander 1 Hz, brain and perception 10 Hz with a random phase per bot, aim and input every tick (CS: think 10 Hz, aim 30 Hz). Budget: `bots.tickbudget` (ms per tick); expensive jobs (cover search, long A*) go through a global FIFO, one per tick.

4. **Brain: dual-utility over a registry of behaviours.**
   - Each behaviour has a rank (hard priority bucket: self-preservation > objective > roam) and a weight (nuance). Options much worse than the best are screened out; among the rest the choice is weighted-random, so bots differ. Lower difficulty widens the screen (`decision_screen`).
   - The current behaviour gets a commitment bonus, minimum run time and cooldowns; each behaviour may declare its own re-evaluation interval (default 1000 ms, minimum 100 ms).
   - Sources: Dill (Game AI Pro 2 ch.3), Killzone.

5. **Behaviours are a kind `bot_behaviors/`, implemented as Actions.**

   ```lua
   -- bot_behaviors/capture_flag.lua
   BEHAVIOR.Modes    = { "dom" }                 -- nil = every mode
   BEHAVIOR.Interval = 0.5                       -- re-evaluation interval, s

   function BEHAVIOR:Rank(bot, ctx)   return ctx.order and ctx.order.type == "capture" and 20 or 10 end
   function BEHAVIOR:Weight(bot, ctx) return (1 - ctx.threat) * ctx.flagCloseness end

   function BEHAVIOR:OnStart(bot, ctx) end
   function BEHAVIOR:Update(bot, ctx)                -- returns Continue / ChangeTo / SuspendFor / Done(reason)
       bot:SetGoal(ctx.flag.pos, 128, "objective")
       return PW.Bot.Continue()
   end
   function BEHAVIOR:OnEnd(bot, ctx) end
   function BEHAVIOR:OnSuspend(bot, ctx) end
   function BEHAVIOR:OnResume(bot, ctx) end
   ```

   - Action stack (Valve L4D / TFBot): a behaviour can be suspended by an urgent one ("under fire") and resumed. Transitions are return values, so addons cannot force each other's state; reason strings feed the debug overlay.
   - Separate channels: target/aim and legs/movement are independent controllers writing different `CUserCmd` fields (L4D SurvivorBots).
   - Built-in behaviours ship with the gamemode; modes and addons add theirs without editing anything.

6. **Navigation: one goal API with typed priorities, own A*.**
   - `bot:SetGoal(point, radius, priority)`, priorities `hunt` < `guard` < `objective` < `tactical` < `critical`; a higher one overrides a lower one.
   - Goal wrapper: navmesh projection, caching, retry backoff, blacklist of unreachable goals, status string.
   - Time-sliced A* over navmesh areas with `Tieske/binaryheap.lua` (MIT, vendored); partial paths on iteration cap; unreachable-pair cache. Cost = distance + danger (recent deaths, decays in 120 s, CS) + penalty for areas used by teammates (natural flanks and spread, Killzone).
   - Path cost terms are **cost layers** registered by modules and baked into a per-area cost table refreshed about once per second; the A* inner loop never calls hooks.
   - Stuck recovery ladder (jump, crouch, back off, side point, repath). Fallback: engine `Path("Follow")`, which accepts player bots (wiki), synchronous.

7. **Perception and knowledge.**
   - FOV cone (`awareViewAngle`), LOS to several body points, reaction queue (the bot acts on the snapshot from N ms ago, CS), sight-acquisition time.
   - Hearing within range only: gunfire (`EntityFireBullets`, suppressors respected), footsteps of sprinting players, explosions (`EntityEmitSound`). Never map-wide.
   - Contact memory per bot: last position and velocity, 12 s; when lost, search 5 points (last seen, ahead along velocity, left, right, far ahead).
   - Taking damage reveals the attacker's direction; "who hit me" becomes an urgent target with a human-like turn, not a snap.
   - Team sharing of contacts with a delay (`share_delay`) and radius by difficulty.
   - **Stimulus sources are pluggable:** modules feed contacts through `PW.Bot.AddStimulus(bot or team, kind, data)` (for example the UAV streak reveals enemies to the team's bots exactly as the radar shows them to humans).

8. **Aim: spring-damper with focus error.**
   - View driven by a spring-damper with an acceleration clamp (CS: stiffness 100–300, damping 25–30, accel 2000–3000 °/s²), integrated at a fixed dt.
   - Error starts large on acquisition and shrinks while the aim is steady (CS: 20° Easy → 2° Expert), resets on big view moves; proportional to range.
   - Lead and headshots gated by difficulty; recoil compensation gain by difficulty, using adapter `GetRecoil` (`04-weapons.md`).
   - Fire only when the aim has settled and the line of fire to head/torso is clear; "visible but blocked" for ≥400 ms → flank.

9. **Team commander.**
   - Per team at 1 Hz: objective list from `MODE:BotObjectives(team)` (position, weight, desired count, required action), assignment pass, attacker/defender rebalance (Halo 3 tasks).
   - Bots may ignore orders to survive (order compliance is a consideration in utility scoring, Killzone 3; `teamwork` parameter).
   - **Hunt slots:** at most 1–2 bots hunt one human at a time; the budget is re-rolled every 30–60 s; a stalled hunter is replaced by a closer bot. Critical for solo play.

10. **Personalities and difficulty are data kinds.**
    - Kind `bot_personalities/`: a set of numbers (engagement range, cover chance, flank radius, third-party delay, aggression) and a type (`active` or `stationary`). Default ratio per team 4 active : 1 stationary. MVP set: run-and-gun, CQB, camper.
    - Kind `bot_difficulties/`: a table of about 30 parameters per tier (reaction, sight time, aim spring, focus error, lead, headshots, recoil gain, burst timing, strafe/slide chances, memory, share delay, decision screen, commitment, teamwork, target persistence). Values start from CS `botprofile.db` (`../notes/14-industry-bot-ai.md` "Difficulty model proposal") and are tuned by us.
    - `match` setting `bots.difficulty` picks a tier (or a mix); playlists can set it.

11. **Debug overlay from day one:** behaviour name and reason, target, goal and path above each bot; perf counters (traces, A* expansions, ms per layer) through the profiler (`00-core.md` decision 6).

12. **Reuse:** vendor only `Tieske/binaryheap.lua` (MIT); everything else is written by us from the designs above. No GMod bot framework is suitable as a dependency. Compatible with any licence we choose.

13. **MVP behaviours.**

    | Behaviour | Rank bucket | What it does |
    | --- | --- | --- |
    | `fight` | combat | Shoot the visible target; strafe/crouch by personality |
    | `take_cover` | survival | Cover point paired with a peek point; alternate hide and peek with a fire-phase gate |
    | `reload_cover` | survival | Reload in cover, then flank back to the remembered position |
    | `retaliate` | survival | Took damage: turn to the attacker with a human-like turn |
    | `search` | combat | Lost the enemy: search 5 points around the last known position |
    | `hunt` | roam | Go to hot spots (recent deaths, sounds), respecting hunt slots |
    | `objective` | objective | Follow the commander's order: capture, defend, collect a tag |
    | `third_party` | combat | Heard a fight nearby: flank into it |
    | `use_streak` | objective | Activate a killstreak when `BotShouldUse` agrees |
    | `throw_equipment` | combat | Grenade at a target behind cover or into an objective zone |
    | `camp` | roam | Stationary personality only: hold a spot and watch its entrances |

    - Domination and Kill Confirmed need no dedicated behaviours: `objective` covers them, with targets and required actions coming from `MODE:BotObjectives`.

    **Revision 2026-11-07 (user decision after the first playtest): bot combat movement.** Playtest finding: bots barely use cover and do not run. Requirements on `fight`, `take_cover` and the movement layer:

    - Under fire a bot uses cover and peeks from it (the `take_cover` cover/peek pairs), instead of standing in the open.
    - A bot strafes while shooting and runs between covers instead of standing still.
    - At close range a bot switches to melee.
    - Optional support for the third-party Quick Slide addon, when it is installed: slide to peek around corners, to dodge incoming fire, and to close distance. Only the addon's public API is read; its code is never copied (`CLAUDE.md`, "Code you must not copy"). The feature is off when the addon is absent.
    - Fairness (decision 2) still holds: the movement uses the same virtual-gamepad inputs and human-like speeds.
    - Combat numbers, decided (confirmed by the user on 2026-11-07; the local manual checklist (not published) section 7, item 67): melee from 110 units (350 with an empty weapon), leaving melee beyond 220; personality field `mobility` (run_and_gun 0.9, cqb 0.7, camper 0.3); difficulty field `slide_chance` 0 / 0.2 / 0.4 / 0.6; no firing while sprinting, a sprint to cover only under pressure; a peek fallback of 80 units sideways; two or more visible enemies count as pressure.

14. **`MODE:BotObjectives(team)` format and MVP content.**

    ```lua
    {
        id     = "flag_B",
        pos    = Vector(...),
        radius = 160,
        action = "capture",   -- "capture" | "defend" | "collect" | "deny" | "hold" (S&D later adds "plant", "defuse")
        weight = 0.8,         -- 0..1, importance for this team now
        want   = 2,           -- desired number of bots
    }
    ```

    - The commander assigns bots every second using `weight`, `want`, distance and personality (stationary personalities prefer `defend`); the `objective` behaviour performs the action.

    | Mode | Objectives |
    | --- | --- |
    | TDM | None; bots are driven by `hunt` |
    | FFA | None; same |
    | Domination | One per flag: not ours → `capture` (higher weight for near flags and the middle one); ours → `defend`, `want` at most a third of the team; ours under capture → `capture` with high weight. Anti-dither: never pull a bot off a flag it is capturing; reassign at most every 30–45 s |
    | Kill Confirmed | One per tag: enemy tag → `collect`; own team's tag → `deny`; `want = 1`, weight grows with closeness; refreshed every second |

15. **Default difficulty tiers.**
    - Tiers: `recruit`, `regular`, `hardened`, `veteran`; each is a file in `bot_difficulties/`.
    - Default values: the 26-parameter table in `../notes/14-industry-bot-ai.md` ("Difficulty model proposal"), plus manoeuvre chances (our tuning): strafe 0 / 0.5 / 0.7 / 0.9, slide 0 / 0.2 / 0.4 / 0.6, dive 0 / 0 / 0.15 / 0.2, corner fire 0 / 0 / 0.5 / 1.
    - Key values:

      | Parameter | Recruit | Regular | Hardened | Veteran |
      | --- | --- | --- | --- | --- |
      | Reaction, s | 0.60 | 0.45 | 0.32 | 0.22 |
      | Initial aim error, ° | 20 | 12 | 6 | 2 |
      | Turn speed, °/s | 180 | 360 | 540 | 720 |
      | Headshots | no | no | rifles only | yes |
      | Strafe chance | 0 | 0.5 | 0.7 | 0.9 |
      | Contact share delay, s | 2.0 | 1.5 | 1.0 | 0.5 |

    - These are starting points, tuned in game; changing them needs no code changes.

16. **The blackboard contract is specified in the API documentation when the code is written**, not in this design. The architectural rule is fixed by decision 3 (layers talk only through the blackboard and `PW_Bot*` hooks).

### Extension points (summary)

| What an addon wants | How |
| --- | --- |
| New behaviour (new mode, new streak usage) | `bot_behaviors/` file |
| Objectives for a new mode | `MODE:BotObjectives(team)` |
| New personality | `bot_personalities/` file |
| New difficulty tier | `bot_difficulties/` file |
| Make bots aware of something (UAV, sensor, sound) | `PW.Bot.AddStimulus` |
| Influence paths (avoid an area, prefer cover) | Register a cost layer |
| Use a streak or equipment | `STREAK:BotShouldUse`, `EQUIPMENT:OnUse` via `PW.Equipment.Use` |
| Weapon-base quirks | Adapter bot methods (`04-weapons.md`) |
| Replace a whole layer (better aim, other navigation) | A module implementing the layer contract |
| React to bot events | `PW_Bot*` hooks |

## Interfaces

TBD.

## Performance budget

- A per-tick budget for bots and heavy searches, spread across frames; no `ents.Find*` in hot loops.

## Security

TBD.

## Open questions

1. ~~Difficulty table~~ Closed: decision 15.
2. ~~MVP behaviours~~ Closed: decision 13.
3. ~~`MODE:BotObjectives`~~ Closed: decision 14.
4. ~~Blackboard contract~~ Closed: decision 16 (API documentation at implementation time).

## Research

- `../notes/14-industry-bot-ai.md` (industry techniques: CS bot numbers, Killzone, dual-utility, perception, aim, difficulty parameters)
