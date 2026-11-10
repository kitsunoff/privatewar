# Agent mandatory test map

Use with [TASKS.md](../TASKS.md) "Mandatory test cases" and the [workflow](agent-workflow.md).
These are **existing regression cases**, not new tests or evidence of a current run. Preserve the whole suites and
write additional task-specific cases first. Paths in the tables are relative to
`addons/privatewar/lua/tests/privatewar/`. Clauses are copied verbatim from the task list; some clauses need
multiple cases. The static checker verifies each clause is still in TASKS.md and each exact name still exists.
It does not inspect assertion strength or prove runtime success. A rename needs coordinated reference updates,
not deletion of a mandatory assertion.

## Continuous modes and round foundation

| Task | Mandatory clause | Suite | Exact existing case name |
| --- | --- | --- | --- |
| T-2.2 | win by score limit | modes_tdm_ffa.lua | Win by score limit: TDM Think finishes the match with the team that reached it |
| T-2.2 | win by time limit | modes_tdm_ffa.lua | Win by time limit: TDM Think finishes the match with the leading team |
| T-2.2 | tie handling | modes_tdm_ffa.lua | Tie handling: a shared top score at the time limit is a draw without a winner |
| T-2.2 | FFA winner is the top player | modes_tdm_ffa.lua | FFA winner is the top player: FFA Think finishes with the player, not a team |
| T-2.3 | round loop until `RoundsToWin` | round_base.lua | Round loop runs until RoundsToWin: no finish before a team has the rounds, one finish at it |
| T-2.3 | side swap every `SwapSidesEvery` | round_base.lua | Side swap every SwapSidesEvery rounds: after rounds 2 and 4, wins move with the players |
| T-2.3 | `PW_RoundStart/End` order | round_base.lua | PW_RoundStart and PW_RoundEnd order: start, end, (swap, respawn), start ... end, then the finish |
| T-2.3 | abstract mode not in lists | round_base.lua | round_base is abstract with defaults and settings; it is absent from the mode lists |
| T-2.4 | capture scalar moves by `rate × min(diff, 3)` and stops at ±100 | mode_dom.lua | The capture scalar moves by rate x min(diff, 3) toward the side with more players |
| T-2.4 | capture scalar moves by `rate × min(diff, 3)` and stops at ±100 | mode_dom.lua | The capture scalar stops at +100 and -100 |
| T-2.4 | contested point does not move | mode_dom.lua | A contested point (equal counts) does not move; an empty point does not move either |
| T-2.4 | scoring per held point | mode_dom.lua | Scoring per held point: each owned flag adds the tick points to its team |
| T-2.4 | `ValidateMapData` rejects < 2 flags | mode_dom.lua | ValidateMapData rejects fewer than 2 flags and flags that are not Vectors |
| T-2.4 | mode hidden on a map without data | mode_dom.lua | The mode is hidden on a map without data: ModeFits is false without a file, entry or 2 flags |
| T-2.5 | tag spawns at victim | mode_kc.lua | The tag spawns at the victim: a death in KC drops a tag at the victim's position |
| T-2.5 | enemy pickup confirms and scores | mode_kc.lua | An enemy pickup confirms and scores: kc_confirm to the collector, one confirm for its team |
| T-2.5 | teammate pickup denies | mode_kc.lua | A teammate pickup denies: kc_deny to the collector, no confirm |
| T-2.5 | tag is removed after pickup | mode_kc.lua | The tag is removed after pickup: out of the list at once, the entity next tick, no second pickup |

For round/objective changes also preserve `round_objective_lifecycle.lua`, `round_initial_spawn.lua`,
`mode_snd.lua`, `mode_hardpoint.lua`, `mode_infection.lua` and the corresponding native suites. T-11.12's exact
named inventory is already in TASKS.md; T-11.13/T-11.14 describe multi-suite assertions rather than one case each.
Read [modes](api/modes.md), [Hardpoint](api/hardpoint.md), [Infection](api/infection.md) and the current test bodies;
do not replace those inventories with this foundation map. Shared seams also retain T-1.12 (core phases), T-2.9
(spawns), T-5.2 (input), T-5.7 (perception), T-5.11 (commander) and T-8.4 (JIP).

### Implemented objective modes

| Task | Mandatory clause | Suite | Exact existing case name |
| --- | --- | --- | --- |
| T-11.12 | Round objective: planted overtime survives the base deadline | round_objective_lifecycle.lua | Round objective: planted overtime survives the base deadline |
| T-11.12 | Round objective: prepare follows swap and precedes every playable respawn | round_objective_lifecycle.lua | Round objective: prepare follows swap and precedes every playable respawn |
| T-11.12 | Round objective: terminal verdict prevents another swap spawn or award | round_objective_lifecycle.lua | Round objective: terminal verdict prevents another swap spawn or award |
| T-11.12 | SND: one bomb survives competing pickups and carrier death disconnect | mode_snd.lua | SND: one bomb survives competing pickups and carrier death disconnect |
| T-11.12 | SND: held interactions cancel on invalid actor range release and round generation | mode_snd.lua | SND: held interactions cancel on invalid actor range release and round generation |
| T-11.12 | SND: exact plant defuse fuse and death boundaries resolve once | mode_snd.lua | SND: exact plant defuse fuse and death boundaries resolve once |
| T-11.12 | SND: reconnect and replacement cannot grant a second life | mode_snd.lua | SND: reconnect and replacement cannot grant a second life |
| T-11.12 | SND: snapshots disclose only approved carrier drop and spectator information | mode_snd.lua | SND: snapshots disclose only approved carrier drop and spectator information |
| T-11.12 | SND bots: sole attacker carries plants and guards through shared input rules | mode_snd.lua | SND bots: sole attacker carries plants and guards through shared input rules |
| T-11.12 | SND bots: sole defender holds use to defuse and death promptly reassigns | mode_snd.lua | SND bots: sole defender holds use to defuse and death promptly reassigns |
| T-11.12 | SND bots: sanitizer preserves approved eligibility without leaking hidden enemies | bots_snd.lua | SND bots: sanitizer preserves approved eligibility without leaking hidden enemies |
| T-11.13 | empty/unequal contested occupancy zero | mode_hardpoint.lua | Hardpoint: empty and unequal contested occupancy score zero |
| T-11.13 | dead/observer/other-floor | mode_hardpoint.lua | Hardpoint: dead observers and other floors never count |
| T-11.13 | rotation wrap/exact-boundary precedence | mode_hardpoint.lua | Hardpoint: rotation wraps and exact boundary scoring follows approved precedence |
| T-11.13 | no stall backfill/double finish | mode_hardpoint.lua | Hardpoint: stalls cannot backfill unsampled occupancy or finish twice |
| T-11.13 | invalid layouts hidden | mode_hardpoint.lua | Hardpoint: invalid authored layouts are hidden in Custom vote and playlists |
| T-11.13 | revision releases sticky holds, including tiny teams | hardpoint_presentation_bots.lua | Hardpoint: rotation releases sticky holds including tiny teams |
| T-11.13 | projected arrival inside the zone | hardpoint_presentation_bots.lua | Hardpoint: projected arrival is inside the authoritative zone |
| T-11.13 | late snapshots reject | hardpoint_presentation_bots.lua | Hardpoint: late snapshot rejects stale visits and transmits no occupants |
| T-11.13 | bot holds/rotates through ordinary inputs | hardpoint_bot_smoke.lua | Hardpoint: bot holds then rotates through normal inputs |
| T-11.14 | prepare roles before every playable spawn | mode_infection.lua | Infection: roles are seeded before loadout resolution and every new round resets converted lives |
| T-11.14 | fixed total 1/3 | round_objective_lifecycle.lua | Fixed total: limits 1 and 3 finish once with no extra respawn despite RoundsToWin 1 |
| T-11.14 | ordinary first-to-wins unchanged | round_objective_lifecycle.lua | Fixed total: absent or zero limit preserves ordinary RoundsToWin |
| T-11.14 | no-repeat seed where possible | mode_infection.lua | Infection: either actor type can be seeded and repeats are avoided when another identity is eligible |
| T-11.14 | conversion/world death | mode_infection.lua | Infection fallback death: world or suicide converts once; stale and infected death do not reconvert |
| T-11.14 | pending respawn not mistaken for absence | mode_infection.lua | Infection: dead pending infected remains present; last infected disconnect gives survivors victory |
| T-11.14 | exact endings | mode_infection.lua | Infection: all-converted wins early; exact deadline has priority and cannot be overwritten |
| T-11.14 | personal outcomes | mode_infection.lua | Infection: living survivors and winning initial seeds earn round wins; converted winners do not |
| T-11.14 | safe late snapshots | infection_presentation.lua | Infection snapshot: sanitize role counts deadline and personal wins, never hidden positions |

These rows supplement, not replace, `infection_lifecycle.lua` and the native input/role suites: actual conversion,
continued infected play, synchronous relationship/effect rollback, ordinary-mode restoration and legal fists need
their existing engine assertions too. Read `role_policy.lua`, `player_overrides.lua`, `bots_input.lua`,
`infection_runtime.lua`, `infection_melee_smoke.lua` and the full T-11.14 contract before changing those seams.

## Weapon adapters

| Task | Mandatory clause | Suite | Exact existing case name |
| --- | --- | --- | --- |
| T-3.1 | highest `Priority` claiming adapter wins | weapon_adapters.lua | Lookup: the highest Priority among the adapters that claim the class wins |
| T-3.1 | adapters with `IsAvailable() == false` are skipped | weapon_adapters.lua | Lookup: adapters with IsAvailable() == false are skipped, even with the highest Priority |
| T-3.1 | every optional method has a working default | weapon_adapters.lua | Defaults: every optional method of the contract has a working default |
| T-3.2 | claims a plain SWEP | weapon_adapter_sweps.lua | Fallback: claims a plain SWEP |
| T-3.2 | stats defaults from `Primary.*` | weapon_adapter_sweps.lua | Fallback: stats defaults come from Primary.* |
| T-3.3 | declarative entry beats programmatic `soft` entry per field | weapons_catalog.lua | Catalogue: a declarative entry beats a programmatic soft entry per field; soft fills the rest |
| T-3.3 | per-weapon ConVar hides a weapon | weapons_catalog.lua | Catalogue: a per-weapon enable ConVar hides the weapon from the enabled list |
| T-3.3 | curation fields (`Attachments`, `Camos`) survive merge | weapons_catalog.lua | Catalogue: curation fields (Attachments, Camos, Unlock) survive the merge, nested tables per key |
| T-3.4 | default ammo suppressed | weapons_ammo.lua | Give: default ammo is suppressed through the adapter and nothing is left over |
| T-3.4 | the core gives the configured magazines | weapons_ammo.lua | Give: the core gives the configured magazines (reserve equals magazines times the clip) |
| T-3.5 | `SetStatMods` writes NW2 values and bumps the revision once | weapons_statmods.lua | SetStatMods: writes the NW2 values and bumps the revision once |
| T-3.5 | refresh is called once per revision per weapon | weapons_statmods.lua | Refresh: called once per revision per weapon, install once per weapon |
| T-3.5 | removal resets to 1.0 | weapons_statmods.lua | Removal: SetStatMods with nil or {} resets every stat to 1.0 and bumps the revision |
| T-3.6–T-3.8 | catalogue lists the pack's weapons with categories | integration_arc9.lua | Catalogue: the pack's weapons are listed with categories and reach the weapons registry |
| T-3.6–T-3.8 | `Apply` on a bot's weapon returns the applied build | integration_arc9.lua | Apply on a bot's weapon returns the applied build |
| T-3.6–T-3.8 | a conflicting build returns what stuck | integration_arc9.lua | Apply with a conflicting build returns what stuck |
| T-3.6–T-3.8 | customization lock is active (the base's own customization path refuses) | integration_arc9.lua | Customization lock: ARC9's own customization paths refuse |
| T-3.6–T-3.8 | stat mods change the server-side value of at least reload time | integration_arc9.lua | Stat mods change the server-side reload time and removal restores it |
| T-3.6–T-3.8 | `PrepareForBot` runs without errors; two bots with different builds of the same class keep different builds (ARC9 instance tables risk) | integration_arc9.lua | PrepareForBot runs without errors; two bots keep different builds of the same class |

The integration rows map **ARC9 only** (T-3.6). For TFA/MW Base, create new integration suites carrying the same
verbatim requirements; no current test name or mounted-support result is claimed for those absent addons.
Existing fallback/lookup/catalogue/stat-mod suites remain unchanged. Preserve current ARC9 discovery/cosmetic
metadata regression suites when touching cache/fast paths.

## Perks

T-4.4 verbatim requirement: "group rule; `PW.Stat` multiplies perk, wildcard and mode multipliers; recomputed on
spawn and loadout change only; event methods called only for the owner; instance cleanup on death."

| Task | Mandatory clause | Suite | Exact existing case name |
| --- | --- | --- | --- |
| T-4.4 | group rule | perks.lua | Group rule: a perk slot accepts only perks of its own group; a slot without a group accepts any |
| T-4.4 | `PW.Stat` multiplies perk, wildcard and mode multipliers | perks.lua | PW.Stat: multiplies the perk, wildcard and mode multipliers |
| T-4.4 | recomputed on spawn and loadout change only | perks.lua | PW.Stat: recomputed on spawn and loadout change only, cached otherwise |
| T-4.4 | event methods called only for the owner | perks.lua | Events: perk event methods are called only for the owner |
| T-4.4 | instance cleanup on death | perks.lua | Instances: every perk instance of the owner ends on death; hooks, cache and stat mods go with it |

For T-11.17 and changes to its seams retain the mandatory clause/case map in TASKS.md "T-11.17 ownership and case
map": `perk_candidates.lua`, `equipment_count_sources.lua`, `perk_player_effects.lua`, `perk_support_ui.lua`,
`perk_rewards.lua`, `perk_knowledge.lua`, `perk_lifecycle.lua`, `perk_engine_smoke.lua`, `ammo_resupply.lua`,
`kill_weapon_provenance.lua` and core instance/disable tests. That map carries exact names and covers the twelve
approved effects; do not retune them or weaken native first/repeated-spawn, real RoundEnd, DSP and disabled-resupply
assertions. Changes also preserve T-4.5/T-11.4 grenades, T-4.6 streaks, T-4.9 progression and bot perception/aim/loadout tests.

## Wildcards

T-4.3 verbatim requirement: "`ModifySlots` effects (extra perk, extra attachment) and their cost."

| Task | Mandatory clause | Suite | Exact existing case name |
| --- | --- | --- | --- |
| T-4.3 | `ModifySlots` effects (extra perk, extra attachment) and their cost | wildcards.lua | ModifySlots: an extra perk in a group is accepted only with the wildcard |
| T-4.3 | `ModifySlots` effects (extra perk, extra attachment) and their cost | wildcards.lua | ModifySlots: an extra attachment raises the cap of the weapon slot by one |
| T-4.3 | `ModifySlots` effects (extra perk, extra attachment) and their cost | wildcards.lua | Budget: the wildcard itself and the extra picks it allows count against the budget |

Also retain these existing extension regressions in `wildcards.lua` (not additional TASKS.md clauses):

- `Removing the wildcard restores the slots (the effective set equals the declared set)`
- `Invalid combination: the same wildcard twice, an unknown wildcard and a wrong kind are rejected`
- `Invalid combination: no extra wildcard slots from a wildcard; a failing ModifySlots is ignored`
- `Repair: the pick a wildcard allows is kept; without the wildcard it is removed`
- `Stats: the equipped wildcards feed PW.Perks.StatSource and multiply with the perk chain`
- `Wiring: sample wildcards on stock content pass the real Validate and cost what the design says`

Keep `loadout.lua`, `loadout_budget.lua`, `loadout_classes.lua`, `gunsmith.lua` and `perks.lua` when changing slot
rules; these exercise wrong kind/filter, budget 0, cosmetics, bans, cap, repair/N/A and group composition. A new
slot needs native giving plus UI/wire tests because effective-slot acceptance alone does not prove the slot is consumed.

## Guidance evaluations

Each skill has `evals/implement/` and `evals/safety/` with realistic prompts and trace graders. They are scenario
definitions, **not executed model benchmarks**. Run only in disposable worktrees with an explicitly authorized model
and tools; no recursive delegation or paid evaluation is implied. Read-only safety cases never authorize Deck use.
Record model/variant, exact base, prompt/skill version, actual diff, commands, assertions and limitations privately.
Compare with/without skill only when both runs genuinely occurred. Never invent pass rates, timings or token counts.
