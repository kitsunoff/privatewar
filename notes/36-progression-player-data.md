# 36 — Progression: player surveys, sentiment and playtime data

Status: research (2026-11-22). Research explains *why*; it is not a decision. Where this note and `../design/` disagree,
`design/` wins.

Evidence labels: [paper] peer-reviewed or preprint study, [survey] commercial or academic questionnaire study,
[industry-report] analytics/market report, [telemetry] measured behaviour data, [press] journalism or opinion,
[forum/anecdotal] player posts. Numbers in brackets such as [S3] point to the "Sources" list. Where a figure came
only from a secondary summary, a search-engine snippet or a paywalled page, the text says so.

## Question

What do surveys, validated questionnaires, telemetry studies and large-scale player sentiment say about how players
perceive grind, reward pacing, unlocks, challenges and battle passes, and how long and how often casual players
actually play? The goal is input for Private War's progression pacing (account level, weapon levels, attachments,
weekly challenges, calling cards, camo challenges, an optional non-expiring season pass), for a game played solo or
with 2–4 friends against bots, often on a Steam Deck, in short evening sessions.

## 1. Player motivation models with data

### 1.1 Quantic Foundry Gamer Motivation Model

1. **Model.** 12 motivations in 6 pairs: Destruction/Excitement (Action), Competition/Community (Social),
   Challenge/Strategy (Mastery), Completion/Power (Achievement), Fantasy/Story (Immersion), Design/Discovery
   (Creativity) [S1]. The reference sheet states that Completion and Power often go together (the "Achievement"
   cluster) and describes high-Completion gamers as wanting "to finish everything the game has to offer" [S1].
   The data base is self-selected respondents of a free online profile: 140k (2016), 239k (2016), 250k (2016),
   400k (2019–2020), later "1.75+ million" and "over 2 million" [S2, S3, S4]. Self-selection biases the sample
   toward engaged, English-speaking gamers.
2. **Completion is the most universal motivation.** "Whether we're comparing gender or age segments, Completion
   is always in the top 3" (n > 250,000, December 2016) [S3]. Completion was later described by Nick Yee as "the
   most age stable motivation in our model, and is higher for women" (October 2019 blog, cited via search
   snippet; the Quantic Foundry site blocked direct fetching) [S5]. One earlier analysis (n = 107,100) reported
   Completion's correlation with age as about −.05, the weakest of the motivations shown, versus −.28 for
   Excitement (secondary snippet, not verified in the original) [S5].
3. **Competition declines most with age.** n > 239,000 (2016): Competition correlates with age at r = −.30 for men
   and r = −.19 for women; steepest drop between 13 and 35; age explains more than twice the variance that gender
   does; the data is cross-sectional, so cohort effects are possible [S2].
4. **Strategy is declining over time.** Yee (2025 interview): the average gamer in 2025 sits at about the 33rd
   percentile of the 2015 baseline on strategic thinking/planning, the largest change of the 12 motivations,
   strongest among teenagers [S4]. Quantic Foundry collects about 200,000 new profiles per year [S4].
5. **Shooters.** Quantic Foundry lists Call of Duty among popular titles for Destruction, Competition,
   Excitement, Power and Completion (reference material, association lists, not a ranked CoD audience profile)
   [S1]. In a 2025 interview, Power is named among the top differentiating motivations of GTA Online players and
   Competition/Excitement for Fortnite, with Destruction in the top three of both [S4].
6. **Gap.** No public source found in this research gives the *share* of shooter players driven by
   Completion/Power. Quantic Foundry's per-game audience reports exist but are commercial. Treat "a large share of
   CoD-style players care about completion" as plausible (Completion is top-3 in every segment) but not measured
   for shooters.

### 1.2 Bartle and Yee

1. **Bartle (1996)** is a typology from MUD observation, not a survey instrument. Yee's factor analysis found that
   "play motivations in MMORPGs do not suppress each other as Bartle suggested" (DiGRA 2005 version) [S6].
2. **Yee (2006)**, CyberPsychology & Behavior 9:772–775, survey of about 3,000 MMORPG players [S6]. The paper
   reports three overarching components, Achievement, Social and Immersion, with ten subcomponents (Achievement:
   Advancement, Mechanics, Competition; Social: Socializing, Relationship, Teamwork; Immersion: Discovery,
   Role-Playing, Customization, Escapism). The grouping is quoted from the paper's well-known abstract; the search
   snippets in this session confirmed the sample and venue but not the full component list [S6].
3. Relevance: "Advancement" (progress, power, accumulation, status) is the closest MMO ancestor of account/weapon
   levels; "Customization" maps to attachments, camos and calling cards.

## 2. Validated questionnaires

| Instrument | Measures | Length / scale | Availability | Validation notes |
| --- | --- | --- | --- | --- |
| PENS (Ryan, Rigby, Przybylski 2006) | Competence, Autonomy, Relatedness, Presence/Immersion, Intuitive Controls | 21 items, 7-point | Owned by Immersyve, not freely available | Structure largely supported, Competence and Controls behaved as one factor; Relatedness items assume multiplayer [S7, S8, S9] |
| GEQ (IJsselsteijn et al.) | Competence, Immersion, Flow, Tension, Challenge, Negative/Positive Affect | Core 33 items, plus in-game and post-game modules | Free, but never formally peer-review published | 7-factor structure not supported (N = 633, CHI PLAY 2018); partial support with 5-factor revision [S10, S11, S8] |
| PXI (Vanden Abeele et al. 2020) | 5 functional (Ease of Control, Progress Feedback, Audiovisual Appeal, Goals and Rules, Challenge) and 5 psychosocial (Mastery, Curiosity, Immersion, Autonomy, Meaning) constructs, plus Enjoyment | 30+ items, 7-point (−3 to +3) | Free for research | Designed to link design-level ("functional") to experience-level constructs [S12] |
| miniPXI (Haider et al. 2022) | Same 11 constructs, 1 item each | 11 items, 7-point | Free; items in the CHI PLAY 2022 paper | 3 studies, 628 players, 15 experts; single-item reliability .51–.83 (mean .68); validity confirmed for 9 of 11 constructs [S12] |
| UPEQ (Azadvar, Canossa 2018) | SDT needs: Autonomy (6), Competence (6), Relatedness (9) | 21 items, 5-point in some uses | In the FDG 2018 paper | Subscales predicted playtime, spend and group play in Ubisoft telemetry; later work found weaknesses in the 3-factor model [S13] |
| BANGS (Ballou et al. 2024) | Satisfaction *and* frustration of Autonomy, Competence, Relatedness (6 subscales) | 7-point; item file on OSF | Free (IJHCS 2024, OSF osf.io/uq8mp) | 5 studies, 1,246 participants; invariant across single and repeated sessions; Autonomy-frustration subscale weaker [S14] |

Notes for a tiny team:

1. **miniPXI is the realistic option** for a 1–2 minute post-session survey. Its 2024 test-retest study (n = 100,
   4 games) found the single items for Enjoyment ("I had a good time playing this game", ICC .704) and several
   functional items moderately repeatable, while Challenge, Mastery, Ease of Control and Immersion (ICC .365) were
   poorly repeatable; a Net-Promoter item and an appreciation item were the most stable (ICC about .79) [S15].
   Implication: with 3–10 testers, single items are useful for spotting *differences between builds*, not as
   precise scores. The exact item wording is in Haider et al. 2022; this session could only verify two items.
2. **BANGS** is the only listed scale that measures *frustration* of needs, which is the construct that matches
   "this grind feels like a chore" (autonomy frustration) and "I keep failing" (competence frustration). It is
   longer than miniPXI.
3. **PENS** is not free and its Relatedness items assume human multiplayer; it fits a bots-only game poorly.
4. **GEQ** should be avoided as a primary instrument: no peer-reviewed validation by its authors and repeated
   failures to reproduce its factor structure [S10, S11].

## 3. Grind, battle passes, FOMO and time-limited content

1. **Battle pass obligation (qualitative, small samples).** Gibson, Griffiths, Calado, Harris (2023), Computers
   in Human Behavior 145:107766, interpretative phenomenological analysis of microtransaction users: players who
   bought battle passes "felt a sense of obligation to continue playing the game"; worries centred on the
   difficulty and time needed to earn XP [S16]. Sample size not verified (IPA studies are typically under 15
   participants).
2. **Battle pass attitudes mostly negative.** A 2024 Journal of Gambling Studies qualitative paper (DOI
   10.1007/s10899-024-10365-9) reported that "attitudes towards battle passes were mainly negative, with discussion
   centring around the spend-grind trade off and elitism" (abstract via search snippet; full text paywalled;
   sample not verified) [S17].
3. **Petrovskaya and Zendle (2020, preprint)**, mixed-methods Dota 2 study: battle pass presence had minimal effect
   on player uptake; interviewees split between positive views and perceptions of elitism/unreachable rewards
   (via citing papers; sample not verified) [S18].
4. **Student theses (low weight).** Apex Legends (Malmö University): players engaged out of fear of missing out and
   were reluctant to abandon a started pass; Overwatch 2 (5 interviews): most did not report a noticeable change in
   engagement [S19].
5. **Monetisation fatigue survey (non-representative).** Arts Management and Technology Lab survey, Jan–Feb 2024,
   431 active gamers (≥ 3 h/week) recruited via Discord/Reddit/social media: 43% had never bought a battle pass;
   47% never or only yearly make in-game purchases; modal monthly spend $0 [S20].
6. **"Too much work to keep up".** A Fandom survey (reported by GameSpot) found fans prefer traditional games and
   that keeping up with live-service titles is "too much work"; the article could not be fetched in this session,
   so date, sample and percentages are unverified [S21].
7. **No representative survey found** that gives "X% of players feel battle passes are a job". The "games as a
   job" framing exists mainly in commentary [press] [S22].
8. **Intrinsic vs extrinsic motivation and wellbeing (telemetry + survey).** Vuorre et al. (2022), Royal Society
   Open Science, 38,935 players of 7 games (including Apex Legends and Forza Horizon 4), six weeks of publisher
   telemetry plus three survey waves: playtime had little to no causal effect on wellbeing; intrinsic motivation was
   associated with higher life satisfaction (+0.18, CI excludes zero), extrinsic motivation with lower wellbeing
   (CIs include zero) [S23]. Ballou et al. (2025), 703 casual adult Nintendo Switch players, about 150 games,
   140,000 h of telemetry: perceived value of gaming ("gaming life fit"), not hours, predicted wellbeing [S24].
   Relevance: these do not test progression systems directly, but they support designing rewards that feel
   *informational* (marking real skill/variety) rather than *obligatory*.

## 4. Large-scale sentiment (CoD, Forza Horizon, Halo Infinite)

### 4.1 Call of Duty camo and weapon-level grind

1. **Complaints** [press, summarising forum/Reddit sentiment]: Black Ops 6 base camos required 100 headshots per
   weapon; high-tier camos on even one weapon class were described as out of reach for many players [S25]; players
   requested an in-game challenge tracker because progress was invisible [S25]; camo challenges were said to push
   players to play for cosmetics instead of objectives in public matches [S26] and to encourage camping
   (Modern Warfare II, 2022) [S27].
2. **Developer responses** [press]: Black Ops 6 removed the weapon-level gate so camo challenges count from the
   moment a weapon is unlocked, made specific categories easier in Season 1 Reloaded, and restored the challenge
   tracker; Black Ops 7 added a Camo Hub and lowered some requirements, though one review argued total effort stayed
   similar [S25].
3. **Weapon levels and attachments.** PC Gamer's Modern Warfare II review: "it takes too long to unlock attachments,
   and it's hard to know what it is you're even chasing" [S28]. Before launch, players called 60–70 levels per
   weapon (Vanguard) "an unnecessary grind"; MWII's shared "platform" attachment unlocks reduced per-gun grind but
   were criticised as too complicated [S28].
4. **Pattern.** Recurring complaints are (a) invisible progress, (b) requirements that force a play style
   (headshots, camping, specific modes), (c) long gates before the interesting part starts, (d) unclear goals.
   Praise clusters around changes that remove gates and make progress visible.

### 4.2 Forza Horizon: the reward flood

1. [forum/anecdotal] Official Forza forum and GTPlanet threads on Forza Horizon 5 (2021): progression "centered
   around wheelspins", rewards "not earned", high-value cars handed out at the start, leading to early boredom;
   some posters argue the series should have no progression at all [S29].
2. [press] Pure Xbox (November 2021) reported fans saying they were already bored with Horizon 5 [S29].
3. [press, secondary] A February 2022 update reportedly removed wheelspins from many car mastery trees, motivated by
   wheelspin farming that harmed the auction economy (secondary source, treat with caution) [S29].
4. [press] PC Gamer's Forza Horizon 6 coverage states that wheelspins were intentionally made rarer "to encourage
   more satisfying, linear progression" [S29]. This is the designer-side admission that the flood was a problem.

### 4.3 Halo Infinite multiplayer (November 2021)

1. [press] At launch, battle pass XP came only from daily/weekly challenges, not from playing matches; players
   objected to the pacing, not to the pass content [S30].
2. [telemetry-ish, press] Kotaku (November 2021): Steam rating still "Mostly Positive", about 17,000 of nearly
   23,000 reviews positive, praise for feel and balance, the battle pass "the one exception" [S30].
3. [press] 343 Industries added XP for finishing matches within days, called it "an initial step", and later tuned
   further; Windows Central later wrote that progression was still slow for many players [S30].
4. [forum/anecdotal] A 2023 Steam discussion still cited "progression is still stupidly slow / tied to challenges"
   as a reason for the mixed rating [S30].
5. **Lesson** consistently drawn in coverage: progression that does not reward simply playing well (only
   challenge completion) feels like homework.

## 5. Playtime data

### 5.1 Hours per week

| Source | Population | Figure |
| --- | --- | --- |
| Limelight State of Online Gaming 2021 [S31] [survey] | about 4,000 weekly gamers, 8 countries | 8.45 h/week global mean; US 7.71 h |
| Limelight 2018 [S31] [survey] | about 3,000 weekly gamers 18+, 6 countries | about 6 h/week mean |
| ESA Essential Facts 2024 [S32] [survey] | US population 5–90 | 61% play at least 1 h/week (hours mean not verified) |
| AMT Lab 2024 [S20] [survey, non-representative] | 431 gamers ≥ 3 h/week | 22% 4–9 h, 27% 10–19 h, 24% 20–29 h, 27% > 29 h |
| Ballou et al. 2025 [S24] [telemetry] | 703 casual adult Switch players | over half logged **no** play in the 2 weeks before the survey; top 10% about 60 min/day |

Means are inflated by heavy players; the medians are not published in the sources found. Self-report surveys of
"weekly gamers" exclude people who play less than weekly.

### 5.2 Sessions, daily playtime, retention

GameAnalytics 2026 benchmarks (2025 data; PC: 3,582 games with ≥ 100 MAU; via a sponsored summary of the report)
[S33] [telemetry/industry-report]:

| PC metric | Median | Top 25% | Top 10% | Top 1% |
| --- | --- | --- | --- | --- |
| Session length | 18 min | often > 30 min | n/a | > 100 min |
| Sessions per active day | 1.65–1.7 | n/a | about 3 | 7–10 |
| Playtime per active user per day | 32–33 min | 70 min | 120 min | > 300 min |
| D1 retention | n/a | 15–16% | n/a | 50–60% |
| D7 retention | n/a | n/a | n/a | > 20% |
| D30 retention | n/a | n/a | about 2.5% | 10% |

These are SDK-integrated (mostly small and mid-size) titles, not representative of all PC games, and "daily
playtime" counts only days on which the user played.

### 5.3 Steam Deck and handhelds

1. No published Valve figure on Steam Deck session length was found. Valve reports aggregates (about 330 million
   hours on Steam Deck in 2024, via PCGamesN) and opt-in frame-rate telemetry [S34].
2. The only handheld-related telemetry found is the Switch study above (not split by handheld/docked mode) [S24].
3. Assumption, not data: handheld play is often fitted into gaps, which pushes toward shorter sessions. This is
   unmeasured here.

### 5.4 Finishing games

1. [paper] Steam achievement analysis of single-player games: for nearly half of the games with an identifiable
   completion achievement (202), 10% or fewer players finished the main game (Springer chapter, 2017; abstract via
   snippet, paywalled) [S35].
2. [press] Digitec/Galaxus analysis of about 100 games (SteamDB and PlayStation trophy data): on average 38.8% of
   players finish, with 17.9 h playtime per game [S36]. Den of Geek: 26.6% of Steam players finished Elden Ring's
   main story; 40.8% finished the short, linear Stray [S36].
3. [telemetry] Steam Replay 2025: median of 4 games played per user in the year; about 14% of playtime went to
   games released that year [S37].
4. Implication: a 55-level cap or a full weapon roster will be reached by a minority. Rewards placed late are seen
   by few players.

## 6. Solo vs co-op vs PvP

1. [survey] MIDiA Research (published October 2024; about 9,000 gamers across several countries per press
   coverage): 53% say single-player is their favourite way to play; 16–19 year olds 30%, 20–24 year olds 35%;
   preference for single-player rises with age (press: 74% of over-55s) [S38].
2. [survey] Ampere Analysis (published November 2025, 34,428 respondents, 22 markets per press): 56% overall
   prefer single-player (press figures vary; US reported as 65%; 49% of 16–24 year olds) [S39].
3. [survey] YouGov Britain: 38% name "solo offline" as their preferred style [S39].
4. [survey] Quantic Foundry (2016, n > 1,200): co-operative play more appealing than competitive; local co-op with
   friends slightly ahead of online co-op; interest lower with strangers; local co-op is "the only game mode whose
   appeal is stable with age" [S40].
5. Relevance to a bots-only game: the age groups that most prefer solo or co-op (25+) are also the groups whose
   Competition motivation is lowest and whose Completion motivation stays stable [S2, S3]. A bots-only shooter
   loses the Competition/Community draw of PvP CoD, so progression, completion and variety carry more of the
   long-term motivation. No source found measures the share of *shooter* players who prefer PvE specifically.

## 7. Practical playtest methods for a tiny team

Sources give instruments and benchmarks; the plan below is a set of options, not a decision.

1. **Telemetry that fits Private War's local saves** (no server needed; log to a local file, export manually):
   - per match: duration, mode, map, bot difficulty, player count, XP earned by source, levels gained (account and
     weapon), unlocks granted, challenge progress;
   - per session: start/end time, matches played, whether the player quit mid-match;
   - derived: time-to-first-unlock, unlocks per session, matches per account level, matches per weapon level,
     share of sessions with zero unlocks, "dry spell" length (matches since last unlock).
2. **Quit points.** Log the last screen and last progression event before the session ends; GameAnalytics-style
   progression events (start/complete/fail) give a funnel per level [S33].
3. **Short survey (1–2 min) after a session**, options:
   - miniPXI Enjoyment item plus Progress Feedback, Clarity of Goals and Autonomy items (wording from [S12]);
   - one BANGS autonomy-frustration item (wording from the OSF item file [S14]);
   - two custom questions: "How did the speed of unlocks feel?" (1 = far too slow, 4 = right, 7 = far too fast) and
     "Did you know what you were working toward next?" (yes / partly / no). Custom items are not validated.
4. **Interpretation limits.** With 3–10 testers, use within-person comparisons between builds and look for large
   shifts. The miniPXI test-retest study shows single items are noisy [S15].

## 8. Implications for Private War (options and trade-offs)

### 8.1 A realistic time budget

The evidence suggests three player profiles; the maintainer must choose which one the pacing targets.

| Profile | Evidence | Assumed play |
| --- | --- | --- |
| Light casual | Over half of casual Switch adults play zero in a given 2-week window [S24] | 0–1 sessions/week, often weeks off |
| Target casual (Steam Deck evenings) | PC median session 18 min, median 32–33 min per active day [S33]; Limelight weekly-gamer mean 6–8.5 h/week, inflated by heavy players [S31] | 1–3 sessions/week x 30–60 min, about 1–3 h/week |
| Engaged | Top-quartile PC users 70 min per active day [S33]; 27% of an active-gamer sample > 29 h/week [S20] | 5–10+ h/week |

Option A: tune for about **2 h/week** (target casual). Then each 30–45 min session should contain at least one
visible unlock or level, and a weekly challenge set must be completable in about 2 h of normal play.
Trade-off: engaged players exhaust content in weeks; compensate with long-tail goals (camos, calling cards).

Option B: tune for about **5 h/week**. Trade-off: target casual players see roughly 40% of the intended reward rate
and may hit dry spells, which is the "WoW 1x" failure mode.

Option C: hybrid. Fast early levels (first sessions), slower later curve, plus weekly goals that cap at about 2 h of
play so missing a week costs little. This mirrors the evidence that most players never reach the end [S35, S36].

The current numbers (one account level per about 2 matches at level 12, one weapon level per 3–4 matches, attachments
clumped at weapon levels 16–17) can be checked against these budgets once match length is known (see open questions).

### 8.2 What the sentiment data warns against

1. **Progress only via challenges** (Halo Infinite 2021): always grant XP for simply playing matches [S30].
2. **Invisible progress** (CoD camo tracker): every chase needs a visible tracker [S25].
3. **Play-style coercion** (headshot/camping camos): challenges that force a narrow play style degrade matches;
   in a bots-only game the damage is to the player's own fun rather than to teammates, but the effect remains
   [S25, S27].
4. **Long gates before the interesting part** (Vanguard 70 levels, MWII attachments) and **reward floods**
   (Forza wheelspins) are both documented failure modes [S28, S29].
5. **FOMO and obligation** (battle pass studies): Private War has no monetisation, so the spend-grind trade-off does
   not apply, but time-limited weekly content can still create obligation [S16, S17]. A non-expiring pass and
   rolling or bankable weekly challenges reduce it.

### 8.3 Motivation fit

1. Completion is the most universal and age-stable motivation [S3, S5]: collection layers (calling cards, camos,
   per-weapon mastery) are likely to matter to many players even if few finish them.
2. Competition matters less for older and solo/co-op players [S2, S38]: rank-like prestige is less important than
   collection and variety.
3. Intrinsic motivation correlates with wellbeing, extrinsic less so [S23]: rewards that *signal* skill or variety
   ("100 kills with 5 different SMGs") are more defensible than raw repetition counts.

### 8.4 Minimal playtest and telemetry plan (option)

1. Add local JSON logging of match and session events (fields in section 7).
2. Run 2–3 testers for 2 weeks with their normal evenings; ask for the 5-item post-session survey once per session.
3. Compute: matches per account level, matches per weapon level, unlocks per session, sessions with zero unlocks,
   time to first attachment on a new weapon.
4. Compare to the chosen budget (section 8.1) and adjust curves; repeat with the next build.

## Open questions for the maintainer

1. What is the typical match length in Private War (minutes) for each mode? All pacing maths depends on it.
2. Which profile from section 8.1 is the design target: about 2 h/week, about 5 h/week, or a hybrid?
3. Should weekly challenges expire, roll over, or bank (for example up to 3 weeks)?
4. How many testers can run a 2-week playtest, and are they willing to answer a 1–2 minute survey after each
   session?
5. Is local telemetry logging acceptable (opt-in, stays on the player's machine), or should it be dev-builds only?
6. Should the "most players never finish" evidence change where the best rewards sit (earlier) or only how they are
   framed (long-tail goals)?

## Sources

1. [industry-report] Quantic Foundry, *Gamer Motivation Model Reference*, 2019 (self-selected online profile,
   >1.25M at the time). <https://quanticfoundry.com/wp-content/uploads/2019/04/Gamer-Motivation-Model-Reference.pdf>
2. [survey] N. Yee, "5 things we learned about the appeal of competition from over 239,000 gamers", Game Developer,
   2016, n > 239,000.
   <https://www.gamedeveloper.com/business/5-things-we-learned-about-the-appeal-of-competition-from-over-239-000-gamers>
3. [survey] "Survey: Men play games to compete, women play to complete", Game Developer, December 2016, n > 250,000
   (Quantic Foundry). <https://www.gamedeveloper.com/game-platforms/survey-men-play-games-to-compete-women-play-to-complete>
4. [industry-report] Player Driven, "Quantic Foundry's Nick Yee on Gamer Motivations, Part 2", 2025 (1.75M+ over a
   decade, about 200k/year). <https://playerdriven.substack.com/p/quantic-foundrys-nick-yee-on-gamer-6b7>
5. [survey, secondary] Quantic Foundry age analyses (2019 blog quoted via search snippets; n = 107,100 analysis);
   PC Gamer coverage. <https://www.pcgamer.com/study-analyses-gaming-tastes-as-we-age> ; <https://quanticfoundry.com/?p=2400>
6. [paper] N. Yee, "Motivations for play in online games", CyberPsychology & Behavior 9:772–775, 2006, about 3,000
   MMORPG players; DiGRA 2005 version. <https://bibbase.org/network/publication/yee-motivationsforplayinonlinegames-2006> ;
   <https://dl.digra.org/index.php/dl/article/download/239/239>
7. [paper] Ryan, Rigby, Przybylski, "The motivational pull of video games: a self-determination theory approach",
   Motivation and Emotion, 2006. <https://link.springer.com/content/pdf/10.1007%2Fs11031-006-9051-8.pdf>
8. [paper] Johnson, Gardner, Perry, "Validation of two game experience scales: the PENS and GEQ", IJHCS 118:38–46,
   2018 (sample size not verified in this session).
   <https://typeset.io/pdf/validation-of-two-game-experience-scales-the-player-2rwxm0820y.pdf>
9. [paper] Game Evaluation Repository, PENS entry (21 items, 7-point, owned by Immersyve).
   <https://game-evaluation.github.io/questionnaires/repository/pens.html>
10. [paper] Law, Brühlmann, Mekler, "Systematic review and validation of the Game Experience Questionnaire (GEQ)",
    CHI PLAY 2018, N = 633 (authors and N via snippet). <https://edoc.unibas.ch/85673/1/20211214105037_61b868ed18195.pdf> ;
    <https://osf.io/2kw4g>
11. [paper] Game Evaluation Repository, GEQ entry. <https://game-evaluation.github.io/questionnaires/repository/geq.html>
12. [paper] Haider et al., "miniPXI: Development and Validation of an Eleven-Item Measure of the Player Experience
    Inventory", CHI PLAY 2022, 628 players + 15 experts.
    <https://www.researchportal.be/en/publication/minipxi-development-and-validation-eleven-item-measure-player-experience-inventory>
13. [paper] Azadvar, Canossa, "UPEQ: Ubisoft Perceived Experience Questionnaire", FDG 2018; critique by Kayser,
    Perrig, Brühlmann. <https://researchr.org/publication/AzadvarC18>
14. [paper] Ballou et al., "The Basic Needs in Games Scale (BANGS)", IJHCS 2024, 5 studies, 1,246 participants;
    user guide. <https://eprints.whiterose.ac.uk/212508/> ; <https://stepherbin.github.io/docs/bangs/userguide>
15. [paper] Haider et al., "An Investigation of the Test-Retest Reliability of the miniPXI", 2024, n = 100, 4 games.
    <https://arxiv.org/html/2407.19516v1>
16. [paper] Gibson, Griffiths, Calado, Harris, "Videogame player experiences with micro-transactions: an
    interpretative phenomenological analysis", Computers in Human Behavior 145:107766, 2023 (sample not verified).
    <https://irep.ntu.ac.uk/id/eprint/48698>
17. [paper] Qualitative study of battle pass attitudes, Journal of Gambling Studies, 2024 (abstract via snippet;
    paywalled). <https://link.springer.com/article/10.1007/s10899-024-10365-9>
18. [paper] Petrovskaya, Zendle, "The Battle Pass: a Mixed-Methods Investigation into a Growing Type of Video Game
    Monetisation", OSF preprint, 2020 (sample not verified). <https://www.sciencegate.app/document/10.31219/osf.io/vnmeq>
19. [paper, student theses] Malmö University (Apex Legends) and Theseus (Overwatch 2, 5 interviews).
    <https://mau.diva-portal.org/smash/get/diva2:1774074/FULLTEXT02.pdf> ;
    <https://www.theseus.fi/bitstream/10024/883328/2/Kunelius_Konsta.pdf>
20. [survey] AMT Lab, "Live Service Games Part II", survey Jan–Feb 2024, 431 gamers, non-representative.
    <https://amt-lab.org/blog/2025/3/live-service-games-part-ii>
21. [survey, unverified] GameSpot on a Fandom survey about games-as-a-service (not fetched).
    <https://gamespot.com/articles/fans-prefer-traditional-games-but-games-as-a-service-dominates-survey-reveals/1100-6509237/>
22. [press] Club386, "Why live-service fatigue is growing among gamers"; PC Gamer, "Battle passes make me never want to
    play a multiplayer game ever again". <https://www.club386.com/why-live-service-fatigue-growing-gamers/> ;
    <https://www.pcgamer.com/battle-passes-make-me-never-want-to-play-a-multiplayer-game-ever-again>
23. [paper, telemetry] Vuorre, Johannes, Magnusson, Przybylski, "Time spent playing video games is unlikely to impact
    well-being", Royal Society Open Science 9:220411, 2022, 38,935 players, 7 games. <https://pmc.ncbi.nlm.nih.gov/articles/PMC9326284>
24. [paper, telemetry] Ballou, Vuorre, Hakman, Magnusson, Przybylski, "Perceived value of video games, but not hours
    played, predicts mental well-being in casual adult Nintendo players", Royal Society Open Science, 2025, 703
    players. <https://www.oii.ox.ac.uk/its-quality-not-quantity-that-predicts-gamers-wellbeing-new-study-finds/>
25. [press] Black Ops 6/7 camo grind coverage: Gamereactor; Dexerto; Charlie Intel; Ginx; Windows Central.
    <https://www.gamereactor.eu/what-really-grinds-my-gears-call-of-duty-black-ops-6s-camo-challenges-1453823/> ;
    <https://dexerto.com/call-of-duty/black-ops-6-devs-promise-long-awaited-change-to-make-camo-grind-easier-3026787> ;
    <https://charlieintel.com/call-of-duty/black-ops-6s-camo-grind-removes-most-time-consuming-step-336884> ;
    <https://www.windowscentral.com/gaming/the-black-ops-7-camo-grind-is-less-stressful-than-last-year-with-one-big-change-everyone-will-love>
26. [press, summarising forum/anecdotal] FandomWire, cosmetic grind dominating casual Black Ops 6 matches.
    <https://fandomwire.com/no-one-in-pubs-is-ever-going-to-seriously-play-obj-cosmetic-grind-still-dominates-casual-matches-in-black-ops-6-leaving-real-gameplay-behind/>
27. [press, summarising forum/anecdotal] Charlie Intel, "CoD players call for major changes to awful camo grind in
    Modern Warfare 2", 2022.
    <https://www.charlieintel.com/call-of-duty-modern-warfare-2/cod-players-call-for-call-for-major-changes-to-awful-camo-grind-in-modern-warfare-2-188277/>
28. [press] PC Gamer, Modern Warfare II review; Charlie Intel on MWII weapon progression vs Vanguard.
    <https://pcgamer.com/call-of-duty-modern-warfare-2-review> ;
    <https://www.charlieintel.com/call-of-duty-modern-warfare-2/modern-warfare-2s-weapon-progression-makes-leveling-up-guns-much-easier-198651/>
29. [forum/anecdotal + press] Forza forums; Pure Xbox; ExpertBeacon (secondary); PC Gamer on Forza Horizon 6.
    <https://forums.forza.net/t/fh5-10-day-review-from-a-veteran-player/536486> ;
    <https://forums.forza.net/t/the-lack-of-progression-and-what-i-think-could-improve-it/538991> ;
    <https://purexbox.com/news/2021/11/some-forza-fans-say-theyre-getting-bored-with-horizon-5-already> ;
    <https://expertbeacon.com/did-forza-remove-wheel-spins/> ;
    <https://pcgamer.com/games/racing/forza-horizon-6s-return-to-wristband-progression-isnt-the-stand-in-for-a-career-mode-i-wanted-it-to-be-but-maybe-thats-for-the-best>
30. [press + forum/anecdotal] Halo Infinite battle pass: GamesRadar; Kotaku (Steam reviews); PC Gamer; Windows
    Central; Steam discussion. <https://gamesradar.com/halo-infinite-battle-pass-progression-controversy> ;
    <https://kotaku.com/halo-infinite-s-multiplayer-as-told-by-steam-reviews-1848084939> ;
    <https://pcgamer.com/halo-infinites-slow-battle-pass-progression-is-being-looked-at-says-343-industries> ;
    <https://windowscentral.com/heres-how-fix-halo-infinite-multiplayer-progression> ;
    <https://steamcommunity.com/app/1240440/discussions/0/7098294290825027432>
31. [survey] Limelight Networks, State of Online Gaming 2021 (about 4,000, 8 countries) and 2018 (about 3,000, 6
    countries), via press releases. <https://www.businesswire.com/news/home/20210310005514/en/Limelights-State-of-Online-Gaming-Report-Shows-Online-Gaming-Spikes-as-Consumers-Seek-Social-Connection-and-Entertainment> ;
    <https://www.businesswire.com/news/home/20180328005610/en/>
32. [survey] ESA, Essential Facts 2024. <https://www.theesa.com/wp-content/uploads/2024/05/Essential-Facts-2024-FINAL.pdf>
33. [telemetry/industry-report] GameAnalytics 2026 Mobile & PC Benchmarks (2025 data, 3,582 PC games), via GameDev
    Reports summary (sponsored). <https://gamedevreports.substack.com/p/gameanalytics-mobile-and-pc-game>
34. [press] PCGamesN, Steam Deck Year in Review 2024 (330 million hours).
    <https://www.pcgamesn.com/steam-deck/year-in-review-2024-growth>
35. [paper] Steam achievement completion analysis, Springer (ICEC 2017 proceedings chapter; paywalled, figures via
    snippet). <https://link.springer.com/chapter/10.1007/978-3-319-66715-7_65>
36. [press] Digitec/Galaxus, "Hardly anyone finishes games"; Den of Geek on Hogwarts Legacy completion.
    <https://www.galaxus.ch/en/page/hardly-anyone-finishes-games-so-why-are-they-so-long-37002> ;
    <https://www.denofgeek.com/?p=824046>
37. [telemetry, press] PC Gamer on Steam Replay 2025.
    <https://www.pcgamer.com/gaming-industry/steams-2025-replay-reveals-we-all-once-again-spent-around-14-percent-of-our-time-on-games-released-in-the-same-year-which-apparently-shakes-out-to-a-median-of-0-56-new-games>
38. [survey] MIDiA Research, "Most gamers prefer single-player games", October 2024; Kotaku coverage for sample.
    <https://www.midiaresearch.com/blog/most-gamers-prefer-single-player-games> ;
    <https://kotaku.com/survey-data-study-53-percent-gamers-singleplayer-pvp-1851665722>
39. [survey] Ampere Analysis via Kotaku and AV Club (November 2025); YouGov Britain.
    <https://kotaku.com/new-survey-most-players-around-world-prefer-singleplayer-games-solo-2000644895> ;
    <https://www.avclub.com/gamers-prefer-single-player-games-over-multiplayer> ;
    <https://yougov.com/en-gb/articles/43184-britain-multiplayer-gaming-more-popular-among-heav>
40. [survey] Quantic Foundry co-op vs competitive, 2016, n > 1,200, via Game Developer.
    <https://www.gamedeveloper.com/design/survey-co-op-more-popular-than-competitive-multiplayer-especially-if-it-s-local>
