# 06 — Progression

Status: decided.

## Goal and scope

XP, unlocks, persistence.

## Decisions

0. Progression is local per player, sent to the host on join, and forgeable (accepted; `../DESIGN.md`, Decided).

1. **MVP layers: player level, weapon level, unlock-all.**
   - Player level (XP) unlocks entities through their `Unlock` field: weapons, perks, equipment, killstreaks, wildcards.
   - Weapon level (XP per weapon) unlocks attachments (decision 2).
   - `server` setting `progression.unlockall`: the host opens everything with one switch (friends on a fresh install should not grind to play). Progression still accumulates.
   - After MVP: prestige, challenges (for example "100 headshots" → camo).

2. **Attachments and camos are curated inside the weapon entry; fallback by count.**

   ```lua
   function MODULE:PW_RegisterWeapons(reg)
       reg.Register({
           Category = "ar",
           Unlock   = 4,                                  -- player level for the weapon itself
           Attachments = {                                -- optional curation, keyed by option id
               optic_acog  = { Unlock = 5 },              -- weapon level
               muzzle_supp = { Unlock = 12, Cost = 2 },
               meme_scope  = { Hidden = true },           -- never offered
           },
           Camos = { gold = { Unlock = 30 } },            -- cosmetic options, weapon level
       }, "arc9_eft_ak74", { soft = true })
   end
   ```

   - Attachments do not become registry entities (no per-attachment ConVars; there are thousands). They stay adapter data (`04-weapons.md` decision 1); curation lives in the weapon entry, declarative (`weapons/<class>.lua`) or programmatic.
   - With curation: `Unlock` by weapon level (MW2019 style), `Cost` for Pick X (`05-loadout.md` decision 2), `Hidden` to never offer an option.
   - Without curation: the weapon level unlocks the **number** of attachments that may be installed (level 1 → 1 attachment, level 5 → 5), any attachment allowed; capped by `loadout.maxattachments`. Any pack works without markup.
   - `PW_PreRegister` runs on the weapon entry, so another addon can patch the attachment curation of someone else's weapon.
   - `soft = true` merges nested tables per option: a curated file overrides automatic values option by option, not the whole `Attachments` table.

   **Revision 2026-11-07 (user decision): stat-based default unlock levels for integrations, starting with ARC9.** A pack with hundreds of weapons cannot be curated by hand, so the integration derives the default levels from stats:

   - Weapons: a power score from stats (damage and time-to-kill at close and mid range, rate of fire, recoil and spread, mobility: ADS time and sprint-to-fire). Weapons are ranked within their category and spread over player levels 1..55, so that 1-2 weapons per category are open at once.
   - Attachments: ranked within their slot by stat gain and spread over weapon levels 1..30. Cosmetics unlock by weapon level as before. Attachments without numeric stats get the middle level of their slot (counted in the report).
   - The result is computed once per map and cached in a data file keyed by the weapon set.
   - It is registered `soft`, so hand curation always wins, option by option.
   - A host setting turns the automatic levels off (then the fallback by count applies).
   - Decided (confirmed by the user on 2026-11-07; the local manual checklist (not published) section 7, item 65): the formula weights and normalisation as implemented (`../docs/api/progression.md`, "Automatic unlock levels"; one table `PW.AutoUnlock.Weights`).
   - Decided on 2026-11-07 (added during implementation, confirmed by the user): weapons of the built-in starter classes (Assault, Close Quarters, Run and Gun) are always open at level 1 and count towards the 1-2 weapons open per category, so the ready-made classes stay usable for a new player with a large pack.
   - Camos are the bases' cosmetic attachment options (`cosmetic` flag); MVP unlocks them by weapon level only; challenge unlocks come later.
   - Banning a single attachment for a match: `set` setting `loadout.bannedatts` with `"<adapter>:<option id>"` strings.

3. **One source for match score, XP and streak progress: score events, a kind `score_events/`.**

   ```lua
   -- score_events/kill.lua
   EVENT.Name   = "#pw.score.kill"
   EVENT.Points = 100            -- match score; also streak progress in "score" mode
   EVENT.XP     = nil            -- nil = same as Points
   EVENT.Medal  = false          -- true = popup with icon and sound

   -- score_events/headshot.lua
   EVENT.Points = 50
   EVENT.Medal  = true
   ```

   - Modes and modules award: `PW.Score.Award(ply, "kill", { weapon = wep })`.
   - The `score` module adds match score and fires the notification `PW_ScoreEvent(ply, eventId, points, xp, weapon)`. Listeners: progression (player XP, and weapon XP when `weapon` is given), killstreaks in `score` mode (`05-loadout.md` decision 9), HUD popups and medals, announcer.
   - Question hook `PW_ScoreValue(ply, eventId, points)` changes the value of any event (hardcore playlists, modes with other balance).
   - Medals are events with `Medal = true`. Their detectors (double kill, revenge, first blood, ...) are code in a medals module that calls `Award`. No separate `medals/` kind (replaces it in the draft kind list of `01-extensibility.md`).
   - Weapon XP comes only from events awarded with `weapon` (usually kills and headshots).
   - MVP events: kill, headshot, assist, point capture, tag confirmed and tag denied (Kill Confirmed), match win; medals: double kill, triple kill, revenge, first blood, 5-kill streak, saviour.

4. **Level curves (defaults, `server` settings).**

   | Parameter | Default |
   | --- | --- |
   | Max player level | 55 |
   | XP to next player level | `1000 × level^1.2` (about 1 000 at level 1, about 12 000 at level 55) |
   | Max weapon level | 30 |
   | Weapon XP to next level | `500 × level^1.1` |

   - The coefficients are `server` settings, so a host can speed up progression (double XP) without `unlockall`.

5. **Storage and transfer: everything lives on the client.**
   - Client file `data/privatewar/progression.json`: `{ v, xp, weapons = { [class] = xp } }`, next to `classes.json` (`05-loadout.md` decision 12).
   - On join the client sends progression together with classes; the server only sanity-checks (no negatives, numbers in sane bounds). Forgery is not detected (accepted).
   - During the match the server accumulates earned XP and every 10 s sends the client a **delta**; the client adds it and saves. A crash loses at most 10 s of progress.
   - The server does not store anyone's progression.
   - At match end the client receives a summary (XP earned, levels gained, unlocks) for the `POSTMATCH` screen.

### Economy

6. **Meta currency and a shop (module `economy`; disabling it leaves level-only unlocks).**
   - Currency is earned through score events: optional `EVENT.Currency`, default 10 % of XP, plus an end-of-match bonus. Stored in `progression.json` next to XP; forgeable (accepted). No real money, ever.
   - Entities may have `Price` next to `Unlock`: an item is unlocked if the level is reached **or** it was bought. Purchases are stored in `progression.json`.
   - **Shop bundles: a kind `bundles/` (data), curated by addon authors.**

     ```lua
     -- bundles/neon_reaper.lua
     BUNDLE.Name   = "Neon Reaper"
     BUNDLE.Price  = 2400
     BUNDLE.Rarity = "legendary"
     BUNDLE.Items  = {
         { kind = "weapons", id = "arc9_eft_ak74" },                  -- early unlock
         { kind = "camo",    weapon = "arc9_eft_ak74", id = "neon" },
         { kind = "cards",   id = "neon_reaper" },
         { kind = "models",  id = "reaper_operator" },
     }
     ```

   - **Rotation without a backend:** "Featured" changes daily, "Weekly" weekly; the selection is deterministic from the current date, so every player sees the same shop. A permanent catalogue sells single unlocks by `Price`.
   - **Minimal cosmetics for MVP**, so bundles have something to sell: kinds `models/` (player models, "operators", visible in match and lobby) and `cards/` (calling cards: lobby, killfeed, killcam, scoreboard); camos already exist (decision 2).
   - After MVP, as separate modules: battle pass (100 reward tiers per season; season derived from the date, no backend), supply drops (random rewards for currency).

7. **Operators and bot names** (decided with the user on 2026-11-07; module `operators`, `../docs/api/operators.md`).
   - One global operator skin per player, not per class: chosen once, used in every match and in the lobby operator panel. The list holds every valid stock player model (`player_manager.AllValidModels()`, Workshop playermodels included) and the economy `models` entries: owned or free ones are selectable, locked purchasable ones show as locked with their price (or level).
   - Default: the player's own GMod `cl_playermodel` when it is valid, else a stock model. The choice is a client setting (`operators.model`, Personal settings); the picker with a model preview is LOADOUT > OPERATOR.
   - The client sends the choice on join and on change through one small validated net message; the server checks it (a valid player model; an economy model must be unlocked or bought) and applies it in `PlayerSetModel` at spawn, with the player colour set to the team colour in team modes.
   - Bots get a random valid player model when they join (economy models included, ownership ignored) and keep it for the session; no team-based split. In team modes their player colour is the team colour too.
   - Bots get human-like names from a built-in, editable pool of about 100 original first names, surnames and callsigns (no real people, no copyrighted characters), unique among the current players; never "Bot01".
   - Details taken by recommendation (economy model wins over a stock model with the same path, fallback order, FFA colours): the local manual checklist (not published) section 7, item 68.

## Interfaces

TBD.

## Performance budget

TBD.

## Security

TBD.

## Open questions

1. ~~XP sources~~ Closed: decision 3.
2. ~~Level curve~~ Closed: decision 4.
3. ~~Storage and transfer~~ Closed: decision 5.
4. ~~Currency~~ Closed: decision 6 (meta currency; in-match cash is a mode's business, `02-modes.md`).

## Research

- `../notes/17-lobby-and-join-flow.md` (trust model)
