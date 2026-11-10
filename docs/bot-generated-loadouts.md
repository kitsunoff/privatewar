# Generated ARC9 bot loadouts

Implementation notes for the optional `privatewar-arc9` provider. Existing design decisions and human classes
are unchanged: `05-loadout.md` d.14–15, `04-weapons.md` d.1–4, `06-progression.md` d.2 and `07-bots.md` d.2.

## Host control and selection

- Game Setup exposes **Generated ARC9 bot loadouts → Generate ARC9 loadouts**
  (`bots_arc9_loadouts.generate`, match-scoped, default on). Existing permission checking, schema validation,
  generated controls and match snapshots apply. Changes during a match take effect next match.
- The provider adds up to **18** candidates, three each of SMG assault, assault rifle, shotgun, LMG, sniper
  and pistol-only. It neither registers `classes/` entries nor modifies presets, hidden classes or custom classes.
  `bots.classes` continues to control its existing preset/player sources independently. Turning off generation
  restores that exact source policy; disabling/removing the integration has the same fallback.
- Candidates join the existing individual-class weighted draw, not a separate guaranteed bot allocation.
  The existing personality weights and `bots.classrepick` cadence remain. Explicit generated archetype metadata
  supplies the weight category for pistol-only and LMG builds; existing classes retain primary-category weights.
- Each candidate passes adapter static legality plus the existing `PW.Loadout.Validate(bot, loadout)` on every
  pool request, including match budgets, attachment caps, weapon/attachment bans, enabled items, slot filters,
  perk groups and `PW_ValidateLoadout`. Rejection removes the candidate, never trims it to fit or rerolls it.
  Bot progression is not consulted; no human unlock, purchase, class selection or storage path changes.

## Content defaults

All styles use the existing frag, flash and UAV / Counter-UAV / airstrike items. Knife discovery requires an
ARC9 melee weapon with the published knife hold type or knife class name. Without one, pistol-only candidates
are omitted rather than substituting a crowbar or another firearm. Other styles may omit an unavailable knife
or pistol backup. Missing categories are omitted; no weapon classes are invented or replaced.

| Archetype | Group 1 | Group 2 | Group 3 |
| --- | --- | --- | --- |
| SMG assault | Fleet Foot | Quick Draw | Quiet Steps |
| Assault rifle | Ready Up | Recoil Control | Adrenaline |
| Shotgun | Flash Guard | Sleight of Hand | Adrenaline |
| LMG | Flak Jacket | Sleight of Hand | Retaliation |
| Sniper | Soft Landing | Sightline | Ghost |
| Pistol-only | Flak Jacket | Quick Draw | Adrenaline |

Pistol-only has no primary: one pistol firearm, knife, grenades and normal perks. Its survivability comes from
Flak Jacket and Adrenaline; Quick Draw supports switching from grenades/knife. There are no bot-only stat buffs.
LMG discovery recognizes curated `lmg` categories, the installed packs' English `SubCategory = Light Machine Guns`,
and MW2019's `_lm_` class family. ARC9's enum classifies those as assault rifles; the human catalogue is not
recategorized. Unknown packs keep their published category, not a speculative damage/magazine heuristic.
Published `ShootEnt` or gun `NotForNPCs = true` excludes scripted special guns: inspection found MW3 XM25/Thumper
projectile weapons mislabeled as SMG/shotgun and an NPC-disabled MW2019 minigun labeled as a shotgun. The knife's
`NotForNPCs` flag is intentionally irrelevant because the integration drives player-bot melee through normal input.

Builds retain integral/default parts and select up to two accessories from offered top-level empty slots,
using published optic/scope, muzzle, grip, stock or laser attachment categories. Receivers, ammo conversions,
weapon perks, underbarrel firearms and arbitrary cosmetic material swaps are not intentionally generated.
Slot discovery and adapter `Validate` establish static compatibility; ARC9 can still prune a conflict that is
only knowable on a live weapon. Spawn uses the existing `Apply` / `PrepareForBot` and partial-build repair path.
No live weapons are created during generation, avoiding first-`Give` model-loading stalls.

## Camouflage evidence and limits

The installed ARC9 reports version `1.0`. Read-only public table/source inspection found 163 attachments with
`CustomCamoTexture` / `CustomCamoScale`, including `camo_arc9_base_flat_blue` and `cod2019_camo_tiger_01`.
These publish `Category = universal_camo`. MW2019 M4 exposes its camo in adapter slot `13`; its knife uses `3`.
The installed `arc9_base/cl_drawmodel.lua`, `cl_model.lua` and `sh_bodygroups.lua` read processed
`CustomCamoTexture` into their model rendering path. This is ARC9 weapon camouflage, not entity `SetSkin`,
`SetMaterial` or `SetSubMaterial`. No third-party code was copied or private functions evaluated.

The provider chooses an offered `universal_camo` option only when its public attachment table actually contains
a nonempty `CustomCamoTexture`. The adapter recognizes that category as cosmetic (free and outside the attachment
cap), including installations whose `ARC9.CosmeticCategories` omits `universal_camo`. Unknown/rejected camouflage
falls back to the base appearance. Nested-only cosmetics are not traversed by this conservative generator.
Packs without a suitable top-level camo slot keep their normal appearance; not every generated weapon has a camo.

The mounted test asserts that actual `Apply` readback retains generated camos and that the live weapon's processed
`CustomCamoTexture` matches the chosen attachment. That establishes server build/texture state, not a visual or
remote-client acceptance checkpoint. Rendering quality, first-person/world-model support and P2P remain manual checks.

## Map lifecycle and performance

- Generation starts after `PW_WeaponsLoaded`, deferred until all registration listeners have completed.
  The precomputation is map-scoped even when inclusion is toggled off: toggling on later does not reroll a map.
- A coroutine yields between weapons, slots and option metadata reads. Each server Think gets at most 32 resumes
  and a cooperative 0.75 ms slice. Individual public addon calls cannot be preempted; the budget is not a hard
  promise that no frame exceeds 0.75 ms. The completion log records total work, maximum slice and frame count.
- Only a completed pool is published. Match startup and spawning never wait; pending, unavailable, empty or failed
  generation contributes nothing to the original pool. An error discards unpublished partial work and is not retried.
- Completed plain-data candidates survive same-map development reloads. An in-flight reload cancels its old coroutine
  and falls back for that map; a schema-version mismatch retires old data. Neither case silently rerolls candidates.
  A real map lifecycle gets a fresh state. Current adapter validation prevents reuse of removed/banned attachment data.
- Hooks and spawn repair receive copies, not ownership of cached builds. Cache contents are never saved to player
  files, networked as human classes or regenerated because match settings change.

## Tests

`bots_arc9_generated.lua` covers archetypes, fallback, actual camo representation, rejection, atomic publication,
time/resume limits, cache/reload/map keys, additive selection weights and settings. `bots_arc9_generated_rules.lua`
exercises the existing slot/budget/cap/ban rules and cache ownership. `bots_arc9_generated_native.lua` checks mounted
generation, live application/camouflage, current pool settings/budget/bans and progression independence.
Existing T-5.13 and hidden-class policy assertions remain in place; the latter explicitly turns off this independent
source when testing the old empty-source policy.

### Additive provider seam

`PW_BotLoadoutCandidates(bot: Player, candidates: PW.BotClassEntry[])` is a notification. A provider appends plain
entries and returns nothing; it must not replace or modify existing entries. The bot-loadout owner appends copies
that pass the existing current-match validator after notification dispatch. Existing presets/player classes are
built first and retain their ordering and source gates. No provider can skip the final validator through this seam.
