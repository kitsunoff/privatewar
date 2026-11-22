# Weekly challenges

Status: `in-progress`

Recorded: 2026-11-21

The independent rotation and filter work started on 2026-11-22 on `feat/weekly-challenges` from
`f5199de`. Remaining implementation resumed on `53f04d4`, which includes the local unlock authority and tactical
stims. Whole-feature gates and human acceptance are pending.

Early scope evidence (2026-11-22, `19b1f71`): steps 1–4 are committed, with `nix develop --command make check`
and pre-commit passing. Full Deck RED was 2144 passed, 23 failed, 0 skipped. After steps 1–3, all 14 of their new
cases passed and the 10 step-4 cases failed as expected, including the dot-separator regression. Full Deck GREEN
at `19b1f71` was 2168 passed, 0 failed, 0 skipped. This does not cover the remaining steps or approve integration.

Design verification (2026-11-22, `4acd7f6`, not integrated): `nix develop --command make check` and pre-commit
passed. Twenty test cases for steps 5–6 were drafted but are not in the branch: LuaLS rejected the drafts with
`no-unknown` on two attempts. No game RED/GREEN was observed for them; neither step is implemented.

Approval (2026-11-22): the user approved every design change proposed in this record and the recommended
default of every open question, except where an answer below says otherwise. This approves the design
direction for implementation; push, PR, merge to `main` and publication still need separate approval.

Instance ID clarification (approved 2026-11-22): a dot is only a component separator. Template IDs must not contain
dots, and dotted parameter values are not selectable. The assembled format and 40-byte limit are unchanged.

Research: [notes/32-weekly-challenges-research.md](../../notes/32-weekly-challenges-research.md) (CoD challenge design,
generic quest architecture, the full event inventory and the gaps).

This record is tracking, not authorization. It does not authorize implementation, design or contract changes, Steam
Deck access, pushes or publication. Every number marked "proposed default" is unapproved. Existing decisions in
`design/` and frozen contracts in `docs/api/` stay in force until the user approves the changes listed in section 2.

Uses the [unlock authority](../done/unlock-entitlements.md), already verified in the local integration (see
[notes/31-unlock-entitlements-research.md](../../notes/31-unlock-entitlements-research.md)). Item rewards and the
reward idempotency ledger are delivered only through that system (`PW.Unlocks.Grant` with a claim id). XP and currency
rewards go through the existing `PW.Progression.AddXP` and `PW.Progression.AddCurrency`. Implementation of this record
starts only after the entitlement change has landed; steps 1 to 6 of section 9 (pure logic) may start earlier.

Line numbers below refer to branch `docs/plan-mwbase-stims-unlocks-challenges` at `cf7c4ed`; the implementer re-checks
them before editing. Paths are relative to `addons/privatewar/` unless they start with a top-level folder.

## 1. User request

- [ ] Build a weekly challenges system. Completing challenges unlocks rewards: weapons, skins (camos, operators, calling
  cards) and similar. Challenge types as in Call of Duty: kills with headshots, kills in TDM or in a playlist, kills
  with a given weapon, and objectives that are not kills. The system must be as flexible as possible, track progress,
  and grant the reward on completion.

## 2. Dependencies and design changes requiring approval

None of these is approved. Proposed wording is for the user to accept, change or reject.

- [ ] **D-WC1, `design/06-progression.md` decision 9 "Weekly challenges"** (replaces the "After MVP: challenges"
  bullet of d.1 for weekly challenges; prestige and per-weapon camo challenges stay future work). Proposed wording:
  "Weekly challenges: a kind `challenges/` holds challenge templates (data plus an optional predicate). Every week
  (Monday 00:00 UTC) each host deterministically selects N templates from the enabled pool by the week number and a
  host seed, binding template parameters, with a difficulty mix. Progress is tracked on the server from authoritative
  events (score events with context, match, round, death and streak notifications, and `PW.Challenges.Report` from
  modes and addons), for human players only, and stored on the client in `data/privatewar/challenges.json` like
  progression (forgeable, accepted, d.0). A completed challenge auto-grants its reward once, idempotent by a claim id
  through the entitlement system; completing `bonusneeded` of the week's challenges grants the weekly bonus. Progress
  of other weeks is ignored and expires."
- [ ] **D-WC2, `design/06-progression.md` d.3 revision: score events carry an optional context.** Proposed wording:
  "`PW.Score.Award(ply, id, opts)` accepts `opts.context` (a plain table describing the event: for kills the victim,
  headshot, distance, weapon category, ADS, stance and similar). The notification gains a sixth argument:
  `PW_ScoreEvent(ply, eventId, points, xp, weapon, context)`. Adding the argument does not change existing listeners
  (`01-extensibility.md` d.14: additive, no `PW.API` bump)." Contract update in `docs/api/modes.md` ("Score module")
  and `lua/privatewar/types/score.lua` by the orchestrator.
- [ ] **D-WC3, new score events `snd_plant` and `snd_defuse`** (Search and Destroy, `design/02-modes.md` d.8). Proposed
  default points 100 each (match score and XP; S&D wins by rounds, so the score does not change outcomes). Alternative
  if rejected: the S&D mode reports challenge-only events through `PW.Challenges.Report` with no score or XP change.
- [ ] **D-WC4, streak notifications** `PW_StreakEarned(ply, streakId)` and `PW_StreakActivated(ply, streakId)`, and a
  public `PW.Streaks.DamageStreakId() -> string?` valid inside `StreakDamage` (contract `docs/api/streaks.md`, loadout
  lane). Without it the streak challenge templates (C14, C15) are dropped from the starter pool.
- [ ] **D-WC5, storage file** `data/privatewar/challenges.json` (new client file, version 1), its upload message and
  delta message (section 3.6, 6). Reason for a new file instead of a `progression.json` section: an older server
  version rewrites `progression.json` and drops unknown fields (note 31 §2.5); the entitlement record makes the same
  choice for `unlocks.json`.
- [ ] **D-WC6, requirements on the entitlement record** (to be reflected in `unlock-entitlements.md`, not edited here).
  That record (section 10, "Interface for weekly challenges") already provides `PW.Unlocks.Grant(ply, items,
  { source = "challenge", grant = <id> })` (idempotent by grant id, refusal `"claimed"`, flushes the delta at once),
  `PW.Unlocks.HasClaim(ply, grant)` on both realms, `PW.Unlocks.Describe(item)`, the question hook
  `PW_UnlockHint(kind, id)` and the notification `PW_UnlockGranted`. Missing and required here: (a) `Grant` with an
  empty item list records the claim (XP-only and currency-only rewards, and rewards whose items are all owned,
  unresolved or refused as `"full"`); (b) XP and currency added before `Grant` travel in the same
  `pw_progression_delta` batch as the claim (the flush inside `Grant` sends both); (c) the client persists claims
   (`unlocks.json`) before applying XP and currency of that batch (`progression.json`), so a crash loses a reward at
   worst and never grants it twice.
   Approved 2026-11-22: defer the entire reward while `PW.Unlocks.IsReady(ply)` is false, before checking claims or
   queuing XP or currency. Otherwise an unrelated flush could pay part of the reward before its claim is recorded.
- [ ] **D-WC7, Hardpoint objective time** (optional): `modules/hardpoint/init.lua` reports a
  challenge-only `objective_time` event (no score change). Without approval template C11 is dropped.
- [ ] **D-WC8, UI placement**: a PROGRESS sub-screen "WEEKLY CHALLENGES" pushed from `progress_home`, and a new HUD
  element (top right toast). `design/10-frontend.md` d.1 lists PROGRESS as "player level, weapon levels, unlocks";
  adding challenges there needs approval. `design/09-hud.md` d.2 overlay list gains "challenge toasts".
- [ ] **D-WC9, lanes**: module `challenges` in the progression lane (`TASKS.md`, "Lanes and ownership", progression row
  gains `modules/challenges/`, `lua/privatewar/challenges/`, `kinds/challenges.lua`). Screen and HUD files are feature
  UI parts built with the kit (`TASKS.md`, "UI grows together with features"); the small edit of
  `screens/progress_home.lua` is a ui-lane file and needs the orchestrator.
- [ ] **D-WC10, task id and mandatory cases**: the orchestrator assigns a task id (proposed `T-11.19 Weekly
  challenges`) and copies section 10 into `TASKS.md` "Mandatory test cases" and `docs/agent-test-map.md`.

## 3. Data model

### 3.1 Kind `challenges` (`lua/privatewar/kinds/challenges.lua`)

- [ ] `KIND.Folder = "challenges"`, `KIND.Global = "CHALLENGE"`, `KIND.Subscribe = "never"`,
  `KIND.Required = { Name = "string", Description = "string" }`. Enable ConVar `pw_challenge_<id>_enabled`
  (`01-extensibility.md` d.11; read at the next match like every flag). Hot reload and `PW_PreRegister` work as for
  every kind. The module validates the rest (like playlists): an invalid template is skipped with one log line
  `challenge <id> rejected: <reason>`.

### 3.2 Template schema

Every field, its type, default and meaning. The shorthand (top-level `Event`, `Filters`, `Filter`, `Target`, `Count`,
`Within`, `ResetOn`) defines objective 1; `Objectives` defines several objectives and then the shorthand fields must be
absent.

```lua
-- lua/privatewar/challenges/<id>.lua ; the id is the file name
CHALLENGE.Name        = "Headhunter"            -- string, required. Display name; may be a "#phrase". Placeholders:
                                                --   {target} {target1}..{target4}, {param.<key>} (display name of the value)
CHALLENGE.Description = "Get {target} headshot kills."  -- string, required. Same placeholders
CHALLENGE.Icon        = nil                     -- string?, material path; nil = tier badge only
CHALLENGE.Tiers       = { "easy", "medium" }    -- PW.ChallengeTier[], default { "easy", "medium", "hard" }. Tiers this
                                                --   template may be selected for
CHALLENGE.Weight      = 1                       -- number > 0, default 1. Relative selection weight inside a tier
CHALLENGE.Group       = "headshots"             -- string?, default = id. At most one template per group per week
                                                --   (relaxed only when a tier would otherwise stay empty)
CHALLENGE.Pool        = "weekly"                -- "weekly" | "none", default "weekly". "none" = never selected by the
                                                --   rotation (reserved for seasonal/permanent sets, out of scope)
CHALLENGE.Requires    = nil                     -- PW.ChallengeRequires?, see below. nil = always available
CHALLENGE.Params      = nil                     -- table<string, PW.ChallengeParam>?, parameter space, see below
CHALLENGE.Mode        = "all"                   -- "all" | "any", default "all": how objectives combine
CHALLENGE.Objectives  = nil                     -- PW.ChallengeObjective[]?, 1..4 entries; nil = use the shorthand
-- shorthand of objective 1 (see PW.ChallengeObjective):
CHALLENGE.Event       = "kill"                  -- string | string[], required unless Objectives is set
CHALLENGE.Filters     = { headshot = true }     -- table?, filter vocabulary (3.3); default {}
CHALLENGE.Filter      = nil                     -- fun(self, ev: PW.ChallengeEvent, params: table): boolean?;
                                                --   custom predicate, run through PW.Call after Filters pass
CHALLENGE.Count       = 1                       -- 1 | "value", default 1: amount added per matching event
                                                --   ("value" adds ev.value, for example seconds or points)
CHALLENGE.Scope       = "cumulative"            -- "cumulative" | "match" | "round" | "life", default "cumulative"
CHALLENGE.Target      = { easy = 10, medium = 25, hard = 60 }  -- integer | table<PW.ChallengeTier, integer>, required
CHALLENGE.Within      = nil                     -- { count: integer, seconds: number }?: an inner run of `count`
                                                --   matching events within `seconds` adds 1 to the counter
CHALLENGE.ResetOn     = nil                     -- PW.ChallengeResetRule[]?: events that reset the current run
CHALLENGE.Rewards     = nil                     -- table<PW.ChallengeTier, PW.ChallengeReward> | PW.ChallengeReward?;
                                                --   nil = the tier defaults of section 3.5
```

```lua
---@alias PW.ChallengeTier "easy"|"medium"|"hard"

---@class PW.ChallengeObjective
---@field Event string|string[]          event type(s); several = OR
---@field Filters? table<string, any>    vocabulary of 3.3
---@field Filter? fun(self: PW.Challenge, ev: PW.ChallengeEvent, params: table<string, string>): boolean?
---@field Count? 1|"value"
---@field Scope? "cumulative"|"match"|"round"|"life"
---@field Target integer|table<PW.ChallengeTier, integer>
---@field Within? { count: integer, seconds: number }
---@field ResetOn? PW.ChallengeResetRule[]
---@field Label? string                  per-objective text for multi-objective challenges

---@class PW.ChallengeResetRule
---@field Event string                   event type that resets the run
---@field Filters? table<string, any>    same vocabulary

---@class PW.ChallengeRequires
---@field modes? string[]                at least one of these mode ids is enabled (PW.Modes.GetEnabledList)
---@field playlists? string[]            at least one of these playlist ids is listed (PW.Playlist.GetList)
---@field categories? string[]           at least one weapon of these categories is in the catalogue
---@field kinds? table<string, string[]> registry entities that must exist, for example { streaks = { "uav" } }
---@field events? string[]               custom event types that must be registered (6.3)

---@class PW.ChallengeParam
---@field values string[]|fun(): string[]  candidate values; the function form is evaluated at selection time
---@field source? "categories"|"weapons"|"modes"|"playlists"  built-in value source (values then optional)
---@field names? table<string, string>    display names for {param.<key>}; default = the value or the entity Name
```

Rules (validation in `sh_template.lua`):

- [ ] Reject template ids that contain a dot; dots are reserved for the separators in the assembled instance id.
- [ ] Exactly one of `Objectives` or the shorthand `Event`. 1 to 4 objectives. Each objective has a known event type
  (built-in or registered, 6.3) and a target ≥ 1 for every tier the template allows (a number target applies to every
  tier). `Within.count` ≥ 2, `Within.seconds` > 0. Unknown filter keys are rejected (typo protection) unless the
  event type is custom and the key is `data` (3.3).
- [ ] A filter value of a param placeholder `"{param.<key>}"` is substituted with the bound value at instance build.
- [ ] Templates are compiled once per registry load into a list of filter closures per objective (no table lookups by
  string in the hot path beyond `ev[field]`).

### 3.3 Filter vocabulary

A filter matches when the event field compares as stated. A value may be a scalar (equality), a set
`{ a = true, b = true }` or a list `{ "a", "b" }` (membership), except where noted. An absent event field never matches
a filter on it (an unknown ADS state does not count as hipfire).

| Filter key | Event field | Semantics | Event types |
| --- | --- | --- | --- |
| `mode` | `mode` | Mode id of the match (`PW.ActiveMode.ClassName` at `PW_MatchStart`) | all match events |
| `modeBase` | `modeBase` | The mode's `Base` chain contains the value (`round_base`, `tdm`) | all match events |
| `playlist` | `playlist` | Active playlist id at match start; `true` = any playlist, `false` = Custom (`""`) | all match events |
| `weapon` | `weapon` | Weapon class of the kill | `kill` |
| `category` | `weaponCategory` | Catalogue `Category` (`ar`, `smg`, `shotgun`, `pistol`, `special`, pack-specific ones) | `kill` |
| `weaponKind` | `weaponKind` | `gun`, `melee`, `throwable`, `launcher`, `other` | `kill` |
| `attachment` | `attachments` | The life's build of that weapon contains the option id (set membership on the event side) | `kill` |
| `headshot` | `headshot` | Boolean | `kill` |
| `distanceMin`, `distanceMax` | `distance` | Metres, inclusive (`units × 0.01905`) | `kill` |
| `ads` | `ads` | `true` = aiming down sights, `false` = hipfire | `kill` |
| `crouch` | `crouch` | Boolean | `kill` |
| `airborne` | `airborne` | Boolean (`not IsOnGround()`) | `kill` |
| `victimBot` | `victimBot` | Boolean | `kill` |
| `explosive` | `explosive` | Damage type includes `DMG_BLAST` | `kill` |
| `streakKill` | `streakKill` | The kill came from streak damage | `kill` |
| `streak` | `streak` | Streak id | `kill` (streak kills), `streak_earned`, `streak_used` |
| `lifeKillsMin` | `lifeKills` | Kills in the current life including this one ≥ value | `kill` |
| `aliveTimeMax` | `aliveTime` | Seconds since the killer's spawn ≤ value | `kill` |
| `event` | `scoreEvent` | Score event id | `score` |
| `medal` | `medal` | Medal id (`PW.Medals.Ids`) | `medal` |
| `objective` | `objective` | `capture`, `confirm`, `deny`, `plant`, `defuse` | `objective` |
| `won`, `draw` | `won`, `draw` | Booleans from `PW.MatchResult` / `PW_RoundEnd` | `match_end`, `round_end` |
| `placementMax` | `placement` | 1-based placement in the sorted standings (FFA: own rank; team modes: team rank) ≤ value | `match_end` |
| `valueMin` | `value` | `ev.value` ≥ value | all |
| `suicide` | `suicide` | Boolean | `death` |
| `data` | `data` | Table of key → scalar/set, each must match `ev.data[key]` | custom types |

Sliding, kills of blinded victims, equipment item ids and "suppressed" are not in the first version (research §3.3
gaps); a template needing them uses `Filter` and must declare the field it reads as `ev.data` of a custom event.

### 3.4 Scope semantics and reset rules

- [ ] `cumulative`: the counter adds across matches during the week and is persisted. With `ResetOn`, a matching reset
  event sets the counter to 0 (an "in a row" challenge; the persisted value is the current run).
- [ ] `match`: a run counter starts at 0 at `PW_MatchStart` (or when the player first appears in a running match) and
  is discarded at `PW_MatchEnd`. The objective completes when the run reaches the target within one match. The
  persisted value is the best run of the week (only grows).
- [ ] `round`: like `match`, reset at `PW_RoundStart`; in a mode without rounds it behaves as `match`.
- [ ] `life`: the run resets when the player dies (`PW_PlayerKilled` as victim), changes team, or spawns without a
  recorded death. Persisted value: best run.
- [ ] `Within`: an inner list of event times per (player, objective); when it holds `count` events within `seconds`,
  the counter adds 1 and the inner list clears. Session only; reset with the objective's scope.
- [ ] `ResetOn` on `match`/`round`/`life` scopes resets the current run only (for example "kills without being
  hit" with a reset on a custom damage event).
- [ ] Order inside one event: reset rules of every objective are applied before increments, so an event that both
  resets and counts (rare) leaves the counter at its increment.
- [ ] A completed objective stops counting. A completed challenge never regresses (ResetOn ignores it).

### 3.5 Reward schema and defaults

```lua
---@class PW.ChallengeReward
---@field xp? integer                    player XP, through PW.Progression.AddXP (xpscale applies)
---@field currency? integer              through PW.Progression.AddCurrency (economy active)
---@field items? PW.UnlockItem[]          entitlement items { kind, id, weapon? } (bundle item shape, economy.md)
---@field duplicateCurrency? integer     paid instead of an item the player already owns; default 250
```

| Tier | XP (proposed default) | Currency (proposed default) | Items |
| --- | --- | --- | --- |
| `easy` | 2500 | 50 | none |
| `medium` | 5000 | 100 | none |
| `hard` | 10000 | 200 | optional, per template |
| weekly bonus | 10000 | 300 | one item from the bonus pool (3.7) |

- [ ] An item that does not resolve on this host is skipped and replaced by `duplicateCurrency` (logged once).
- [ ] With the economy module disabled, currency rewards are skipped silently; XP and items still apply.

### 3.6 Progress storage (`data/privatewar/challenges.json`)

```lua
---@class PW.ChallengeFile
---@field v integer                       version, PW.Challenges.FileVersion = 1
---@field weeks table<string, PW.ChallengeFileWeek>  key = ISO week label "2026-W47"
---@field batch? { session: integer, seq: integer }  last delta applied (idempotency, as progression)

---@class PW.ChallengeFileWeek
---@field index integer                   Monday-week index (days since 1970-01-05 // 7)
---@field items table<string, PW.ChallengeFileItem>  key = instance id
---@field bonus? boolean                  weekly bonus completed (the reward claim itself lives in the entitlement ledger)

---@class PW.ChallengeFileItem
---@field p integer[]                     per objective: cumulative counter, or best run for match/round/life
---@field done? boolean                   completed
```

Example: `{ "v": 1, "weeks": { "2026-W47": { "index": 2967, "items": { "headshots": { "p": [12] } } } },
"batch": { "session": 41, "seq": 3 } }`.

- [ ] Bounds (`sh_storage.lua`): at most `MaxWeeks` = 4 week entries (the highest indices kept), `MaxItems` = 16 per
  week, `MaxObjectives` = 4, a counter 0 to `MaxCount` = 1e6 (floored; NaN, negative, non-number → 0), a week label
  matching `^%d%d%d%d%-W%d%d$`, an instance id matching `^%l[%w_]*[%w_%.%-]*$` of at most 40 bytes. Anything else is
  dropped. A malformed or missing file reads as empty; a file with `v` greater than the known version is not
  rewritten (read-only for that session, one log line), so a newer client file survives an older host.
- [ ] Migration: version 1 is the first version; `_Migrate(raw)` exists from the start and maps unknown or missing `v`
  to an empty file. Each future version adds one migration step and a test.
- [ ] Pruning: the client drops week entries whose index is below `currentIndex - 1` of its own clock when it writes the
  file; the server never deletes entries (clock skew between friends' hosts, research §4).
- [ ] Upload: `pw_challenges_upload` (C→S, once per connection; section 6.4) carries only the entry whose label equals
  the server's session week. The client sends all entries (at most 4); the server keeps only the session week and
  ignores the rest.
- [ ] Server clamp on upload: counters above the template target are clamped to the target; ids not in the session's
  active set are ignored (kept on the client); `done` is recomputed from counters (a forged `done` without counters
  is not honoured; a forged counter is accepted, d.0).

### 3.7 Weekly set schema

```lua
---@class PW.ChallengeWeek
---@field index integer                    Monday-week index
---@field label string                     ISO label "2026-W47"
---@field startsAt integer                 UTC unix time of Monday 00:00
---@field endsAt integer                   startsAt + 7 * 86400
---@field seed integer                     the seed used (diagnostics)
---@field items PW.ChallengeInstance[]     sorted: easy, medium, hard, then id
---@field bonus { needed: integer, reward: PW.ChallengeReward }

---@class PW.ChallengeInstance
---@field id string                        instance id: template id, then "." and each bound param value in key order
---@field template string                  template id
---@field tier PW.ChallengeTier
---@field params table<string, string>     bound parameters
---@field targets integer[]                per objective
---@field reward PW.ChallengeReward        resolved (template or tier default)
```

- [ ] Bonus pool: `PW.Challenges.BonusPool` (`PW.UnlockItem[]`), filled by content through
  `PW.Challenges.AddBonusItem(item)` at load (sorted by entitlement key before selection; default empty → XP and
  currency only). Reward-only items are declared `Unlock = false` as the entitlement record specifies. The week picks
  one item with the same generator after the challenges.

### 3.8 Idempotency keys

Grant ids follow the entitlement pattern `^[%w_%-%.:]+$`, at most 64 bytes (`unlock-entitlements.md`,
`PW.UnlockGrantMeta.grant`).

- [ ] Challenge reward grant id: `challenge:<label>:<instance id>` (for example
  `challenge:2026-W47:kills_category.smg`). Instance ids are at most 40 bytes so the grant id fits; the template id
  `bonus` is reserved.
- [ ] Weekly bonus grant id: `challenge:<label>:bonus`.
- [ ] Reward order on completion (server, `sv_rewards.lua`): (1) `PW.Unlocks.HasClaim(ply, id)` true → mark done,
  grant nothing; (2) filter items: drop those whose `PW.Unlocks.Describe(item)` is invalid or that the player already
  has (`PW.Unlocks.IsUnlocked`), adding `duplicateCurrency` for each; (3) `PW.Progression.AddXP` and
  `PW.Progression.AddCurrency`; (4) `PW.Unlocks.Grant(ply, items, { source = "challenge", grant = id })`, which
  records the claim and flushes the delta (D-WC6); (5) on refusal `"full"` or `"toomany"`, retry once with an empty
  item list plus `duplicateCurrency` per item, so the claim is still recorded; any other refusal is logged and the
  completion is retried at the next phase change (the XP of step 3 is not re-added: the module keeps a session flag
  per grant id until the claim exists).
- [ ] The challenge module keeps no claim flag of its own in `challenges.json` (`done` is progress, not a claim).

## 4. Event pipeline

### 4.1 Consumed events

| Source | Normalized type | Notes |
| --- | --- | --- |
| `PW_ScoreEvent` with id `kill` | `kill` | Uses the new `context` argument (4.3). A kill without context (third-party award) counts with only `weapon` known |
| `PW_ScoreEvent` (every id) | `score` | `scoreEvent`, `value = points` |
| `PW_ScoreEvent` with a medal id (`PW.Medals.Ids`) | `medal` | Also emitted as `score`. `PW_Medal` is not consumed (it would double count) |
| `PW_ScoreEvent` with `dom_capture`, `kc_confirm`, `kc_deny`, `snd_plant`, `snd_defuse` | `objective` | `objective` field from a fixed map in `sv_events.lua`; also emitted as `score` |
| `PW_PlayerKilled` (victim side) | `death` | Life resets; `suicide`, killer facts |
| `PW_MatchStart` | none | Snapshots `mode`, `modeBase`, `playlist`, the match serial and the session week |
| `PW_MatchEnd` | `match_end` per human who played | `won`, `draw`, `placement`; also `time_played` with `value` = seconds present |
| `PW_RoundStart` / `PW_RoundEnd` | `round_end` per human | Round scope resets; `won` from the winner team |
| `PW_PlayerSpawned` | none | Spawn time for `aliveTime`; life scope safety reset |
| `PW_LoadoutGiven` | none | Caches the life's builds for the `attachment` filter |
| `PW_StreakEarned`, `PW_StreakActivated` (new, D-WC4) | `streak_earned`, `streak_used` | |
| `PlayerDisconnected` | `time_played` | Seconds present so far; then flush |
| `PW.Challenges.Report(ev)` | custom | Modes and addons (6.3) |

### 4.2 Normalized `PW.ChallengeEvent`

```lua
---@class PW.ChallengeEvent
---@field type string                -- built-in type or a registered custom type "<namespace>:<name>"
---@field player Player              -- the human whose challenges progress (never a bot)
---@field value number               -- amount, default 1 (seconds, points)
---@field mode string                -- match snapshot
---@field modeBase string[]          -- base chain, nearest first
---@field playlist string            -- "" for Custom
---@field match integer              -- match serial (session counter)
---@field week integer               -- session week index the event counts into
---@field time number                -- CurTime()
-- kill
---@field victim? Player
---@field victimBot? boolean
---@field weapon? string             -- class
---@field weaponCategory? string
---@field weaponKind? PW.WeaponKind
---@field attachments? table<string, boolean>
---@field headshot? boolean
---@field distance? number           -- metres
---@field ads? boolean
---@field crouch? boolean
---@field airborne? boolean
---@field explosive? boolean
---@field streakKill? boolean
---@field streak? string
---@field lifeKills? integer
---@field aliveTime? number
-- score / medal / objective
---@field scoreEvent? string
---@field medal? string
---@field objective? string
-- match_end / round_end / death
---@field won? boolean
---@field draw? boolean
---@field placement? integer
---@field suicide? boolean
-- custom
---@field data? table<string, string|number|boolean>
```

- [ ] One table per event, built by `sv_events.lua`; kills and score events are rare (no per-tick events).
- [ ] Bots: an event whose `player` is a bot or invalid is dropped before any matching. Victims may be bots.
- [ ] Question hook `PW_ChallengeCanCount(ply, ev)`: a `false` answer drops the event (for example an addon excluding
  a practice mode). Default: counts.
- [ ] Only during `LIVE` (events outside `LIVE` are dropped), except `match_end`, which is processed at `PW_MatchEnd`.

### 4.3 New fields on existing events

- [ ] `lua/privatewar/types/score.lua:13-15`: add `---@field context? table<string, any>` to `PW.ScoreOpts`; document
  the sixth argument on `PW.ScoreLib.Award` (`:27-35`).
- [ ] `lua/privatewar/modules/score/init.lua:60-80` (`_Award`): read `opts.context` and pass it as the sixth argument
  of `PW.Notify("PW_ScoreEvent", ...)` at `:77`. Nothing else changes: popups, `PW_ScoreChanged`, return values. The
  existing listeners `modules/progression/init.lua:229` and `modules/streaks/init.lua:309` keep their signatures.
- [ ] `lua/privatewar/modules/match_rules/init.lua:71-93` (`ScoreKill`): build one context table per kill before the
  award loop at `:92` and pass `{ weapon = weapon, context = ctx }` for both `kill` and `headshot`. Fields:
  `victim`, `victimBot`, `headshot` (already computed at `:78`), `distance` (metres), `ads` (`PW.Adapters.CallFor(weapon,
  "IsAiming", weapon)` when the weapon is valid, else nil), `crouch`, `airborne`, `explosive` (`dmg:IsDamageType(DMG_BLAST)`),
  `streakKill` (`PW.Streaks.IsDamage()` nil-safe), `streak` (`PW.Streaks.DamageStreakId()`, D-WC4). Weapon category
  and kind are resolved by the challenges module from the class, not here (keeps match_rules small).
- [ ] `lua/privatewar/modules/snd/sh_round.lua:47-61` (`complete`): record `state.completed = { action, id, site }` on
  a finished plant or defuse (pure, testable). `lua/privatewar/modes/snd.lua:71`: after `Step`, when
  `state.completed` is set, award `snd_plant` or `snd_defuse` to the player whose `PW.SND.Identity(ply)` matches, then clear
  it. New files `lua/privatewar/score_events/snd_plant.lua`, `snd_defuse.lua` (D-WC3).
- [ ] `lua/privatewar/modules/streaks/init.lua`: fire `PW_StreakEarned(ply, id)` for each id returned by `_OnScore`
  (`:309-311`) and `PW_StreakActivated(ply, id)` after a successful `lib.Use` (`:259`); keep the streak id in the
  `StreakDamage` store for `DamageStreakId` (D-WC4).
- [ ] Optional (D-WC7): `lua/privatewar/modules/hardpoint/init.lua:74-92` reports `objective_time` (`value` =
  sample seconds) for each eligible occupant of a scoring, uncontested zone, through `PW.Challenges.Report` when the
  module exists (`rawget(PW, "Challenges")`).
- [ ] Every change is additive: existing tests of `score.lua`, `match_rules.lua`, `medals.lua`, `progression.lua`,
  `streaks.lua`, `mode_snd.lua`, `snd_runtime.lua` must pass unchanged. The kill context is not added to medal
  awards (medals give no weapon and keep their call `PW.Score.Award(ply, id)`).

## 5. Rotation

### 5.1 Week math (pure, `sh_rotation.lua`)

- [ ] Day number: reuse the algorithm of `PW.Economy._DayNumber` (`modules/economy/sh_rotation.lua`); the challenges
  module must not depend on the economy module being enabled, so it calls a shared copy moved to a neutral helper
  only with the orchestrator's approval, otherwise it keeps its own pure copy with the same tests.
- [ ] `WeekIndex(unixUtc) -> integer`: `floor((floor(unixUtc / 86400) - 4) / 7)`; 1970-01-05 (day 4) is the first
  Monday. Monday 00:00 UTC is the reset.
- [ ] `WeekLabel(index) -> string`: Thursday of the week = day `index * 7 + 4 + 3`; ISO year = calendar year of that
  Thursday; ISO week = `floor((dayOfYear(Thursday) - 1) / 7) + 1`; format `"%04d-W%02d"`.
- [ ] `WeekBounds(index) -> startsAt, endsAt` in UTC unix seconds.
- [ ] Test vectors (verified, research §2): 2026-11-21 → index 2967, `2026-W47`; 2026-12-28 and 2027-01-03 → 2973,
  `2026-W53`; 2027-01-04 → 2974, `2027-W01`; 2021-01-03 → 2660, `2020-W53`; 2025-12-29 → 2921, `2026-W01`;
  2024-12-30 → 2869, `2025-W01`.

### 5.2 Selection

`PW.Challenges._Select(index, pool, opts) -> PW.ChallengeWeek` (pure). `pool` is a list of validated templates with
their availability already resolved; `opts = { count, bonusNeeded, seed, bonusPool, tierDefaults }`.

1. [ ] Seed: `mix(index, hash("challenges"), opts.seed)` with the store's MINSTD generator constants (modulus
   2147483647, multiplier 48271, period spread 2654435761, three warm-up draws). A zero seed becomes 1.
2. [ ] Tier counts from `count` (setting, proposed default 5): `hard = count >= 3 and max(1, floor(count / 4)) or 0`;
   the rest split `easy = ceil(rest / 2)`, `medium = floor(rest / 2)`. 5 → 2 easy, 2 medium, 1 hard; 3 → 1/1/1;
   1 → 1 easy.
3. [ ] Tiers are filled in the order `hard`, `medium`, `easy` (the scarcest first). For each slot: candidates are the
   templates that allow the tier, are not chosen yet and whose `Group` is not used yet; when empty, the group rule is
   relaxed; when still empty, the slot moves to the next easier tier; when nothing is left, the week has fewer items.
4. [ ] Weighted pick: candidates sorted by id; `r = next() * totalWeight`; walk cumulative weights. Never depends on
   registry order.
5. [ ] Parameters: for each param key in sorted order, the candidate values (static list, function result or built-in
   source) are filtered by availability and sorted; one is picked with `next()`. A template whose param has no
   candidate value is not selectable. Instance id: `<template>.<value1>.<value2>` (keys in sorted order). A value that
   contains a dot, would make the instance id longer than 40 bytes, or would break the id pattern of 3.6 is not a
   candidate. The same rule applies to values from static lists, functions and built-in sources.
6. [ ] Targets and rewards resolved per tier; bonus item picked last from the sorted bonus pool.
7. [ ] Determinism guarantee: the same `index`, `seed`, `count`, template definitions and resolved availability give
   the same week on every host and every run. Hosts with different installed content or settings may differ; progress
   keyed by instance id carries over only where the same instance is selected.

### 5.3 Session week and boundaries (server, `init.lua`)

- [ ] The session week is computed from `os.time()` at module load, at every `PW_PhaseChange` to `LOBBY` or
  `PREMATCH`, and by one 60 s timer while the phase is not `LIVE`. No per-tick work.
- [ ] At `PW_MatchStart` the session week is frozen for the match: every event of the match counts into the week the
  match started in, even if Monday 00:00 UTC passes during it. The new week is applied after `PW_MatchEnd`, at the
  next phase change.
- [ ] On a week change: send the new state to every human, fire `PW_ChallengeWeek(label, week)`, reset session
  counters; a player's progress for the new week comes from their uploaded entry if present (a friend's host may have
  been ahead), else empty.
- [ ] Clock jumps: within one server session the session index never decreases (a backwards jump keeps the current
  week, one log line). A forward jump of more than one week simply selects the new week; missed weeks expire.
- [ ] Clients never compute the active set themselves; they display the server's state (the host clock is
  authoritative for its session, like `pw_phase_end`).

## 6. Public API and hooks

Namespace `PW.Challenges` (`lua/privatewar/types/challenges.lua`). Everything prefixed `_` is internal (d.14).

```lua
---@class PW.ChallengesLib
---Shared. The active week as the server sent it (client) or computed it (server); nil before the first state.
---@field GetWeek fun(): PW.ChallengeWeek?
---Shared. The active instances (empty list when the module is off or before the first state).
---@field GetActive fun(): PW.ChallengeInstance[]
---Server: any human; client: the local player only. Progress of one instance: per-objective counters (current run for
---match/round/life scopes while a run is open, else the persisted value), targets, done.
---@field GetProgress fun(ply: Player, instanceId: string): PW.ChallengeProgress?
---Server. Reports an event from a mode or an addon. Fills mode/playlist/match/week/time; drops bots, invalid players,
---unknown types and events outside LIVE. Returns true when the event reached the matcher.
---@field Report fun(ev: PW.ChallengeEventInput): boolean
---Shared. Registers a custom event type; must be called at file load or in PW_RegistriesLoaded on both realms.
---@field RegisterEventType fun(id: string, def: PW.ChallengeEventType): boolean
---Server. Completes or resets for development (guarded, section 6.5).
---@field _DevComplete fun(ply: Player, instanceId: string): boolean
---@field _DevReset fun(ply: Player): boolean
---Constants.
---@field FileVersion integer
---@field FilePath string                 "privatewar/challenges.json"
---@field ProgressInterval number         1 (seconds, throttle of progress messages)
---@field BonusPool PW.UnlockItem[]
---Shared. Adds an item to the weekly bonus pool (content files, at load).
---@field AddBonusItem fun(item: PW.UnlockItem): boolean

---@class PW.ChallengeProgress
---@field values integer[]
---@field targets integer[]
---@field done boolean

---@class PW.ChallengeEventInput
---@field type string
---@field player Player
---@field value? number
---@field data? table<string, string|number|boolean>

---@class PW.ChallengeEventType
---@field fields? table<string, "string"|"number"|"boolean">  declared data fields (validated on Report)
---@field label? string
```

### 6.1 Notifications (no return value, `01-extensibility.md` d.9)

| Hook | Arguments | When |
| --- | --- | --- |
| `PW_ChallengeProgress` | `ply, instanceId, objective, value, target` | A counter changed (server; batched sends are separate) |
| `PW_ChallengeCompleted` | `ply, instanceId, label` | Once per player, instance and week |
| `PW_ChallengeRewarded` | `ply, claimId, reward` | After the reward was queued (never for an existing claim) |
| `PW_ChallengeBonus` | `ply, label` | The weekly bonus was earned |
| `PW_ChallengeWeek` | `label, week` | The session week changed |
| `PW_ChallengesChanged` (client) | `week` | The client received a new state or progress |

### 6.2 Question hook

| Hook | Arguments | Answer |
| --- | --- | --- |
| `PW_ChallengeCanCount` | `ply, ev` | `false` drops the event; anything else counts |

### 6.2a Entitlement hooks answered by the module

- [ ] `PW_UnlockHint(kind, id)` (question, entitlement record): for an item that is the reward of an active challenge or
  the weekly bonus, answer `"Weekly challenge: <challenge name>"` or `"Weekly bonus"`, else `nil`.
- [ ] The completion toast (11.2) shows the challenge and its XP/currency; the item itself is announced by the
  entitlement record's grant toast (`PW_UnlockGranted`, source `challenge`), so the item is never announced twice.

### 6.3 Custom event types from modes and addons

- [ ] An addon declares `PW.Challenges.RegisterEventType("pw_infection:survive", { fields = { role = "string" } })` and
  calls `PW.Challenges.Report({ type = "pw_infection:survive", player = ply, data = { role = "human" } })` at the end
  of a round where the player survived as a human. Templates of that addon set
  `Requires = { events = { "pw_infection:survive" }, modes = { "pw_infection" } }`.
- [ ] Ids: `^[%l%d_]+:[%l%d_]+$`, at most 48 bytes; built-in types have no colon. Re-registering replaces (hot reload).
- [ ] `Report` validates `data` against the declared fields (unknown or mistyped fields are dropped with one log line
  per type per session) and never errors into the caller.
- [ ] The custom `Filter` predicate runs through `PW.Call(template, "Filter", ev, params)`. An error disables that
  template until the map changes (`01-extensibility.md` d.15); other templates keep working.

### 6.4 Net messages

Explicit `net.Write*`, no `net.WriteTable`. Client → server through `PW.Net.Receive`.

| Message | Direction | When | Fields |
| --- | --- | --- | --- |
| `pw_challenges_upload` | C→S | `InitPostEntity`, once per connection | `count` UInt(3), `count` × (`label` string, `index` UInt(32), `items` UInt(5), `items` × (`id` string, `n` UInt(3), `n` × UInt(20), `done` bool)). `PW.Net.Receive`: `who = "any"`, rate 0.5, `maxLen` = `UploadMaxBytes` (computed from the bounds, below 8 KB), owner = the module; accepted once per connection |
| `pw_challenges_state` | S→C owner | After the upload, on week change, at `PW_MatchStart` | `label` string, `index` UInt(32), `startsAt` UInt(32), `endsAt` UInt(32), `bonusNeeded` UInt(4), `bonusDone` bool, bonus reward, `count` UInt(4), `count` × instance (`id`, `template` string, `tier` UInt(2), `params` UInt(3) × (`key`, `value` string), `n` UInt(3) × (`target` UInt(20), `value` UInt(20)), `done` bool, reward) |
| `pw_challenges_progress` | S→C owner | Dirty instances, at most once per `ProgressInterval` per player, at once on a completion, and on every phase change | `count` UInt(4) × (`id` string, `n` UInt(3) × `value` UInt(20), `done` bool) |
| `pw_challenges_delta` | S→C owner | With the progression flush cadence (10 s, phase change, completion) | `session` UInt(32), `seq` UInt(32), `label` string, `index` UInt(32), `count` UInt(5) × (`id` string, `n` UInt(3) × UInt(20), `done` bool), `bonus` bool. Absolute values, applied in batch order, duplicates (same session, seq not above the last) ignored |

Reward encoding: `xp` UInt(24), `currency` UInt(20), `items` UInt(3) × (`kind` string, `id` string, `weapon` string or
empty). Values above a field's range are clamped on encode.

### 6.5 Dev console commands (server)

Privilege `pw.challenges.dev` (default `superadmin`, `PW.Privilege`) **and** server setting `challenges.dev` true
(default false). Every command logs one line.

- [ ] `pw_challenges_list [player]`: the session week, instances, progress.
- [ ] `pw_challenges_week <offset|YYYY-Www|now>`: overrides the session week index for this server session (dev only;
  lost on map change); `now` clears the override.
- [ ] `pw_challenges_complete <instanceId|bonus> [player]`: completes and rewards through the normal path (claims
  still idempotent).
- [ ] `pw_challenges_reset [player]`: clears session progress of the session week for that player and queues a delta
  writing empty counters; claims in the entitlement ledger are not touched (a re-completion grants nothing).

### 6.6 Settings (module `challenges`, `01-extensibility.md` d.17)

| Id | Scope | Type | Default (proposed) | Range | Meaning |
| --- | --- | --- | --- | --- | --- |
| `challenges.perweek` | server | int | 5 | 1 to 12 | Challenges per week |
| `challenges.bonusneeded` | server | int | 4 | 0 to 12 | Completions for the weekly bonus; 0 = no bonus; clamped to the week's item count |
| `challenges.seed` | server | int | 0 | 0 to 2147483646 | Host seed; hosts with equal seeds and content share weeks |
| `challenges.dev` | server | bool | false | | Enables the dev commands |

## 7. Initial content (starter pool)

Files `lua/privatewar/challenges/<id>.lua`. All targets and rewards are proposed defaults; rewards use the tier
defaults of 3.5 unless stated. Every template uses only events that exist or that this record adds.

| # | Id | Text | Event and filters | Scope | Targets e / m / h | Requires |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | `kills` | Get {target} kills | `kill` | cumulative | 30 / 75 / 150 | none |
| C2 | `headshots` | Get {target} headshot kills | `kill`, `headshot = true` | cumulative | 10 / 25 / 60 | none |
| C3 | `kills_category` | Get {target} kills with {param.category} weapons | `kill`, `category = "{param.category}"`; `Params.category.source = "categories"` | cumulative | 15 / 40 / 80 | `categories` non-empty |
| C4 | `headshots_category` | Get {target} headshots with {param.category} weapons | `kill`, `headshot`, `category` param | cumulative | 5 / 15 / 30 | same |
| C5 | `kills_weapon` | Get {target} kills with the {param.weapon} | `kill`, `weapon` param (`source = "weapons"`, guns only) | cumulative | 10 / 25 / 50 | none |
| C6 | `kills_mode` | Get {target} kills in {param.mode} | `kill`, `mode` param (`source = "modes"`) | cumulative | 25 / 60 / 120 | none |
| C7 | `kills_playlist` | Get {target} kills in any playlist | `kill`, `playlist = true` | cumulative | 25 / 60 / 120 | `playlists` listed |
| C8 | `longshots` | Get {target} kills from 30 m or more | `kill`, `distanceMin = 30` | cumulative | 5 / 15 / 30 | none |
| C9 | `hipfire` | Get {target} hipfire kills | `kill`, `ads = false` | cumulative | 10 / 25 / 50 | none |
| C10 | `captures` | Capture {target} flags in Domination | `objective`, `objective = "capture"` | cumulative | 5 / 15 / 30 (medium, hard only in practice; all tiers allowed) | `modes = { "dom" }` |
| C11 | `hardpoint_time` | Hold the Hardpoint for {target} seconds | `objective_time`, `Count = "value"` | cumulative | 60 / 180 / 400 | `modes = { "hardpoint" }`, D-WC7 |
| C12 | `kc_confirms` | Confirm or deny {target} tags in Kill Confirmed | `objective`, `objective = { "confirm", "deny" }` | cumulative | 10 / 25 / 50 | `modes = { "kc" }` |
| C13 | `snd_plants` | Plant or defuse the bomb {target} times | `objective`, `objective = { "plant", "defuse" }` | cumulative | 2 / 5 / 10 | `modes = { "snd" }`, D-WC3 |
| C14 | `streaks_earned` | Earn {target} killstreaks | `streak_earned` | cumulative | 3 / 8 / 15 | D-WC4 |
| C15 | `streak_kills` | Get {target} kills with killstreaks | `kill`, `streakKill = true` | cumulative | 3 / 10 / 20 | D-WC4, `kinds = { streaks = ... }` any lethal streak |
| C16 | `medals_multikill` | Earn {target} double or triple kill medals | `medal`, `medal = { "double_kill", "triple_kill" }` | cumulative | 3 / 8 / 15 | none |
| C17 | `wins` | Win {target} matches | `match_end`, `won = true` | cumulative | 2 / 5 / 10 | none |
| C18 | `matches_played` | Finish {target} matches in {param.mode} | `match_end`, `mode` param | cumulative | 2 / 4 / 8 (easy, medium only) | none |
| C19 | `match_kills` | Get {target} kills in a single match | `kill` | match | 15 / 25 / 40 (medium, hard) | none |
| C20 | `life_kills` | Get {target} kills without dying | `kill` | life | 5 / 8 / 12 (medium, hard) | none |
| C21 | `quick_kills` | Get 2 kills within 10 seconds, {target} times | `kill`, `Within = { count = 2, seconds = 10 }` | cumulative | 5 / 12 / 25 | none |
| C22 | `combo_objective` | Get {target1} kills and {target2} captures in Domination | `Objectives`: `kill` + `mode = "dom"`; `objective = "capture"` | cumulative | (20, 3) / (40, 8) / (80, 15) | `modes = { "dom" }` |
| C23 | `win_streak` | Win {target} matches in a row | `match_end`, `won = true`, `ResetOn = { { Event = "match_end", Filters = { won = false } } }` | cumulative | 2 / 3 / 4 (hard only) | none |

- [ ] Groups: C1/C6/C7 group `kills`; C2/C4 `headshots`; C3/C5 `weapon_kills`; C19/C20/C21 `skill_kills`; C10/C11/C12/C13
  /C22 `objective`; C14/C15 `streaks`; C17/C18/C23 `matches`.
- [ ] Tier rewards per 3.5; hard C23 and C22 add `items` only after the bonus pool exists (left empty in the first
  version).
- [ ] Existing tiers of C2, C8, C10, C15, C20 and C17 also grant `cards:challenge_headshots`,
  `cards:challenge_longshots`, `cards:challenge_captures`, `cards:challenge_streak_kills`,
  `cards:challenge_life_kills` and `cards:challenge_wins`, respectively. This adds no new tiers.
  The [calling-card definitions](../done/calling-card-kill-banner.md) are needed for integration of the rewards, not for
  the earlier progress, storage or event steps.
- [ ] Display names for params: categories from a fixed table in the module (`ar` → "assault rifle", `smg` → "SMG",
  `shotgun` → "shotgun", `pistol` → "pistol", `special` → "special"; unknown → the id); weapons and modes from their
  registry `Name`.

## 8. Files to create or modify

Paths verified in the repository; new files marked (new). Lane in brackets.

- [ ] (new) `addons/privatewar/lua/privatewar/kinds/challenges.lua` [progression]
- [ ] (new) `addons/privatewar/lua/privatewar/challenges/*.lua`, 23 templates of section 7 [progression]
- [ ] (new) `addons/privatewar/lua/privatewar/modules/challenges/shared.lua`: `MODULE`, `PW.Challenges`, settings,
  constants, `RegisterEventType`, includes the `sh_` files [progression]
- [ ] (new) `.../modules/challenges/sh_template.lua`: validation, compilation, placeholder text [progression]
- [ ] (new) `.../modules/challenges/sh_filters.lua`: the vocabulary of 3.3 as comparator builders [progression]
- [ ] (new) `.../modules/challenges/sh_rotation.lua`: week math and `_Select` [progression]
- [ ] (new) `.../modules/challenges/sh_progress.lua`: pure apply of an event to a player's progress (scopes, Within,
  ResetOn, completion) [progression]
- [ ] (new) `.../modules/challenges/sh_storage.lua`: file shape, clamp, migration, delta apply [progression]
- [ ] (new) `.../modules/challenges/sh_wire.lua`: encode/decode of the four messages over an injected writer/reader
  [progression]
- [ ] (new) `.../modules/challenges/sh_view.lua`: pure view models for the screen and the toast (text, fractions,
  countdown) [progression]
- [ ] (new) `.../modules/challenges/init.lua`: server glue (hook listeners, session week, flush timer, net send)
  [progression]
- [ ] (new) `.../modules/challenges/sv_events.lua`: event normalization from hooks [progression]
- [ ] (new) `.../modules/challenges/sv_rewards.lua`: claim check, reward queueing through `PW.Unlocks` and progression
  [progression]
- [ ] (new) `.../modules/challenges/sv_dev.lua`: dev commands [progression]
- [ ] (new) `.../modules/challenges/cl_init.lua`: receive state, progress and delta; file write; upload [progression]
- [ ] (new) `addons/privatewar/lua/privatewar/types/challenges.lua` (`---@meta`, every type of sections 3 and 6)
  [progression]
- [ ] (new) `addons/privatewar/lua/privatewar/screens/progress_challenges.lua` [feature UI part, built with the kit]
- [ ] (new) `addons/privatewar/lua/privatewar/hud/challenges.lua` [feature UI part]
- [ ] (new) `addons/privatewar/lua/privatewar/score_events/snd_plant.lua`, `snd_defuse.lua` [progression; D-WC3]
- [ ] (new) `addons/privatewar/lua/tests/privatewar/challenges_*.lua` (section 10)
- [ ] (new) `docs/api/challenges.md` [orchestrator]
- [ ] (modify) `addons/privatewar/lua/privatewar/modules/score/init.lua`, `types/score.lua` [modes; D-WC2]
- [ ] (modify) `addons/privatewar/lua/privatewar/modules/match_rules/init.lua` [modes; D-WC2]
- [ ] (modify) `addons/privatewar/lua/privatewar/modules/snd/sh_round.lua`, `modes/snd.lua` [modes; D-WC3]
- [ ] (modify) `addons/privatewar/lua/privatewar/modules/streaks/init.lua`, `types/streaks.lua` [loadout; D-WC4]
- [ ] (modify, optional) `addons/privatewar/lua/privatewar/modules/hardpoint/init.lua` [modes; D-WC7]
- [ ] (modify) `addons/privatewar/lua/privatewar/screens/progress_home.lua`: a "WEEKLY CHALLENGES" entry that pushes
  `progress_challenges` [ui; D-WC9]
- [ ] (modify) `docs/api/modes.md`, `docs/api/streaks.md`, `docs/api/progression.md` (rewards), `docs/api/ui.md`
  (screen and element), `docs/api/README.md` (new row) [orchestrator]
- [ ] (modify) `TASKS.md` (task row, lanes row, mandatory cases), `docs/agent-test-map.md`, `changes/INDEX.md` (only
  when the record moves) [orchestrator]
- [ ] (modify, after approval) `design/06-progression.md`, `design/09-hud.md`, `design/10-frontend.md` [orchestrator]
- [ ] Every new Lua file stays under 500 lines and every function under 60 lines (`make rules`).

## 9. Implementation steps (TDD; one commit per step)

Each step: write the listed tests first and see them fail, implement, run `nix develop --command make check`, commit
with `git commit --signoff` and the `Assisted-by: LLM` trailer.

1. [ ] Types and kind: `types/challenges.lua`, `kinds/challenges.lua`, empty module `shared.lua`. Test: the kind is
   declared and a fixture template registers. Commit `feat(challenges): declare the challenges kind and types`.
2. [ ] Week math (`sh_rotation.lua`: `WeekIndex`, `WeekLabel`, `WeekBounds`) with the test vectors of 5.1. Commit
   `feat(challenges): add UTC week math with ISO labels`.
3. [ ] Template validation and compilation (`sh_template.lua`, `sh_filters.lua`): every filter key, rejections,
   placeholders. Commit `feat(challenges): validate and compile challenge templates`.
4. [ ] Selection `_Select` (5.2): determinism, tier mix, groups, weights, params, bonus pick. Commit
   `feat(challenges): select weekly challenges deterministically`.
5. [ ] Progress engine (`sh_progress.lua`): scopes, `Within`, `ResetOn`, multi-objective, completion once. Commit
   `feat(challenges): track objective progress with scopes`.
6. [ ] Storage and wire (`sh_storage.lua`, `sh_wire.lua`): clamp, migration, malformed files, delta idempotency,
   encode/decode bounds. Commit `feat(challenges): add the client file and wire format`.
7. [ ] Score context (D-WC2; modes lane files): `PW.ScoreOpts.context`, sixth argument, `ScoreKill` context. Tests in
   `score.lua` and `match_rules.lua` (new cases; existing ones unchanged). Commit
   `feat(score): pass kill context with score events`.
8. [ ] S&D plant/defuse score events (D-WC3) with cases in `mode_snd.lua`/`snd_runtime.lua`. Commit
   `feat(snd): award plant and defuse score events`.
9. [ ] Streak notifications (D-WC4) with cases in `streaks.lua`. Commit `feat(streaks): notify streak earned and used`.
10. [ ] Server glue (`init.lua`, `sv_events.lua`): normalization, bots excluded, session week, match freeze, dirty set,
    throttled sends, upload once. Commit `feat(challenges): track challenges from match events`.
11. [ ] Rewards (`sv_rewards.lua`) on top of the landed entitlement API: claims, XP, currency, items, duplicates, bonus,
    flush. Commit `feat(challenges): grant rewards once through entitlements`.
12. [ ] Custom events and `Report` (6.3) plus `PW_ChallengeCanCount`. Commit `feat(challenges): accept custom events
    from modes and addons`.
13. [ ] Client (`cl_init.lua`): state, progress, delta apply and file write, upload. Commit
    `feat(challenges): store challenge progress on the client`.
14. [ ] Starter pool (section 7) with a registry test that every template validates and each tier has enough
    candidates. Commit `feat(challenges): add the starter challenge pool`.
15. [ ] View models (`sh_view.lua`), screen `progress_challenges.lua`, `progress_home.lua` entry. Commit
    `feat(ui): add the weekly challenges screen`.
16. [ ] HUD toast `hud/challenges.lua`. Commit `feat(hud): show challenge progress and completion toasts`.
17. [ ] Dev commands (`sv_dev.lua`). Commit `feat(challenges): add guarded dev commands`.
18. [ ] Optional hardpoint time (D-WC7). Commit `feat(hardpoint): report objective time to challenges`.
19. [ ] Docs: `docs/api/challenges.md` and the contract updates (orchestrator). Commit
    `docs(api): document weekly challenges`.

## 10. Mandatory test cases

Pure unless marked "in-game". Case names are exact; file names are proposed.

`addons/privatewar/lua/tests/privatewar/challenges_rotation.lua`:

- [ ] `Week: index and ISO label for the verified vectors including 2026-W53 and 2027-W01`
- [ ] `Week: bounds start Monday 00:00 UTC and last seven days`
- [ ] `Rotation: the same week, seed and pool give the same set regardless of registry order`
- [ ] `Rotation: a different week gives a different set (over 20 consecutive weeks at least 15 distinct sets)`
- [ ] `Rotation: year boundary weeks 2026-W53 and 2027-W01 are distinct and deterministic`
- [ ] `Rotation: no template twice in a week and groups are not repeated unless a tier would stay empty`
- [ ] `Rotation: tier mix for 1, 3, 5 and 8 challenges`
- [ ] `Rotation: weights bias selection and a zero-candidate tier falls back to an easier tier`
- [ ] `Rotation: parameters bind deterministically and unavailable values are never chosen`
- [ ] `Rotation: dots are reserved for instance id separators`
- [ ] `Rotation: a different host seed changes the set`

`challenges_filters.lua`:

- [ ] `Filters: mode, modeBase and playlist match scalars, sets, lists and the playlist true/false forms`
- [ ] `Filters: weapon, category, weaponKind and attachment`
- [ ] `Filters: headshot, ads, crouch, airborne, explosive, streakKill and streak`
- [ ] `Filters: distanceMin and distanceMax are inclusive and in metres`
- [ ] `Filters: lifeKillsMin, aliveTimeMax and valueMin`
- [ ] `Filters: event, medal and objective`
- [ ] `Filters: won, draw and placementMax on match_end and round_end`
- [ ] `Filters: suicide on death and data on custom events`
- [ ] `Filters: an absent event field never matches`
- [ ] `Templates: unknown filter keys, bad targets, missing tiers and both Objectives and Event are rejected`
- [ ] `Templates: param placeholders are substituted in filters and text`

`challenges_progress.lua`:

- [ ] `Scope: cumulative counts across matches`
- [ ] `Scope: match resets at match start and keeps the best run`
- [ ] `Scope: round resets at round start and acts as match without rounds`
- [ ] `Scope: life resets on death and team change and keeps the best run`
- [ ] `Within: count events inside the window add one and the window clears`
- [ ] `ResetOn: a matching event resets the run; a completed challenge never regresses`
- [ ] `Objectives: all and any combinations complete correctly`
- [ ] `Count: value adds ev.value`
- [ ] `Completion fires once per player, instance and week`
- [ ] `Bonus: the weekly bonus completes after bonusneeded completions and only once`

`challenges_storage.lua`:

- [ ] `Storage: file round trip for version 1`
- [ ] `Storage: malformed, missing and non-table files read as empty`
- [ ] `Storage: unknown version newer than known is not rewritten`
- [ ] `Storage: bounds clamp counters, ids, labels, weeks and items`
- [ ] `Storage: migration maps a missing version to an empty file`
- [ ] `Storage: delta apply is idempotent per batch id and applies absolute values in order`
- [ ] `Storage: upload keeps only the session week, clamps to targets and ignores unknown ids`
- [ ] `Storage: progress of an expired week is ignored and not deleted by the server`
- [ ] `Wire: upload, state, progress and delta survive encode and decode`
- [ ] `Wire: forged counts cannot read past the size bound`

`challenges_server.lua` (server glue over injected stores, fake players and bots; in-game where marked):

- [ ] `Events: bots never progress and bot victims count for humans`
- [ ] `Events: kill context reaches the matcher from PW_ScoreEvent`
- [ ] `Events: events outside LIVE are dropped; match_end is processed at PW_MatchEnd`
- [ ] `Events: PW_ChallengeCanCount false drops the event`
- [ ] `Week: a match counts into the week it started in across a Monday boundary`
- [ ] `Week: a backwards clock jump keeps the session week; a forward jump selects the new week`
- [ ] `Custom: Report validates type and data; an erroring Filter is isolated through PW.Call and other templates count`
- [ ] `Net: progress messages are throttled to one per interval per player and completions flush at once`
- [ ] `Net: the upload is accepted once per connection and bounded` (bot sender, `PW.Net.Receive` handler called
  directly)
- [ ] `Perf: one kill event touches only objectives of its type` (counts matcher calls with a stub)

`challenges_rewards.lua`:

- [ ] `Rewards: completion queues XP, currency and items once with the claim id`
- [ ] `Rewards: an existing claim grants nothing across reconnect and module reload`
- [ ] `Rewards: an owned or unresolved item pays duplicateCurrency`
- [ ] `Rewards: economy disabled skips currency only`
- [ ] `Rewards: the weekly bonus uses its own claim id and is granted once`
- [ ] `Rewards: a reward flushes the progression delta at once`

Existing files (new cases, existing cases unchanged):

- [ ] `score.lua`: `Award passes opts.context as the sixth PW_ScoreEvent argument and old listeners still work`
- [ ] `match_rules.lua`: `ScoreKill builds one kill context with victim, headshot, distance and stance facts`
- [ ] `mode_snd.lua` or `snd_runtime.lua`: `SND: a completed plant or defuse awards its score event to the actor once`
- [ ] `streaks.lua`: `Streaks: earned and activated notifications fire once with the streak id`

`challenges_view.lua`:

- [ ] `View: rows hold text with placeholders filled, fraction, tier, scope text and reward summary`
- [ ] `View: countdown text for days, hours and minutes, never negative`
- [ ] `View: bonus card shows completed of needed and the reward`
- [ ] `Toast: milestones at 25, 50 and 75 percent and completion; no toast for unchanged values; queue limit`

The automated cases never replace the human checkpoint (section 14).

## 11. UI spec

### 11.1 Screen `progress_challenges` (`Tab = "progress"`, not a root, pushed from `progress_home`)

- [ ] Layout with `PW.UI.Layout.Columns` like `progress_home` (left 520, right 560 design units). Left: week card
  ("WEEK 47 · 2026"), countdown "Resets in 2d 14h" (local time computed from `endsAt` and `os.time()`; refreshed every
  30 s), bonus card ("BONUS 2 / 4", progress bar, reward preview with item names through the entitlement `Describe`).
  Centre: a `PWCardList` with one card per challenge: tier badge (`EASY`, `MEDIUM`, `HARD`, palette tokens only),
  name, description, progress bar with "12 / 25", a check mark when done, reward line ("+5 000 XP · 100 CR").
  Right: details of the selected challenge: per-objective bars for multi-objective challenges, scope text ("in a
  single match", "without dying", "within 10 seconds"), requirements ("Domination only"), reward items.
- [ ] Empty states: module off ("Weekly challenges are off on this server."), no state yet ("Waiting for the host…"),
  zero instances ("No challenges available with the installed content.").
- [ ] Data only from `PW.Challenges.GetWeek()` and `GetProgress(LocalPlayer(), id)`; refresh on
  `PW_ChallengesChanged` and every 2 s at most; no allocation per frame beyond the kit's normal paint.
- [ ] Controller and keyboard: up/down moves the focus in the card list (`PW.UI.Focus`), left/right crosses to the bonus
  card and the details by geometry, `accept` toggles details, `back` pops to PROGRESS. Hints: `{ accept = "Details",
  back = "Back" }`. Works with Steam Input on the Deck (keys).
- [ ] `progress_home` gets one focusable "WEEKLY CHALLENGES · 3 / 5" card in the left column that pushes the screen.

### 11.2 HUD element `challenges` (`hud/challenges.lua`)

- [ ] `Order = 32`, phases `LIVE`, `POSTMATCH`. Position top right (radar and scoreboard are top left, medals centre),
  width 420 design units, below the top edge by 120.
- [ ] Progress toast at milestones (25, 50, 75 %, only for targets ≥ 4): "HEADHUNTER 13 / 25", small bar, 2.5 s.
  Completion toast: larger, accent colour, "CHALLENGE COMPLETE", the name and the reward line, 4 s, sound
  `buttons/bell1.wav` (stock). Bonus toast: "WEEKLY BONUS EARNED" with the item name.
- [ ] Queue of at most 3 entries; merges repeated milestones of the same instance; drops older milestones when a
  completion arrives. Pure queue rules in `sh_view.lua`.
- [ ] No allocation in `HUDPaint`; fonts and colours from `PW.UI.Style`; scale with `PW.HUD.S`.

### 11.3 Postmatch (optional, after the screen lands)

- [ ] A "Challenges" row in the postmatch summary: completions this match and the biggest progress gain (data from the
  client state); ui lane change through the orchestrator.

## 12. Performance budget

- [ ] Event handling is O(k) per event, k = active objectives of that event type for that player (≤ 12 for 5
  challenges with up to 4 objectives; usually 1 to 3), through `byType[type]` built once per week change.
- [ ] Filters are precompiled comparator closures; no string building, no `table.concat`, no registry lookup per
  event except one catalogue lookup for the weapon category, cached per weapon class for the map.
- [ ] No `Think`/`Tick` hook during `LIVE`. One 60 s timer outside `LIVE`. One flush per player at most per second
  for progress and on the 10 s progression cadence for the delta.
- [ ] Network: at most one `pw_challenges_progress` per player per second (~ ≤ 100 bytes); state ≤ 2 KB.
- [ ] Target: ≤ 0.05 ms server time per kill event on the Deck (all challenge work, measured with the profiler,
  `PW.Call` timings and `SysTime()` around the listener over a 10-minute bot match). Verification: the measurement and
  the case `Perf: one kill event touches only objectives of its type`; a result is written to the change evidence, not
  claimed in advance.

## 13. Open questions for the user (recommended defaults)

1. [ ] Challenges per week: recommended 5 (2 easy, 2 medium, 1 hard); bonus after 4 of 5.
2. [ ] Reset day and time: recommended Monday 00:00 UTC (same as the store's weekly rotation). CoD uses a weekday
   midday reset in US time; a UTC boundary is simpler and matches the existing store.
3. [ ] Progress per host or travelling with the client: recommended travelling with the client (`challenges.json`,
   like progression, d.5); progress continues on a friend's host only for instances that host also selected.
4. [ ] Rerolls: recommended none in the first version; later one reroll per week stored in the file (Cold War style).
5. [ ] Catch-up of missed weeks: recommended none (a past week expires); seasonal sets later through `Pool`.
6. [ ] Rewards: are the tier XP/currency values acceptable; which cosmetics form the bonus pool (needs content: camos,
   cards, operators flagged as challenge rewards in the entitlement record)?
7. [ ] S&D plant/defuse as score events with 100 points (D-WC3) or challenge-only events?
8. [ ] Should challenges count with `progression.unlockall` on and against `recruit` bots? Recommended yes (casual
   game; progression is forgeable anyway).
9. [ ] Host seed: keep one shared default (0) so friends see the same weeks, or let each host vary it? Recommended
   default 0, host-changeable.

## 14. Gates and checkpoints

- [ ] `set -o pipefail; nix develop --command make check` passes (glualint, lua-language-server, markdownlint, rules,
  agent guides).
- [ ] `set -o pipefail; nix develop --command make test` passes. Game tests need explicit user permission and
  confirmation that the Steam Deck is free; without them, report game tests skipped and the merge gate incomplete.
- [ ] Human checkpoint (`CP-WC`, items for the local manual checklist; the user tests in GMod):
  1. The PROGRESS tab shows the WEEKLY CHALLENGES entry; the screen lists the week, countdown, bonus and five cards,
     readable at 1280×800 on the Deck, navigable with the controller.
  2. Headshot, kill-in-mode and weapon-category challenges progress in a bot TDM match; toasts appear at milestones
     and on completion without overlapping medals or the LEVEL UP popup.
  3. A single-match and a without-dying challenge reset correctly.
  4. Completion grants XP, currency and an item once; rejoining and a map change do not grant again.
  5. Two humans on a listen server progress independently; bots never show progress.
  6. Dev commands work only for the host with `challenges.dev` on; `pw_challenges_week` shows a different set.
  7. Progress survives a map change and a game restart.
- [ ] User acceptance is recorded separately; automated results do not replace it.

## Evidence and links

- Research: [notes/32-weekly-challenges-research.md](../../notes/32-weekly-challenges-research.md).
- Dependency: [unlock entitlements](../done/unlock-entitlements.md) and
  [notes/31-unlock-entitlements-research.md](../../notes/31-unlock-entitlements-research.md).
- Related: [scheduled events](../in-progress/scheduled-events.md) (UTC handling, playlist availability), store rotation
  `addons/privatewar/lua/privatewar/modules/economy/sh_rotation.lua`, `design/06-progression.md` d.0, d.1, d.3, d.5, d.6.
- Verification of the early scope and design commit is recorded above. The remaining implementation and full
  feature gates are pending.
