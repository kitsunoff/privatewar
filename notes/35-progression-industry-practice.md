# 35 — Progression in industry practice: talks, case studies and XP curves

Status: research (2026-11-22). Research explains *why*; it is not a decision. Where this note and `../design/`
disagree, `design/` wins.

Evidence labels: [talk] conference talk (GDC Vault page or the speaker's own slides), [dev-blog] official developer
or publisher page, [essay] designer essay, [press] games press, [wiki] fan or reference wiki, [forum] player forum.
"Not opened" means the page refused automated fetching (HTTP 403 or timeout) and the claim rests on search snippets
or secondary coverage; such claims are marked inline. Numbers from fan wikis or community estimates are marked as such.

## Question

How do shipped games and their designers pace progression and rewards, what went wrong and right, and how are XP
curves built mathematically? The goal is input for a Private War progression that sits between a reward flood
("Forza Horizon problem") and a very slow grind ("WoW 1x server"), for short solo or co-op sessions against bots.

## 1. Conference talks and designer essays

### 1.1 Raph Koster, "Gritty Systems Design for Retention", Austin Game Conference 2016 [talk]

Slides and the author's blog post [1], [2]. This is the most directly useful source for XP curves.

- **Pace is the number of encounters per level, not the XP number.** An exponential XP curve can feel flat if XP per
  encounter grows with it; what the player feels is "number of kills per level". A game can even get easier as the
  player advances if encounter rewards grow faster than the curve [2].
- **His recommended method ("the right way")**: define level distances as a smooth ramp of *successful encounters*;
  pick any visually pleasing XP curve (for example "a 1.2x increase per level"); set XP per encounter = XP needed /
  number of encounters; when tuning, change the encounter count and cascade the values back, so the XP curve and the
  moment-to-moment pacing stay stable [2].
- **"Hell levels"**: a level whose difficulty is out of line with its neighbours raises churn for the cohort that
  reaches it [2]. In the Q&A (reported on the blog, not in the slides) Dave Rickey said a small kink in the Dark Age
  of Camelot XP curve changed churn at that level from 1–3% to 22% [1].
- **Pokémon Go case**: XP needed rose sharply while XP per capture stayed flat, catch and flee rates worsened and ball
  supply stayed flat; Koster lists "20 year time to max assuming optimal play", cheating and massive churn as the
  outcome. Each fix (more balls, more XP per monster) had side effects on revenue or on newcomer pacing [2].
- Pure random reward tables give very uneven pacing; he models them with Monte Carlo simulation [1], [2].

### 1.2 Raph Koster, "A Theory of Fun 10 Years Later", GDC Online 2012 [talk]

GDC Vault page [3] (video not opened; content from the author's blog and press [4]). Fun is the brain learning
patterns; once a pattern is mastered the activity becomes boring. Implication used by many progression designers:
rewards that do not introduce something new to learn or express decay quickly. Koster said in 2012 that cognitive
science since the book largely supports the theory [4].

### 1.3 Daniel Cook, "Value chains", Lostgarden, 2021-12-12 [essay]

[5]. A method for faucet-and-drain economies.

- Every chain of resources must end in an **anchor**: a real player motivation (self-expression, mastery,
  relatedness). Rewards that do not lead to an anchor are "disconnected nodes of isolated atomic meaning" and lose
  value.
- Listed failure modes: structural breaks (an output nobody uses), missing or weak anchor, anchor invisible early,
  **overabundance** (resources pile up and nothing pulls on the chain), scarcity or grind, burnout from repetition.
- Generic undifferentiated rewards (two monsters giving the same generic XP) let players pick the single most
  efficient path and ignore the rest; distinct rewards per path ("lock and key") keep all content pulling.

### 1.4 Daniel Cook, "The Chemistry of Game Design", Gamasutra, 2007-07-19 [essay]

[6] (original page not opened; content from the Game Developer mirror listing and commentary by Koster [7]).
Introduces **skill atoms** (action → simulation → feedback → new skill) chained into **skill chains**; players
enjoy acquiring new skills, and "burnout" happens when an atom no longer teaches anything. For progression: an
unlock is worth most when it opens a new skill atom (a new attachment that changes how a gun plays), less when it
is a number or a cosmetic.

### 1.5 Laralyn McWilliams, GDC 2010 [talk]

"Motivating Casual Players: Non-Traditional Character Progression and Player Retention" (Sony Online
Entertainment) [8] (session page only; video not opened). Compares progression in RPGs/MMOs, competitive shooters
and fighting games, and single-player games (Free Realms, Pogo, Halo) and proposes a method to choose progression
types beyond levels, stats and item unlocks, for casual audiences.

### 1.6 Travis Day, "Rewards in Video Games", GDC 2017 (Blizzard) [talk]

[9]. Session description: "how reward systems can guide or harm player experience" in World of Warcraft and
Diablo 3. The talk content itself was not retrieved (only the listing and a short 80.lv note [10]); no key points
are claimed here beyond the description.

### 1.7 Ben Lewis-Evans (Epic Games), GDC 2017 talk on player psychology and rewards [talk/press]

Reported by Shacknews [11] (exact talk title not confirmed in that article).

- Rewards are feedback: the player must know that they got a reward, why, and what it is worth.
- Reward schedules: fixed ratio, fixed interval (daily login), variable ratio (loot), variable interval (Destiny public
  events). Fixed schedules are predictable but cause drop-off during long waits; overlap several timers to avoid
  dead zones. Variable ratio is the most compelling and the most exploitable.
- Use short-term progress markers (bars, quests) toward long goals; frequent "surprises" stop being surprises.
- Be careful with social comparison; self-comparison and co-operative stats are safer.

### 1.8 Josh Mosqueira, Diablo III Reaper of Souls, GDC 2015 [talk]

"Against the Burning Hells: Diablo III's Road to Redemption with Reaper of Souls" (Blizzard) [12], coverage
[13]. Per the coverage, the talk explains the removal of the Auction House and how randomness and itemization
changed ("Loot 2.0"). The video was not watched in this pass, so no finer points are claimed; the general reading
that fewer, more relevant drops replaced a flood of low-value ones is the press framing of Loot 2.0, not a quote.

### 1.9 Battle pass talks

- David Fox (Double Coconut), "Free-to-Play Summit: Don't Pass on Battle Pass: Best Practices for F2P Design",
  GDC 2022 [talk] [14]. Battle passes are popular because they are easy to refresh with seasonal content, a "strong
  and proven retention-booster", and a monetization tool. The retention part transfers to a free game; the
  monetization part does not.
- Eino Joas (Supercell), Clash of Clans battle pass, GDC 2020 virtual talk [talk] [15] (video not opened; coverage
  only): two years of iteration on the pass and its fit with the economy.
- Frank Yan (Supercell), "Brawl Stars: Learnings from the Removal of Loot Boxes", GDC 2024 [talk] [16] (listing
  only): loot boxes were removed and later re-added as engagement-based rewards.

### 1.10 Bungie / Destiny

John Hopson (Bungie user research) at GDC 2015 discussed the "Loot Cave" exploit; Bungie's research found it was
"not nearly as good as players thought it was" (Kotaku coverage [17], not opened; snippet only). No Bungie GDC
talk specifically on loot pacing was found in this pass.

### 1.11 Not covered in this pass

Jesse Schell (The Art of Game Design), Joris Dormans (Machinations / "Game Mechanics: Advanced Game Design"), Riot
and Overwatch-specific GDC talks were searched only lightly and are not summarised. Overwatch background from an
interview: Jeff Kaplan said Overwatch is not a progression-based game; level-ups grant cosmetic loot boxes [18].

## 2. Call of Duty progression in detail

### 2.1 Structure by title

- **CoD 4 (2007)**: levels 1–55, then reset prestige. Prestige was reportedly "a last-minute, untested idea"
  [19] [press].
- **MW 2019**: Enlisted ranks 1–55, never reset. Officer ranks 56–155 (100 seasonal ranks), reset each season;
  ribbons and emblems stay recorded. Each weapon level gives an attachment, a perk or a camo; about 50 attachments
  per weapon on average [20] [dev-blog], [21] [dev-blog, not opened].
- **Black Ops Cold War (2020)**: Military ranks 1–55. Seasonal prestige: 4 prestiges per season at season levels
  50/100/150/200, Prestige Master at 200, levels continue to 1000 each season, a milestone every 50 levels (Prestige
  Key, tier skip); Create-a-Class content is never lost [22] [dev-blog].
- **MWII (2022)**: Military ranks 1–55, then seasonal prestige ranks; season 1 capped at rank 250 (Prestige 5), a
  later cap reported as 1,250 [23] [press]. Weapon "platforms": attachments unlocked on one gun are shared across its
  family; guns are unlocked by levelling other guns [24] [press].
- **MWIII (2023)**: Armory Unlocks (from level 25): pick an item and unlock it through 2–8 daily challenges instead of
  weapon levels [25], [26] [press].
- **BO6 (2024)**: levels 1–55, 10 classic prestiges (each resets the level), then Prestige Master levels 56–1000
  without reset; 10 permanent unlock tokens (one per prestige); attachments by weapon level; camos need no weapon
  level [27] [dev-blog], [28] [dev-blog, timed out].
- **BO7 (2025)**: Weapon Prestige returns (first time since BO4): after max weapon level a weapon can be prestiged
  twice, then levelled to 250 [29] [dev-blog, not opened], [30] [press].

The Cold War post states the reasons explicitly: players avoided prestiging because they "don't want to lose access
to the Create-a-Class content", wanted progress to continue across seasons, and wanted "always a next target" [22].

### 2.2 Camo ladders and mastery camos

- **MW 2019**: about 10 camo categories × 10 challenges per weapon; Gold needs all of them on one weapon; Platinum
  needs Gold on every weapon of a class; Damascus needs Platinum on every class; Obsidian (added in April 2020)
  needs only Gold on that weapon plus a kill count [31] [press], [32] [dev-blog, not opened]. Press called the
  Damascus grind "one of gaming's most arduous tasks" (headline of [33]; body not retrieved).
- **BO6**: per weapon and per mode 9 sequential military camos and 2 special camos; 4 mastery camos per mode, ending
  in Dark Matter (MP), Nebula (Zombies), Abyss (Warzone); 450+ calling cards; camo progress no longer requires the
  weapon to be max level [27]. Record pace: one streamer needed 57 hours for the first Dark Matter and 65 hours for
  all weapons (an outlier, not a typical time) [34] [press].
- **BO6 Prestige Master level 1000** rewards were received as underwhelming in coverage [35] [press] — the cost of a
  very long tail is that its endpoint is judged harshly.

### 2.3 Community reception

- **MWII platform system** (launch, October 2022): players called it confusing and hard to track (for example
  levelling an M4 to 14 to unlock a sniper rifle; levelling two unrelated SMGs to get one camo); defenders liked that
  attachments were unlocked once per family instead of per gun [36] [press], [24] [press]. The designer's stated
  intent was less grind [24].
- **MWIII Armory** was reported as a direct answer to MWII weapon progression complaints [26].
- **Time-to-max**: no official time-to-max numbers were found for any CoD title. The recurring pattern is that the
  account level 1–55 path is meant to be finished, while the 1000-level tails are open-ended clocks.

## 3. Case studies of the two failure modes and of fixes

### 3.1 Reward flood: Forza Horizon 4 and 5

- FH4: cars "dozens of them, are thrown at you as rewards for your performance" through wheelspins, the auction
  house, the shop and barn finds [37] [press]. Wheelspins were the main reward channel [37].
- FH5 reviews (pages not opened; via search summaries): TrueAchievements called the game "generous to a fault",
  with money, cars and items arriving so often that players stop valuing them, while noting that Accolades give
  lesser cars some value; Push Square named the sheer number of cars and the weak sense of progression as its main
  complaint; PC Gamer described the garage filling at an absurd rate but was positive overall [38], [39], [40].
- Counter-example in the same game: in February 2022 Playground removed wheelspins from many car mastery trees and
  made them rarer, citing exploits; players then complained about scarcity and abrupt, uncommunicated change [41]
  [forum], [42] [forum].
- Lesson that recurs in sources [5], [12]: quantity without a connection to a goal (an anchor) makes each reward
  worth less; the overcorrection is also punished.

### 3.2 Too slow: WoW leveling

- **Classic 1x**: estimates of 120–350 hours (5–14 days played) to level 60 for most players; the world-first took
  3 days 6 hours played [43] [press/guide, community estimate], [44] [guide]. Private-server anecdotes put typical
  time at about 8–10 days played [43] [forum anecdote].
- **Shadowlands level squish** (announced BlizzCon 2019): reasons as paraphrased by MMOGames from Ion Hazzikostas:
  levelling was "INCREDIBLY long", and there were too few new abilities and talents to give intrinsic rewards —
  some classes went nearly 15 levels without a new one. The squish was projected to make Battle for Azeroth levelling
  "roughly 50–70% faster" [45] [press, paraphrase, no primary transcript found]. Note the second reason: dead levels
  (no new ability), not only the time.
- **Rested XP**: a bonus pool accrues while logged out (up to 150% of a level, shown as "bubbles"), doubling kill XP
  until spent. The wiki frames it as letting players who play less often level faster and nudging heavy players to
  take breaks [46] [wiki]; forum players describe it as "a catch up mechanic not a speed up mechanic" [46].

### 3.3 Halo Infinite (2021–2023)

- August 2021: battle pass progress at launch would come only from daily and weekly challenges [47] [press].
- November 2021 backlash, then two patches (via press quoting 343 tweets; Waypoint posts not found): from
  2021-11-18 a repeatable "Play 1 Game" daily challenge worth 50 XP; from 2021-11-30 the first six matches each day
  pay 300/200/200/100/100/100 XP and later matches 50 XP; one pass level costs 1,000 XP, so six matches ≈ one level
  per day [48] [press], [49] [press].
- Winter Update (November 2022, "Match XP Beta"): XP for completing any match plus performance bonuses; challenges
  became playlist-agnostic because players "didn't enjoy queuing for playlists they wouldn't otherwise play" and mode
  challenges were "prohibitive to playing with friends"; players "shouldn't have to choose between progress or playing
  together" [50] [dev-blog].
- June 2023 (Season 4): Career Rank, 272 ranks (Recruit 1 to Hero 272) across six tiers, from personal score in
  matchmaking, never reset, no skill gate; Hero unlocks the Mark VI armor [51] [dev-blog], [52] [dev-blog].
- Non-expiring passes were a launch promise; the support FAQ says all battle passes are permanently available, but
  free-track progress stops when the Operation ends unless upgraded [53] [dev-blog], [54] [press].

### 3.4 Battlefield

- **Battlefield 6 (2025)**: weapon mastery was the only route to attachments and was criticised as slow; on
  2025-10-17 DICE cut the XP for the first 20 attachment ranks (useful attachments "almost twice as fast"), raised
  match XP per minute by 10% and daily bonus XP by 40%, and moved career assignments from ranks 20/23/26 to 10/15/20;
  a later post reported attachments unlocking "roughly 50% faster" [55] [dev-blog, EA forum], [56] [press].
- **Battlefield 2042 / V**: little primary material found in this pass; one player on EA forums said the 2042
  attachment grind "was over by mastery 12" [57] [forum]. Not analysed further.

### 3.5 Destiny 2 sunsetting

Weapons and armor got a power cap so that old loot became obsolete ("sunsetting"), meant to keep the loot pool
balanced and focused; in February 2021 Bungie dropped it, saying "our execution was off the mark" [58] [press]. In
2024 Bungie let old gear be infused to current power and said it regretted that deleted weapons could not be
recovered [59] [press]. Lesson: taking earned rewards away is remembered for years.

### 3.6 Deep Rock Galactic Performance Pass

Season 01 FAQ [60] [dev-blog]: free, 100 levels, target "about one hour per level" (≈100 hours), season of 4–5
months; it is "not intended that most players complete the pass"; unclaimed cosmetics "will not be lost" and return
through other sources after the season. Ghost Ship acknowledged other games use such systems to monetize and chose
to "focus on the positive side". Later seasons made old passes replayable; that detail was not verified on a primary
page in this pass.

### 3.7 Battle pass length references

- **Fortnite**: 100 tiers; Epic's own estimate of "75–150 hours" to unlock everything (Season 3, 2018; fortnite.com
  not opened, figure via secondary sources) [61] [press]. Total about 7.5 M XP [61] [community estimate].
- **Apex Legends Season 1**: Respawn said about 100 hours to reach pass level 100 with bonuses, in response to
  complaints that progress was too slow [62] [press].

### 3.8 Warframe Mastery Rank

Every item contributes a fixed amount once: weapons 100 mastery points per rank up to 30 (3,000 each), Warframes 200
per rank (6,000 each); variants (Mk1, Vandal, Prime) count separately; a rank-up test gates each Mastery Rank [63]
[dev-blog], [64] [wiki]. This is the clearest shipped example of an account level that **grows with content count**:
the more items exist, the higher the reachable rank.

## 4. XP curve mathematics

Notation: `c(L)` = cost to go from level `L` to `L+1`; `C(N) = Σ_{L=1}^{N-1} c(L)` = total to reach `N`.

### 4.1 Common shapes

- **Constant**: `c(L) = c0`, `C(N) = c0 (N-1)`. A level is a clock; used by flat long tails (CoD Prestige Master).
- **Linear increment**: `c(L) = c0 + d (L-1)`, `C(N) = c0 (N-1) + d (N-1)(N-2)/2`. Luban's "linear progression
  curve": the *increase* between thresholds grows linearly [65].
- **Power**: `c(L) = a L^p`, `C(N) ≈ a N^(p+1) / (p+1)`. Private War today: player `1000 L^1.2`, weapon
  `500 L^1.1` (`design/06-progression.md` d.4).
- **Geometric**: `c(L) = c0 r^(L-1)`, `C(N) = c0 (r^(N-1) - 1) / (r - 1)`. Luban: a low `r` is nearly flat, a high
  `r` makes late levels unreachable [65]; Koster's example uses "a 1.2x increase per level" [2].
- **Cubic total (Pokémon)**: total XP at level `n` is Medium Fast `n³`, Fast `4n³/5`, Slow `5n³/4`, Medium Slow
  `6/5 n³ − 15 n² + 100 n − 140`; totals at 100: 1,000,000 / 800,000 / 1,250,000 / 1,059,860 [66] [wiki; totals
  checked by computation].

**RuneScape / OSRS** [67] [wiki, page not opened]:

```text
XP(L) = floor( (1/4) * Σ_{x=1}^{L-1} floor( x + 300 * 2^(x/7) ) )
```

Checked in this pass by computation: it gives 83 (level 2), 101,333 (50), 6,517,253 (92) and 13,034,431 (99), the
same totals the wiki reports; level 92 is half of level 99 because cost doubles every 7 levels.

**D&D 5e** [68] [wiki/SRD]: hand-made table, 0 / 300 / 900 / 2,700 / 6,500 … 305,000 (19) / 355,000 (20). It is not
a formula; encounter XP also grows with level, so sessions per level stay in a narrow band — the same idea as Koster's
"encounters per level".

### 4.2 Deriving a curve from a time budget (Koster's method, written as formulas)

1. Choose the felt pace first: `m(L)` = matches (or encounters) per level, a smooth function. Source: [2].
2. Measure or assume XP per match `E` (median player, bots, typical mode). Then `c(L) = E · m(L)`.
3. Total time: `T = t_match · Σ m(L)`. Fix `T` and the shape, solve for the free parameter.
4. If `E` changes later (new score events), recompute `c(L)` from `m(L)`; do not touch `m(L)`.

Geometric example: 55 steps with `m(1) = 0.5` matches and a target of 150 matches in total,
`0.5 (r^55 − 1)/(r − 1) = 150`, gives `r ≈ 1.053` (computed): level 10 ≈ 0.8 matches, 30 ≈ 2.2, 40 ≈ 3.7,
55 ≈ 8 matches.

Content-driven example (Warframe-like): `levels = Σ items · points_per_item / points_per_level`, so the cap moves with
the installed content.

### 4.3 What Private War's current curves imply (computed, not measured)

- Player: `c(L) = 1000 L^1.2`. Cost at level 12 ≈ 19,700 XP; if that takes about 2 matches,
  `E ≈ 9,900` XP per match. Total to 55 ≈ 3.0 M XP ≈ 300 matches; level 54 alone ≈ 120,000 XP ≈ 12 matches.
  The comment in `design/06-progression.md` d.4 ("about 12 000 at level 55") does not match the formula
  (≈ 120,000); the code (`modules/progression/sh_curves.lua`) uses the formula.
- Weapon: `c(L) = 500 L^1.1`, cap 30, total ≈ 290,000 weapon XP; at ~3.5 matches for level 10, about 160 matches to
  max one weapon.

### 4.4 Catch-up and diminishing returns

- **Rested XP** (WoW): accrues offline, boosts XP until spent; rewards returning, not grinding [46].
- **First-matches-of-the-day bonus** (Halo 2021): 300/200/200/100/100/100 then 50 [48], [49]; same effect inside a
  session.
- **Double XP events** (MW 2019 ran one before Season 1 [21]); time-limited by nature.
- **Diminishing returns**: Halo's descending per-match payout is one; any daily cap is another. Both reduce the gap
  between heavy and light players but can feel like punishment if they are visible as a "cut".

## 5. Unlock distribution

- **One item per level** for weapons: MW 2019 states each weapon level rewards an attachment, a perk or a camo [20].
- **Milestones every N levels** in long tails: Cold War every 50 season levels [22]; MW 2019 Officer emblem every 10
  ribbons [20].
- **Choice instead of order**: MWIII Armory lets players pick the next unlock and earn it via daily challenges [25];
  BO6 permanent unlock tokens let a player keep one item through prestige resets [27].
- **Shared unlocks across a family** (MWII platforms) cut grind but made the graph hard to read [24], [36].
- **No dead stretches**: the Shadowlands reasoning (classes going ~15 levels without a new ability) [45] and Koster's
  hell levels [2] both point to keeping the gap between meaningful unlocks short and even.
- **Separate gameplay from cosmetics**: Overwatch made level-ups purely cosmetic [18]; BO6 decoupled camos from
  weapon level [27]; Battlefield 6 front-loaded the first 20 attachments because those affect play [55].
- **Unlock cadence rule of thumb**: no industry source found states a numeric "one unlock per N minutes" rule. The
  closest concrete figures are Halo's "one pass level per ~6 matches a day" [49], DRG's "one hour per level" [60] and
  Lewis-Evans's advice to overlap timers so there is no long wait [11].

## 6. Prestige and long-tail systems

- **Reset prestige** (CoD 4 to BO6 classic prestige): status for resetting; disliked when it removes loadouts [22].
- **Non-reset prestige / clock levels**: MW 2019 officer ranks, Cold War Prestige Master to 1000, BO6 Prestige
  Master to 1000, Halo Career Rank 272 [20], [22], [27], [51]. What fills them: emblems, calling cards, legacy
  icons, milestone keys, a final showpiece (Mark VI for Halo Hero). Risk: a weak final reward is judged harshly [35].
- **Weapon prestige** (BO4, BO7): extends a favourite weapon's track rather than the account's [29], [30].
- **Mastery challenges** (camos, calling cards) give the long tail a skill flavour instead of a time flavour [27],
  [31].
- **Collection rank** (Warframe): rank grows with the number of different items mastered, pushing variety [63].
- **Never take earned things away**: Destiny sunsetting [58], [59]; DRG keeps unclaimed rewards [60]; Halo keeps
  passes [53].

## 7. Implications for Private War (options and trade-offs)

### 7.1 The attachment clump at weapon levels 16–17 has a mechanical cause

The automatic rules spread each attachment **slot** independently over weapon levels 1..30 with no attachment open at
level 1 (`modules/autounlock/sh_rules.lua`, `_Spread` and `_SlotLevels`). A slot with one ranked option puts it near
level 16; options without numeric stats get `round((1 + 30) / 2) = 16`. Many packs have few options per slot, so the
first unlock of every slot lands at the same middle level. This matches the reported clump. Options:

1. **Global schedule across slots**: rank all options of a weapon together and assign one per level (round-robin by
   slot), like MW 2019's "each level gives an attachment, perk or camo" [20]. Trade-off: needs a tie-break order for
   slots.
2. **Weapon cap from content count**: max weapon level = number of attachments (+ a few cosmetic levels), so every
   level gives exactly one thing whatever the pack contains. Trade-off: weapons with 5 attachments max out fast,
   weapons with 60 take long; could be bounded (for example 10..40) and pad or merge.
3. **Front-load**: dense unlocks in levels 2–10 (the "first 20 attachments" fix in Battlefield 6 [55]), sparse later.
4. **Place unranked options deterministically spread** instead of at the middle.

### 7.2 500–1000 account levels

Industry precedent supports a long count only as a **two-part** system: a finite "meaningful" part (CoD 1–55) and a
clock tail with flat cost and milestone rewards (Cold War, BO6, MW 2019) [20], [22], [27]. Computed examples with a
ramp of 0.5 → 3 matches per level over 1..55 (≈ 96 matches) and a flat tail, at 10-minute matches:

| Cap | Tail cost per level | Total matches | Hours |
| --- | --- | --- | --- |
| 500 | 0.5 match | ≈ 320 | ≈ 53 |
| 500 | 1 match | ≈ 540 | ≈ 90 |
| 1000 | 0.5 match | ≈ 570 | ≈ 95 |
| 1000 | 1 match | ≈ 1,040 | ≈ 174 |
| 1000 | 1.5 matches | ≈ 1,510 | ≈ 252 |

Trade-offs: a level every match makes level-ups common, so each one must be cheap to present (a counter tick, not a
full reward screen) — otherwise this is the Forza flood [38], [5]. Milestones every 10/25/50 levels carry the real
rewards (calling cards, camos, titles). A long tail with a weak endpoint draws criticism [35]. Alternative without a
huge count: keep 55 + non-reset prestige tiers (Cold War style).

### 7.3 Variable content count from Workshop packs

Fixed totals such as "Gold on every weapon" (MW 2019 Damascus [31]) are undefined when the weapon list differs per
player and can be enormous. Options: requirements in counts ("Gold on 5 assault rifles"), Warframe-style collection
points that scale with installed content [63], or tie a mastery camo to the weapon itself (Obsidian-style [32]).
Account-level unlocks of weapons (the "spread over 1..55, 1–2 per category open" rule in `design/06-progression.md`)
already adapt; the same adaptive idea fits the weapon level cap (7.1 option 2).

### 7.4 Short Deck sessions (about two matches)

- Target at least one visible unlock or milestone per session in the early game; Koster's method (pace in matches)
  makes this a direct parameter [2].
- FOMO-free catch-up: a rested-style pool that fills while away and doubles the first match(es) of a session [46],
  or Halo's descending first-matches bonus [48]. Rested XP accrues by real time, so it rewards returning without
  punishing absence; a daily descending bonus can read as a cut for longer sessions.
- Avoid hell levels: smooth `m(L)`; the current player curve ends at ~12 matches per level at 54, which is long for
  a 2-match evening.

### 7.5 Solo/co-op against bots

- Halo's lesson: challenges that require a mode or playlist split friends; make weekly challenges mode-agnostic or
  include enough options [50].
- Bot matches give stable `E`, so the encounter-based derivation is more reliable than in PvP; but bot difficulty
  settings change `E` and should be considered when targeting time.

### 7.6 No FOMO, no monetization

- Non-expiring pass precedents: DRG returns unclaimed items [60]; Halo passes stay available [53]. Without money
  there is no reason to cap passes in time; a "season" can be a themed reward track that stays claimable.
- The retention reasons for battle passes (refreshable content, clear goal) transfer; the monetization reasons do
  not [14].
- Never remove or invalidate earned unlocks (Destiny [58], [59]; Cold War prestige rationale [22]).

### 7.7 Gameplay vs cosmetic rewards

Keep gameplay unlocks (weapons, attachments, perks) scarce, front-loaded and finite; let cosmetics (calling cards,
camos, titles) carry the long tail. Each cosmetic chain should end in a visible anchor (lobby, kill card, scoreboard)
or it becomes "isolated atomic meaning" [5].

## Open questions for the maintainer

1. Should the account level stay one number (500–1000) or split into "core 1–55" plus a non-reset prestige / clock
   tail? Is resetting ever acceptable (classic prestige), or never?
2. What is the target time to finish the gameplay unlocks (account core and a typical weapon), in matches or hours?
   This fixes `m(L)` and `T` in section 4.2.
3. Should the weapon level cap be fixed (30) or follow each weapon's attachment count (7.1 option 2)?
4. Is a rested-style or first-match-of-session bonus acceptable under "no FOMO", or should catch-up be avoided?
5. How should mastery camos and weekly challenges count weapons when the installed set varies (counts per category,
   collection points, per-weapon only)?
6. Which rewards carry milestones in a long tail (calling cards, camos, titles, kill-card frames), and how many such
   assets can realistically be produced?
7. The `design/06-progression.md` d.4 comment "about 12 000 at level 55" disagrees with the formula (≈ 120,000):
   which one reflects the intent?

## Sources

1. [talk] Raph Koster, "My AGC talk on Retention and Systems Math" (2016-09-25, mirror of raphkoster.com post):
   <https://www.goodreads.com/author_blog_posts/13993343-my-agc-talk-on-retention-and-systems-math>
2. [talk] Raph Koster, "Gritty Systems Design for Retention", slides (AGC 2016), text extracted in this pass:
   <https://www.raphkoster.com/wp-content/uploads/2026/07/Gritty-Systems-Design.pdf>
3. [talk] Raph Koster, "A Theory of Fun 10 Years Later", GDC Online 2012 (not opened):
   <https://gdcvault.com/play/1016632/A-Theory-of-Fun-10>
4. [press] Engadget, "GDC Online 2012: Raph Koster's keynote on a Theory of Fun, 10 years later" (search summary):
   <https://www.engadget.com/2012/10/10/gdc-online-2012-raph-kosters-keynote-on-a-theory-of-fun-10-ye/>
5. [essay] Daniel Cook, "Value chains – A method for creating and balancing faucet-and-drain game economies",
   2021-12-12: <https://lostgarden.com/2021/12/12/value-chains/>
6. [essay] Daniel Cook, "The Chemistry of Game Design", 2007 (not opened):
   <https://www.gamedeveloper.com/pc/feature-the-chemistry-of-game-design->
7. [essay] Raph Koster, "Cooking up Chemistry", 2007 (search summary):
   <https://www.raphkoster.com/2007/07/23/cooking-up-chemistry/>
8. [talk] Laralyn McWilliams, "Motivating Casual Players: Non-Traditional Character Progression and Player
   Retention", GDC 2010: <https://gdcvault.com/play/1012261/Motivating-Casual-Players-Non-Traditional>
9. [talk] Travis Day, "Rewards in Video Games", GDC 2017 (listing): <https://gdcvault.com/play/1023948/Rewards-in-Video>
10. [press] 80.lv, "GDC: Rewards in Video Games": <https://80.lv/articles/gdc-rewards-in-video-games>
11. [press] Shacknews, "GDC 2017: Epic Games' Ben Lewis-Evans on player psychology and rewards":
    <https://shacknews.com/article/99219/gdc-2017-epic-games-ben-lewis-evans-on-player-psychology-and-rewards>
12. [talk] Josh Mosqueira, "Against the Burning Hells: Diablo III's Road to Redemption with Reaper of Souls",
    GDC 2015 (listing): <https://gdcvault.com/play/1021776/Against-the-Burning-Hells-Diablo>
13. [press] Game Developer, "Video: How Blizzard built Reaper of Souls to redeem Diablo III" (search summary):
    <https://gamedeveloper.com/design/video-how-blizzard-built-i-reaper-of-souls-i-to-redeem-i-diablo-iii-i->
14. [talk] David Fox, "Free-to-Play Summit: Don't Pass on Battle Pass: Best Practices for F2P Design", GDC 2022:
    <https://gdcvault.com/play/1027584/Free-to-Play-Summit-Don>
15. [press] "Video: How Supercell designed the Clash of Clans Battle Pass" (Eino Joas, GDC 2020; mirror):
    <https://www.jikguard.com/news/video-how-supercell-designed-the-clash-of-clans-battle-pass>
16. [talk] Frank Yan, "Brawl Stars: Learnings from the Removal of Loot Boxes", GDC 2024 (listing):
    <https://schedule.gdconf.com/session/brawl-stars-learnings-from-the-removal-of-loot-boxes/902677>
17. [press] Kotaku, "Bungie explains why they really killed Destiny's Loot Cave" (not opened):
    <https://kotaku.com/bungie-explains-why-they-really-killed-destinys-loot-ca-1689513172>
18. [press] PC Gamer, "Jeff Kaplan talks Overwatch progression, unlocks, and beta invites" (search summary):
    <https://pcgamer.com/jeff-kaplan-talks-overwatch-progression-unlocks-and-beta-invites>
19. [press] GamesRadar, Call of Duty devs on perks and prestige (search summary):
    <https://www.gamesradar.com/call-of-duty-devs-wanted-perks-to-be-a-bit-like-fallout-and-with-modern-warfare-accepted-they-were-never-making-a-better-version-of-counter-strike>
20. [dev-blog] Activision, "Explaining Player Progression in Call of Duty: Modern Warfare", 2019-10-18:
    <https://blog.activision.com/call-of-duty/2019-10/Feature-Explaining-Player-Progression-in-Call-of-Duty-Modern-Warfare>
21. [dev-blog] Activision, "Officer Rank Refresh", 2019-11 (not opened; snippet):
    <https://blog.activision.com/call-of-duty/2019-11/Officer-Rank-Refresh>
22. [dev-blog] Treyarch, "Player Progression in Black Ops Cold War", 2020-11:
    <https://www.treyarch.com/game-intel/2020/11/Player_Progression_in_Black_Ops_Cold_War>
23. [press] GamesRadar, "How to prestige in Modern Warfare 2" (search summary); Dot Esports on the 1,250 cap:
    <https://www.gamesradar.com/modern-warfare-2-prestige-how-to-explained-call-of-duty>, <https://dotesports.com/?p=719663>
24. [press] GamesRadar, "Modern Warfare 2 Gunsmith 2.0 promises more customization with shared unlocks and less
    grind" (search summary): <https://gamesradar.com/modern-warfare-2-gunsmith-20-promises-more-customization-with-shared-unlocks-and-less-grind>
25. [press] GameSpot, "CoD: Modern Warfare 3 Has A New Way To Unlock Attachments With Challenges" (search summary):
    <https://www.gamespot.com/articles/cod-modern-warfare-3-has-a-new-way-to-unlock-attachments-with-challenges/1100-6518946/>
26. [press] Dexerto, "New Modern Warfare 3 feature finally addresses MW2 weapon progression complaints":
    <https://dexerto.com/call-of-duty/new-modern-warfare-3-feature-finally-addresses-mw2-weapon-progression-complaints-2370521>
27. [dev-blog] Activision Support, "Progression in Black Ops 6":
    <https://support.activision.com/black-ops-6/articles/progression-in-black-ops-6>
28. [dev-blog] Call of Duty blog, Black Ops 6 launch progression (timed out; snippet):
    <https://www.callofduty.com/blog/2024/10/call-of-duty-black-ops-6-launch-progression-leveling-prestiging-challenges-intel>
29. [dev-blog] Activision Support, "Progression in Black Ops 7" (not opened; snippet):
    <https://support.activision.com/content/atvi/support/web/en_gb/black-ops-7/articles/progression-in-black-ops-7.html>
30. [press] Attack of the Fanboy on BO7 weapon prestige (search summary): <https://attackofthefanboy.com/?p=1046745>
31. [press] GamesRadar, "How to unlock Modern Warfare camos" (search summary): <https://gamesradar.com/modern-warfare-camos>
32. [dev-blog] Activision, "Become a True Weapon Master with Obsidian Camo", 2020-04 (not opened):
    <https://blog.activision.com/call-of-duty/2020-04/Become-a-True-Weapon-Master-with-Obsidian-Camo-Now-in-Call-of-Duty-Modern-Warfare>
33. [press] GamesRadar, "Grinding to the Damascus camo in Modern Warfare is one of gaming's most arduous tasks"
    (headline only): <https://www.gamesradar.com/grinding-to-the-damascus-camo-in-modern-warfare-is-one-of-gamings-most-arduous-tasks>
34. [press] GamesRadar, first Dark Matter camo after 57 hours (search summary):
    <https://www.gamesradar.com/games/call-of-duty/call-of-duty-black-ops-6-player-wins-race-to-first-dark-matter-camo-after-57-hours-of-grinding-and-just-3-hours-of-sleep-gets-the-other-32-just-1-day-later>
35. [press] PCGamesN, "Black Ops 6's secret Prestige 1,000 rewards have been revealed" (search summary):
    <https://www.pcgamesn.com/call-of-duty-black-ops-6/prestige-master-1000-rewards>
36. [press] Charlie Intel, "Modern Warfare 2 players slam Platform-based weapon unlock system", 2022-10-31:
    <https://www.charlieintel.com/call-of-duty-modern-warfare-2/modern-warfare-2-players-slam-platform-based-weapon-unlock-system-207553/>
37. [press] Trusted Reviews, "Forza Horizon 4" review (search summary): <https://www.trustedreviews.com/reviews/forza-horizon-4>
38. [press] TrueAchievements, "Forza Horizon 5 review" (not opened; search summary):
    <https://www.trueachievements.com/n47612/forza-horizon-5-review-xbox>
39. [press] Push Square, "Forza Horizon 5" (PS5) review (not opened; search summary):
    <https://www.pushsquare.com/reviews/ps5/forza-horizon-5>
40. [press] PC Gamer, "Forza Horizon 5 review" (search summary): <https://www.pcgamer.com/forza-horizon-5-review/>
41. [forum] Forza forums, "The lack of progression, and what I think could improve it":
    <https://forums.forza.net/t/the-lack-of-progression-and-what-i-think-could-improve-it/538991>
42. [forum] Steam, Forza Horizon 5 discussion on wheelspin changes:
    <https://steamcommunity.com/app/1551360/discussions/0/4353368966471893175>
43. [press] ExpertBeacon, "How Long Does it Take to Level from 1-60 in WoW Classic?" (community estimates):
    <https://expertbeacon.com/how-long-does-it-take-to-level-1-60-wow-classic/>
44. [press] Icy Veins, "WoW Classic Leveling Guide" (search summary): <https://www.icy-veins.com/wow-classic/leveling-guide>
45. [press] Phil DeMerchant, "WoW Wednesday: How Shadowlands fixes leveling", MMOGames, 2019-11-06:
    <https://www.mmogames.com/articles/archives/wow-wednesday-how-shadowlands-fixes-leveling>
46. [wiki] Warcraft Wiki, "Rested bonus" (search summary): <https://warcraft.wiki.gg/wiki/Rested_bonus>
47. [press] Windows Central, "Halo Infinite Battle Pass progression will be limited to challenges":
    <https://www.windowscentral.com/halo-infinite-battle-pass-progression-will-be-limited-challenges>
48. [press] PC Gamer, "Halo Infinite will now give you bonus XP for your first few matches each day":
    <https://www.pcgamer.com/halo-infinite-will-now-give-you-bonus-xp-for-your-first-few-matches-each-day>
49. [press] GameSpot, "Halo Infinite Battle Pass And XP Progression Patch Out Now" (search summary):
    <https://www.gamespot.com/articles/halo-infinite-major-battle-pass-progression-changes-coming-this-week/1100-6498137/>
50. [dev-blog] Halo Waypoint, "Match XP Beta, Progression and the Winter Update":
    <https://www.halowaypoint.com/news/match-xp-beta-progression-winter-update>
51. [dev-blog] Halo Waypoint, "Career Rank Overview (Season 4)": <https://www.halowaypoint.com/news/career-rank-overview-season-4>
52. [wiki] Halopedia, "Rank (Halo Infinite)": <https://www.halopedia.org/Rank_(Halo_Infinite)>
53. [dev-blog] Halo Waypoint Support, battle pass FAQ (search summary):
    <https://support.halowaypoint.com/hc/en-us/articles/4408373413268>
54. [press] PC Gamer, "Halo Infinite season 2 introduces another 'Battle Pass that never expires'":
    <https://pcgamer.com/halo-infinite-season-2-introduces-the-battle-pass-that-never-expires>
55. [dev-blog] EA forums, "BFComms: Battlefield 6 progression changes now live" (search summary):
    <https://forums.ea.com/blog/battlefield-game-info-hub-en/bfcomms-battlefield-6-progression-changes-now-live/12783981>
56. [press] MP1st, "Battlefield 6 Weapon and Player Progression Update Now Live, Attachment Ranks Reduced":
    <https://mp1st.com/title-updates-and-patches/battlefield-6-weapon-player-progression-update-live-attachment-ranks-reduced>
57. [forum] EA forums, "BF2042 XP, soldier progression and ranking up":
    <https://forums.ea.com/discussions/battlefield-2042-general-discussion-en/bf2042-xp-soldier-progression-and-ranking-up/6781697>
58. [press] Kotaku, "Destiny 2 is ditching sunsetting" (search summary): <https://kotaku.com/destiny-2-is-ditching-sunsetting-1846356691>
59. [press] PC Gamer, Bungie regrets no recovery for deleted sunset weapons (search summary):
    <https://www.pcgamer.com/games/fps/remember-all-those-destiny-2-guns-you-deleted-after-they-got-sunset-bungie-admits-you-shouldnt-have-done-that-we-regret-we-have-no-recovery-mechanism>
60. [dev-blog] Ghost Ship Games, "Season 01 FAQ": <https://www.deeprockgalactic.com/season01-faq>
61. [press] Gamepressure, "Fortnite: How long does it take to complete?" (Epic's 75–150 h figure; fortnite.com not
    opened): <https://www.gamepressure.com/fortnite-battle-royale/how-long-is-the-game/zcd03e>,
    <https://www.fortnite.com/news/welcome-to-season-3-battle-pass-breakdown?lang=en-US>
62. [press] Dexerto, "Apex Legends devs respond to complaints that Battle Pass progress is too slow":
    <https://dexerto.com/apex-legends/apex-legends-devs-respond-complaints-season-1-battle-pass-progress-too-slow-470128>
63. [dev-blog] Warframe, "Mastery Ranks Guide": <https://www.warframe.com/news/mastery-ranks-guide>
64. [wiki] Warframe Wiki, "Mastery Rank": <https://wiki.warframe.com/w/Mastery_Rank>
65. [essay] Pascal Luban, "Quantitative design – How to define XP thresholds?", 2018:
    <https://www.gamedeveloper.com/design/quantitative-design---how-to-define-xp-thresholds->
66. [wiki] pret/pokered wiki, "Add a new growth rate" (coefficients); totals checked by computation:
    <https://github.com/pret/pokered/wiki/Add-a-new-growth-rate>
67. [wiki] Old School RuneScape Wiki, "Experience" (not opened, HTTP 403; totals via search, formula checked by
    computation): <https://oldschool.runescape.wiki/w/Experience>
68. [wiki] Roll20 compendium (SRD 5e), "Level Advancement":
    <https://roll20.net/compendium/dnd5e/Rules:Level%20Advancement>
