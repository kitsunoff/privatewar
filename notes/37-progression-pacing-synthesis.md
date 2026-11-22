# 37 — Progression pacing: synthesis for the rebalance

Status: research (2026-11-22). Research explains *why*; it is not a decision. Where this note and `../design/` disagree,
`design/` wins. This note combines [34](34-progression-psychology.md) (psychology),
[35](35-progression-industry-practice.md) (industry practice and curve math) and
[36](36-progression-player-data.md) (player data). Evidence strength and sources live in those notes; this note cites
them by section.

## Question

How should Private War pace account levels, weapon levels and unlocks so that it avoids both the "Forza Horizon
problem" (a reward flood where nothing feels earned) and the "WoW 1x server" (so slow that players quit first), for a
free game played solo or with 2–4 friends against bots, often in short Steam Deck sessions?

## 1. Current state (code facts, verified 2026-11-22 on `main`)

1. **Curves.** `modules/progression/sh_curves.lua:10`: `maxLevel = 55`, player XP to next level `1000 × L^1.2`,
   `maxWeaponLevel = 30`, weapon XP to next level `500 × L^1.1`. The exponents are server settings
   (`modules/progression/shared.lua:26`, `:30`).
2. **Design text is wrong about the curve.** `design/06-progression.md:80` says "about 12 000 at level 55";
   `1000 × 55^1.2` is about 122 600. The code follows the formula.
3. **Attachment clump, root cause.** `modules/autounlock/sh_rules.lua`: `_SlotLevels` (line 170) spreads the options
   of *each slot independently* over `1..cap` with `_Spread(n, 0, cap)` (line 137), level
   `1 + round((cap - 1) · i / (n + 1))`. With `cap = 30`, a slot with one option lands on level 16, a slot with two
   options on 11 and 20, and options without numeric stats get the slot middle (`round((1 + cap) / 2) = 16` when the
   slot has no ranked options). Many weapons have many small slots, so most first options of all slots fall near
   16–17 and nothing opens at level 1. The same `_Spread` places weapons inside a category (line 214).
4. **Measured feel (maintainer, 2026-11-22).** At account level 12 one level takes about 2 matches; one weapon level
   takes about 3–4 matches. Note 35 section 7 derives about 9 900 XP per match from that, about 300 matches from 1 to
   55, and about 160 matches to weapon level 30 for one weapon (a calculation, not a measurement).

## 2. Why the two failure modes happen

| Failure | Mechanism | Evidence |
| --- | --- | --- |
| Reward flood (Forza) | Frequent, predictable rewards become background (hedonic adaptation); rewards not tied to an "anchor" (mastery, self-expression) carry no meaning; random rewards feel unearned | 34 §5, §7; 35 §1 (Cook, value chains), §3; 36 §4 (FH6 makes wheelspins rarer) |
| Slow grind (WoW 1x) | Long stretches without a visible next goal; "dead levels" without a meaningful unlock; spikes ("hell levels") in an otherwise smooth curve raise churn | 34 §4 (goal gradient); 35 §3 (Shadowlands squish reasons, DAoC churn spike) |
| Both | Pacing measured in XP instead of in sessions; content count changes but the curve does not | 35 §4 (Koster: matches per level first) |

The current state has both at once: weapon levels 1–15 are "dead levels", then levels 16–17 are a flood.

## 3. Principles the three notes agree on

1. **Pace in sessions, derive XP.** Choose the target number of matches per level `m(L)` first; the XP cost is
   `c(L) = E · m(L)` where `E` is the average XP per match. Changing XP rewards then never changes the feel
   (35 §4).
2. **Always give XP for simply playing a match.** Challenges add on top; they never replace match XP (36 §4 and
   35 §3, Halo Infinite 2021).
3. **Something visible moves every session; something new arrives about every session.** A near, visible next goal
   keeps players going (goal gradient, 34 §4). No industry source gives a numeric cadence rule (35 §5); "one
   meaningful unlock per session" is a derived target, to be checked in playtest.
4. **Frequency is inverse to value.** Small rewards often, notable ones every few sessions, big ones rarely; gameplay
   unlocks one at a time so each can be tried; cosmetics may come more often (34 §5, §7; 35 §5).
5. **Tie rewards to player action and choice.** Earned beats random; choosing what to grind (weapon levels,
   challenges, an "armory"-style pick) supports autonomy (34 §2, §7; 35 §5).
6. **Smooth curve, no spikes, no retroactive slowdown.** Never make an already started path slower; resets never take
   away unlocked content (34 §1; 35 §3, §6).
7. **No FOMO; catch-up instead of speed-up.** Rested XP style bonuses and non-expiring passes fit a solo game; a
   weekly boundary motivates without losses ("fresh start" effect) (34 §6; 35 §3; 36 §3).
8. **Unexpected bonuses are safe; expected material rewards may crowd out intrinsic motivation** (contested, 34 §2).
   Game XP and levels themselves showed no crowding-out in one study (34 §2).
9. **Solo players need self-comparison instead of an audience.** Personal records, a session summary, mastery
   markers; competition motivation falls with age while completion stays (34 §8; 36 §1).
10. **Most players never reach the end.** Rewards at the end of a long track are seen by a minority; put the core
    experience early (36 §5).

## 4. Applying them to Private War (options, not decisions)

### 4.1 Time budget

Session data (36 §5): median PC session about 18 minutes, about 33 minutes per playing day; weekly hours vary widely.
Note 36 section 8 offers three budgets:

| Option | Assumption | Effect |
| --- | --- | --- |
| A | About 2 h per week, at least one unlock per 30–45 minute session | Safe for casual Deck play; long tail must carry long-term players |
| B | About 5 h per week | Core lasts longer; casual players risk the "1x" feeling |
| C | Fast start, weekly goals sized for about 2 h, catch-up for missed time | Combines A's start with a longer middle |

The missing input is the average match length per mode; without it matches cannot be turned into hours.

### 4.2 Account levels: finite core plus long tail

Call of Duty's 500–1000 levels are always two parts: a finite core (1–55) where every gameplay unlock lives, then a
flat-cost long tail with milestone rewards (35 §2, §6). Options:

1. Keep 55 as the core, retune `m(L)` (for example fast early levels, then a gentle rise without spikes), and add a
   long tail with a flat cost per level and a reward every N levels (calling cards, emblems, camos).
2. Make the core length a function of content count (more weapons → more levels with a cap on unlocks per level),
   with the tail on top. More adaptive to Workshop packs, harder to reason about.

Note 35 section 7 estimates, for 10-minute matches: core 1–55 about 96 matches; a 500-level tail at 1 match per
level about 90 h; 1000 levels at 0.5 match per level about 95 h.

### 4.3 Weapon levels and attachments

1. Spread attachments over the weapon's levels *across all slots together*, not per slot: rank all options of the
   weapon, open a starter at level 1–2, then about one option per level. Weapon max level can follow the option
   count instead of a fixed 30.
2. Make the first weapon levels fast (first unlock inside the first match with the weapon), then 1–2 matches per
   level.
3. Options without stats get a defined place (for example spread between ranked options), not the slot middle.

### 4.4 Many weapons from Workshop packs

Requirements like "all weapons" are undefined when content varies per player (35 §7). Fitting patterns: count-based
goals ("gold on 5 rifles"), a collection score that grows with content (Warframe Mastery Rank), camo tied to the
weapon itself.

### 4.5 Rewards in solo play

Session summary at match end (progress beat at a natural stopping point, 34 §9), personal records, mastery camos,
calling cards; unexpected bonuses (first win of the day, rested XP) instead of streak-loss pressure.

### 4.6 Measure before tuning

Minimal plan (36 §7, §8): a local JSON log per match and session (XP gained, levels, unlocks, match length, quit
point), 2–3 testers for two weeks, a five-item post-session survey; miniPXI (11 items) to compare builds, not to
produce exact scores. Optionally a pure simulation function "after N matches the player has unlocked X" with tests.

## 5. Decisions for the maintainer

1. Target time budget: option A, B or C (4.1), and the average match length per mode.
2. Account levels: keep a 55-level core plus a long tail, or a content-driven core (4.2); tail length and reward
   interval.
3. Weapon levels: cross-slot spread with about one option per level and a variable max level (4.3)?
4. Whether to fix the design text in `design/06-progression.md:80` together with the rebalance (requires approval as a
   design change).
5. Catch-up mechanics: rested XP or first-match-of-the-day bonus, or none.
6. Whether to build the local telemetry log and simulation before changing any curve (recommended by 36 §8).

## 6. Suggested follow-up

A change record `changes/planned/progression-rebalance.md` after the decisions above: telemetry and simulation first,
then the cross-slot attachment spread (independent, fixes the clump), then the curve retune and the long tail. Weapon
camo challenges and a season pass framework build on `unlock-entitlements` and `weekly-challenges` and are separate
records.
