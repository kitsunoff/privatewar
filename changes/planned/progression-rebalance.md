# Progression rebalance: pacing, attachment spread and long tail

Status: `planned`

Recorded: 2026-11-22

## Goal and scope

Rebalance account levels, weapon levels and unlock distribution so progression sits between two failure modes the
maintainer named: the "Forza Horizon problem" (a reward flood where nothing feels earned) and the "WoW 1x server" (so
slow that players quit first). Target audience: solo or 2–4 friends against bots, often short Steam Deck sessions,
free, no monetization, no FOMO.

In scope: account XP curve and level count, weapon XP curve and level cap, the automatic attachment and weapon spread
(`autounlock`), a long tail after the core unlocks, catch-up bonuses, local pacing telemetry and a pure pacing
simulation. Out of scope (separate records, built on `unlock-entitlements` and `weekly-challenges`): weapon camo
challenges, a season pass framework.

**This record is not approved for implementation.** Every question in "Questions for the maintainer" must be answered
first; the answers are then written into the "Decisions" section with a date, and `design/06-progression.md` is
updated only with explicit approval.

## Research

- [notes/34](../../notes/34-progression-psychology.md): psychology of reward pacing (goal gradient, hedonic
  adaptation, SDT/PENS, crowding-out, FOMO, stopping points).
- [notes/35](../../notes/35-progression-industry-practice.md): GDC talks, Call of Duty progression, Forza, WoW, Halo
  Infinite, Deep Rock Galactic, XP curve formulas, unlock distribution, long tails.
- [notes/36](../../notes/36-progression-player-data.md): motivation surveys, questionnaires (miniPXI, BANGS), session
  length, sentiment, playtest methods.
- [notes/37](../../notes/37-progression-pacing-synthesis.md): synthesis and options; read it first.

## Current state (verified on `main` 2026-11-22)

1. `addons/privatewar/lua/privatewar/modules/progression/sh_curves.lua:10`: `maxLevel = 55`, player XP to next level
   `1000 × L^1.2`, `maxWeaponLevel = 30`, weapon XP to next level `500 × L^1.1`; exponents are server settings
   (`modules/progression/shared.lua:26`, `:30`).
2. `design/06-progression.md:80` says "about 12 000 at level 55"; the formula gives about 122 600. The code follows
   the formula.
3. Attachment clump root cause: `modules/autounlock/sh_rules.lua` `_SlotLevels` (line 170) spreads each slot's options
   independently over `1..30` via `_Spread` (line 137); one option per slot lands on level 16, options without stats
   on the slot middle (16). Nothing opens at weapon level 1, most first options meet at 16–17.
4. Maintainer playtest feel: about 2 matches per account level at level 12, about 3–4 matches per weapon level.
   Derived (calculation, notes/35 section 7): about 9 900 XP per match, about 300 matches from 1 to 55, about 160
   matches to weapon level 30 for one weapon, about 12 matches for account level 54 alone.

## Questions for the maintainer

Each question lists the options and, where research supports one, a recommendation. A recommendation is not a
decision.

### A. Time budget and measurement

1. **Average match length per mode, in minutes** (TDM, Domination, Hardpoint, S&D, others). All pacing math depends
   on it. No default; measure or estimate.
2. **Target player profile:** A — about 2 h per week, at least one unlock per 30–45 minute session; B — about 5 h per
   week; C — hybrid: fast start, weekly goals sized for about 2 h, catch-up for missed time. Recommendation: C or A
   (notes/36 section 8; median PC session about 18 minutes).
3. **Target time to finish the gameplay unlocks**, in *sessions* (not matches): for the account core and for one
   typical weapon. No default; the research supports pacing per session (notes/34 Q1, notes/35 Q2).
4. **Measure before tuning?** Build a local JSON pacing log (XP per match, levels, unlocks, match length, quit point)
   and a pure simulation ("after N matches the player has X") before changing curves. Recommendation: yes.
5. **Telemetry scope:** opt-in for players and stays on the player's machine, or dev builds only. Recommendation: dev
   builds plus opt-in local log; never sent anywhere.
6. **Playtest:** how many testers for two weeks, and will they answer a 1–2 minute survey (5 items, or miniPXI with
   11 items) after each session?

### B. Account levels

7. **Structure:** one long count (500–1000 levels), or a finite core (1–55, all gameplay unlocks) plus a long tail
   with flat cost and milestone rewards? Recommendation: core plus tail; every 500–1000-level system in Call of Duty is
   two-part (notes/35 section 2, 7.2).
8. **Core length:** keep 55, or derive it from the content count (more weapons → more levels, with a cap on unlocks
   per level)?
9. **Tail:** length (for example 500 or 1000), cost per level (0.5 / 1 / 1.5 matches) and milestone interval (every
   10 / 25 / 50 levels). See the hours table in notes/35 section 7.2.
10. **Prestige reset:** never reset, or optional classic prestige? Recommendation: never take away unlocked content
    (Cold War prestige rationale, Destiny sunsetting, notes/35 section 3 and 6).
11. **Shape of `m(L)` (matches per level):** for example fast early levels (0.5 match), then a smooth rise to a cap
    (2–3 matches), no spikes. Which cap per level is acceptable for a 2-match evening? The current curve reaches
    about 12 matches per level near 54.
12. **Protect existing players:** never make an already started path slower; recompute levels from total XP so
    nobody loses a level? Recommendation: yes (notes/34 section 1).
13. **Design text:** which is the intent at level 55, "about 12 000" or the formula (about 122 600)? Fix
    `design/06-progression.md:80` in the same change?

### C. Weapon levels and attachments

14. **Spread across slots:** rank all options of a weapon together and open about one per level (round-robin by
    slot), instead of per slot. Recommendation: yes; this fixes the clump (notes/35 section 7.1 option 1).
15. **Starter at level 1–2:** open one option at weapon level 1 or 2 so the first unlock arrives in the first match
    with the weapon? Recommendation: yes.
16. **Weapon level cap:** fixed 30, or follow the attachment count (bounded, for example 10..40, padded with
    cosmetics)? (notes/35 Q3, 7.1 option 2.)
17. **Front-loading:** dense unlocks in weapon levels 2–10, sparser later (Battlefield 6 fix, notes/35 section 5)?
18. **Options without stats:** spread them between ranked options instead of the slot middle? Recommendation: yes.
19. **Player choice:** fixed unlock order, or a choice ("armory" / token style, MWIII and BO6) on the Deck UI?
    (notes/34 Q3.)
20. **Weapon spread on account levels:** keep "1–2 per category open, the rest spread over 1..55", or add a cap on
    weapons per level?
21. **Per-weapon tracks for every auto-discovered weapon,** or grouped class mastery so the reward volume does not
    grow with installed packs? (notes/34 Q4.)

### D. Rewards, catch-up and solo play

22. **Catch-up:** rested-style pool (fills while away, doubles the first match or matches), a descending
    first-matches-of-the-day bonus (Halo), or none? Recommendation: rested-style; the daily descending bonus can feel
    like a cut for longer sessions (notes/35 section 7.4).
23. **Unannounced bonuses** (occasional surprise rewards, not random loot): acceptable? Research: unexpected rewards
    do not lower intrinsic motivation (notes/34 section 2).
24. **End-of-session or end-of-match summary** with "next unlock in N" information? Trade-off: strong goal gradient
    versus a near-miss pull (notes/34 Q7).
25. **Long-tail milestone rewards:** which types (calling cards, camos, titles, kill-card frames) and how many assets
    can realistically be produced?
26. **Where the best rewards sit:** most players never finish a game (notes/36 section 5). Move the best rewards
    earlier, or keep them at the end and frame them as long-term goals?
27. **Calling cards for co-op friends:** bots are not an audience; should friends see your card in other places
    (scoreboard, lobby)? (notes/34 Q6.)
28. **Variable weapon set:** how mastery camos and challenges count weapons when the installed set varies — counts
    per category ("gold on 5 rifles"), a collection score that grows with content, or per weapon only? (notes/35 Q5;
    belongs partly to the camo challenge record.)
29. **Weekly challenges:** expire weekly, roll over, or bank (for example up to 3 weeks)? (notes/36 Q3; coordinate
    with `weekly-challenges`.)

## Decisions

None yet. Write each answer here as `Qn: answer (date)` before any implementation step starts.

## Draft step plan (after the decisions; each step TDD, pure functions in `sh_` files)

1. Pacing telemetry log and pure simulation (if Q4 is yes). Mandatory cases: simulation reproduces the current curve
   numbers in "Current state"; log records match length and unlocks.
2. Cross-slot attachment spread (Q14–Q18). Mandatory cases: one option per level across slots; starter at level 1–2;
   no level receives more than the configured number of options; unranked options spread; deterministic order.
3. Weapon level cap from content (if Q16 says so).
4. Account curve retune from `m(L)` (Q7–Q13), with migration that never lowers a level.
5. Long tail and milestone rewards (Q9, Q25) through `PW.Unlocks.Grant`.
6. Catch-up bonus (Q22).
7. UI: session or match summary (Q24), progress display for the tail.

## Human checkpoints (to be filled when the plan is approved)

- [ ] First weapon unlock arrives within the first match with a new weapon.
- [ ] No weapon level grants a visible flood of attachments.
- [ ] An evening of two matches always shows visible progress.
