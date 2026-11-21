# Arctic's Combat Stims: research for stim equipment

**RESEARCH / NOT DECIDED.** This note explains facts and options; it decides nothing. No decision in `design/`, no
frozen API and no implementation is changed or authorized by it. The plan built on it is
[`changes/in-progress/stim-equipment.md`](../changes/in-progress/stim-equipment.md). Repository code was read on branch
`docs/plan-mwbase-stims-unlocks-challenges` at `cf7c4ed`, 2026-11-21. No game, Steam Deck, GLuaTest or performance run
was performed. Sections 2–10 were written before the addon's Lua was available; **section 11 (source inspection,
2026-11-21) supersedes them where they disagree.**

Path prefixes: `P = addons/privatewar/lua/privatewar/`.

Evidence labels:

- **[verified-in-source]**: read in a source file (this repository, or a public upstream file with commit and line).
- **[documented]**: stated by the author's own page or the Steam Web API.
- **[community-claim]**: stated by users (Workshop comments, discussions); not confirmed by source.
- **[assumption]**: inference or expectation; needs an in-game check (section 10).

## 1. Summary

1. The request names "artic stims". The matching addon is **"[GCAL] Arctic's Combat Stims"** (formerly
   "[VManip] Arctic's Combat Stims"), Workshop ID `2370028261`, author Arctic (`neco_arctic`, the ARC9/ArcCW author).
   It is a VManip/GCAL off-hand animation addon, **not** an ARC9 or ArcCW dependency. [documented]
2. It requires the off-hand animation library GCAL (Workshop `3727245204`, by Midawek), which replaces and emulates
   VManip. ArcCW is optional. [documented]
3. No licence or reuse permission is stated and no public source repository exists. Its assets include Valve (CS:GO)
   and Turtle Rock (L4D2) material. **Nothing from it may be vendored**; only runtime use of whatever the player has
   installed is possible. [documented]
4. The addon is a self-contained "pick up stims, hold a key, scroll, release to inject" system with its own
   inventory, its own console command `+arc_vm_medshot`, its own net message and its own status effects. It has no
   documented API to inject programmatically, and its effects are client-driven by a held key. [documented,
   community-claim]
5. Its effect code could not be read, so **how** it applies heal and speed is unknown. Users report that its speed
   boost does not affect sprint, and that speed sometimes does not apply. [community-claim] Private War must not
   rely on its effect logic.
6. Recommendation for the plan: implement both stims in core as ordinary weapon-less equipment items whose effects
   are PW-owned (health ticks; speed through the existing `move_speed` stat chain), with a built-in fallback
   presentation, and an optional integration addon that only plays Arctic's first-person injection animation
   through the public GCAL/VManip API when installed. Section 9 justifies this.

## 2. Identity, dependencies, licence

| Fact | Value | Label and source |
| --- | --- | --- |
| Title | `[GCAL] Arctic's Combat Stims` (earlier `[VManip] Arctic's Combat Stims`) | [documented] Steam Web API `GetPublishedFileDetails`, queried 2026-11-21; Workshop page <https://steamcommunity.com/sharedfiles/filedetails/?id=2370028261>; the old title appears in user-quoted error headers in the comments |
| Workshop ID | `2370028261` | [documented] |
| Author | Arctic, Steam profile `neco_arctic`, SteamID64 `76561198072670107` | [documented] page breadcrumb and API `creator` |
| Posted / last updated | 22 Jan 2021 / 10 Feb 2021 (`time_updated` 1612998675); 19 change notes | [documented] page and API |
| Size, popularity | 7,234,958 bytes; about 102,641 subscribers | [documented] API |
| Ban state | `banned: 0`. The "removed from the community" and "incompatible" texts seen by automated fetchers are hidden HTML templates (`style="display: none"`), not real notices | [verified-in-source] raw page HTML, 2026-11-21 |
| Required item | Garry's Mod Compliant Armature Layer (GCAL), ID `3727245204`, by Midawek, updated 16 Nov 2026 | [documented] page "Required items"; API |
| Optional | ArcCW (`2131057232`): "has features that cooperate with ArcCW"; Arctic's Radial Binds (`2391301431`) suggested | [documented] description |
| Credits | Code and textures: Arctic; status icons: Aerosun; animation: Datæ; Medi-Shot texture and audio: Valve (CS:GO); Adrena-Shot model, texture and audio: Turtle Rock Studios (L4D2); IK rig: Pavlendia; font: Bender | [documented] description |
| Licence / permissions | None stated. A user asked whether the code may be reused with credit; no answer is visible | [documented] page and comments |
| Public source | None found: no repository linked; GitHub code search for `arc_vm_medshot`, `vm_arc_medshot`, `arc_medshot_replacevial`, `sv_vm_arc_medshots.lua` returned 0 results (2026-11-21) | [verified-in-source] GitHub search API |
| GCAL licence | The public repository <https://github.com/Midawek/gcal> (read at `09cc0a3`) has **no licence file**; its README warns the GitHub version is not release-ready | [verified-in-source] |

Consequences for the project (`CLAUDE.md`, "Third-party code"):

- Rule 2 (vendoring only GPL-compatible code with a notice) cannot be met for this addon or GCAL. **Do not copy
  models, sounds, materials, animation files or Lua** from either into the repository or a published tree.
- Rule 4 allows an integration addon that uses only the public API of the installed addon. Section 9 defines what
  "public API" can mean here.

## 3. User-facing behaviour of the addon

| Behaviour | Label and source |
| --- | --- |
| Bind `+arc_vm_medshot` (the page says `BIND J +ARC_VM_MEDSHOT`). Hold the key to open a selector, scroll to choose a stim, release to inject | [documented] description |
| Stims are obtained as entities: spawn menu "Entities" tab under "VManip (Arctic)"; by default HL2 health vials are replaced by random stims (`arc_medshot_replacevial 0` stops it) | [documented] description; changelog 23 Jan 2021 "Option to replace medical vials with random stim" |
| NPCs drop stims when killed | [community-claim] several comments ask how to disable "NPC stim drops" |
| Several stim types, helpful and harmful ("Krokodil", "Mutant", "Boat" cleaner, a speed stim, an adrenaline stim, a "coldblooded" effect). The in-game menu describes each | [documented] description and changelog (Krokodil, Mutant, Necrosis, Speed); [verified-in-source] for the effect key `coldblooded` (section 4) |
| Status effect icons; effects blink for 5 seconds before they wear off | [documented] changelog 4 Feb and 6 Feb 2021 |
| A used syringe model drops after use | [documented] changelog; [community-claim] the used model `w_arc_vm_medshot_used` sometimes renders as an error model |
| Injecting others: "boat" works on NPCs, positive stims on players only | [community-claim] many comments |
| Effects were fixed to not bleed into a new life | [documented] changelog (search result summary of the second changelog page) |

There are no documented gameplay numbers (heal amount, speed multiplier, durations).

## 4. Internals observed indirectly

The addon's Lua could not be read: there is no public source, and extracting the installed `.gma` from the Deck is
forbidden for this research. The following names come from error messages users pasted and from other public
addons that integrate with it.

| Name | What it suggests | Label and source |
| --- | --- | --- |
| `lua/autorun/sv_vm_arc_medshots.lua`, `lua/autorun/sh_vm_arc_medshots.lua`, `lua/autorun/cl_vm_arc_medshots.lua` | Plain autorun files (server, shared, client), not a SWEP | [community-claim] pasted stack traces (comments 2021-11-27, 2022-02-12, 2024-06-12, 2026-02-07) |
| `UseMedShot` in `cl_vm_arc_medshots.lua:57`, called from a concommand at line 194; it indexes the global `VManip` | Injection starts on the client from the key release, and plays a VManip animation | [community-claim] trace "attempt to index global 'VManip' (a nil value)" |
| Net message `vm_arc_medshot_use`, sent in `sv_vm_arc_medshots.lua:99`; warns when the target is a non-player | Server is told of the use and replies to the target player (fails for NPC targets) | [community-claim] traces 2022–2026 |
| Hook error in `sh_vm_arc_medshots.lua:530` "attempt to call field 'GetAll'" | A shared hook iterates something per tick or per event; fragile with other addons | [community-claim] |
| `ply.ArcticMedShots_Inv` (table `shotID -> quantity`) and global `ArcticMedShots_SyncPlayer(ply)` | Server-side per-player inventory on the player table, synced to the client by a function | [verified-in-source] third-party addon `EntranceJew/gmod-addons` `death_combined_luggage/lua/autorun/death_combined_luggage.lua` lines 119–120, 205–206, 387–396 at `6dc07f4` |
| `ent.ArcticMedShots_ActiveEffects["coldblooded"]` | Active effects are a table on the player entity keyed by effect id, readable on the client | [verified-in-source] Arctic's own ARC9 `lua/weapons/arc9_base/cl_flir.lua` line 258 at `dd22238` (<https://github.com/necoarctic/ARC-9>) and ArcCW `lua/weapons/arccw_base/cl_holosight.lua` line 114 at `829fb3a` |
| Entity classes `arc_medshot_*` | One scripted entity per stim type for pickups | [verified-in-source] `SergeantPan/Miscellaneous-Addons` `CoolIcons - World icons for Ammo-Weapons-Items/lua/autorun/server/3ditemicons-itemmarker.lua` line 63 at `4e07846` |
| Animation name `arc_vm_medshot_inject` | The injection sequence registered with VManip | [community-claim] only a search-result summary of a discussion; **unverified**; must be checked in game (section 10) |
| Model `weapons/c_mifl_vm_medshot2.mdl` | One of the first-person animation models | [community-claim] comment 2022-06-22 "Failed load of .VTX data for weapons\c_mifl_vm_medshot2.mdl" |

None of these are a documented API. The globals and player fields are internal state another author happened to
use; they may change or disappear (the item's dependency already moved from VManip to GCAL without a code update).

## 5. How heal and speed are applied (unknown)

- **Heal.** Unknown whether it is instant or over time, and whether it uses `SetHealth` or armor. [assumption]
- **Speed.** Unknown mechanism. Two user reports: the adrenaline stim "doesn't really boost your SPRINT speed, only
  the running/non shift speed" (2023-03-30) and "the speed boosts dont apply" (2025-11-20). [community-claim]
  Either symptom is consistent with writing walk speed or `SetupMove` max speed in a way that another addon or the
  weapon base overrides. [assumption]
- **Client/server mismatch.** "The client gets a different set of effects than the server does when you use a
  mutant syringe" (2026-04-03). [community-claim] Random effects appear to be rolled separately per realm.
- **Death.** Effects are cleared on a new life (changelog). [documented]

Conclusion: the addon's effect logic is unknown, unverified and reportedly buggy for speed. Private War must own
heal and speed itself and must never let Arctic's logic apply on top of it.

## 6. Can it be invoked programmatically?

| Path | Assessment |
| --- | --- |
| Run `+arc_vm_medshot` for a player | Client concommand driven by a held key and scroll selection; cannot be run for bots (no client) and would apply Arctic's own effects. Rejected. [documented, assumption] |
| Write `ply.ArcticMedShots_Inv` and send `vm_arc_medshot_use` | Internal, undocumented, unverified; would apply Arctic's effects and its bugs. Rejected. [assumption] |
| Play only the first-person animation through GCAL or VManip | `GCAL:Play(name, trackID)`, `GCAL:IsTrackActive(trackID)`, `GCAL:GetAnimationNames()` and `GCAL.Anims[name]` are GCAL's documented native API; `VManip:PlayAnim(name)`, `VManip:GetAnim(name)` and `VManip:IsActive()` are the legacy API that GCAL redirects. Animations from `vmanip/anims/*.lua` of any addon are imported automatically. Purely clientside, local player only. **Viable**, provided the stim's animation name is registered. [verified-in-source] GCAL `DEVELOPER.md` sections 0, 1, 3.5, 7 at `09cc0a3`; VManip `lua/autorun/client/cl_vmanip.lua` lines 155–157, 243–263 at `bf049d5` (mirror <https://github.com/1yling/VManip>) |
| Use Arctic's models or sounds directly | Paths are unknown (section 4 has one community-claimed model path); usable at runtime only when installed and verified with `util.IsValidModel` / `file.Exists(..., "GAME")`. Possible, low value. [assumption] |

Bots: they have no client, so they never see first-person animations. Their stim use must be the PW server path
only (`PW.Equipment.Use`). [verified-in-source] `P/modules/bots_tactics/shared.lua:259` (`UseEquipment` calls
`PW.Equipment.Use`).

## 7. Multiplayer, prediction and interplay

- VManip/GCAL animations are first-person and local: other players do not see them; GCAL has an experimental
  third-person IK, described by its author as beta. [verified-in-source] GCAL `DEVELOPER.md` section 0, section 5
- The ARC9 base composes its own speed on top of the player's walk/run speed in a shared `SetupMove` hook: it caps
  the commanded speed at `mv:GetMaxClientSpeed()` and multiplies it by the weapon's `Speed`, reading
  `ply:GetRunSpeed()` / `GetWalkSpeed()` while aiming. So a stim that scales walk/run speed composes multiplicatively
  with ARC9 weapon speed. [verified-in-source] <https://github.com/necoarctic/ARC-9> `lua/arc9/shared/sh_move.lua`
  lines 4–28, 64 at `dd22238`
- Because that hook also runs on the client, the client must see the same walk/run speed as the server, or the
  player is corrected (rubber-banding). The existing `move_speed` owner sets speeds on the server only; whether
  GMod networks walk/run speed to the owning client is not verified here. Fleet Foot already relies on this path
  (spawn-time only); a stim is the first **mid-life** change of it. [assumption] Checkpoint item in the plan.
- Arctic's addon keeps running independently of Private War if installed: replacing map health vials with random
  stims (default on) and letting anyone with an inventory inject via `+arc_vm_medshot`. Private War derives from
  `base` (`addons/privatewar/gamemodes/privatewar/privatewar.txt`), so there is no spawn menu; pickups can only
  come from replaced vials or NPC drops. [verified-in-source for the base; documented for vials;
  community-claim for drops]
- Known conflicts: scroll wheel selection fights weapon switching; binds lost after map change; a VManip conflict
  disables the addon. [community-claim]

## 8. Performance (Steam Deck)

- GCAL creates hidden clientside models per active track and removes them when the track ends; one short
  injection is a few frames of bone copying. [verified-in-source] GCAL `DEVELOPER.md` section 0
- Arctic's addon itself: unknown hooks (one shared hook at `sh_vm_arc_medshots.lua:530` exists). Users report lag
  only from many dropped stim entities. [community-claim] With vial replacement off and no NPCs, the addon should
  be idle. [assumption]
- The PW-owned effects proposed in the plan cost one instance timer per heal and one stat recompute at speed start
  and end; nothing per frame except a HUD text that is rebuilt only when it changes. [assumption, by design]

## 9. Architecture options

| Option | Pros | Cons | Verdict |
| --- | --- | --- | --- |
| A. Core items with PW-owned effects and a built-in fallback presentation; optional integration addon `addons/privatewar-stims/` that only plays Arctic's injection animation (GCAL/VManip public API) and turns its vial replacement off | Works with no third-party content (default install, GLuaTest runner, bots); one code path for humans and bots; no dependency on Arctic internals; follows "Third-party code" rule 4 and the `privatewar-arc9` precedent | Fallback has no first-person animation; the animation name must be verified in game | **Recommended** |
| B. Items only in the integration addon, requiring Arctic's addon | Full visuals from day one | Stims vanish without a 2021 unlicensed addon plus GCAL; tests need Workshop mounting; still cannot use Arctic's effect code | Rejected |
| C. Drive Arctic's own inventory and command | Closest to "integrate the addon" literally | Undocumented internals, unknown and buggy effects, double application, impossible for bots | Rejected |

Why A matches project rules: `design/05-loadout.md` d.11 ("equipment is just an item in a slot; its behaviour
belongs to the item"; "the slot may declare an action key ... pressing the slot key calls `OnUse`"); "Thin glue"
(pure rules in `sh_` files, engine calls in wrappers); global rule 2 (a disabled module or missing addon breaks
nothing); and `CLAUDE.md` "Third-party code" rules 1, 2 and 4.

## 10. Open facts to verify in game (by the user or with explicit Deck permission)

1. With GCAL and Arctic's stims installed, list registered animation names in the client console:
   `lua_run_cl for _, n in ipairs(GCAL and GCAL:GetAnimationNames() or {}) do if string.find(n, "medshot") then print(n) end end`
   (or iterate `VManip.Anims` when only legacy VManip is installed). Record the injection animation name(s) and
   whether the heal-looking (Medi-Shot) and speed-looking (Adrena-Shot) syringes are separate sequences, models or
   bodygroups.
2. Play the found animation on its own (`lua_run_cl GCAL:Play("<name>")`) with an ARC9 weapon and with an HL2
   weapon: does the syringe appear, how long is it, does it conflict with ARC9's viewmodel?
3. Confirm `arc_medshot_replacevial` exists as a server ConVar and whether an NPC-drop ConVar exists
   (`find arc_medshot` in console).
4. Confirm that a mid-life `SetRunSpeed` change (Fleet Foot path) does not rubber-band on the owning client.

## 11. Source inspection (2026-11-21)

The orchestrator downloaded Workshop items `2370028261` (Arctic's Combat Stims, 130 files) and `3727245204` (GCAL,
46 files) anonymously with Valve's `steamcmd` into a session scratchpad and extracted the `.gma` files there. Nothing
was copied into the repository; the files stay outside it (no licence). File paths below are relative to the
addon's `lua/` folder. Labels: **[src]** = read in the downloaded source.

1. **Effects are a shared global table** `ArcticMedShots_Effects[name] = { Think, OnWearOff, Network, NoReset,
   StatusIcon }` driven by a shared `Think` hook over `player.GetAll()` (`autorun/sh_vm_arc_medshots.lua:527`).
   Per-player state lives on `ply.ArcticMedShots_ActiveEffects[name] = dieTime`. **[src]**
2. **Programmatic entry point exists but is an undocumented global:**
   `ArcticMedShots_ApplyEffect(ply, effect, duration, delay, infl)` (`:478`). Only effects with `Network = true` are
   sent to clients (`vm_arc_medshot_effect`, `:500`); `speed_boost_25` and `regen_1` are **not** networked
   (`:144`, `:15`). **[src]**
3. **Speed** is a shared `Move` hook (`:567-586`): `mv:SetMaxSpeed(mv:GetMaxSpeed() * s)` and
   `SetMaxClientSpeed`, with `s` = 2 (`bus_that_couldnt_slow_down`), 1.25 (`speed_boost_25`), 0.75 (`speed_down_25`).
   Because the effect is not networked, the client only predicts it when it also applied the effect itself: the
   addon's own client calls `shottable.OnInject(LocalPlayer())` locally after the animation
   (`autorun/cl_vm_arc_medshots.lua:54-77`). A server-only `ApplyEffect` would mispredict movement (rubber-banding).
   It also multiplies after every other `Move`/`SetupMove` change, so it does not compose with Private War's speed
   owner. The "does not boost sprint" reports are therefore an interaction effect, not a missing sprint path. **[src]**
4. **Heal:** `morphine` heals 50 at once and overheals to `GetMaxHealth() + 25` (`:195-210`); `regen_1` heals 1 HP
   every 0.4 s (`:15-26`). **[src]**
5. **Use flow:** client `UseMedShot` plays `VManip:PlayAnim("arc_vm_medshot_inject")`, sets the gesture skin from the
   shot's `Skin` (heal `morphine` 0, speed `adrenaline` 1) and optional `ShotMaterial`, then after `timer.Simple(1)`
   sends `vm_arc_medshot_use` (`cl_vm_arc_medshots.lua:54-77`). The server receiver (`sv_vm_arc_medshots.lua:41-102`)
   checks the inventory, plays a third-person gesture `ACT_GMOD_GESTURE_MELEE_SHOVE_1HAND` and the sound
   `weapons/arc_vm_medshot/healthshot_success_01.wav` to others, spawns a used-syringe prop after 0.75 s, applies
   `OnInject` and decrements `ply.ArcticMedShots_Inv`. **[src]**
6. **Animation (verified):** `vmanip/anims/medshot_anim.lua` registers `arc_vm_medshot_inject` (self) and
   `arc_vm_medshot_inject_player` (another player) with model `weapons/c_arc_vm_medshot.mdl`, speed 0.5, sounds at
   0, 7/30, 28/30 and 31/30 of the cycle; effect timing in the addon is 1 s after start. One animation serves every
   shot; the variants differ only by skin/material. **[src]**
7. **GCAL** provides a VManip compatibility shim (`gcal/lua/autorun/aaa_gcal_shim.lua`): `VManip:RegisterAnim`,
   `PlayAnim`, `GetVMGesture` and others, with no-op stubs when the backend is missing. **[src]**
8. **Other side effects:** `PlayerSpawn` resets inventory and effects (`sv_vm_arc_medshots.lua:122`);
   `arc_medshot_replacevial` (archived, replicated, default 1) replaces every `item_healthvial` with a random stim
   pickup (`:143`); the client hooks `PlayerBindPress` for `+arc_vm_medshot` and draws its own `HUDPaint` wheel and
   `RenderScreenspaceEffects`. **[src]**

Consequences for the plan (confirms the recommended option A):

- Do not call `ArcticMedShots_ApplyEffect` or send `vm_arc_medshot_use`: non-networked effects mispredict, the
  `Move` multiplier bypasses the Private War speed owner, and the morphine overheal contradicts the max-HP cap.
- The integration only plays `arc_vm_medshot_inject` on the owner's client through `VManip:PlayAnim`, sets the
  gesture skin (`stim_heal` → 0, `stim_speed` → 1), and on the server sets `arc_medshot_replacevial 0` for the session.
- Private War's own speed path (`SetRunSpeed`/`SetWalkSpeed` through `player_overrides`) is engine-networked, so it
  predicts correctly without extra messages.

## Sources

- Workshop item: <https://steamcommunity.com/sharedfiles/filedetails/?id=2370028261>, change notes
  <https://steamcommunity.com/sharedfiles/filedetails/changelog/2370028261>, comments (rendered through the public
  comment endpoint, 589 comments, read 2026-11-21).
- Steam Web API `ISteamRemoteStorage/GetPublishedFileDetails` for IDs `2370028261` and `3727245204`, 2026-11-21.
- GCAL: <https://steamcommunity.com/sharedfiles/filedetails/?id=3727245204>, <https://github.com/Midawek/gcal>
  (`09cc0a3`, `DEVELOPER.md`).
- VManip legacy API mirror: <https://github.com/1yling/VManip> (`bf049d5`).
- ARC9: <https://github.com/necoarctic/ARC-9> (`dd22238`); ArcCW: <https://github.com/necoarctic/ArcCW> (`829fb3a`).
- Third-party users of the addon's state: <https://github.com/EntranceJew/gmod-addons> (`6dc07f4`),
  <https://github.com/SergeantPan/Miscellaneous-Addons> (`4e07846`).
- Repository code: `P/modules/equipment/`, `P/modules/player_overrides/init.lua`, `P/modules/perks/`,
  `P/modules/bots_tactics/`, `P/hud/equipment.lua`, `docs/api/equipment.md`, `docs/api/player-overrides.md`,
  `docs/api/perks.md`.
