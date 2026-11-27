# 32 — Weekly challenges: research and event inventory

Status: research (2026-11-21). Research explains *why*; it is not a decision. The plan is
`../changes/in-progress/weekly-challenges.md`. Where this note and `../design/` disagree, `design/` wins.

## Question

How do Call of Duty titles structure weekly, daily and camo challenges, how are such systems modelled in general
(event → filter → counter → reward), and which events does Private War already emit that a challenge tracker can
consume? What is missing to support the CoD-style objective types the user listed (headshots, kills in TDM or a
playlist, kills with a weapon, non-kill objectives)?

## 1. Call of Duty challenge design

### 1.1 Structure per title

| Title | Weekly | Daily | Notes |
| --- | --- | --- | --- |
| Modern Warfare (2019) | A weekly list per season week, about 10 multiplayer and 10 Warzone challenges, each with a flat XP reward (2 500 / 5 000 / 10 000 XP by difficulty) | Yes (dailies) | Example week (Season 4, Week 1) below. Source: tracker.gg |
| Black Ops Cold War | Weekly challenges per season | 3 dailies per mode every 24 h; finished dailies give bonus XP; active challenges can be swapped with reserve ones, swapped ones keep progress and stay completable until season end | Source: Treyarch "Daily Challenges Have Arrived" |
| Modern Warfare III (2023) | Weekly challenge sets released weekly (Wednesday); a week's reward (for example a weapon blueprint) for completing a number of that week's challenges (for example "complete five challenges"); all weekly rewards of a season → a mastery camo; past weeks stay completable during the season, future weeks are locked | Yes | Sources: ONE Esports, Pro Game Guides, gfinity, Game8 |
| Black Ops 6 | Announced without weekly challenges (dailies and events instead) | Yes | Source: MP1st (COD POD); Sportskeeda argues for their return |

Common traits:

1. **A fixed set per period**, the same for every player, published by the server on a schedule (weekly reset at a fixed
   weekday and hour).
2. **Difficulty tiers by target size**, not by different mechanics: "Get 50 kills" vs "Get 250 kills" are the same
   objective with a bigger counter (MW3 Season 6 lists both "Get 40 Operator Kills" and "Get 250 Kills").
3. **A meta reward: complete N of M → item**; completing every meta reward of a season → a mastery item. This is the
   "complete N of M" bonus requested by the user.
4. **Flat per-challenge rewards** (XP) plus the meta item.
5. **Rerolls/swaps** exist in some titles (Cold War) to reduce frustration with unsuited challenges.
6. **Catch-up**: MW3 kept previous weeks completable until the season ends; MW2019 weeklies expired with the season.

### 1.2 Objective vocabulary seen in real challenges

Verbatim examples (sources in §5):

- MW2019 S4 W1 multiplayer: "Get 5 Headshots using an LMG", "Call in the Personal UAV Killstreak 5 times", "Get 5
  Longshot kills", "Get 5 Hipfire Kills", "Activate the Deployable Cover Field Upgrade 7 Times", "Get 7 Kills using the
  Thermite equipment", "Win 3 Matches while equipped with Minotaur as your Allegiance Operator", "Capture the objective
  15 times in Objective based modes", "Get 3 Longshot Kills within 90 seconds of each other 5 times", "Get 50 Kills
  using an Assault Rifle".
- MW3 S6: "Get 30 Operator Kills while crouching", "Get 15 Operator Kills with explosions", "Get 250 One-shot Kills",
  "Get 60 Kills with a weapon set to single fire mode", "Get three Operator Double Kills", "Get 25 Operator Kills
  shortly after sprinting", "Get 20 Operator Kills from behind", "Get 100 Critical Kills with an assault rifle", "Get 10
  Operator Point Blank or Melee Kills", "Get 30 Operator Assists", "Get 500 Hipfire Kills", "Get 20 Operator Kills after
  reloading", "Get 20 Kills with an LMG without reloading 10 times", "Get 10 Operator Sliding or Midair Kills", "Get 10
  Kills against Operators who are blinded or stunned", "Get 10 Operator Kingslayer or Revenge Kills", "Get 25 Operator
  Kills while moving", "Get 10 Operator Quickscope Kills", "Destroy five Killstreaks", "Get two Operator Kills with one
  magazine three times", "Get 10 Kills without being hit 20 times".

Decomposition into a small grammar:

| Element | Examples |
| --- | --- |
| Event | kill, headshot kill, assist, death, capture, plant, defuse, match win, match played, killstreak called in / earned / kill with, equipment use, medal (double kill, revenge, longshot), time played |
| Weapon filter | weapon class ("using an LMG", "Assault Rifle"), specific weapon, attachment/fire mode, akimbo, suppressed, melee, explosive, equipment item |
| Player state filter | crouching, sliding, midair, ADS vs hipfire, moving, after sprint, after reload, after weapon swap, with N perks |
| Victim filter | "Operator" kills = real players vs AI (Zombies/DMZ), blinded/stunned victim, from behind |
| Geometry | longshot (distance ≥ x), point blank |
| Context | mode or mode family ("in Objective based modes"), playlist, operator/loadout ("with Minotaur") |
| Scope/composition | cumulative over the week (default); "within 90 seconds of each other" (time window); "with one magazine" / "without reloading" (window by a reset event); "in a single match"; "without dying" (life) |
| Multiplier | "N times" over a sub-condition ("3 longshot kills within 90 s, 5 times"): a nested counter |

### 1.3 How these map to a model

Every listed challenge is **event type + predicate over event fields + counter + scope (+ optional reset events or a
time window) + target**. Composite "X within window, N times" challenges are a nested counter: an inner run counter
(reset by time or event) whose completion increments the outer counter. Multi-objective challenges ("A and B") are a
list of counters that all must reach target.

## 2. Generic quest/achievement architecture

Patterns found in public quest/achievement frameworks:

1. **Data-driven definitions separate from systems** (quests as data loaded from files; Bevy all-in-one quest system;
   SUQS data tables in Unreal; Heroic Labs Hiro achievements with `count`/`max_count`, `category` "once"/"daily"/"weekly",
   `reward`, preconditions and sub-achievements).
2. **Event-driven progress, no polling**: gameplay emits events, the quest system updates generic objectives; objectives
   subscribe to events only while their quest is active (the Unreal guide's performance note).
3. **Definition / instance / manager split**: a template is static, an instance holds per-player progress, a manager
   routes events.
4. **Explicit claim state** separate from completion (Hiro: claimed when `ClaimTimeSec > 0`), so a reward is never
   granted twice.
5. **Progress milestones notify the player** (Steam `IndicateAchievementProgress` "at significant points"), not on
   every increment.
6. **Merge rule for offline progress**: Steam keeps the larger progress when two machines disagree.

Architecture this note recommends (details in the change record):

```text
engine/modes  ->  score events (PW_ScoreEvent + context), PW_PlayerKilled, PW_MatchEnd, PW_RoundEnd, streak hooks,
                  PW.Challenges.Report(ev) from addons
                       |
                       v
               normalize -> PW.ChallengeEvent { type, player, value, mode, playlist, kill fields ... }
                       |
                       v
         index by type: byType[type] -> active objectives of the player's week set  (O(k), k <= ~10)
                       |
           compiled filter list (cheap field compares) -> optional custom Filter through PW.Call
                       |
             counter per (week, instance, objective) with scope run (cumulative | match | round | life)
                       |
             completion -> claim ledger (idempotency key) -> rewards (entitlement Grant, XP, currency)
                       |
             dirty set -> batched net to owner (<= 1 msg/s) and client storage via the progression delta
```

**Deterministic weekly instances** from a seed: the same technique as the store rotation
(`addons/privatewar/lua/privatewar/modules/economy/sh_rotation.lua`: a day number since 1970-01-01, Monday-based week
number `floor((day - 4) / 7)`, a salted seed, MINSTD generator, partial Fisher-Yates over sorted ids, so the result
does not depend on listing order). Templates may declare a parameter space (for example weapon category), and the
generator binds parameters deterministically, so one template yields many weekly variants.

**ISO week labels**: ISO 8601 weeks start on Monday; week 1 contains the year's first Thursday, so a year has 52 or
53 weeks and 1–3 January can belong to the previous ISO year (ISO week date, Wikipedia). Verified test vectors
(Python `date.isocalendar()`): 2026-11-21 → 2026-W47 (Monday-week index 2967); 2026-12-28, 2026-12-31 and
2027-01-03 → 2026-W53 (index 2973); 2027-01-04 → 2027-W01 (index 2974); 2020-12-31 and 2021-01-03 → 2020-W53;
2025-12-29 → 2026-W01; 2024-12-30 → 2025-W01. The Monday-week index is monotonic and needs no year logic; the ISO label
is only for display and storage keys.

## 3. Event inventory in the repository

Paths are relative to `addons/privatewar/lua/privatewar/` unless stated.

### 3.1 Score events (`score_events/`, `design/06-progression.md` d.3)

Kind `score_events`, `EVENT` table (`Name`, `Points`, optional `XP`, `Medal`, `Currency`). Awarded by
`PW.Score.Award(ply, id, opts)`; `modules/score/init.lua:60` resolves the value (`PW_ScoreValue`), adds the score,
sends `pw_score_popup` to humans, then fires `PW_ScoreEvent(ply, eventId, points, xp, weapon)` (`:77`) and
`PW_ScoreChanged` (`:78`). The notification fires even when the resolved points are 0 (Infection answers
`PW_ScoreValue` with 0). `PW.ScoreOpts` has only `weapon` (`types/score.lua:13-15`).

| Event id | Awarded by | Data that reaches `PW_ScoreEvent` |
| --- | --- | --- |
| `kill` | `modules/match_rules/init.lua:71-93` (`ScoreKill`), called from `PW_PlayerKilled` of `tdm`, `kc`, `round_base` (`snd`); `ffa`, `dom`, `hardpoint` inherit TDM | player, weapon entity (`PW.WeaponAmmo.DamageWeapon`, nil for streak or world damage) |
| `headshot` | same call, in addition to `kill` when `victim:LastHitGroup() == HITGROUP_HEAD` | same |
| `dom_capture` | `modes/dom.lua:148`, every member of the capturing team | player only |
| `kc_confirm`, `kc_deny` | `modes/kc.lua:137` from `PW_KCTagCollected` | player only |
| `first_blood`, `double_kill`, `triple_kill`, `revenge`, `streak5`, `saviour` | medals module `modules/medals/init.lua:27-30` through `PW.Score.Award(ply, id)`; also `PW_Medal(ply, id)` | player only, no weapon |

Not present although `design/06-progression.md` d.3 lists them as MVP events: **`assist`** and **match win**.

### 3.2 `PW_*` notifications usable by a tracker (server)

| Hook | Fired at | Arguments | Notes |
| --- | --- | --- | --- |
| `PW_PlayerKilled` | `modules/match_rules/init.lua:151` (`DoPlayerDeath`, `LIVE` only) | `victim, attacker, dmg` | Listeners run before the active mode (`01-extensibility.md` d.9); the mode scores the kill afterwards. Infection (`privatewar-infection`) handles kills itself and never calls `ScoreKill`, so no `kill` score event exists there |
| `PW_PlayerSpawned` | `modules/match_rules/init.lua:16` | `ply` | Life start |
| `PW_MatchStart` | `gamemode/core/sv_match.lua:136` | none | After `MODE:Start`; `PW.ActiveMode.ClassName` is the mode id; `PW.Playlist.GetActive()` the playlist (`""` Custom) |
| `PW_MatchEnd` | `gamemode/core/sv_match.lua:109` | `result` (`PW.MatchResult`: `winner` team index or player, `draw`, `teams`, sorted `standings`) | Win/loss/placement derivable per player |
| `PW_PhaseChange` | `gamemode/core/sv_match.lua:164` | `to, from, endsAt` | Flush points |
| `PW_RoundStart`, `PW_RoundEnd`, `PW_RoundPreparing`, `PW_RoundPrepared` | `modes/round_base.lua:187-191, 283-285` | `round, winner, wins` / `round, swapped` | S&D and Infection round boundaries |
| `PW_KCTagCollected` | `modules/kc_tags/init.lua:68` | `collector, victim, verdict` | Already becomes a score event |
| `PW_Medal` | `modules/medals/shared.lua:132` | `ply, medalId` | Fires for bots too |
| `PW_ProgressionXP`, `PW_ProgressionLevelUp`, `PW_ProgressionWeaponLevelUp` | `modules/progression/init.lua:150-170` | `ply, ...` | Level-based challenges ("reach weapon level 10") possible |
| `PW_EconomyPurchase` | `modules/economy/init.lua:152` | `ply, key, price` | Not a match event |
| `PW_LoadoutGiven` | `modules/loadout/init.lua:48` | `ply, loadout` | Snapshot of class/weapons/attachments/perks per life |
| `PW_Blinded` | `modules/throwables/sv_blind.lua:55` | `ply, seconds-related args` | "Kill a blinded enemy" possible by caching the blind end time |
| `PW_PlayerTeamChanged` | `modules/teams/init.lua:41` | `ply, from, to, reason` | Life/match scope edge cases |

Question hooks (`PW_CanTakeDamage`, `PW_ScoreValue`, ...) are not event sources.

### 3.3 Facts available at kill time but not carried by any event

Inside `ScoreKill` (synchronous with `DoPlayerDeath`) the following can be computed cheaply; none of it reaches
`PW_ScoreEvent` today:

| Fact | Source |
| --- | --- |
| Victim, victim is a bot | `victim`, `victim:IsBot()` |
| Headshot | `victim:LastHitGroup() == HITGROUP_HEAD` (computed, only converted into the separate `headshot` event) |
| Distance | `attacker:GetPos():Distance(victim:GetPos())` (1 unit = 0.01905 m) |
| Weapon class, category, kind | weapon entity → class → `PW.WeaponsCatalog` entry `Category`, `Kind` (`types/weapons_catalog.lua:17-18`) |
| ADS / hipfire | `ADAPTER:IsAiming(wep)` (`docs/api/adapter.md`, default `KeyDown(IN_ATTACK2)`) |
| Crouch, airborne | `attacker:Crouching()`, `not attacker:IsOnGround()` |
| Sliding | only through the optional Quick Slide / combat-movement state; no public accessor for humans: **gap** |
| Streak kill | `PW.Streaks.IsDamage()` is true inside the streak damage callback (`types/streaks.lua:7`); the streak id is not exposed: **gap** |
| Explosive / melee | `dmg:IsDamageType(DMG_BLAST)`, weapon `Kind == "melee"` |
| Equipment kill (which item) | grenade SWEPs carry `PWGrenade = true` (`modules/equipment/sv_grenades.lua:16`); the projectile's item id is not exposed: **gap** (category "explosive" works) |
| Attachments, suppressor | the life's loadout build from `PW_LoadoutGiven`; "suppressed" needs a curated tag: **gap** |
| Alive time, kills this life | not tracked publicly; the tracker can track spawn time and its own per-life counters |

### 3.4 Missing events for the target challenge types

| Wanted objective | Status | Where it would be added |
| --- | --- | --- |
| Kill context (headshot flag, distance, ADS, stance, victim, category) on `kill` | Missing | `PW.ScoreOpts.context` + 6th argument of `PW_ScoreEvent` (`modules/score/init.lua:60-80`), built in `ScoreKill` (`modules/match_rules/init.lua:71-93`); additive, existing listeners ignore extra arguments |
| S&D plant / defuse | Missing (pure `complete()` in `modules/snd/sh_round.lua:47-61` changes state silently) | Record the completed action and actor id in the state; `modes/snd.lua:71` awards new score events `snd_plant`, `snd_defuse` |
| Hardpoint time in zone | Missing per player | `modules/hardpoint/init.lua:74-92` (`hp.Think`) reports challenge-only `objective_time` per scoring sample, or a score event (balance change) |
| Match win / played / placement | Derivable from `PW_MatchEnd` | Tracker-side; optional `match_win` score event per d.3 |
| Assist | Missing everywhere | Needs a damage ledger (medals already keep a recent-damage window for `saviour`); separate task |
| Killstreak earned / activated / streak kill id | Missing | Notifications `PW_StreakEarned(ply, id)` and `PW_StreakActivated(ply, id)` in `modules/streaks/init.lua` (`_OnScore` returns earned ids; `lib.Use` at `:259`); streak id during `StreakDamage` |
| Equipment use / kill by item | Missing | Notification `PW_EquipmentUsed(ply, itemId)` in `modules/equipment/init.lua:171-175`; item id on the thrown projectile |
| Infection survive as human, infect | Mode-internal | The addon calls `PW.Challenges.Report({ type = "pw_infection:survive", ... })` |
| Time played | Derivable | Tracker accumulates seconds per player between `PW_MatchStart`/join and `PW_MatchEnd`/leave |

## 4. Storage and trust facts that constrain the design

1. `design/06-progression.md` d.0 and d.5: progression lives on the client (`data/privatewar/progression.json`), is
   sent on join, sanity-checked, forgeable (accepted); the server stores nothing; 10 s deltas with an idempotent
   batch id (`docs/api/progression.md`, "Storage and deltas").
2. A map change is a `changelevel` (`design/00-core.md` d.9): server Lua state is lost, so per-session challenge
   progress must reach the client before it (progression already flushes on every phase change).
3. XP and currency rewards are additive. If a challenge's claim flag and its XP reward are written in different files,
   a crash between the writes either loses the reward or grants it twice. Carrying the claim id and the reward in the
   same delta batch, and writing the claim before the reward, makes a crash lose a reward at worst, never grant it
   twice.
4. The parallel entitlement research (`31-unlock-entitlements-research.md` §4) proposes `PW.Unlocks.Grant` with a
   grant/claim id for idempotency, claims stored in a new client file `data/privatewar/unlocks.json`, and claims
   travelling in `pw_progression_delta` with the existing batch idempotency. It also argues for new client files
   instead of growing `progression.json`, because an older server version rewrites `progression.json` and drops
   fields it does not know. Challenge progress therefore fits best in its own client file, with reward idempotency
   delegated to the entitlement claim ledger.
5. Each host computes the week from its own clock (`os.time()` UTC, like `PW.Economy.Today` in
   `modules/economy/shared.lua:65`). Friends' hosts may disagree near a boundary; per-week keyed progress kept on the
   client survives that.

## 5. Sources

- tracker.gg, "Modern Warfare & Warzone Season 4 Week 1 challenges":
  <https://tracker.gg/warzone/articles/modern-warfare-warzone-s4-w1-challenges>
- Treyarch, "Daily Challenges Have Arrived" (Black Ops Cold War, 2020-12):
  <https://www.treyarch.com/game-intel/2020/12/Daily_Challenges_Have_Arrived>
- ONE Esports, "MW3/WZ Season 6 weekly challenges": <https://www.oneesports.gg/call-of-duty/mw3-wz-season-6-weekly-challenges/>
- Pro Game Guides, "MW3 weekly challenges and rewards": <https://progameguides.com/call-of-duty/mw3-weekly-challenges-and-rewards/>
- gfinity, "Modern Warfare 3 weekly challenges": <https://www.gfinityesports.com/guides/modern-warfare-3-weekly-challenges>
- Game8, MW3 weekly challenges: <https://game8.co/games/MW3/archives/432359>
- MP1st, "Black Ops 6 won't feature weekly challenges":
  <https://mp1st.com/news/black-ops-6-wont-feature-weekly-challenges-zombies-to-have-more-support-for-in-game-events>
- Sportskeeda, weekly challenges in Black Ops 6:
  <https://www.sportskeeda.com/call-of-duty-game/why-call-duty-bring-back-weekly-challenges-black-ops-6-warzone>
- Heroic Labs Hiro, quests and achievements: <https://heroiclabs.com/docs/hiro/guides/gameplay-mechanics/quests/>
- Bevy all-in-one quest system: <https://yaskhan.github.io/bevy_allinone/quest_system.html>
- SUQS (Unreal data-driven quests): <https://github.com/sinbad/SUQS>
- Quest system guide (Unreal blueprints): <https://grzott.github.io/how-to-make-a-game-ue56-bp/solutions/quest-system.html>
- Steamworks achievements documentation: <https://partner.steamgames.com/doc/features/achievements>
- ISO week date: <https://en.wikipedia.org/wiki/ISO_week_date>

Limits: a primary MW2019 Season 1 list and the exact MW3 weekly reward rule per season were not retrieved (one guide
returned HTTP 403); the "complete N of M" figure comes from secondary guides. Exact CoD numbers are context, not
requirements.
