# Calling cards: equip a card, show the victim's card to the killer

Status: `done`

Recorded: 2026-11-22

Implemented on `feat/calling-card-kill-banner` from `76ed4c8` and merged locally into
`integration/overnight-2026-11-22` at `0710176` on 2026-11-22. Not merged into `main`.

- Test-first runs covered choice and wire, server validation, HUD, and picker. All 18 mandatory names and
  28 card tests were verified. On `f308644` and again on `0710176`, `make check` passed and the full Deck
  `make test` passed 2276, 0 failed, 1 skipped (requires the optional Arctic addon).
- Package verification compared all ten 512×128 release PNGs byte-for-byte and rejected unrelated and nested
  PNGs. The source artwork is not packaged.
- Deck smoke confirmed Recruit in the picker, the reason on a reward-locked card, and the victim's card and
  name above the XP strip after an actual enemy kill. The gradient edge was corrected and rechecked.
  Profile data and settings checked by the probe were unchanged. The human checkpoint below remains pending.

Approval (2026-11-22): the user approved every design change proposed in this record and the recommended
default of every open question, except where an answer below says otherwise. This approves the design
direction for implementation; push, PR, merge to `main` and publication still need separate approval.

This record is tracking only; it does not authorize implementation, design or API changes, Steam Deck access or
publication. Paths: `P = addons/privatewar/lua/privatewar/`, `T = addons/privatewar/lua/tests/privatewar/`; checked
at `cf7c4ed`. Numbers are **proposed defaults, user to confirm**.

Related: card unlocks must stay valid under [programmatic unlocks](../done/unlock-entitlements.md) (cards are natural
[weekly challenge](../in-progress/weekly-challenges.md) rewards); the selection flow mirrors operators
(`docs/api/operators.md`).

## 1. User request

- [ ] Record (translated, 2026-11-22): "Calling cards: you set a card, and when you die the other player is shown who
  you are and with which card. Position: centre of the screen, above the XP bar."
- [ ] Interpretation used here: when player V is killed by player K, **K** sees a banner with V's nickname and V's
  equipped calling card. The reverse (V sees K's card on the death screen, CoD "killed by") is open question 1.

## 2. Current state (verified)

- [ ] Kind `cards` exists, data only (`P/kinds/cards.lua`): required `Name`, `Material`; optional `Price`, `Unlock`,
  `Rarity`, `Description`; ConVar `pw_card_<id>_enabled`. Samples `P/cards/bomb.lua`, `gold_medal.lua`,
  `lightning.lua` use 16-pixel `icon16/*.png` materials; they are sold in the store and in bundles.
- [ ] There is **no** way to equip a card and no place shows one. `design/06-progression.md` d.6 lists calling cards
  for "lobby, killfeed, killcam, scoreboard"; none is implemented (killfeed is vanilla `DeathNotice`,
  `design/09-hud.md`; killcam is a draft, `design/11-camera.md`).
- [ ] The XP bar is a full-width strip along the bottom edge: height 6, gap 10 to the bottom, design units 1920×1080
  (`P/hud/progression.lua`). The vanilla health and ammo panels sit bottom left and right and end near y 1053; the
  bottom centre above the XP bar is free. Medal and LEVEL UP popups are at y 250–300 (`P/hud/popups.lua`).
- [ ] Kills reach modules on the server as `PW_PlayerKilled(victim, attacker, dmg)` (`P/modules/match_rules/init.lua:151`).
  No client message carries "you killed V" today.

## 3. Design changes requiring approval

- [ ] `design/06-progression.md` d.6: add "A player equips one calling card (client setting, validated by the
  server like the operator choice, d.7). When a player is killed by another human, the killer sees a kill banner with
  the victim's name and calling card, centred above the XP bar. Lobby, killfeed, killcam and scoreboard placements
  stay future work."
- [ ] `design/09-hud.md`: add the element "kill card banner" (bottom centre, above the XP bar, `LIVE` only).

## 4. Architecture

### 4.1 Selection (mirrors operators, `design/06-progression.md` d.7)

- [ ] New module `P/modules/calling_cards/` (`shared.lua`, `init.lua`, `cl_init.lua`), library `PW.CallingCards`.
- [ ] Client setting `calling_cards.selected` (scope `client`, dynamic enum, default `default` for Recruit), shown in
  SETTINGS > Personal and
  edited by a picker screen LOADOUT > CALLING CARD (`P/screens/loadout_card.lua`, modelled on
  `P/screens/loadout_operator.lua`): grid of cards, locked ones shown locked with the requirement text, preview of the
  banner at the bottom.
- [ ] The client sends `pw_card_choice` (string, at most 32 bytes) on join and on change through `PW.Net.Receive`
  (`who = "any"`, `rate = 2`, `maxLen = 34`, owner the module). The empty string remains a wire-only reset to Recruit;
  it is not a settings enum option. The settings core does not change.
- [ ] Server validation, pure `PW.CallingCards._Resolve(id, facts) -> string`: returns `id` when the card is registered,
  enabled and unlocked for the player (`PW.Unlocks.IsUnlocked(ply, "cards", id)`),
  else the default card id. Malformed input keeps the previous choice. Re-checked at every spawn (an unlock can be
  lost when the host changes settings).
- [ ] The resolved id is published as the NW2 string `pw_card` on the player (written only on change).
- [ ] Default card: `P/cards/default.lua` ("Recruit", level 1, free; section 4.4). Without it the banner draws a
  plain plate.
- [ ] Bots: a random enabled card picked once per bot per session (locks ignored), the same way bots get a random
  operator. Pure `_BotCard(ids: string[], rng) -> string?` over the sorted id list.

### 4.2 Trigger (server)

- [ ] In the module's `PW_PlayerKilled(victim, attacker)`: when `attacker` is a valid **human** player, `attacker ~=
  victim`, and the phase is `LIVE`, send `pw_kill_card` to the attacker only.
- [ ] Payload (explicit writes, no `net.WriteTable`): victim name (`net.WriteString`, truncated to 32 bytes on the
  server), card id (`net.WriteString`, at most 32 bytes, the victim's current `pw_card`), `net.WriteBool(victimIsBot)`.
  The name is a snapshot so a victim who disconnects still shows correctly.
- [ ] Nothing is sent for suicides, world kills, kills by non-players or kills by bots. Team kills: open question 4.

### 4.3 Banner (client)

- [ ] HUD element `P/hud/kill_card.lua`, `HUDELEMENT.Phases = { "LIVE" }`, order between progression (15) and popups
  (30), e.g. 20.
- [ ] Layout in design units (1920×1080, scaled like the other elements): card 400×100 (4:1, the common calling-card
  aspect), horizontally centred, bottom edge 24 above the top of the XP bar (y ≈ 1040 − 100 = 940 top). The card
  material fills the plate; the victim's name is drawn over the left part in `PW.UI.FontName("medium")` with a shadow;
  a small label `ELIMINATED` above the name in the `text_muted` token. Bot victims show the same layout.
- [ ] Timing: fade in 0.15 s, hold 2.5 s, fade out 0.3 s. A new kill **replaces** the current banner and restarts the
  timer (open question 2).
- [ ] Missing or failed material (`Material(path):IsError()`): draw a plate in the rarity colour (`common`, `rare`,
  `epic`, `legendary` tokens; fallback neutral) with the card's `Name`. Materials are cached per card id; no
  allocation per frame.
- [ ] Client setting `calling_cards.banner` (bool, default true): hide the banner.
- [ ] Pure seams in `shared.lua`: `_BannerAlpha(startedAt, now, fadeIn, hold, fadeOut) -> number` (0 when finished),
  `_BannerRect(scrW, scrH, scale) -> x, y, w, h`, `_Encode(state, writer)` / `_Decode(reader)`.

### 4.4 Card set and art (user decision 2026-11-22)

- [ ] Ten original cards: **4 for player level, 6 for weekly challenges**, one card per challenge type. Art prompts and
  the id mapping: `design/visual-prompts/15-calling-cards.md`. Assets are generated by the maintainer, then converted
  to 512×128 PNG under `addons/privatewar/materials/privatewar/cards/` (original project art; no third-party or
  brand imagery).

| Card id | Name | Rarity | `Unlock` |
| --- | --- | --- | --- |
| `default` | Recruit | common | none (level 1, the default choice) |
| `level_20` | Veteran | rare | `20` |
| `level_40` | Elite | epic | `40` |
| `level_55` | Legend | legendary | `55` |
| `challenge_headshots` | Headhunter | epic | `{ level = false, reward = "challenge" }` |
| `challenge_longshots` | Marksman | rare | `{ level = false, reward = "challenge" }` |
| `challenge_captures` | Flag Runner | rare | `{ level = false, reward = "challenge" }` |
| `challenge_streak_kills` | Air Support | epic | `{ level = false, reward = "challenge" }` |
| `challenge_life_kills` | Untouchable | epic | `{ level = false, reward = "challenge" }` |
| `challenge_wins` | Champion | legendary | `{ level = false, reward = "challenge" }` |

- [ ] Art status (2026-11-22): **10 of 10** generated and reviewed (no text or logos, faces hidden, set style
  consistent). Sources and 4:1 versions are kept locally outside the repository until implementation; then 4:1
  sources go to a non-shipped source folder; the game uses **512×128 PNG** files at
  `addons/privatewar/materials/privatewar/cards/<id>.png` (GMod loads PNG through `Material()`, as the existing
  `icon16/*.png` samples do), so no VTF conversion is needed. `CARD.Material = "privatewar/cards/<id>.png"`. 3:1 originals were made
  4:1 by cropping, except `level_55`, which was extended to the left with the `bg` colour and a soft fade (the full
  figure does not fit a crop). Known compromises: the `challenge_captures` crop loses most of the capture ring (can be
  redone with the same left extension); `challenge_longshots` and `challenge_streak_kills` have detail in the left
  text zone.
- [ ] Readability does not depend on the art: the banner always draws a left-to-right dark gradient under the name
  (`bg` token, alpha about 0.85 at the left edge fading to 0 at 55 % of the width) before the text. Pure layout case
  in section 7: `Name plate gradient is drawn under the name on every card`.
- [ ] The `{ level = false, reward = ... }` form exists only after [programmatic unlocks](../done/unlock-entitlements.md).
  Until then the six challenge cards are registered but hidden from the picker (or the whole challenge half ships
  with weekly challenges); the four level cards need no other change.
- [ ] Each weekly challenge template grants its card through `Rewards.items` (`{ kind = "cards", id = ... }`) when the
  challenge is completed: `headshots` (C2), `longshots` (C8), `captures` (C10), `streak_kills` (C15), `life_kills`
  (C20), `wins` (C17) in `changes/in-progress/weekly-challenges.md` section 7, at any existing tier. Delivery of
  these rewards is owned by the weekly change and is not part of this feature's verification.
- [ ] The three existing samples (`bomb`, `gold_medal`, `lightning`, store and bundle items) stay; their 16-pixel icons
  are drawn **centred** on a rarity plate, never stretched (pure layout case in section 7).

## 5. Files to create or modify

| Path | Action |
| --- | --- |
| `P/modules/calling_cards/shared.lua` | Create: `MODULE.Settings`, pure `_Resolve`, `_BotCard`, `_BannerAlpha`, `_BannerRect`, encode/decode |
| `P/modules/calling_cards/init.lua` | Create: choice receiver, NW2 `pw_card`, spawn re-check, bot pick, `PW_PlayerKilled` sender |
| `P/modules/calling_cards/cl_init.lua` | Create: send choice on join/change, receive `pw_kill_card`, feed the banner |
| `P/hud/kill_card.lua` | Create: banner element |
| `P/screens/loadout_card.lua` | Create: picker |
| `P/cards/default.lua`, `level_20.lua`, `level_40.lua`, `level_55.lua`, `challenge_*.lua` (6) | Create |
| `P/types/calling_cards.lua` | Create: LuaLS annotations |
| `addons/privatewar/materials/privatewar/cards/<id>.png` (10 files, 512×128) | Create (art approved and ready) |
| `docs/api/calling-cards.md`, `docs/api/README.md`, `docs/api/economy.md` (cards row), `docs/api/ui.md` (screen, HUD element) | Create/modify (orchestrator) |
| `T/calling_cards.lua`, `T/hud_kill_card.lua` | Create |

## 6. Implementation steps (TDD; one commit each)

- [ ] Approve section 3; apply the design text. `docs(design): add calling card kill banner`.
- [ ] Contracts: `docs/api/calling-cards.md` and the touched API docs. `docs(api): freeze calling card contracts`.
- [ ] Pure rules and settings: tests first, then `shared.lua` and types. `feat(cards): add calling card selection rules`.
- [ ] Server: choice receiver, NW2, spawn re-check, bots, kill sender. `feat(cards): validate and publish calling cards`.
- [ ] Client: choice upload, `pw_kill_card` receiver, banner element. `feat(hud): show the victim's calling card`.
- [ ] Picker screen and default card. `feat(ui): add calling card picker`.
- [ ] Art (if approved). `feat(cards): add calling card art`.
- [ ] Gates and the human checkpoint.

## 7. Mandatory test cases

`T/calling_cards.lua`:

- [ ] `Resolve: a registered, enabled, unlocked card is accepted`
- [ ] `Resolve: unknown, disabled or locked cards fall back to the default card`
- [ ] `Resolve: malformed input keeps the previous choice`
- [ ] `Spawn re-check falls back when the card became locked`
- [ ] `Choice publishes pw_card only on change`
- [ ] `BotCard: deterministic for the same rng and id list, nil for an empty list`
- [ ] `Kill sends pw_kill_card to a human attacker only, with the victim name and card`
- [ ] `No pw_kill_card for suicide, world kill, bot attacker or outside LIVE`
- [ ] `Victim name is truncated to 32 bytes`
- [ ] `Encode and decode round-trip the banner state`
- [ ] `pw_card_choice over maxLen or above the rate limit is dropped`

`T/hud_kill_card.lua`:

- [ ] `BannerAlpha: fade in, hold, fade out, then 0`
- [ ] `A new kill replaces the banner and restarts the timer`
- [ ] `BannerRect: centred, 4:1, bottom edge above the XP bar at common resolutions` (1280×800 Deck, 1920×1080)
- [ ] `Missing material falls back to a rarity plate with the card name`
- [ ] `Small icon materials are drawn centred, not stretched`
- [ ] `Name plate gradient is drawn under the name on every card`
- [ ] `Banner hidden when calling_cards.banner is off`

## 8. Human checkpoint (Steam Deck; fresh permission, Deck free)

- [ ] Pick a card in LOADOUT > CALLING CARD; locked cards show the requirement.
- [ ] Kill a bot: its card and name appear centred above the XP bar, readable on the Deck screen, gone after ~3 s.
- [ ] With a friend: each sees the other's chosen card when killing them.
- [ ] The banner does not overlap health, ammo, equipment, medals or LEVEL UP.

## 9. Answers and open questions

User answers (2026-11-22):

1. Killer's card on the victim's death screen: no preference; **out of scope** for this record.
2. Several kills in a row: **replace** the banner.
3. Card art: **ten cards**, 4 for player level and 6 for weekly challenges (one per challenge type); the maintainer
   generates the art from `design/visual-prompts/15-calling-cards.md`.
4. Team kills: **no banner**.
5. Bots: **random card per bot**.

6. Show the victim's level next to the name? **No for now** (bots have no real level).
7. Which challenge completion grants its card: **any existing tier**, implemented separately with weekly challenges.

## 10. Gates

- [ ] `nix develop --command make check` and `nix develop --command make test` with `set -o pipefail` before merge.
- [ ] Game tests and the checkpoint need explicit permission and a free Deck; record user acceptance separately.
