# 10 — Frontend

Status: decided (2026-11-07). One step is pending: vendoring the font files (d.4). D4 (the licence of the gamemode) is decided since 2026-11-07 (GPL-3.0-or-later), so this step is now a follow-up task in `TASKS.md`.

Decision material: `../notes/16-frontend-d1-proposal.md` (options, palette tables, component inventory, mockups, the `U-1`..`U-9` plan). When the note and this file disagree, this file wins.

## Goal and scope

Menus: main menu, lobby screen, loadout, gunsmith, end of match; screen router and widget kit.

## Decisions

- UI is Lua only: a small in-house widget kit. No DHTML, no npm toolchain. UI is verified in game (hot reload + screenshot) (`../DESIGN.md`).

1. **Screen map.**

   ```text
   LOBBY (hub)
   ├── PLAY            playlist list | Custom (mode, map) | Game Setup        [host]
   ├── CLASSES         class list → class editor (slots, Pick X budget)
   │                   └── GUNSMITH  weapon + attachment slots + stats + camo
   ├── STORE           Featured | Weekly | Catalogue → bundle details
   ├── PROGRESS        player level, weapon levels, unlocks
   └── SETTINGS        client settings (HUD scale, keys, audio) | host settings [host]

   IN MATCH
   ├── class picker on death     (choose class for next spawn)
   ├── pause menu                (settings, leave)
   └── scoreboard                (custom result-style table, hold Tab; revision 2026-11-10)

   POSTMATCH
   ├── result + scoreboard
   ├── XP / unlocks summary
   └── VOTE                      (map + mode cards)

   SPECIAL
   ├── singleplayer hint         ("New Game → Max Players 12+")
   └── navmesh generation dialog
   ```

   - Modules add screens through the `screens/` kind (`08-lobby.md` decision 3).
   - Wording changed by d.8 (2026-11-07): the hub tabs are PLAY / LOADOUT / PROGRESS / STORE; CLASSES is called LOADOUT, and SETTINGS is a hint-bar action (F2 / Start), not a tab.

2. **Visual style: dark, clean, one green accent.**
   - Semi-transparent near-black panels with background blur over a blurred game scene; large uppercase condensed headings, plain sans body; flat buttons; monochrome line icons; no heavy gradients.
   - Colour tokens: `bg #0B0F0C` (~70 % opacity), `border #1F2A22`, `accent #5BE37D`, `text #E8EDE9`, `text_muted #8A958D`, `enemy #FF4D4D`, `friendly #4FC3F7`, `warning #FFB547`.
   - Original look "in the spirit of modern military shooters", without any real game's logos, names or recognisable assets.
   - Image-generator prompts for every screen: `visual-prompts/` (`00-style.md` is the shared style block).

3. **Widget kit: extend the vgui kit** (decided with the user on 2026-11-07).
   - The kit keeps vgui panels for structure, mouse hit-testing, scrolling and text entry only.
   - Every `PW*` control paints itself from tokens (no derma skin).
   - Layout, focus and routing are pure functions over rectangles in design units (`PW.UI.Layout`, `PW.UI.Focus`, `PW.UI.Input`, the router), in `sh_`-style shared files so the server-only test runner covers them; vgui only applies the result in `PerformLayout`.
   - Immediate-mode panels and vendored libraries (Mantle, RNDX) are not used.
   - Focus model: *focused* (the keyboard or controller cursor; mouse hover moves it too, so there is one highlight) is separate from *selected* (the chosen value). Locked nodes are focusable and show their reason in the hint bar; disabled nodes are skipped. The router is a stack per tab (`Push`, `Pop`, `Replace`, `SwitchTab`); screens are added through the `screens/` kind (`08-lobby.md` d.3).
4. **Fonts: Fira Sans Condensed (headings) + Fira Sans (body)** (decided with the user on 2026-11-07; pending step blocked by D4).
   - Both are OFL 1.1 and cover Cyrillic, so Cyrillic nicknames render. Planned static files: `FiraSansCondensed-SemiBold`, `FiraSansCondensed-Bold`, `FiraSans-Regular`, `FiraSans-Medium`, plus the OFL text. Static instances only; each weight is named explicitly.
   - **The font files are not vendored until D4 is decided** (`../CLAUDE.md`, "Code you must not copy"). Until then the kit uses built-in GMod fonts through one family indirection: font families live in `PW.UI.Style`, and every font is created from a family name there. Switching to Fira later is a one-place change (the family names plus `resource.AddFile` / `AddWorkshop` of the files). The fallback chain is: our family, then `"Roboto"`, then derma defaults.
   - Fonts are created once outside paint hooks; `extended = true` for Cyrillic. The font ladder (design units): display 64, H1 44, H2 32, body 26, small 22.
   - The "similar to Barlow Condensed" line of `visual-prompts/00-style.md` is to be updated when the font files land.
5. **Palette: Variant A "Field green"** (decided with the user on 2026-11-07). It keeps the colours of d.2 and adds the missing tokens. `bg_scrim` is always drawn behind menus (it keeps `text_muted` readable over a bright scene).

   | Token | Hex | Use |
   | --- | --- | --- |
   | `bg_scrim` | `#050806` at 55 % | Full-screen darkening behind menus |
   | `bg_panel` | `#0B0F0C` at 72 % | Panels, cards |
   | `bg_raised` | `#141B16` at 85 % | Expanded card, info card header |
   | `bg_hover` | `#1C2620` | Focused (hovered) row |
   | `bg_selected` | `#163020` | Selected row (with the accent edge bar) |
   | `border` | `#1F2A22` | Panel borders, title rule |
   | `border_strong` | `#2E3D32` | Focused card outline |
   | `text` | `#E8EDE9` | Primary text |
   | `text_muted` | `#8A958D` | Secondary text |
   | `text_disabled` | `#545D57` | Disabled and locked labels (always with a lock glyph) |
   | `accent` | `#5BE37D` | Focus edge bar, active tab, primary button, key numbers |
   | `on_accent` | `#06200F` | Text on accent fills |
   | `positive` | `#5BE37D` (= accent) | Victory, ready, gains |
   | `negative` | `#FF4D4D` (= enemy) | Defeat, errors |
   | `warning` | `#FFB547` | Warning chips (always with an icon) |
   | `team_friendly` | `#4FC3F7` | Own team (relative to the local player) |
   | `team_enemy` | `#FF4D4D` | Other team (relative to the local player) |
   | `badge_new` | `#FFB547` | "NEW" badge |

   - The lobby list before team assignment (`pw_teams = 0` in `LOBBY`) uses neutral `text`.
6. **Operator scene: `DModelPanel` in the centre** (decided with the user on 2026-11-07).
   - A `PWOperator` panel wraps a `DModelPanel` with our own lights, over a blurred live view of the map (with `bg_scrim`). It shows the local player's model; the weapon of the selected class's primary is added after CP-3 (T-7.3). The same panel serves the gunsmith preview.
   - A scene in the real map with an orbit camera is revisited after D2 (`11-camera.md`); it is not decided here.
7. **Input: keyboard navigation is the main path** (decided with the user on 2026-11-07).
   - Controller codes sit in the same action table (`PW.UI.Input`); on the Steam Deck, Steam Input turns the buttons into keys.
   - Button hints (`PWHintBar`) follow the last used device; a client setting `pw_ui_hints auto|keyboard|gamepad` overrides it. Hint glyphs are our own (key caps, round letter badges).
   - Esc means Back while our menu is open (`GM:OnPauseMenuShow` returns `false`).
   - Native gamepad is checked at the UI checkpoint, not promised.
8. **Hub tabs: PLAY / LOADOUT / PROGRESS / STORE** (decided with the user on 2026-11-07). This changes the wording of d.1: CLASSES is renamed LOADOUT, and SETTINGS leaves the tab bar and becomes a hint-bar action (F2 / Start). The rest of the screen map in d.1 stands. Tabs whose screens are not shipped yet are shown locked.
9. **Party card v1** (decided with the user on 2026-11-07): the ready flag and the player level are deferred to P4 (progression). Version 1 shows the name and a host marker only. Bots are collapsed to a "+N bots" row.
10. **Mode icons: own monogram badges** (decided with the user on 2026-11-07). The text comes from an optional `MODE.Short` field (for example "TDM", "DOM", "KC", `../docs/api/modes.md`); the fallback is the initials of `Name`. No icon artwork is taken from elsewhere.
11. **Checkpoint CP-UI1** (decided with the user on 2026-11-07): after kit v1 (`U-1`..`U-4` in `../TASKS.md`) and before the screens are rewritten, the user looks at the kit on the Deck and at 1920×1080.
12. **Rule: references give layout patterns only** (decided with the user on 2026-11-07). From the reference screenshots in `ui/` (commercial shooters) we take generic genre layout patterns only: title with a rule, tab bar, left card column, right information column, centre operator, selection summary, grouped player list, bottom hint bar. We never take a reference game's look, names, icons, fonts or exact colours.
13. **Scaling** (rules from note 16 §2 Q6, adopted with the decisions above). Design units are 1920×1080; sizes use `PW.HUD.S` (`min(sx, sy)`), positions are anchored (left column to the left edge, right column to the right edge, the centre fills the rest; title, tabs and status at the top, hint bar at the bottom). The kit reuses `PW.HUD.S/X/Y/Font`; without the `hud` module it falls back to `min(ScrW() / 1920, ScrH() / 1080)`.
14. **In-match scoreboard revision (user-approved 2026-11-10).** Replaces the vanilla Tab entry of d.1 with a held, input-transparent overlay using the same table component as POSTMATCH. Tab remains the default `+showscores` binding; remapping and Steam Input retain that path, with native controller View supported too. Use the existing widget kit, tokens and scale, no new dependencies/assets and no per-frame data gathering. The lifecycle, public-data allowlist and performance limits are specified in `09-hud.md`, revision 2026-11-10; all other screen-map decisions stand.

## Interfaces

TBD.

## Performance budget

TBD.

## Security

TBD.

## Open questions

None. The four questions of the earlier draft (widget kit, fonts, operator scene, input) are closed by d.3, d.4, d.6 and d.7. Pending steps: the font files wait for D4 (d.4); the real-map operator scene waits for D2 (d.6); native gamepad is checked at CP-UI1 (d.7).

## Research

- `../notes/16-frontend-d1-proposal.md` (D1 decision material: options, tokens, component inventory, mockups, plan)
- `../notes/20-ui-tooling.md` (its DHTML recommendation is superseded by the Lua-only decision)
