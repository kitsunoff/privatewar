# 14 — How the industry builds multiplayer shooter bots

Scope: published techniques (GDC talks, Game AI Pro chapters, theses, shipped data files, open-source reimplementations) for bots that play like humans, play objectives, and scale difficulty without cheating. Libraries and frameworks are out of scope.

Labels:

- **[source]**: stated in the cited document, code or data file (read in this session unless noted).
- **[inference]**: my conclusion for our gamemode, not stated by the source.
- **[unverified]**: from memory or secondary reporting; not confirmed against a primary source in this session.

Primary evidence for Valve's bot comes from two places. The first is the shipped `botprofile.db`, still carrying Michael Booth's header in CS2, mirrored by SteamTracking. The second is ReGameDLL_CS, an open-source (GPL) reimplementation of the CS 1.6 game DLL that includes Booth's bot (`cs_bot_*.cpp`). The GDC 2004 slides ("The Making of the Official Counter-Strike Bot") are on GDC Vault behind a login, and the known mirrors (files.aigamedev.com, Dropbox) were dead or returned HTML. I did not read the slides.

## TL;DR — takeaways for our design

1. Bots must use the same "virtual controller" as players and must not touch the engine directly. In our case that means CUserCmd only: no `SetPos` and no damage hacks. [source: Killzone 3, GAP1 ch.29]
2. Model reaction time with a delay queue: the bot "attends" to the perception snapshot from N ms ago. Valve uses a 20-slot ring buffer at 10 Hz. [source: ReGameDLL `UpdateReactionQueue`]
3. Use reaction times of about 0.2 s (simple, expected) to 0.4 s (go/no-go). Add time for weak stimuli (far or partly visible), required aim travel, and attention lapses. [source: Rabin, GAP2 ch.5]
4. Drive the view with a spring-damper with acceleration limits, rather than snapping angles. Valve uses stiffness 100–300, damping 25–30 and max accel 2000–3000 deg/s². [source: CS `botprofile.db` + `UpdateLookAngles`]
5. Aim error should start large, shrink while the view is steady ("focus"), and reset on big view moves. Error is proportional to range, so the angular error stays constant. CS profiles range from 20° initial spread (Easy) to 2° (Expert). [source: `botprofile.db`, `SetAimOffset`]
6. Split the brain into layers: commander (per team) → squad → individual. Orders flow down and reports flow up. The individual keeps its freedom (target, position, weapon). [source: Killzone 2/3]
7. Run the commander as an objective list with weights and desired bot counts, plus a bot-to-objective assignment pass. Halo 3 uses a priority task tree with capacities, which maps directly to Domination flags. [source: KZ3; Halo 3 Objectives]
8. Make paths tactical by adding danger or influence to area costs. Penalise areas used by friendly squads to get natural flanks and spread. [source: CS `PathCost`, KZ2/KZ3 squad pathfinder]
9. Choose positions with a generate → cheap filters → score → expensive raycast filters (best-first) pipeline, and cap raycasts per frame. [source: Crytek TPS, GAP1 ch.26]
10. For decision selection that third parties can extend, use dual-utility: rank buckets plus weighted-random choice among near-best options. It gives priority control and variety without "stupid" picks. [source: Dill, GAP2 ch.3]
11. Persistence on a target, revenge on attackers, and "hustling" (only ever nerf, never buff) read as human. Players are bad at detecting randomness and cheating, but they notice AI doing better than normal. [source: Wetzel & Anderson, GAP3 ch.4]
12. Budget: full think at 10 Hz and aim at 30 Hz (CS); plan re-evaluation at 5 Hz (KZ2). Run one A* at a time, use a weighted heuristic, and add a cheap reactive path follower on top. [source: ReGameDLL `bot.h`; KZ2 slides; Rabin & Sturtevant GAP1 ch.17; L4D AIIDE 2009]

## 1. Brain architectures in shipped shooters

### What studios used

| Game / studio | Architecture | Why (as stated) | Source |
| --- | --- | --- | --- |
| Counter-Strike bot (Valve / Turtle Rock, 2003–) | Hierarchical state machine: Idle, Hunt, Attack, MoveTo, Hide, Buy, PlantBomb, DefuseBomb, Follow, InvestigateNoise, FetchBomb, EscapeFromBomb, UseEntity | Simple, debuggable; game-specific | [source: ReGameDLL `dlls/bot/states/`] |
| Left 4 Dead (Valve, 2008), "NextBot" | Components (Locomotion, Body, Vision, Intention). Intention is concurrent Behaviors, each an HFSM plus a stack of Actions with `OnStart/Update/OnEnd/OnSuspend/OnResume`. Transitions `Continue/ChangeTo/SuspendFor/Done("reason")`. Events and "contextual queries" propagate from the innermost Action outward | Atomic transitions, encapsulation, reason strings for debugging. SurvivorBots run two concurrent behaviour systems, "Main" and "Legs" | [source: Booth, AIIDE 2009 slides] |
| F.E.A.R. (Monolith, 2005) | GOAP: an FSM with three states (GoTo, Animate, UseSmartObject) plus an A* planner over actions | Decouple goals from actions so different characters satisfy the same goal differently; layering of simple behaviours; dynamic problem solving | [source: Orkin GDC 2006] |
| Halo 2 / Halo 3 (Bungie) | Behaviour tree / DAG for individuals. Halo 3 adds an "Objectives" system: a tree of prioritized tasks with activation conditions and capacities; squads are "poured in" and fill the highest-priority open tasks | Manage complexity; designer control of large battles that can be fought in any order | [source: Isla GDC 2005 article; Isla GDC 2008 slides] |
| Killzone 2/3 multiplayer bots (Guerrilla) | HTN planner (SHOP-like) at individual, squad and (in KZ3, experimentally) commander level | "Good control over what plans can be generated and a clear definition of priorities between plans" | [source: KZ3, GAP1 ch.29] |
| Transformers: Fall of Cybertron (High Moon) | HTN; replaced GOAP used in War for Cybertron | HTN planner "considerably faster than our GOAP system"; forward decomposition with no cost sorting | [source: Humphreys, GAP1 ch.12] |
| Guild Wars 2: Heart of Thorns (ArenaNet) | Infinite Axis Utility System: decisions scored by multiplied considerations through response curves | Robust, modular, designer-authored behaviour packages | [source: Mark & Lewis GDC 2015; Lewis GAP3 ch.13] |
| Paragon bots (Epic, UE4) | Heavily parameterized behaviour trees + blackboard + EQS spatial queries | Bots were added late, so the team reused UE4 systems and parameterized everything through the blackboard | [source: Zieliński, GAP3 ch.32] |
| Quake III Arena bot (id, 1999) | Layered: AAS navigation, goal selection by fuzzy weights, per-bot "characteristics" file, chat | Personality via data files | [source: van Waveren thesis 2001; ioq3 `chars.h`] |

### Trade-offs relevant to us

- **GOAP**: its strength is that goals and actions are decoupled, so new character types satisfy old goals [source: Orkin]. Its weaknesses: it uses backward search, so the whole search must finish before the first step is known [source: Humphreys GAP1 ch.12], and later studios found HTN faster [source: Humphreys]. Designers also get less direct control over which plan wins [inference, consistent with the KZ3 rationale].
- **HTN**: designers control branch order, so priorities are explicit. It is fast because it does not sort [source: KZ3; Humphreys]. Killzone used re-planning at a fixed rate plus "continue" branches to stop twitchiness and avoid re-checking. KZ2 numbers: 360 methods, 1,048 branches, 147 continue branches; re-evaluated at 5 Hz; about 500 plans/s, 8,000 decompositions/s and 24,000 branch evaluations/s for 14 bots [source: KZ2 slides]. The weakness for us is that a third party cannot insert a behaviour without editing the domain's branch order [inference]. Ordering is global, so an addon has to know where to insert.
- **Behaviour trees**: well understood and debuggable, with the same third-party insertion problem as HTN. Priority comes from tree position, so addons must patch the tree [inference].
- **Utility (IAUS / dual-utility)**: each behaviour scores itself. Adding a behaviour means adding one more scored option, with no global edit [inference, consistent with the IAUS claim that "core behaviors written by any designer can be added to any character" — gameai.com/iaus.php]. The weaknesses are oscillation between near-equal scores (fix with a commitment bonus, weights, cooldowns) and tuning effort; Lewis recommends a slider tool for visualising curves [source: Lewis GAP3 ch.13].
- **Hybrid is the norm**: Killzone pairs a generic planner with specialised solvers for position picking, squad paths and low-level "skills". L4D runs concurrent behaviours (Main and Legs) [source: KZ3; L4D].

## 2. Valve's Counter-Strike bot (Booth) and L4D

Verified from ReGameDLL_CS (reimplementation of the shipped CS 1.6 bot) and the shipped CS2 `botprofile.db`:

- **Update rates**: `g_flBotCommandInterval = 1/30 s` (aim and upkeep) and `g_flBotFullThinkInterval = 1/10 s` (decisions and perception) [source: `game_shared/bot/bot.h`].
- **Reaction time**: a ring buffer of 20 threat snapshots is filled at 10 Hz, and the bot acts on the snapshot `ReactionTime` seconds old. Reaction time is therefore capped below 2 s [source: `cs_bot_vision.cpp UpdateReactionQueue`, `cs_bot.h MAX_ENEMY_QUEUE = 20`]. The snapshot also stores "is reloading", so bots react to *perceived-then* state.
- **Look model**: `UpdateLookAngles` is a spring-damper with max acceleration. Code constants are stiffness 200 / damping 25 normally and 300 / 30 when attacking, with maxAccel 3000. The shipped profile defaults are `LookAngleStiffnessNormal 100`, `DampingNormal 25`, `MaxAccelNormal 2000`, `StiffnessAttacking 150`, `DampingAttacking 30`, `MaxAccelAttacking 3000` [source: `cs_bot_vision.cpp`, CS2 `botprofile.db`]. The code comment notes the spring is not timestep invariant, so it must be ticked at a fixed rate.
- **Aim error ("focus")**: `SetAimOffset(accuracy)` works as follows [source: `cs_bot_weapon.cpp`]:
  - If the view rotated more than about 100 units, focus resets.
  - Focus time is `max(5·(1−accuracy), 2)` s, and focus can raise accuracy to at most 0.75.
  - The error radius is `range · (FOV/90) · 0.1 · (1−accuracy)` as a random 3-D offset, so it scales with range and the angular error is constant.
  - The offset goal is re-rolled every 0.25–1.0 s, and the offset is lerped toward it at 0.1 per tick, which gives a smooth wander rather than jitter.
- **Target point selection**: skill > 0.5 leads the target by `relVel · dt · 3`. Bots with skill < 0.8, or using AWP / shotgun / MG / high recoil, aim at the chest instead of the head. Partially visible enemies are aimed at the visible part (head, chest, left side, right side, feet) [source: `cs_bot_update.cpp Upkeep`].
- **Navigation data**: an auto-generated nav mesh. Each area holds hiding spots flagged `IN_COVER`, `GOOD_SNIPER_SPOT` and `IDEAL_SNIPER_SPOT`, plus approach areas and encounter spots [source: `nav_area.cpp`; Valve Developer Wiki "NAV (file format)"]. The bot recomputes "approach points" when it has moved more than 50 units, and periodically glances at a random hiding spot it has not checked recently [source: `cs_bot_update.cpp`, `cs_bot_vision.cpp`].
- **Danger map**: each nav area holds per-team danger. A death adds danger to nearby areas, and danger decays linearly ("one kill == 1.0, which we will forget about in two minutes") [source: `nav_area.cpp DecayDanger`]. The path cost adds `(1 − 0.95·aggression) · 100 · danger`, so aggressive bots take risky routes [source: `cs_bot.h PathCost`].
- **Hearing**: `cs_bot_listen.cpp` makes bots turn toward noises without an FOV check. Smoke does not block hearing [source].
- **Difficulty profiles** (shipped CS2 `botprofile.db`, Booth header) [source]:

| Template | Skill | Aggression | ReactionTime (s) | AttackDelay (s) | AimFocusInitial (deg) | AimFocusDecay | AimFocusOffsetScale | AimfocusInterval (s) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Easy | 5 | 10 | 0.60 | 0.70 | 20 | 0.7 | 0.60 | 0.70 |
| Fair | 25 | 15 | 0.60 | 0.90 | 17 | 0.6 | 0.50 | 0.70 |
| Normal | 50 | 30 | 0.60 | 0.80 | 12 | 0.5 | 0.35 | 0.60 |
| Tough | 60 | 45 | 0.50 | 0.70 | 10 | 0.4 | 0.25 | 0.50 |
| Hard | 75 | 60 | 0.40 | 0 | 10 | 0.4 | 0.20 | 0.40 |
| VeryHard | 80 | 70 | 0.30 | 0 | 5 | 0.3 | 0.17 | 0.30 |
| Expert | 90 | 80 | 0.20 | 0 | 2 | 0.2 | 0.15 | 0.20 |
| Elite | 100 | 95 | 0.05 | 0 | 0.5 | 0.1 | 0.05 | 0.05 |

Header comments: `AimFocusDecay` is "how much focus shrinks per second (.25 = 25% of size after 1 sec)". `AimFocusOffsetScale` "controls accuracy when tracking to target (0 == perfect)". `AimfocusInterval` is "how often focus is adjusted (smaller intervals means better movement tracking)". Note that Elite's 0.05 s reaction is below the human floor, so Elite deliberately behaves superhumanly [inference via Rabin].

Community "better bots" edits of this file exist (for example gist so0k/7505931 with ReactionTime 0.01). They are not Valve's values; do not cite them as such.

**Left 4 Dead (Booth, AIIDE 2009)** [source]:

- SurvivorBots must be "fair": imperfect knowledge through simulated senses, simulated aiming, reaction times, and reliable, predictable decision making.
- The game "cheats" only to prevent bad experiences: bots deal no friendly fire, never use Molotovs, and are teleported back to the team when no human is looking.
- Bots prioritise human teammates over other bots.
- Reactive path following: steer toward a look-ahead point plus local avoidance, instead of an optimised path. Re-pathing is cheap and the motion is fluid; following the path directly "looks robotic".
- The nav mesh doubles as a spatial-reasoning database ("has area A been seen by actor B?", "a spot near the Survivors not visible to any of them"). The AI Director paces intensity.

## 3. Other shooters' bots

- **Killzone 2 (2009)**. Source: slides by Straatman, Verweij and Champandard; Verweij MSc thesis 2007.
  - Three layers: strategy (per faction) → squad → individual. Strategy decides *what* (objectives), and squads and individuals decide *how*.
  - Objectives: `DefendMarker`, `AdvanceWaypoint`, `AttackEntity`, `EscortEntity`. Sub-objectives scale with the number of bots.
  - Assignment: compute the ideal distribution → create or remove squads → pick objectives → unassign excess bots → assign free bots to the nearest squad.
  - Strategic graph: waypoints are clustered into areas at export. An influence map per faction is built from bots, turrets and deaths, then smoothed over space and time.
  - Each squad runs an incremental single-source pathfinder with influence-based costs ("safe areas nearly free, risky areas exponentially worse"). Squad corridors penalise other squads' paths so squads spread.
  - Speaker notes mention removing an "ammo cheat".
- **Killzone 3 (GAP1 ch.29)** [source]:
  - Bots use the same virtual controller as players. "Bots have the same weapons and abilities as human players."
  - Perception: sensors with view cones and maximum distance, feeding a per-bot world database that "may be believably wrong". Daemons add facts such as weapon and health state.
  - Position picking: generate nearby waypoints, then score them on cover from known threats, distance to threats or friends, line of fire and travel distance, with weights per behaviour. Per-waypoint directional cover data is precomputed offline.
  - Threat prediction: compute the most likely hiding waypoints of a lost enemy, then search or scan them.
  - Squads restrict members to the areas on the strategic path (a corridor). This keeps squad intent and also shrinks the individual search space.
  - Commander: mode-specific classes add and remove objectives, each with a weight and an optimal bot count. Six-step assignment; bots pick the spawn with the best travel cost to their squad.
  - Hand-placed annotations: regroup, sniping, defend and VIP hiding locations.
  - Lesson: squad assignment was harder with more objectives and fewer bots. The team moved the commander to HTN and used reinforcement learning to tune branch order from bot-vs-bot games.
- **Quake III Arena** (van Waveren thesis 2001; ioq3 source) [source]:
  - Each bot is a characteristics file with `REACTIONTIME` [0..5 s], `AIM_ACCURACY`, `AIM_SKILL`, `VIEW_FACTOR`, `VIEW_MAXCHANGE` (deg/s), `ATTACK_SKILL`, `CROUCHER`, `JUMPER`, `CAMPER`, `AGGRESSION`, `SELFPRESERVATION`, `VENGEFULNESS`, `ALERTNESS`, `FIRETHROTTLE`, plus chat tendencies.
  - Skill thresholds unlock behaviours. For example: `ATTACK_SKILL ≥ 0.4` circle-strafes and `> 0.7` changes strafe direction randomly; `AIM_SKILL 0.4–0.8` leads targets linearly and `> 0.8` exactly; `> 0.5` takes prediction shots at unseen enemies; `> 0.6` aims splash at nearby geometry.
  - A bot will not fire until the enemy has been in sight for `reactiontime` (`ai_dmq3.c`).
- **Unreal Tournament 2004** [source: BeyondUnreal wiki]:
  - Skill tiers: Novice → Average → Experienced → Skilled → Adept → Masterful → Inhuman → Godlike.
  - Per-bot `StrafingAbility` and `CombatStyle` are in [−1, 1] (−1 = snipe at range, +1 = charge).
  - The Liandri wiki describes Novice as roughly 60% move speed, about 30° aim error and less than 180°/s turn. That wiki itself says the details are "sketchy" [unverified].
- **Call of Duty**:
  - Treyarch's "Combat Training" (Black Ops, 2010) began as an internal development tool. Black Ops II tied it to progression up to level 10, aimed at the "30 to 40 percent" of players who never try multiplayer [source: Shacknews / GameRevolution interviews].
  - No public technical talk on Call of Duty multiplayer bot AI was found [gap].
- **Battlefield**:
  - BF2042 bots fill servers. DICE claimed they would be "really hard" to tell apart from humans; bots cannot use specialist traits [source: MP1st / Pocket-lint].
  - No technical talk was found [gap].
  - EA SEED trained Battlefield 1 agents with imitation learning followed by RL. It was a research and QA project, not shipped bots [source: ea.com/news/teaching-ai-agents-battlefield-1].
- **Titanfall**: grunts exist so pilots get a quick time-to-kill feedback loop [source: Xbox Wire 2014]. No public grunt AI talk was found [gap].
- **Rainbow Six Siege, Valorant**: no public bot-AI technical material was found in this session [gap].
- **CS2**: still uses Booth's `botprofile.db` lineage [source: SteamTracking mirror].
- **Research: MLMove** (Durst et al., SCA 2024). A transformer trained on 123 h of pro CS:GO movement, limited to Retakes on de_dust2. Expert raters judged its movement more human-like than the shipped bot and a rule-based bot, and its position distributions were closer to pros [source: arXiv 2408.13934]. Not feasible for us at runtime [inference], but its evaluation method is reusable (see §7).

## 4. Tactical reasoning

- **Position selection: Crytek TPS (GAP1 ch.26)** [source]:
  - Queries are written in a small DSL. "Options" are tried in order (fallbacks), and each has generation, conditions (filters) and weights.
  - Evaluation order: cheap filters → weights → expensive filters, evaluated best-first until one passes. Raycasts are "the dominant cost", so cap them per frame and run them asynchronously.
  - Focus on hiding from the one opponent you are engaged with rather than from all of them.
  - Verify that the spot lets you shoot the target (cover *with* a firing line).
  - Query failure is a signal: flag it on the blackboard to change behaviour or abort a squad action.
- **Killzone position picking**: the same pattern on waypoints with precomputed directional cover [source: KZ3; Straatman et al. "Dynamic tactical position evaluation", AIGPW3].
- **For Source navmesh** [inference]:
  - Hiding spots (`IN_COVER`, sniper flags) are the cheap candidate set. Area centres and connection midpoints are the open-ground candidates.
  - "Cover from threat X" can be approximated at first with a trace from the threat's eye to the spot at stand and crouch height, run last and capped per tick.
- **Influence and danger maps**:
  - CS: per-area per-team danger from deaths, linear decay over 120 s [source].
  - KZ: per-area influence from unit counts, turrets and deaths, spatially smoothed then blended over time [source].
  - Paragon: 5×5 m grid cells; each agent's influence is applied in a radius instead of propagated, as a cheap approximation [source: GAP3 ch.32].
  - Dave Mark's modular influence maps combine layers (proximity, threat, interest) per query [source: GAP2 ch.30, title only read].
- **Squad and team coordination**:
  - Commander → squad → bot with orders and reports [KZ].
  - Halo 3 task tree with priorities and capacities [Isla 2008].
  - Flanking emerges from cost-modified paths: influence costs plus a penalty on areas other squads use [KZ3].
  - Crysis-style squad-level position queries avoid two bots wanting the same spot, but they couple behaviours tightly [source: GAP1 ch.26].
  - Prefer individual queries plus a shared "reserved spot" table [inference].
- **Objective play**:
  - Encode objectives as data: type, location, weight, desired count. Mode code only adds and removes objectives; for example, in Capture and Hold, when ahead with 2 of 3 points, generate only defend objectives [source: KZ3].
  - For S&D later: carrier escort and attack objectives map 1:1 [source: KZ3 Search and Retrieve].

## 5. Perception and knowledge

- **Senses**:
  - View cone plus max distance plus LOS [KZ3; CS `IsVisible(testFOV)`].
  - Partial visibility: CS tests head, chest, left side, right side and feet and aims at the visible part [source].
  - Hearing has no FOV gate [CS listen].
  - Stimulus intensity matters: weaker or farther stimuli slow reaction [source: Rabin citing Luce 86].
- **Memory**:
  - A per-bot world database that can be wrong is a feature [KZ3].
  - CS stores the last enemy position and aims there after losing LOS [source: `m_lastEnemyPosition`].
  - Threat prediction to likely hiding spots [KZ3].
  - Danger memory decays over 2 min [CS].
- **Knowledge sharing**:
  - KZ bots "send information on observed threats" up to the squad, and medics `!broadcast` to nearby bots within a radius [source].
  - CS uses radio events [source: `cs_bot_radio.cpp` exists; content not reviewed].
  - Fair sharing [inference]: deliver shared contacts with a delay (0.5–2 s), as a position with uncertainty rather than a live entity, and only within a radius or squad. The receiving bot must still acquire the target through its own sight and reaction queue before firing.
- **Avoiding omniscience**: L4D lists "imperfect knowledge – simulated senses" as a fairness requirement [source]. KZ3 notes cloak and disguise must fool perception [source].

## 6. Aiming and difficulty

- **Reaction**: about 0.19–0.22 s for a simple visual reaction and about 0.38 s for go/no-go (friend vs foe). Add time for weak stimuli, aim travel and lapses [source: Rabin GAP2 ch.5]. In our mixed-team FFA/TDM every contact needs friend-or-foe recognition, so about 0.35–0.45 s is the realistic baseline for "Normal" [inference].
- **Motor model**:
  - CS uses a second-order spring-damper with an acceleration clamp [source]. With the damping ratio below 1 it overshoots naturally; the CS constants (k = 300, c = 30 → ζ ≈ 30 / (2·√300) ≈ 0.87) are slightly under-damped [inference from the code].
  - The literature on human pointing: FPS rotation-aiming conforms to Fitts' law (Looser et al., cited in Carleton "Game devices" paper; Boudaoud et al. 2023). Expert flicks fit sigmoids, and harder targets produce more corrective sub-movements and overshoot [source: Donovan et al. 2022 Frontiers; Roberts et al. 2016].
  - For us [inference]: a flick phase with a duration from Fitts' law (`T = a + b·log2(1 + D/W)`, where D is the angle to the target and W is its angular size) and a sigmoid or minimum-jerk profile, overshooting 5–15% on large flicks. Then a correction sub-movement. Then a tracking phase using the spring-damper plus a focus-decay error.
- **Error that shrinks with tracking time**: the CS focus model (§2) is the shipped precedent [source].
- **Target leading and hit-zone choice**: gate by skill. CS: lead if skill > 0.5, headshots if skill ≥ 0.8 and the weapon is accurate [source]. Q3 uses graded leading thresholds [source].
- **Recoil**: CS picks the chest for high-recoil weapons. The profile comment says `LookAngleDampingAttacking` affects "how much a bot will compensate for recoil" (comment from a community-edited copy) [unverified]. For us [inference]: the bot sees its own view punch the way a player does, and the aim controller pulls down against it with a per-skill gain (0.3–0.9) and delay, with burst length limited by skill (Q3 `FIRETHROTTLE` is the precedent).
- **Difficulty knobs that do not feel like cheating**:
  - Reaction, focus, turn speed, leading and headshot permission (all "human-like" axes) [CS / Q3].
  - Decision quality: dual-utility "pick among the near-best" plus Wetzel's "pick second best if within 20%" [source].
  - Aggression changes route risk and engagement eagerness, not stats [CS].
  - Avoid damage and health multipliers; KZ2 removed an ammo cheat [source]. Players notice AI doing *better* than normal [source: Wetzel GAP3 ch.4].
- **Dynamic difficulty / rubber-banding**:
  - Wetzel's "hustling" AIs only nerf when far ahead, and players did not notice [source].
  - The GAP3 ch.33 token system (only token holders may hit, with the delay modulated by distance, stance, cover, facing and velocity) is a PvE single-player technique [source]. For real-bullet PvP bots, the equivalent is a per-target "pressure budget": when several bots engage one human on Easy, only one at a time gets tight focus and the others keep a widened spread [inference].
  - Rubber-banding needs explicit opt-in for competitive modes, and stats should never be secretly buffed [inference].

## 7. Believability

- **Movement**:
  - Reactive path following with look-ahead instead of rigid waypoint hugging [L4D].
  - Q3 movement traits (crouch, jump and walk tendencies; circle-strafe at attack skill ≥ 0.4; random strafe changes > 0.7) [source].
  - UT2004 `StrafingAbility` and `CombatStyle` [source].
  - CS bots look at approach points and unchecked hiding spots while moving, which makes them look attentive [source].
  - Avoid looking at spots closer than 100 units because it causes "erratic view rotation" [source: CS code].
- **Human touches**:
  - Target persistence. Switching targets too often was judged "computery" [source: Wetzel GAP3 ch.4].
  - Revenge [source: same]. UT^2 "held grudges" [source: UT Austin 2012 news].
  - Communication: F.E.A.R. uses dialogue to make coordination legible [source: Orkin; "Combat Dialogue in FEAR", GAP2 ch.2, title only].
  - Q3 chat tendencies [source].
  - CS uses chatter and radio files [source: `cs_bot_chatter.cpp` exists].
- **Debuggability**: L4D transition "reason" strings, the KZ `!log_color` task, and Paragon's Visual Log [source]. We need an on-screen bot debug overlay from day 1 [inference].
- **Turing tests: BotPrize (UT2004)**:
  - 2012 winners: MirrorBot (52.2% judged human) and UT^2 (51.9%), against human players at 41.4% [source: UT Austin / ScienceDaily].
  - UT^2 replays recorded human navigation traces (indexed by nav point in a KD-tree) whenever its own navigation fails or gets stuck, and uses neuroevolved combat [source: Schrum, Karpov & Miikkulainen CIG 2011]. MirrorBot mirrored opponents' behaviour [source: 2012 coverage].
  - Takeaway [inference]: what gives a bot away is navigation failure (getting stuck, odd paths) and inhuman reactions more than tactics. Invest early in robust unstuck recovery.
- **Evaluation method** [inference, adapted from MLMove and BotPrize]:
  - Record per-match heatmaps (death and kill locations, time alive) for humans and for bots, and compare the distributions.
  - Run blind "which of these is a bot" sessions with spectator replays.

## 8. Performance practices

- **Tick split**: CS uses decision and perception at 10 Hz and aim at 30 Hz [source]. KZ2 re-plans at 5 Hz [source].
- **Pathfinding** (Rabin & Sturtevant, GAP1 ch.17) [source]:
  - Preallocate node memory.
  - Use a weighted (overestimating) heuristic for large speedups with small loss of optimality.
  - An unordered open list beats a heap when the open list stays under about 20–30 nodes.
  - Do not backtrack to the parent.
  - Do not time-slice many searches at once (memory and cache thrash). Process them one at a time like a supermarket queue, with an express lane for short searches.
  - Caching paths is listed as a bad idea.
- **Squad-level search**: KZ squads run incremental, anytime single-source pathfinders on the coarse strategic graph. Individual searches are restricted to corridor areas, which cuts cost [source].
- **Repathing**: reactive path following makes repaths cheap and frequent repathing acceptable [L4D].
- **Spatial queries**: cap raycasts per frame, run them asynchronously, and put them last in the evaluation [source: GAP1 ch.26].
- **Influence maps**: coarse cells with radius stamping instead of propagation [Paragon]. Update the per-area danger lazily on read (CS decays on `GetDanger`) [source].
- **Our implications** [inference]:
  - LuaJIT on a listen server has no threads, so "async" means queued work spread across ticks.
  - Stagger the 10 Hz bot thinks over ticks: with 24 bots at 66 tick, about 4 bot-thinks per tick.
  - Keep a global A* node-expansion budget per tick and a global trace budget per tick.

## Mapping to our layers

| Our layer | Recommended technique | Source | Notes for Lua / listen server |
| --- | --- | --- | --- |
| Manager | Bot profiles as data (template inheritance, like `botprofile.db` / Q3 characteristics) | CS, Q3 | Profiles are plain Lua tables; templates merged with `table.Inherit`-style copy [inference] |
| Input writer | Virtual controller: the bot writes only CUserCmd (view angles, move, buttons) | KZ3 | Enforces fairness; the same code path for recoil and spread as players [inference] |
| Scheduler | 30 Hz upkeep (aim, steering) and 10 Hz think, staggered round-robin; per-tick budgets for A* expansions and traces | CS `bot.h`; GAP1 ch.17, ch.26 | Use `SysTime()` budget checks; spread bots across ticks [inference] |
| Time-sliced A* | One active search at a time (FIFO + express lane), weighted heuristic, preallocated arrays, danger/influence cost terms | GAP1 ch.17; CS `PathCost`; KZ | Navmesh areas as nodes; costs `dist + aggressionFactor·danger + squadPenalty` [inference] |
| Path following | Reactive look-ahead + local avoidance; unstuck recovery (jump, crouch, back off, repath) | L4D; BotPrize UT^2 | Most visible failure mode; build early [inference] |
| Perception | FOV + range + multi-point LOS (head, chest, sides, feet); hearing events without FOV; reaction ring buffer | CS vision/listen; KZ3; Rabin | Hook gunfire/footstep events into a per-bot stimulus queue [inference] |
| Memory | Per-bot contact list with last-seen position, time, confidence; decays; predicted hiding spots | KZ3; CS | Search candidate hiding spots near the last-seen area [inference] |
| Aim controller | Flick (Fitts duration, overshoot) → spring-damper tracking with accel clamp → focus-decay error; lead/headshot gated by skill; recoil pull-down gain | CS code + profile; Fitts literature | Integrate at fixed dt (spring is not timestep invariant per CS comment) [source + inference] |
| Brain | Dual-utility selection over registered behaviours (rank + weight), commitment bonus, cooldowns; behaviours implemented as L4D-style Actions with OnStart/Update/OnEnd/OnSuspend/OnResume and reason strings | Dill GAP2 ch.3; Lewis GAP3 ch.13; L4D | See next section |
| Tactical queries | TPS-style query: generate (hiding spots, area points) → cheap filters → score → raycast filters best-first | GAP1 ch.26; KZ3 | Queries as Lua tables, so addons can register criteria [inference] |
| Team commander | Objective list (type, pos, weight, desired count) per mode + periodic assignment pass; Halo-3-style priority/capacity tree; area influence map; squad path penalties | KZ2/KZ3; Halo 3 | Re-run assignment every 1–2 s or on events [inference] |

## Recommended brain architecture for us

**Recommendation**: dual-utility selection over a registry of behaviours, where each behaviour is an L4D/NextBot-style Action object. The per-team commander uses Killzone-style objectives with Halo-3-style priority and capacity.

Justification:

1. **Third-party extensibility.** With utility, adding a behaviour does not require editing a global order. An addon registers `{name, rank(bot, ctx), weight(bot, ctx), action}` [inference; IAUS modularity claim, gameai.com]. HTN and BT require inserting into a designer-ordered tree, which breaks when two addons both want "just above combat" [inference].
2. **Priority control is kept.** Dual-utility "rank" gives HTN-like hard priorities (for example self-preservation > objective > roam), while "weight" handles nuance and variety. Low-quality options are screened out ("eliminate options much worse than the best") [source: Dill GAP2 ch.3].
3. **Difficulty through decision quality.** Lower skill widens the screening threshold, so the bot picks among more near-best options [inference, extends Dill + Wetzel "second best within 20%"].
4. **Stability.** Add a commitment bonus to the current behaviour plus minimum run times and cooldowns [source: Lewis GAP3 ch.13]. Re-evaluate at 5–10 Hz, like the KZ2 plan monitor [source].
5. **Execution.** Actions have `OnStart/Update/OnEnd/OnSuspend/OnResume`. Transitions are returned values (`Continue/ChangeTo/SuspendFor/Done(reason)`), which keeps addons from forcing each other's state, and reason strings feed the debug overlay [source: L4D].
6. **Concurrency.** Run separate "Main" (target, attack, behaviour) and "Legs" (movement/stance) channels, as L4D SurvivorBots do [source]. In practice that means aim, movement and decision are separate controllers writing different CUserCmd fields [inference].
7. **Hierarchy.** The commander issues orders (attack/defend area, escort, regroup) that become an input to utility scoring: order compliance is a consideration. This mirrors KZ3, where bots "can decide to temporarily ignore orders in order to survive" [source].

Sketch of the registration contract (illustrative only):

```lua
-- illustrative API shape, not an implementation
BotBrain.RegisterBehaviour("capture_flag", {
    rank   = function(bot, ctx) return ctx.order and ctx.order.type == "capture" and 20 or 10 end,
    weight = function(bot, ctx) return Curve.Logistic(ctx.flagDistNorm) * (1 - ctx.threatLevel) end,
    action = CaptureFlagAction, -- OnStart/Update/OnEnd/OnSuspend/OnResume
    minRunTime = 1.5,
    cooldown = 0,
})
```

## Difficulty model proposal

All values are per-bot profile fields, with templates for Easy, Normal, Hard and Expert. Ranges come from sources where noted; the defaults are my proposal [inference].

| Parameter | Meaning | Easy | Normal | Hard | Expert | Basis |
| --- | --- | --- | --- | --- | --- | --- |
| `reaction_mean` (s) | Delay from first visibility to "recognised" (reaction queue) | 0.60 | 0.45 | 0.32 | 0.22 | CS 0.6 → 0.2; Rabin 0.2 simple / 0.38 go-no-go |
| `reaction_jitter` | Log-normal sigma; plus a lapse chance (p ≈ 0.05, +0.3–0.6 s) | 0.35 | 0.30 | 0.25 | 0.20 | Rabin "attentional lapse" [inference for numbers] |
| `reaction_floor` (s) | Hard minimum | 0.25 | 0.20 | 0.18 | 0.15 | Human simple RT ≈ 0.19–0.22 s [Rabin]; CS Elite 0.05 deliberately excluded |
| `attack_delay` (s) | Extra hesitation before the first shot | 0.7 | 0.4 | 0.1 | 0 | CS 0.9 → 0 |
| `aim_focus_initial` (deg) | Initial angular error on acquisition | 20 | 12 | 6 | 2 | CS Easy 20 / Normal 12 / VeryHard 5 / Expert 2 |
| `aim_focus_decay` | Fraction of error left after 1 s of steady aim | 0.7 | 0.5 | 0.35 | 0.2 | CS 0.7 → 0.2 |
| `aim_focus_reset_deg` | View rotation that resets focus | 10 | 10 | 15 | 20 | CS resets on "view moving" [inference for value] |
| `aim_offset_scale` | Tracking error while the target moves | 0.6 | 0.35 | 0.2 | 0.15 | CS 0.6 → 0.15 |
| `aim_reroll_interval` (s) | How often the error offset re-targets | 0.7 | 0.6 | 0.4 | 0.2 | CS `AimfocusInterval`; code re-rolls every 0.25–1.0 s |
| `look_stiffness` / `look_damping` | Spring-damper constants (attacking) | 100 / 25 | 150 / 30 | 200 / 30 | 300 / 30 | CS profile 100–150; code 200–300 |
| `look_max_accel` (deg/s²) | Angular acceleration clamp | 1500 | 2000 | 3000 | 3000 | CS 2000 / 3000 |
| `turn_max_speed` (deg/s) | Max view speed | 180 | 360 | 540 | 720 | Q3 `VIEW_MAXCHANGE` [1, 360]; UT Novice < 180 [unverified] |
| `flick_overshoot` | Overshoot fraction on large flicks | 0.15 | 0.10 | 0.07 | 0.05 | Corrective sub-movements literature [inference for values] |
| `lead_target` | Velocity leading | off | partial (0.5) | full | full | CS skill > 0.5; Q3 0.4–0.8 linear, > 0.8 exact |
| `headshot_allowed` | Aim at head when visible | no | no | rifles only | yes | CS skill ≥ 0.8 + weapon class |
| `recoil_comp_gain` | Pull-down against view punch | 0.3 | 0.5 | 0.75 | 0.9 | [inference]; Q3 `FIRETHROTTLE` for burst control |
| `burst_len` (shots) | Max auto burst before re-settle | 3–5 | 5–8 | 8–12 | full | [inference] |
| `aggression` | Danger weight in paths; push vs hold | 0.1 | 0.3 | 0.6 | 0.8 | CS 10 → 80 (danger factor `1 − 0.95·aggr`) |
| `danger_memory` (s) | Decay horizon of per-area danger | 120 | 120 | 120 | 120 | CS "forget in two minutes" |
| `contact_memory` (s) | How long a lost contact is pursued or predicted | 3 | 6 | 10 | 15 | [inference]; KZ3 threat prediction |
| `share_delay` (s) | Delay before a teammate's sighting reaches this bot | 2.0 | 1.5 | 1.0 | 0.5 | [inference]; KZ broadcast / CS radio precedent |
| `share_radius` | Who receives shared contacts | squad | squad | team in 30 m | team | [inference] |
| `decision_screen` | Keep options with weight ≥ X·best, then weighted random | 0.5 | 0.7 | 0.8 | 0.9 | Dill step 3; Wetzel "second best within 20%" |
| `commitment_bonus` | Score multiplier for the current behaviour | 1.1 | 1.15 | 1.2 | 1.25 | Lewis GAP3 ch.13 [values inference] |
| `teamwork` | Probability of following commander orders over own impulse | 0.5 | 0.75 | 0.85 | 0.95 | CS `Teamwork` 25–100 (community copy), Default 75 |
| `target_persistence` (s) | Minimum time before voluntary target switch | 0.5 | 1.0 | 1.5 | 1.5 | Wetzel: frequent switching looks "computery" |

Rules:

- Never change damage, health, ammo or spread for bots. KZ2 removed an ammo cheat [source].
- Optional rubber-banding only nerfs bots, never buffs them. Players notice AI doing better than normal [source: Wetzel].
- Use the Easy-mode "pressure budget": at most N bots with tight focus on one human at once [inference from GAP3 ch.33].

## Reading list (ranked)

1. Straatman, Verweij, Champandard, Morcus, Kleve — "Hierarchical AI for Multiplayer Bots in Killzone 3", Game AI Pro 1 ch.29 — <http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter29_Hierarchical_AI_for_Multiplayer_Bots_in_Killzone_3.pdf>
2. ReGameDLL_CS bot source (reimplementation of Booth's CS bot: vision, aim, nav, states) — <https://github.com/rehlds/ReGameDLL_CS/tree/master/regamedll/dlls/bot> — plus shipped `botprofile.db` — <https://github.com/SteamTracking/GameTracking-CS2/blob/master/game/csgo/pak01_dir/botprofile.db>
3. Booth — "The AI Systems of Left 4 Dead", AIIDE 2009 — <https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf>
4. Straatman, Verweij, Champandard — "Killzone 2 Multiplayer Bots", Paris Game AI Conference 2009 — <https://www.slideshare.net/guerrillagames/killzone-2-multiplayer-bots>; Verweij thesis — <https://www.guerrilla-games.com/media/News/Files/VUA07_Verweij_Hierarchically-Layered-MP-Bot_System.pdf>
5. Jack — "Tactical Position Selection: An Architecture and Query Language", Game AI Pro 1 ch.26 — <http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter26_Tactical_Position_Selection.pdf>
6. Dill — "Dual-Utility Reasoning", Game AI Pro 2 ch.3 — <http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter03_Dual-Utility_Reasoning.pdf>; Lewis — "Choosing Effective Utility-Based Considerations", Game AI Pro 3 ch.13 — <http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter13_Choosing_Effective_Utility-Based_Considerations.pdf>
7. Rabin — "Agent Reaction Time: How Fast Should an AI React?", Game AI Pro 2 ch.5 — <http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter05_Agent_Reaction_Time_How_Fast_Should_An_AI_React.pdf>
8. Wetzel & Anderson — "What You See Is Not What You Get: Player Perception of AI Opponents", Game AI Pro 3 ch.4 — <http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter04_Player_Perception_of_AI_Opponents.pdf>
9. Rabin & Sturtevant — "Pathfinding Architecture Optimizations", Game AI Pro 1 ch.17 — <http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter17_Pathfinding_Architecture_Optimizations.pdf>
10. van Waveren — "The Quake III Arena Bot" (MSc thesis, 2001) — <https://fabiensanglard.net/fd_proxy/quake3/The-Quake-III-Arena-Bot.pdf>; and ioq3 `code/game/chars.h` — <https://github.com/ioquake/ioq3/blob/main/code/game/chars.h>

Secondary and also cited:

- Orkin, "Three States and a Plan" (GDC 2006) — <https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf>
- Humphreys, "Exploring HTN Planners through Example" (GAP1 ch.12) — <http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter12_Exploring_HTN_Planners_through_Example.pdf>
- Ocio Barriales, "Using Your Combat AI Accuracy to Balance Difficulty" (GAP3 ch.33) — <http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter33_Using_Your_Combat_AI_Accuracy_to_Balance_Difficulty.pdf>
- Zieliński, "Paragon Bots: A Bag of Tricks" (GAP3 ch.32) — <http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter32_Paragon_Bots_A_Bag_of_Tricks.pdf>
- Isla, "Handling Complexity in the Halo 2 AI" — <https://www.gamedeveloper.com/programming/gdc-2005-proceeding-handling-complexity-in-the-i-halo-2-i-ai>
- Isla, Halo 3 Objectives slides — <https://web.cs.wpi.edu/~rich/courses/imgd4000-d09/lectures/halo3.pdf>
- Mark & Lewis, "Building a Better Centaur" (GDC 2015) — <https://www.gdcvault.com/play/1021848/>
- IAUS — <https://gameai.com/iaus.php>
- Booth, "The Making of the Official Counter-Strike Bot" (GDC 2004, Vault login) — <https://gdcvault.com/play/1013625/The-Making-of-the-Official>
- Valve Developer Wiki, NAV format — <https://developer.valvesoftware.com/wiki/NAV_(file_format)>
- BotPrize 2012 results — <https://news.utexas.edu/2012/09/26/artificially-intelligent-game-bots-pass-the-turing-test-on-turings-centenary/>
- UT^2 paper (CIG 2011) — <https://nn.cs.utexas.edu/downloads/papers/schrum.cig11competition.pdf>
- Durst et al., MLMove — <https://arxiv.org/abs/2408.13934>
- Donovan et al. 2022 (Aim Lab kinematics) — <https://www.frontiersin.org/journals/human-neuroscience/articles/10.3389/fnhum.2022.979293/full>
- UT2004 bot variables — <https://wiki.beyondunreal.com/UE2:Bot_internal_variables_(UT2004)>
- Liandri Archives "Bot" — <https://liandri.beyondunreal.com/Bot>
- Treyarch Combat Training — <https://shacknews.com/article/75949/how-black-ops-2-makes-online-multiplayer-less-intimidating>
- EA SEED BF1 agents — <https://www.ea.com/news/teaching-ai-agents-battlefield-1>
- Titanfall AI (Xbox Wire) — <https://news.xbox.com/en-us/2014/02/18/games-titanfall-ai/>

## Gaps and caveats

- Booth's GDC 2004 slides were not readable. CS details come from ReGameDLL (reimplementation, GPL) and the shipped data file, not from Valve's own CS:S/CS:GO source.
- No public technical material was found on CoD, Battlefield 2042, Titanfall grunt, R6 Siege or Valorant bots.
- Dave Mark's IAUS formula details (compensation factor for multiplied considerations) were not verified in this session. Check the GDC 2015 Vault video before implementing.
- Fitts' law and overshoot numbers for bots are design proposals derived from human-pointing literature, not from shipped games.
