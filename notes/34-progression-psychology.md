# 34 — Progression psychology: reward pacing and motivation

Status: research (2026-11-22). Research explains *why*; it is not a decision. Where this note and `../design/`
disagree, `design/` wins.

Scope: the psychology and behavioural-science side of progression pacing. Industry talks, case studies and player
survey data are covered by sibling notes and are referenced here only where a researcher wrote them. No game build,
telemetry or playtest was used. Source numbers in square brackets refer to the "Sources" list at the end.

Evidence-strength labels used in each section:

- **Strong**: meta-analysis, large preregistered or telemetry study, or a finding replicated across many labs.
- **Moderate**: several peer-reviewed studies, but lab-only, small samples, or a single field study.
- **Weak**: one study, practitioner reasoning, or a contested/failed-replication finding.
- **Contested**: published, credible disagreement exists; both sides are cited.

Source-access note: where only an abstract, a press release or a secondary summary was read, the text says so.
Full text was read for [1] (Deci, Koestner and Ryan 1999, abstract and result sections), [4] (Hopson 2001),
[5] (Hopson 2012 retrospective), [13] (Thaler 1985, principle statements) and [30] (Alexandrovsky et al. 2024).
Everything else relies on abstracts, publisher records or secondary summaries found by search.

## Question

What does research in psychology and behavioural science say about reward pacing, progression and long-term
motivation in games, and what does it imply for a solo/co-op progression system against bots, where there is
little social audience?

Pain points this note is meant to inform (from the maintainer):

1. Account level max 55; at level 12 one level takes about 2 matches.
2. One weapon level takes about 3–4 matches; attachments arrive in a clump at weapon levels 16–17, nothing earlier.
3. Hundreds of auto-discovered weapons; planned weekly challenges, calling cards, programmatic unlocks, possibly
   non-expiring season passes.
4. Target failure modes to avoid: "Forza Horizon problem" (reward flood, nothing meaningful) and "WoW 1x server"
   (so slow that players quit first).
5. Context: free, no monetization, short Steam Deck evening sessions (a couple of matches), solo or 2–4 friends.

## 1. Reinforcement schedules and the ethics of compulsion loops

### 1.1 Findings

1. **The four classic schedules.** Ferster and Skinner's *Schedules of Reinforcement* [2] (pigeon experiments)
   established fixed-ratio (FR), variable-ratio (VR), fixed-interval (FI) and variable-interval (VI) schedules.
   Hopson's widely cited game-design translation [4] (read in full) describes the typical response patterns:
   - FR (reward after N actions, for example "level up every 1000 XP"): "a long pause, then a steady burst of
     activity as fast as possible until a reward is given". The post-reward pause grows with the ratio; Hopson warns
     that rising requirements can lead players to quit.
   - VR (reward after an unpredictable number of actions, for example random drops): "a steady flow of activity at
     a reasonably high rate", with no post-reward pause. Highest overall activity of the four.
   - FI (first action after a set time pays, for example a daily reset): pause after the reward, then more checking
     as the time approaches.
   - VI (unpredictable time): steady but slower activity, "no low points where the players' attention might wander".
2. **Practical mapping to progression.** An XP bar with a fixed cost per level is an FR schedule in "XP units";
   a level curve whose cost rises per level is an FR schedule with a growing ratio, which is exactly the condition
   Hopson associates with lengthening pauses and quitting [4]. Random loot is VR. Weekly challenges with a reset
   are FI-like.
3. **Reward cuts are aversive.** Hopson: "reducing the level of reinforcement is a very punishing thing for your
   players"; violated expectations are "perceived as an aggressive act, an unfair decision by the game's creators"
   [4]. Relevant to any rebalance that makes progress slower for existing players.
4. **The prediction-error account.** Schultz, Dayan and Montague [3] proposed that dopamine neurons signal errors in
   reward prediction (better or worse than expected), not reward itself. A fully predictable reward produces
   little prediction-error signal once learned. This is the usual neuroscientific explanation of why surprise and
   variability feel stronger than a guaranteed payout. (Abstract and summaries read, not full text.)
5. **Near-miss and rarity effects come from gambling research.** Clark et al. 2009 [9] (fMRI, slot-machine task)
   found near-misses were rated *less pleasant* than full misses yet *increased the desire to keep playing*, and
   recruited win-related striatal and insula activity, more so when the player had personal control. Larche et al.
   [10] found rarer loot box rewards produced larger arousal responses and stronger urge to open more boxes.
6. **Ethics and criticism.**
   - Zagal, Björk and Lewis [6] catalogued "dark game design patterns" in three groups: temporal (for example
     grinding, playing on a schedule), monetary and social-capital. Deterding, Stenros and Montola [7] argued the
     concept lacks an explicit ethical framework and is not a productive basis for ethical analysis.
   - King and Delfabbro [8] defined "predatory monetization" (limited disclosure, unavoidable solicitations,
     manipulated reward outcomes). Editorial; abstract and press coverage read only.
   - Zendle and Cairns [11] found loot box spending linked to problem-gambling severity in a large survey, and a
     replication [12] found the link again; direction of causality is unknown.
   - Hopson's own position in his 2012 retrospective [5]: calling games "Skinner boxes" "completely miss[es] the
     point"; contingencies "are ethical if the designer believes the player will have more fun" by meeting them.
     This is a practitioner opinion, not a research finding.

### 1.2 Evidence strength

- Schedule effects on response rate: **Strong** in animal and human operant research [2]; their transfer to games
  is **Moderate/Weak** (mostly argued by practitioners such as [4], little direct game experimentation found).
- Dopamine prediction-error model: **Strong** as neuroscience; its use to explain game enjoyment is an inference.
- Near-miss motivation: **Moderate** (lab and fMRI, gambling context) [9].
- Loot box – problem gambling association: **Moderate**, correlational [11, 12].
- Dark-pattern taxonomy: **Contested** as an ethical framework [6, 7].

## 2. Self-Determination Theory, PENS, and the crowding-out of intrinsic motivation

### 2.1 Findings

1. **Basic needs.** Self-Determination Theory (SDT) holds that satisfaction of three needs — competence, autonomy,
   relatedness — yields enhanced self-motivation and well-being [14].
2. **Games specifically (PENS).** Ryan, Rigby and Przybylski 2006 [15], four studies: in-game autonomy, competence
   and relatedness independently predicted enjoyment and intention for future play. This is the origin of the
   Player Experience of Need Satisfaction (PENS) measure [16]. Rigby and Ryan's book *Glued to Games* [17] argues
   that games that satisfy these needs poorly are not engaging (book review read, not the book).
3. **Need satisfaction versus compulsion.** Przybylski, Weinstein, Ryan and Rigby 2009 [18]: low need satisfaction
   predicted *obsessive* passion (more play, post-play tension, lower enjoyment); high need satisfaction predicted
   *harmonious* passion and energy after play. High play correlated with lower well-being only for obsessive
   players. (Abstract-level summary.)
4. **Crowding-out / overjustification, with numbers.** Deci, Koestner and Ryan's meta-analysis of 128 experiments
   [1] (abstract and result sections read):
   - Expected tangible rewards undermined free-choice intrinsic motivation: engagement-contingent d = −0.40,
     completion-contingent d = −0.36, performance-contingent d = −0.28; expected tangible overall d = −0.36.
   - **Unexpected** tangible rewards had no effect (free-choice d = 0.01, 9 studies; self-report d = 0.05).
   - **Positive feedback enhanced** intrinsic motivation (free-choice d = 0.33, self-reported interest d = 0.31).
   - Tangible rewards were more detrimental for children than college students.
5. **The controversy.** Cameron and Pierce (1994) and Cameron, Banko and Pierce 2001 [19] argued negative effects
   are limited, that rewards for low-interest tasks *raise* free-choice motivation, and that performance-level
   rewards leave intrinsic motivation unchanged or raise it. Deci, Koestner and Ryan replied that the earlier
   meta-analysis was flawed [20]. The dispute is unresolved in the literature.
6. **Do in-game rewards count as "extrinsic"?** Direct evidence is thin.
   - Mekler et al. 2017 [21] (points, levels, leaderboards in an image-tagging task): no effect on intrinsic
     motivation or competence satisfaction either way; elements raised *quantity* of output, acting as extrinsic
     incentives.
   - A 2022 experiment in *Current Psychology* [22] with children rewarded for playing video games reported no
     overall undermining, but reduced willingness to play for games with high initial interest. Only the search
     snippet was read; authors and full method not verified.
   - Practitioner commentary [23] suggests the informational-versus-controlling distinction from Cognitive
     Evaluation Theory: an achievement that recognises what the player already did reads as informational;
     one that prescribes how to play reads as controlling. **Opinion**, not tested.
7. **Feedback type matters.** Burgers et al. 2015 [24] (brain-training game, N = 157, abstract read): evaluative
   feedback increased later voluntary play, *comparative* feedback decreased it; positive feedback satisfied
   competence and autonomy and boosted intrinsic motivation; negative feedback lowered competence but increased
   immediate replay ("repair" behaviour).
8. **Well-being from telemetry.** Vuorre et al. 2022 [25] (about 39,000 players, seven publishers' telemetry):
   time played has a very small average effect on well-being. Ballou et al. 2025 [26] (703 adult Nintendo players,
   about 140,000 hours): hours did not predict well-being; *perceived value* of play and "gaming life fit" did.
   Johannes, Vuorre and Przybylski 2021 [27] reported a small positive correlation of play with well-being and
   linked experience quality (need satisfaction) to it; full text could not be opened, so details are unverified.

### 2.2 Evidence strength

- SDT needs predicting game enjoyment: **Strong** (replicated, large literature) [14, 15, 16].
- Expected tangible rewards undermining intrinsic motivation in lab tasks: **Strong but Contested** [1, 19, 20].
- Unexpected rewards neutral, positive feedback enhancing: **Strong** within [1]; Cameron's side agrees on verbal
  rewards [19].
- Transfer of overjustification to in-game XP/levels: **Weak** (few direct tests, mixed) [21, 22].
- Playtime not driving well-being; quality of experience does: **Strong** for the time finding [25, 26],
  **Moderate** for the quality finding (cross-sectional) [26].

## 3. Flow and difficulty/progression pacing

### 3.1 Findings

1. **Flow** (Csikszentmihalyi [28]) is deep absorption that arises when challenge matches skill, goals are clear
   and feedback is immediate. Too much challenge produces anxiety, too little produces boredom.
2. **Meta-analysis.** Fong, Zaleski and Leach [29] pooled 28 studies: challenge–skill balance had a moderate
   relationship with flow and a weaker one with intrinsic motivation; clear goals and sense of control were also
   robust antecedents. (Abstract only.)
3. **Games.** Sweetser and Wyeth's GameFlow model [31] maps flow to eight game criteria: concentration, challenge,
   player skills, control, clear goals, feedback, immersion, social interaction. Chen [32] argues that each player
   has a personal flow zone and favours player-chosen difficulty over invisible automatic adjustment, because
   automatic adjustment can strip autonomy. Chen's article is a designer essay (**opinion/talk-level**).
4. **Implication for progression.** Flow is about moment-to-moment *challenge*, not about unlock pacing. Unlocks
   interact with flow mainly by changing player power (a new attachment can lower effective challenge) and by
   supplying clear proximate goals.

### 3.2 Evidence strength

- Challenge–skill balance as a flow antecedent: **Moderate–Strong** (meta-analysis, moderate effect) [29].
- GameFlow and personal flow zones as design heuristics: **Weak–Moderate** (expert review, designer argument).

## 4. Goal gradient, endowed progress, Zeigarnik, near-miss and progress bars

### 4.1 Findings

1. **Goal-gradient effect.** Kivetz, Urminsky and Zheng 2006 [33]: in a real "buy 10, get 1 free" café programme,
   purchase intervals shortened as customers approached the reward; in an online song-rating programme, users
   visited more, rated more per visit and persisted longer near the goal. After a reward is redeemed, the pace
   "resets" (secondary commentary). **Field evidence.**
2. **Illusory/endowed progress.** Same paper [33]: a 12-stamp card with 2 pre-filled stamps sped up purchases
   compared with an empty 10-stamp card (same real requirement). Nunes and Drèze 2006 [34] (car wash): 34 % of
   customers with a 10-space card with 2 free stamps completed versus 19 % with an empty 8-space card (secondary
   summaries; full text not read). Moderators: the effect was stronger when a reason for the head start was given
   and when progress was recorded in points rather than purchases.
3. **Zeigarnik effect is not reliable.** Ghibellini and Meier 2025 [35] meta-analysed the Zeigarnik (better memory
   for interrupted tasks) and Ovsiankina (tendency to resume interrupted tasks) effects. They found no general
   memory advantage for unfinished tasks; the Ovsiankina resumption tendency held as a general effect.
   (Abstract and secondary summaries; the exact study counts differ between summaries.) So "unfinished bars nag
   people back" rests on the resumption effect, not on the memory effect popular in design writing.
4. **Near-miss.** See section 1: near-misses are less pleasant but more motivating [9]. In progression terms, a bar
   at 95 % at the end of a session is a near-miss-like state. Whether that is healthy depends on whether the
   player can reach it on their own terms (the effect was stronger under personal control [9]).
5. **Personal bests as reference points.** Anderson and Green 2018 [36] (133 million online chess games): players
   exert extra effort as they near their personal-best rating and *quit once they set a new one*. Goals act as
   reference points; reaching one is a natural stopping point.
6. **Goal setting.** Locke and Latham's review [37] summarises 35 years of evidence that specific, difficult
   but attainable goals with feedback raise performance more than vague "do your best" goals. (Abstract and
   secondary description; this is one of the most replicated findings in organisational psychology.)
7. **Fresh-start effect.** Dai, Milkman and Riis 2014 [38]: aspirational behaviour (gym visits, goal commitments,
   "diet" searches) rises after temporal landmarks such as the start of a week or month. Relevant to weekly resets.

### 4.2 Evidence strength

- Goal gradient: **Moderate–Strong** (field + online, replicated concept) [33].
- Endowed progress: **Moderate** (field experiments; one main paper each) [33, 34].
- Zeigarnik memory effect: **Weak / failed to replicate in aggregate** [35]; Ovsiankina resumption: **Moderate** [35].
- Personal-best reference points: **Strong** as observational big-data evidence in one domain [36].
- Goal-setting theory: **Strong** [37].
- Fresh-start effect: **Moderate** (archival field data) [38].

## 5. Hedonic adaptation, reward devaluation and variety (the "Forza problem")

### 5.1 Findings

1. **Hedonic adaptation.** Frederick and Loewenstein [39] define it as a decline in the emotional intensity of good
   and bad circumstances over repeated or continued exposure. A reward that arrives every few minutes becomes the
   new baseline; its absence starts to feel like a loss.
2. **Prediction error again.** If rewards are fully expected, their signal is small [3]. A constant drip is fully
   expected.
3. **Segregate gains.** Thaler 1985 [13] (read): "segregate gains and integrate losses". Two separate gains feel
   better than one combined gain of the same size. Taken alone, this argues *for* many small rewards; combined with
   adaptation, it argues for separating rewards *in time and kind* rather than stacking many in one screen.
4. **Interruptions restore enjoyment.** Nelson and Meyvis 2008 [40]: breaks during a pleasant experience disrupt
   adaptation and intensify enjoyment afterwards (massage, music). Nelson, Meyvis and Galak 2009 [41] showed the
   same for TV commercial breaks. (Secondary summaries read.)
5. **Variety versus rate.** Galak, Kruger and Loewenstein 2011 [42]: people prefer variety to repetition of a better
   single stimulus under continuous consumption, but the preference *reverses* when breaks between episodes reduce
   satiation. Galak, Redden and Kruger 2009 [43]: simply recalling past variety restores enjoyment of a satiated
   favourite. Variety must be noticed to help.
6. **Synthesis for games (inference, not a tested game finding).** The Forza-style flood combines three things the
   literature predicts will devalue rewards: very high rate (adaptation), high predictability (low prediction
   error) and low distinctiveness (rewards look alike, so variety is not noticed). Reward *quantity* is less
   important than rate relative to the player's adaptation, distinctiveness, and whether rewards are spaced by
   breaks.

### 5.2 Evidence strength

- Hedonic adaptation as a general phenomenon: **Strong** [39].
- Segregation of gains: **Moderate** (classic, widely cited; based on hypothetical-choice studies) [13].
- Interruptions disrupting adaptation: **Moderate** (multiple studies by one group) [40, 41].
- Variety × rate interaction and variety amnesia: **Moderate** [42, 43].
- Direct game evidence for "reward flood devalues rewards": **not found**; the claim is an inference.

## 6. Loss aversion, FOMO, time-limited content

### 6.1 Findings

1. **Loss aversion** (prospect theory, Kahneman and Tversky 1979 [44]): losses loom larger than equivalent gains.
   This is the standard rationale for battle-pass expiry and daily streaks.
2. **Contested.** Gal and Rucker 2018 [45] argue loss aversion is far less robust and universal than assumed and
   that many cited effects have alternative explanations (for example inertia). Simonson and Kivetz [46] disagreed
   with parts of the evidence but accepted that loss aversion is contingent. Treat "losses loom larger" as
   context-dependent, not a law.
3. **FOMO.** Przybylski et al. 2013 [47] define fear of missing out as "a pervasive apprehension that others might be
   having rewarding experiences from which one is absent" and link higher FOMO to lower need satisfaction and lower
   mood and life satisfaction (correlational, social-media context).
4. **Battle passes specifically.** Peer-reviewed, experimental evidence isolating battle-pass FOMO effects was
   **not found** in this search. Adjacent: a 13-week longitudinal study (*Computers in Human Behavior Reports*,
   2024 [48], abstract only) reported a bidirectional FOMO ↔ loot box use relationship. Student theses and
   non-peer-reviewed reviews claim FOMO drives battle-pass engagement; they are not cited as evidence here.
5. **Obligation versus volition.** SDT research distinguishes "wanting to" from "having to" play [18]; time-limited
   rewards create pressure that SDT would classify as controlling (inference from [1, 14, 18]). The dark-pattern
   taxonomy lists "playing by appointment" as a temporal dark pattern [6].

### 6.2 Evidence strength

- Loss aversion: **Contested** [44, 45, 46].
- FOMO as a correlate of low need satisfaction and lower well-being: **Moderate** (correlational) [47].
- Battle-pass FOMO effects on wellbeing and churn: **no direct evidence found**.

## 7. Meaningful choice, agency, earned versus random rewards, effort justification

### 7.1 Findings

1. **Autonomy is one of the three needs** [14, 15]; choices that express player preference support it.
2. **Earned and completed effort raises value.** Norton, Mochon and Ariely 2012 [49] ("IKEA effect"): people value
   things they built themselves more, *but only if they completed them* — the effect disappeared when creations were
   destroyed or left unfinished.
3. **Effort paradox.** Inzlicht, Shenhav and Olivola 2018 [50] review evidence that effort is both a cost people
   avoid and a source of value people seek; meaning and value can come from effort itself.
4. **Unexpected rewards do not undermine** intrinsic motivation [1]; expected, contingent tangible rewards can.
   This suggests that surprise bonuses (not promised in advance) are low-risk for motivation.
5. **Random rewards and agency.** Near-misses are more motivating when the player chose the play [9], which is the
   gambling-adjacent side of agency: perceived control can increase persistence without increasing pleasure.
6. **Recognition versus prescription.** Positive, evaluative feedback supports competence and autonomy; comparative
   feedback reduced later play [24]. Achievements framed as recognition rather than instruction are suggested by
   practitioners [23] but untested.

### 7.2 Evidence strength

- IKEA effect: **Moderate** (four lab studies; one research group) [49].
- Effort paradox: **Moderate** (review; heterogeneous evidence) [50].
- Unexpected rewards neutral: **Strong** [1].

## 8. Social comparison, status display, and the solo case

### 8.1 Findings

1. **Social comparison theory** (Festinger 1954 [51]): people evaluate their abilities by comparing with others
   *when objective, non-social standards are unavailable*, and prefer non-social standards when they exist.
2. **Why players buy in-game content (cosmetics are not isolated).** Hamari et al. 2017 [52] (survey, N = 519,
   19 purchase reasons grouped into six dimensions): unobstructed play, social interaction and economic
   rationale predicted spending; competition and social interaction are explicit dimensions.
   A related Hamari and Keronen 2017 meta-analysis found purchase
   reasons depend strongly on the platform (reported in search summaries; not opened). Lehdonvirta 2009 [53]
   analysed purchase-driving attributes of virtual items from a sociology-of-consumption view across 14 platforms
   (only a truncated abstract was read; the full attribute list was not verified).
3. **Comparative feedback can backfire.** In Burgers et al. [24], comparative feedback *decreased* future play while
   evaluative feedback increased it.
4. **Temporal (self) comparison as a substitute.** Anderson and Green [36] show personal bests act as powerful
   reference points even without an audience. A children's study [55] (abstract only) reported that comparison
   with one's past self produced pride without triggering superiority goals.
   Direct evidence for solo games was **not found**; this is an extrapolation.
5. **Relatedness in co-op.** SDT's relatedness need [14, 15] can be served by co-op with friends; bots are not a
   social audience, but friends in a 2–4 player session are a small one.

### 8.2 Evidence strength

- Social comparison as a general mechanism: **Strong** (foundational theory, large literature) [51].
- Social motives in virtual-goods purchasing: **Moderate** (surveys) [52, 53].
- Self-comparison replacing social comparison in solo games: **Weak** (extrapolated) [36].

## 9. Session length, stopping points and healthy engagement

### 9.1 Findings

1. **Players want closure.** Alexandrovsky et al. 2024 [30] (interviews n = 16, survey n = 111; read in full,
   arXiv preprint, venue listed by other sources as CHI PLAY 2024): positive exits involve closure (agreement
   M = 5.20) and satisfaction (M = 5.83). Players stop at the end of a level or mission, prefer quiet low-load
   moments, avoid stopping mid-action, and rely on autosaves. One interviewee: "the end of the level or a task is a
   good point to stop; otherwise it'll be an endless loop". Reasons for stopping include planned time limits,
   exhaustion, external obligations, frustration and boredom.
2. **Design reflections from [30]:** make play structure transparent; account for tired players; prioritise agency
   (no trapping, no pushing out, clear information about progress loss). The authors note forced breaks and time
   caps contradict player preferences.
3. **Children and closure.** A 2025 follow-up [54] (abstract) found children forced to stop before closure are
   frustrated, and recommends disengagement-friendly design.
4. **Goals as stopping points.** Reaching a reference point leads to quitting [36]; post-reward pauses appear under
   fixed schedules [4]. A designer can choose to *align* such pauses with the end of a match or session.
5. **Fixed-interval patterns** (daily/weekly resets) produce pause-then-check behaviour [4]; the fresh-start effect
   [38] suggests weekly boundaries can be motivating without being punitive if nothing is lost by missing a week
   (inference).
6. **Well-being.** Hours played do not predict well-being; perceived value does [25, 26]. Obsessive engagement is
   associated with low need satisfaction [18]. The healthy target suggested by this literature is need-satisfying
   sessions with clean exits, not maximal session length.

### 9.2 Evidence strength

- Closure as the core of a positive exit: **Moderate** (one mixed-methods study, n = 111 survey) [30].
- Goal attainment → stopping: **Strong** in chess data [36].
- Playtime vs well-being: **Strong** [25, 26].

## 10. Implications for Private War (options and trade-offs)

These are options derived from the research above, not decisions. Each names the trade-off.

### 10.1 Reward flood versus slow grind: pace by session, not by match count alone

- **Option A — calibrate "one meaningful reward per session".** With sessions of about two matches, one account
  level per session (current state at level 12) sits close to the goal-gradient sweet spot: the next goal is
  always visible and reachable tonight [33]. Trade-off: a growing per-level cost (FR with rising ratio) lengthens
  post-reward pauses [4]; if the curve keeps rising toward level 55, late levels may take several sessions and fall
  into the "WoW 1x" failure mode.
- **Option B — flatten the late curve and add distinct milestones instead of raising cost.** Keeps the FR ratio
  stable while milestones (calling cards, rare unlocks) provide distinctiveness. Trade-off: more content to author;
  risk of the flood if milestones are too frequent.
- **Option C — keep a predictable spine plus occasional unannounced bonuses.** Unexpected rewards do not undermine
  intrinsic motivation [1] and carry prediction-error "surprise" [3]. Trade-off: must stay small and not
  random-loot-like, to avoid VR/gambling-like loops [9, 10, 11]; for a free game this is low-risk but not zero.
- **Avoid lowering existing players' rates abruptly.** Hopson [4] reports reward cuts are perceived as punishment
  and unfair. If the rebalance slows anything, consider grandfathering or compensating.

### 10.2 The attachment clump at weapon levels 16–17

- The research predicts the current shape is the weakest one: 15 levels with no new distinct reward means a long
  stretch of low goal-gradient (the goal is far) followed by a clump whose items adapt against each other [39, 42].
- **Option A — spread attachments evenly** (for example one every one or two weapon levels). Strong goal gradient,
  each unlock separated in time (segregated gains [13], interruptions between them [40]). Trade-off: early levels
  give fewer power changes per unlock, and hundreds of weapons multiply authoring/derivation work.
- **Option B — front-load a few, then spread.** Endowed-progress logic [33, 34]: an early unlock in the first match
  with a new weapon makes the track feel started. Trade-off: early power spikes can change challenge balance [29].
- **Option C — give the player the choice of which attachment to unlock next** (autonomy [14, 15], completion-based
  valuation [49]). Trade-off: UI complexity on a Deck screen; choice paralysis if options are many.

### 10.3 Hundreds of weapons: guard against devaluation

- With so many weapons, every weapon having its own full track multiplies rewards and risks the Forza flood through
  sheer volume, even if each track is slow. Options: account-wide "weapon class" mastery, a small curated set of
  per-weapon milestones, or making only some weapons' tracks visible at a time. Trade-off between breadth
  (variety, discovery) and distinctiveness (each reward noticed) [42, 43].

### 10.4 Solo audience: replace social comparison with self-comparison and recognition

- Calling cards shown to killers have no human audience against bots. Options:
  - Show cards to co-op friends (small but real audience; relatedness [14, 15]).
  - Use personal records as goals (personal-best reference points [36]); evaluative rather than comparative
    feedback [24].
  - Frame achievements and cards as recognition of what the player did, not as instructions (practitioner
    suggestion [23], untested).
- Trade-off: self-comparison is supported by weaker evidence in games than social comparison is in multiplayer;
  cosmetics may simply matter less in this context, so investment in many cosmetic tiers may have low return.

### 10.5 Short Deck sessions: design stopping points

- Align progress beats with the end of a match so the natural post-reward pause [4] coincides with a clean exit
  (closure [30]).
- **Option — end-of-session summary** ("tonight: +1 level, 2 attachments, next unlock in ~1 match"). Gives closure
  [30] and a visible next goal for the next session (goal gradient [33], Ovsiankina resumption [35]). Trade-off: a
  "next unlock in 1 match" line is a near-miss-like nudge to keep playing [9]; whether that is a feature or a dark
  pattern depends on intent [5, 6] — a factual statement without urgency is the milder version.
- Breaks between sessions restore enjoyment of the same content [40, 42]; slower per-session rates are less of a
  problem than they seem when sessions are naturally spaced.

### 10.6 No FOMO: weekly challenges and season passes without expiry

- The project's no-FOMO stance is consistent with the evidence: loss aversion is contested [45], FOMO correlates with
  low need satisfaction [47], appointment play is listed as a dark pattern [6], and controlling pressure undermines
  intrinsic motivation per SDT [1, 14].
- **Option A — weekly challenges that refresh but never expire unfinished progress** (or that bank missed weeks).
  Retains the fresh-start motivation of a weekly boundary [38] without loss. Trade-off: weaker urgency, so lower
  short-term engagement, which is acceptable for a free game.
- **Option B — non-expiring season tracks.** Goal gradient without FOMO. Trade-off: no "season" urgency; the track
  must itself be interesting (distinct rewards), because pressure is not doing the work.

### 10.7 Measuring instead of guessing

- The literature cannot set numbers for this game. Small local telemetry (matches per level, per weapon level,
  session count per evening, where players stop) plus the PENS-style questions [16] in a playtest would show whether
  sessions feel rewarding. Trade-off: telemetry design and privacy work.

## Open questions for the maintainer

1. What is the target "time to max" for an account (55 levels) and for one weapon, expressed in *sessions*, not
   matches? The research supports pacing against sessions, but the number is a design choice.
2. Should existing players' progress be protected (no slower rates for already-earned levels) during the rebalance?
3. Is a player-choice unlock order for attachments acceptable on the Deck UI, or should order stay fixed?
4. Should per-weapon tracks exist for all auto-discovered weapons, or be grouped (class mastery) to avoid reward
   volume growing with installed packs?
5. Are unannounced bonus rewards (not random loot, just occasional surprises) acceptable, or should every reward be
   predictable?
6. Should calling cards be shown to co-op friends, since bots are not an audience?
7. Is an end-of-session summary with "next unlock" information wanted, given the near-miss trade-off above?
8. Is local telemetry for pacing (matches per level, stop points) acceptable for a privacy-sensitive free mod?

## Sources

1. [paper] Deci, Koestner, Ryan (1999). A meta-analytic review of experiments examining the effects of extrinsic
   rewards on intrinsic motivation. *Psychological Bulletin* 125(6). Full text (Ovid copy) read for abstract and
   result sections. <https://depts.washington.edu/techdocs/papers/deciExtrinsicRewardsAndIntrinsicMotivation99.pdf>;
   PubMed: <https://pubmed.ncbi.nlm.nih.gov/10589297/>
2. [book] Ferster, Skinner (1957). *Schedules of Reinforcement*. Publisher record only.
   <https://bfskinner.org/product/schedules-of-reinforcement/>
3. [paper] Schultz, Dayan, Montague (1997). A neural substrate of prediction and reward. *Science* 275.
   Abstract read. <https://pubmed.ncbi.nlm.nih.gov/9054347/>
4. [article] Hopson (2001). Behavioral Game Design. Gamasutra / Game Developer. Read in full.
   <https://www.gamedeveloper.com/design/behavioral-game-design>
5. [opinion] Hopson (2012). "There is no Skinner box," says Bungie user research lead. Game Developer. Read.
   <https://gamedeveloper.com/design/there-is-no-skinner-box-says-bungie-user-research-lead>
6. [paper] Zagal, Björk, Lewis (2013). Dark Patterns in the Design of Games. FDG 2013. Record and summaries.
   <https://research.chalmers.se/en/publication/177148>
7. [paper] Deterding, Stenros, Montola (2020). Against "Dark Game Design Patterns". DiGRA 2020. Summary only.
   <https://eprints.whiterose.ac.uk/156460/1/DiGRA_2020_paper_189.pdf>
8. [paper] King, Delfabbro (2018). Predatory monetization schemes in video games and internet gaming disorder.
   *Addiction* 113(11). Editorial; abstract and press only.
   <https://researchnow.flinders.edu.au/en/publications/predatory-monetization-schemes-in-video-games-eg-loot-boxes-and-i/>
9. [paper] Clark, Lawrence, Astley-Jones, Gray (2009). Gambling near-misses enhance motivation to gamble and recruit
   win-related brain circuitry. *Neuron* 61. Abstract and summaries. <https://pmc.ncbi.nlm.nih.gov/articles/PMC2658737>
10. [paper] Larche, Chini, Lee, Dixon, Fernandes (2021). Rare loot box rewards trigger larger arousal and reward
    responses, and greater urge to open more loot boxes. *Journal of Gambling Studies* 37(1). Abstract only.
    <https://uwspace.uwaterloo.ca/items/f3df3e42-ecb1-4cf9-89cf-87626dbfbaf1>
11. [paper] Zendle, Cairns (2018). Video game loot boxes are linked to problem gambling. *PLoS ONE*. Abstract.
    <https://eprints.whiterose.ac.uk/139116/>
12. [paper] Zendle, Cairns (2019). Loot boxes are again linked to problem gambling. *PLoS ONE* 14(3). Abstract.
    <https://eprints.whiterose.ac.uk/143229>
13. [paper] Thaler (1985). Mental accounting and consumer choice. *Marketing Science* 4(3). Principle statements
    read. <https://fermatslibrary.com/s/mental-accounting-and-consumer-choice>
14. [paper] Ryan, Deci (2000). Self-determination theory and the facilitation of intrinsic motivation, social
    development, and well-being. *American Psychologist* 55(1). Abstract. <https://pubmed.ncbi.nlm.nih.gov/11392867/>
15. [paper] Ryan, Rigby, Przybylski (2006). The motivational pull of video games: a self-determination theory
    approach. *Motivation and Emotion* 30. Abstract and press release.
    <https://www.doi.org/10.1007/S11031-006-9051-8>
16. [article] Self-Determination Theory site: Player Experience of Need Satisfaction (PENS).
    <https://selfdeterminationtheory.org/player-experience-of-needs-satisfaction-pens/>
17. [book] Rigby, Ryan (2011). *Glued to Games*. Praeger. Book review read, not the book.
    <https://www.museumofplay.org/app/uploads/2022/01/4-4-book-review-4.pdf>
18. [paper] Przybylski, Weinstein, Ryan, Rigby (2009). Having versus wanting to play: background and consequences of
    harmonious versus obsessive engagement in video games. *CyberPsychology & Behavior*. Abstract-level summary.
    <https://repository.essex.ac.uk/1605/>
19. [paper] Cameron, Banko, Pierce (2001). Pervasive negative effects of rewards on intrinsic motivation: the myth
    continues. *The Behavior Analyst* 24(1). Abstract. <https://pmc.ncbi.nlm.nih.gov/articles/PMC2731358>
20. [paper] Deci, Koestner, Ryan (2001). Extrinsic rewards and intrinsic motivation in education: reconsidered once
    again. *Review of Educational Research* 71(1). Not opened; cited for the existence of the reply.
    <https://www.selfdeterminationtheory.org/SDT/documents/2001_DeciKoestnerRyan.pdf>
21. [paper] Mekler, Brühlmann, Tuch, Opwis (2017). Towards understanding the effects of individual gamification
    elements on intrinsic motivation and performance. *Computers in Human Behavior* 71. Abstract/highlights.
    <https://glassmanlab.seas.harvard.edu/annotated_works/mekler17.pdf>
22. [paper] (2022). Experiments on external reward for video game play in children. *Current Psychology*.
    Search snippet only; authors and title not verified. <https://link.springer.com/article/10.1007/s12144-022-02905-6>
23. [opinion] Psychology of Games (2016). The overjustification effect and game achievements.
    <https://psychologyofgames.com/2016/10/the-overjustification-effect-and-game-achievements>
24. [paper] Burgers, Eden, van Engelenburg, Buningh (2015). How feedback boosts motivation and play in a
    brain-training game. *Computers in Human Behavior* 48. Abstract.
    <https://research.vu.nl/en/publications/how-feedback-boosts-motivation-and-play-in-a-brain-training-game/>
25. [paper] Vuorre, Johannes, Magnusson, Przybylski (2022). Time spent playing video games is unlikely to impact
    well-being. *Royal Society Open Science* 9. Abstract and press release.
    <https://www.oii.ox.ac.uk/major-new-study-finds-little-evidence-for-causal-connection-between-well-being-and-video-game-playing/>
26. [paper] Ballou, Vuorre, Hakman, Magnusson, Przybylski (2025). Perceived value of video games, but not hours
    played, predicts mental well-being in casual adult Nintendo players. *Royal Society Open Science* 12(3).
    Abstract and press release. <https://doaj.org/article/a08bdfb7c8014c32958a5e2afaed07cc>
27. [paper] Johannes, Vuorre, Przybylski (2021). Video game play is positively correlated with well-being.
    *Royal Society Open Science* 8. Full text could not be opened (captcha); details unverified.
    <https://pmc.ncbi.nlm.nih.gov/articles/PMC8074794>
28. [book] Csikszentmihalyi (1990). *Flow: The Psychology of Optimal Experience*. Harper & Row. Catalogue record.
    <https://search.worldcat.org/oclc/20392741>
29. [paper] Fong, Zaleski, Leach (2015). The challenge–skill balance and antecedents of flow: a meta-analytic
    investigation. *Journal of Positive Psychology*. Abstract only.
    <https://www.instituteofcoaching.org/resources/challenge%E2%80%93skill-balance-and-antecedents-flow-meta-analytic-investigation>
30. [paper] Alexandrovsky, Gerling, Opp, Hahn, Birk, Alsheail (2024). Disengagement from games (arXiv:2406.00189;
    CHI PLAY 2024, DOI 10.1145/3677066). Read in full (first 100k characters). <https://arxiv.org/html/2406.00189v1>
31. [paper] Sweetser, Wyeth (2005). GameFlow: a model for evaluating player enjoyment in games. *ACM Computers in
    Entertainment* 3(3). Abstract and summaries. <https://api.crossref.org/works/10.1145%2F1077246.1077253>
32. [opinion] Chen (2007). Flow in games (and everything else). *Communications of the ACM* 50(4). Designer essay;
    summaries read. <https://khoury.northeastern.edu/~lieber/courses/csu670/f08/materials/p31-chen-flow-in-games.pdf>
33. [paper] Kivetz, Urminsky, Zheng (2006). The goal-gradient hypothesis resurrected: purchase acceleration,
    illusionary goal progress, and customer retention. *Journal of Marketing Research* 43. Abstract and summaries.
    <https://business.columbia.edu/sites/default/files-efs/pubfiles/1200/goalgradient.pdf>
34. [paper] Nunes, Drèze (2006). The endowed progress effect: how artificial advancement increases effort.
    *Journal of Consumer Research* 32(4). Abstract and secondary summaries (34 % vs 19 % from summaries).
    <https://ideas.repec.org/a/oup/jconrs/v32y2006i4p504-512.html>
35. [paper] Ghibellini, Meier (2025). Interruption, recall and resumption: a meta-analysis of the Zeigarnik and
    Ovsiankina effects. *Humanities and Social Sciences Communications* 12. Abstract and secondary summaries.
    <https://ideas.repec.org/a/pal/palcom/v12y2025i1d10.1057_s41599-025-05000-w.html>
36. [paper] Anderson, Green (2018). Personal bests as reference points. *PNAS* 115(8). Abstract.
    <https://pmc.ncbi.nlm.nih.gov/articles/PMC5828569>
37. [paper] Locke, Latham (2002). Building a practically useful theory of goal setting and task motivation: a 35-year
    odyssey. *American Psychologist* 57(9). Abstract.
    <https://goal-lab.psych.umn.edu/orgpsych/2020/readings/5.%20Motivation/Locke%20&%20Latham%20(2002).pdf>
38. [paper] Dai, Milkman, Riis (2014). The fresh start effect: temporal landmarks motivate aspirational behavior.
    *Management Science* 60(10). Abstract.
    <https://faculty.wharton.upenn.edu/wp-content/uploads/2014/06/Dai_Fresh_Start_2014_Mgmt_Sci.pdf>
39. [book] Frederick, Loewenstein (1999). Hedonic adaptation. In Kahneman, Diener, Schwarz (eds.), *Well-Being: The
    Foundations of Hedonic Psychology*, pp. 302–329. Chapter abstract. <https://muse.jhu.edu/book/15017>
40. [paper] Nelson, Meyvis (2008). Interrupted consumption: disrupting adaptation to hedonic experiences. *Journal of
    Marketing Research*. Secondary summaries only.
    <https://dunn.psych.ubc.ca/wp-content/uploads/2015/05/combatting_hedonic_adaptation.pdf>
41. [paper] Nelson, Meyvis, Galak (2009). Enhancing the television-viewing experience through commercial
    interruptions. *Journal of Consumer Research*. Abstract.
    <https://interruptions.net/literature/Nelson-JConsumRes09.pdf>
42. [paper] Galak, Kruger, Loewenstein (2011). Is variety the spice of life? It all depends on the rate of
    consumption. *Judgment and Decision Making* 6(3). Abstract.
    <https://dlab.sauder.ubc.ca/sjdm/journal/11/10624/jdm10624.html>
43. [paper] Galak, Redden, Kruger (2009). Variety amnesia: recalling past variety can accelerate recovery from
    satiation. *Journal of Consumer Research* 36(4). Abstract.
    <https://ideas.repec.org/a/oup/jconrs/v36y2009i4p575-584.html>
44. [paper] Kahneman, Tversky (1979). Prospect theory: an analysis of decision under risk. *Econometrica* 47(2).
    Cited from general knowledge of the canonical paper; not re-opened. <https://www.jstor.org/stable/1914185>
45. [paper] Gal, Rucker (2018). The loss of loss aversion: will it loom larger than its gain? *Journal of Consumer
    Psychology* 28(3). Summary only.
    <https://www.kellogg.northwestern.edu/academics-research/research/detail/2018/the-loss-of-loss-aversion-will-it-loom-larger/>
46. [paper] Simonson, Kivetz (2018). Bringing (contingent) loss aversion down to earth. *Journal of Consumer
    Psychology*. Abstract.
    <https://www.gsb.stanford.edu/faculty-research/publications/bringing-contingent-loss-aversion-down-earth-comment-gal-ruckers>
47. [paper] Przybylski, Murayama, DeHaan, Gladwell (2013). Motivational, emotional, and behavioral correlates of
    fear of missing out. *Computers in Human Behavior* 29(4). Abstract.
    <https://selfdeterminationtheory.org/wp-content/uploads/2014/04/2013_PrzybylskiMurayamaDeHaanGladwell_CIHB.pdf>
48. [paper] Hartanto et al. (2024). Longitudinal study of FOMO and loot box use. *Computers in Human Behavior
    Reports*. Abstract only; full author list not verified. <https://doaj.org/article/9e858f67693d4eebb05936643cdeca43>
49. [paper] Norton, Mochon, Ariely (2012). The IKEA effect: when labor leads to love. *Journal of Consumer
    Psychology* 22(3). Abstract. <https://dash.harvard.edu/handle/1/12136084>
50. [paper] Inzlicht, Shenhav, Olivola (2018). The effort paradox: effort is both costly and valued. *Trends in
    Cognitive Sciences* 22(4). Abstract. <https://pmc.ncbi.nlm.nih.gov/articles/6172040/>
51. [paper] Festinger (1954). A theory of social comparison processes. *Human Relations* 7. Summary.
    <https://www2.psych.ubc.ca/%7Eschaller/528Readings/Festinger1954.pdf>
52. [paper] Hamari, Alha, Järvelä, Kivikangas, Koivisto, Paavilainen (2017). Why do players buy in-game content?
    An empirical study on concrete purchase motivations. *Computers in Human Behavior* 68. Abstract.
    <https://research.utu.fi/converis/portal/detail/Publication/17788064?lang=en_GB>
53. [paper] Lehdonvirta (2009). Virtual item sales as a revenue model: identifying attributes that drive purchase
    decisions. *Electronic Commerce Research* 9. Abstract only.
    <https://link.springer.com/content/pdf/10.1007/s10660-009-9028-2.pdf>
54. [paper] Alsheail et al. (2025). Children's disengagement from games and parental mediation. CHI PLAY / GAMES
    2025. Abstract only; full title not verified. <https://doi.org/10.1145/3748614>
55. [paper] Better than my past self: temporal comparison raises children's pride without triggering superiority
    goals (University of Amsterdam repository). Abstract only; authors and year not verified.
    <https://www.dare.uva.nl/id/025ef0c9-044f-4a89-a791-13a312a4802a>
