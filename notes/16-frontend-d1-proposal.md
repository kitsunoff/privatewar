# 16 — Frontend: decision material for D1

Status: proposal (research, not a decision). Date: 2026-11-07. Answers the open questions of `design/10-frontend.md` (D1 in `TASKS.md`) and gives the `ui` lane a component list, screen mockups and a task order. When the user decides, the answers move into `design/10-frontend.md` through the orchestrator; until then `design/` wins over this note.

Inputs: `DESIGN.md`, `TASKS.md` (D1, Phase 6–8, "UI grows together with features"), `design/08-lobby.md`, `design/09-hud.md`, `design/10-frontend.md`, `design/visual-prompts/`, [`20-ui-tooling.md`](20-ui-tooling.md), and the code of `ui_kit`, `lobby_ui`, `vote`, `hud`, `playlists`, `teams`. The layout follows generic patterns of the military-shooter genre.

## 0. What we take from the genre, and what we do not

We take **generic genre layout patterns** only. They are common to the whole genre and are not one game's identity:

1. a screen title with a thin rule under it;
2. a tab bar under the title;
3. a left column of cards, one card per menu entry; the selected card expands to show a description;
4. a right column of information cards;
5. a 3D character in the centre;
6. a selection summary block (mode icon, mode name, map name);
7. a player list grouped by team;
8. a bottom bar of button hints;
9. a status line at the top centre.

We do **not** take any specific game's fonts, logo, icons and emblems, names of its features (season pass, currency and so on), its colours, its card artwork, its controller glyphs, or its pixel layout. Our identity comes from `design/10-frontend.md` d.2 (dark panels, one accent) plus the font and palette chosen below.

## 1. Starting point: facts about what exists

| Item | Fact | Where |
| --- | --- | --- |
| Kit v0 | Four vgui classes on derma: `PWPanel` (`DPanel`), `PWButton` (`DButton`), `PWList` (`DScrollPanel` of `PWButton` rows), `PWSettingsForm` (derma `DNumSlider`, `DNumberWang`, `DCheckBoxLabel`, `DComboBox`, `DTextEntry`) | `lua/privatewar/modules/ui_kit/cl_init.lua` |
| Pure kit logic | `PW.UI.WidgetFor`, `PW.UI.BuildForm` (settings groups to sections), `PW.UI.ToWire`; tested in `lua/tests/privatewar/ui_kit.lua` | `ui_kit/shared.lua` |
| Style | `PW.UI.Style`: 6 colours (`bg`, `border`, `accent`, `text`, `textMuted`, `hover`), derma fonts `DermaLarge` / `DermaDefault`, `pad = 8` px; sizes are raw pixels, not scaled | `ui_kit/cl_init.lua` |
| Input | Mouse only; no focus model, no keyboard navigation, no gamepad | — |
| Lobby v0 | One `PWPanel` frame: playlist list, mode list, map list, Game Setup form, toggle column, footer (Close, navmesh line, Start). Data: `pw_lobby_state` (maps, modes with match settings, `canStart`, `canEdit`, `canToggle`, nav) and `pw_playlist_list` (playlists, active, `canPick`) | `lobby_ui/`, `playlists/cl_init.lua` |
| Vote | One row per option ("mode on map", votes, own vote selected), PICK per row for `pw.vote.pick`; data `pw_vote_state`: options (mode, name, map, votes), `mine`, `canPick`; the timer from `pw_phase_end` | `vote/` |
| HUD | One `HUDPaint` over the `hud/` registry; `PW.HUD.X/Y/S` scale from 1920×1080 (`S = min(sx, sy)`); `PW.HUD.Font(id, size, weight)` creates `PW_HUD_<id>` at the scaled size, family hard-coded to `"Roboto"`, recreated on resolution change | `hud/shared.lua`, `hud/cl_init.lua` |
| Players in LOBBY | No player list in any lobby message. Teams are not assigned in `LOBBY`: the NW2 global `pw_teams` is `0` there; teams appear at `PREMATCH → LIVE` | `docs/api/teams.md` |
| Ready flag | Mentioned in `08-lobby.md` d.3 and `00-core.md` d.5 as informational; not implemented | grep |
| Bots count | Match setting `bots.fill` (int, default 12): fill up to N players in total | `modules/bots/shared.lua` |
| Vendoring | Only `binaryheap.lua` (MIT) until D4; Mantle/RNDX (MIT) therefore cannot be vendored now | `CLAUDE.md` |
| Target screen | Steam Deck: 1280×800 (16:10), 7 inch; the game runs as the Windows build under Proton 10 | `TASKS.md` "Dev loop" |

## 2. Open questions of D1: options and recommendations

### Q1. Widget kit, layout, router and focus model

Sketch of the recommended shape:

```text
PW.UI (ui_kit)
  shared, pure, tested            client, thin vgui glue
  ───────────────────────          ─────────────────────────
  Style tokens (names only)        Style values (Color, fonts)
  Layout.Columns(screenW, screenH) PWRoot   (EditablePanel, MakePopup, owns keys)
  Focus.Move(model, cur, dir)      PWTabBar, PWCardList, PWCard, PWInfoCard,
  Input.Action(key, device)        PWSummary, PWPlayerList, PWHintBar, PWPager,
  Router (stack per tab)           PWButton v1, form controls v1, PWOperator
  models of each component         each control: Paint from tokens, no derma skin
```

| Option | What it is | Facts | Cost |
| --- | --- | --- | --- |
| **A. Extend the vgui kit** (recommended) | Keep vgui panels for structure, mouse hit-testing, scrolling and text entry. Every `PW*` control paints itself from tokens (no derma skin). Layout and focus are pure functions over rectangles in design units; vgui only applies the result in `PerformLayout`. | Existing `PWSettingsForm`, `lobby_ui` and `vote` already build on vgui; `DTextEntry` is the only practical text input in GMod; vgui gives `OnCursorEntered`, `OnKeyCodePressed`, `MakePopup`, scissoring and scroll for free | Medium: restyle 4 classes, add about 10 |
| B. Immediate-mode panels | One root panel whose `Paint` draws the whole screen every frame with `draw.*`; own hit-testing, own scroll | Matches the HUD style; trivially testable layout. But text entry, scroll bars, tooltips and IME must be rebuilt or mixed in from vgui anyway; the settings form (6 widgets) would be rewritten | High; no gain for menus |
| C. Adopt a library (Mantle, MIT) | Use Mantle's panels and RNDX renderer | Vendoring beyond `binaryheap.lua` is blocked until D4 (`CLAUDE.md`) | Blocked now |

**Focus and selection model (for keyboard and gamepad):**

1. Two states are kept apart:
   - *focused*: where the cursor of the keyboard or gamepad is; mouse hover moves the focus too, so the screen never shows two highlights;
   - *selected*: the chosen value (the active playlist, the chosen map, the own vote).
2. A screen declares **focus groups**: a tab bar (horizontal), a card list (vertical), a button row (horizontal), a form (vertical). Each group has nodes `{ id, rect, enabled, locked }`.
3. `PW.UI.Focus.Move(model, current, direction)` (pure):
   - inside a group, move along its axis to the next node that is enabled or locked (locked nodes are focusable so the player can read why they are locked; disabled nodes are skipped);
   - at the end of a list: stop (no wrap) in vertical lists, wrap in the tab bar;
   - leaving a group in a direction: pick the group whose nearest node lies in that direction (score = distance along the direction + 2 × sideways offset) and restore that group's last focused node;
   - no candidate: stay.
4. Activate (Enter / A / click) calls the node's action; a locked node shows its reason in the hint bar instead.
5. The router is a stack per tab: `Push(screen)`, `Pop()`, `Replace(screen)`, `SwitchTab(index)`. Back (Esc / B) pops; at the root of a tab it does nothing in `LOBBY` (the lobby is the home screen).
6. Screens are added by modules through a `screens/` kind (`08-lobby.md` d.3). The kind file lives in `lua/privatewar/kinds/` (core lane): the orchestrator adds it.

**Recommendation:** A. Keep vgui, own painting from tokens, pure layout/focus/router logic in `ui_kit/shared.lua` (testable on the server runner), thin vgui glue on the client.

### Q2. Fonts with an open licence

**How GMod loads a custom font** (facts from the wiki pages `surface.CreateFont`, `Structures/FontData`, `resource.AddFile`, read 2026-11-07):

1. The `.ttf` file goes to `resource/fonts/<file>.ttf` inside the addon (the gamemode's Workshop addon mounts it).
2. Clients must have the file: for a Workshop release the server calls `resource.AddWorkshop(<addon id>)`; `resource.AddFile("resource/fonts/<file>.ttf")` adds it to the download list for non-Workshop installs (the dev addon on the Deck). A P2P listen server has no FastDL, so downloads go through the game connection; two to four font files of about 100–200 KB are acceptable.
3. `surface.CreateFont(name, data)`: `data.font` must be the font's "nice" name (the name the OS font viewer shows), not the file name, **except on Linux and macOS clients**, where the wiki says the file name is more reliable. `data.font` is limited to 31 characters. `size` is 4 to 255 px.
4. `extended = true` is required for glyphs outside Latin-1 (Cyrillic). The wiki: it "has no effect on Linux, the value is capped at just 0xFF on the Linux client".
5. Fonts are static: create each one once, outside paint hooks, and only the ones in use (`PW.HUD.Font` already does this and recreates on resolution change).

**Caveats for our platforms:**

1. The Deck runs the **Windows build under Proton**, so Windows rules apply: nice name, `extended` works. To verify on the Deck: Wine's GDI resolves the name of a static non-RIBBI weight (SemiBold, Medium) by its legacy family name (name ID 1, for example `"Fira Sans Condensed SemiBold"`), not by the typographic family (name ID 16). The kit should therefore name each weight file explicitly.
2. A friend on the **native Linux client**: Cyrillic names render as missing glyphs whatever font we pick (`extended` capped at 0xFF); a font lookup by nice name may fail, so the kit keeps a fallback chain (our family, then `"Roboto"`, then derma defaults).
3. Variable fonts: GMod's font loading of variable TTFs is unverified; ship **static** instances only.
4. Player names: the user and friends may have Cyrillic nicknames, so the body font needs Cyrillic.
5. GMA whitelist: `.ttf` in `resource/fonts/` is allowed; where the OFL text goes (`data_static/*.txt` or inside a `.lua` comment) is to verify against the GMA whitelist at T-10.2.

**Candidates** (licence and subsets read from `google/fonts` `ofl/<family>/METADATA.pb`, 2026-11-07; every one is `license: "OFL"`, SIL Open Font License 1.1):

| Family | Role | Cyrillic | Static weights in `google/fonts` | Upstream source |
| --- | --- | --- | --- | --- |
| **Fira Sans Condensed** | Headings, tabs, buttons | yes (+ Greek) | 100–900 (9 static files) | `github.com/googlefonts/FiraGFVersion` (Mozilla Fira) |
| **Fira Sans** | Body, lists | yes | 100–900 (variable entry; static files in upstream) | same |
| Barlow Condensed / Barlow | Headings / body | **no** (latin, latin-ext, vietnamese) | 100–900 static | `github.com/jpt/barlow` |
| Oswald | Headings | yes | variable only in `google/fonts`; static in upstream | `github.com/googlefonts/OswaldFont` |
| Inter | Body | yes (+ Greek) | variable in `google/fonts`; static TTF in upstream releases | `github.com/rsms/inter` |
| Saira Condensed | Headings | **no** | 100–900 static | `github.com/Omnibus-Type/Saira` |
| Rajdhani, Teko | Headings | **no** (latin + devanagari) | 300–700 static | `github.com/itfoundry/rajdhani`, `github.com/googlefonts/teko` |
| Chakra Petch | Headings ("tactical" look) | **no** (latin + thai) | 300–700 static | `github.com/m4rc1e/Chakra-Petch` |
| Roboto Condensed | Headings | yes | variable | `github.com/googlefonts/roboto-classic` |
| JetBrains Mono / IBM Plex Mono | Numbers, timers (optional) | yes | static / static | `github.com/JetBrains/JetBrainsMono`, `github.com/googlefonts/plex` |

OFL 1.1 in short: the fonts may be bundled with software, including free or paid distribution; the font files may not be sold on their own; the licence text must travel with them; a modified font must not use a Reserved Font Name. Shipping the **unmodified** `.ttf` files avoids the renaming question.

| Option | Pair | For | Against |
| --- | --- | --- | --- |
| **A** (recommended) | Fira Sans Condensed (SemiBold, Bold) + Fira Sans (Regular, Medium) | One family, Cyrillic and Greek, static weights, condensed uppercase headings fit the genre without copying anyone | Very common on the web (neutral, not "military") |
| B | Barlow Condensed + Barlow | Already named in `visual-prompts/00-style.md` | No Cyrillic: Cyrillic nicknames show as missing glyphs |
| C | Oswald + Inter | Both Cyrillic; Oswald is narrow and strong | Two families to tune; static files only from upstream; Oswald is overused in GMod addons |

**Recommendation:** A, 4 files: `FiraSansCondensed-SemiBold.ttf`, `FiraSansCondensed-Bold.ttf`, `FiraSans-Regular.ttf`, `FiraSans-Medium.ttf`, plus `OFL.txt`. The style prompt `00-style.md` says "similar to Barlow Condensed"; it would change to Fira Sans Condensed (needs approval, `design/` file).

### Q3. Colour palette as named tokens

Both variants are original. Contrast ratios (WCAG formula) were computed for each text colour against the panel colour, solid and at the given panel opacity over a bright scene (`#9A9A9A`, worst case).

**Variant A "Field green"**: `design/10-frontend.md` d.2 kept as is, extended to a full token set (no change to a decision, only additions).

| Token | Hex | Use | Contrast on panel (solid / over bright scene at 72 %) |
| --- | --- | --- | --- |
| `bg_scrim` | `#050806` at 55 % | Full-screen darkening behind menus | — |
| `bg_panel` | `#0B0F0C` at 72 % (d.2: ~70 %) | Panels, cards | — |
| `bg_raised` | `#141B16` at 85 % | Expanded card, info card header | — |
| `bg_hover` | `#1C2620` | Focused (hovered) row | — |
| `bg_selected` | `#163020` | Selected row (with the accent edge bar) | — |
| `border` | `#1F2A22` | Panel borders, title rule | — |
| `border_strong` | `#2E3D32` | Focused card outline | — |
| `text` | `#E8EDE9` | Primary text | 16.3 / 10.3 |
| `text_muted` | `#8A958D` | Secondary text | 6.2 / **3.9** |
| `text_disabled` | `#545D57` | Disabled, locked labels (always with a lock glyph) | 2.8 / 1.8 |
| `accent` | `#5BE37D` | Focus edge bar, active tab, primary button, key numbers | 11.7 / 7.4 |
| `on_accent` | `#06200F` | Text on accent fills | 10.4 on accent |
| `positive` | `#5BE37D` (= accent) | Victory, ready, gains | 11.7 / 7.4 |
| `negative` | `#FF4D4D` (= enemy) | Defeat, errors | 5.9 / 3.7 |
| `warning` | `#FFB547` | Warning chips (maxplayers) | 11.0 / 7.0 |
| `team_friendly` | `#4FC3F7` | Own team | 9.6 / 6.1 |
| `team_enemy` | `#FF4D4D` | Other team | 5.9 / 3.7 |
| `badge_new` | `#FFB547` | "NEW" badge | 11.0 / 7.0 |

**Variant B "Graphite and hazard yellow"**: warmer neutrals, a yellow accent. Changes the accent of d.2 (needs approval).

| Token | Hex | Contrast (solid / over bright scene at 78 %) |
| --- | --- | --- |
| `bg_scrim` | `#060606` at 55 % | — |
| `bg_panel` | `#111214` at 78 % | — |
| `bg_raised` | `#1A1C20` at 88 % | — |
| `bg_hover` | `#23262B` | — |
| `bg_selected` | `#2B2614` | — |
| `border` | `#2A2D33` | — |
| `border_strong` | `#3A3E46` | — |
| `text` | `#F1EEE8` | 16.2 / 11.4 |
| `text_muted` | `#9C978D` | 6.4 / 4.5 |
| `text_disabled` | `#5C5952` | 2.7 / 1.9 |
| `accent` | `#F2C230` | 11.2 / 7.9 |
| `on_accent` | `#1A1400` | 11.0 on accent |
| `positive` | `#7DDC8B` | 11.1 / 7.9 |
| `negative` | `#FF5A5F` | 6.1 / 4.3 |
| `warning` | `#FF8A3D` | 8.0 / 5.6 |
| `team_friendly` | `#4CC9F0` | 9.7 / 6.9 |
| `team_enemy` | `#FF5A5F` | 6.1 / 4.3 |
| `badge_new` | `#F2C230` | 11.2 / 7.9 |

Findings:

1. In A, `text_muted` drops to 3.9:1 over a bright scene at 72 % panel opacity. Fix inside A without changing d.2 colours: draw `bg_scrim` behind every menu, or raise `bg_panel` to 80 %.
2. In A, `positive` equals `accent`: "selected" and "good" share a colour. Acceptable (green means "go" in both); the selection is also marked by the edge bar.
3. In B, yellow accent and orange warning are close in hue; warnings must always carry an icon.
4. Team colours are relative to the local player (friendly / enemy), as in `09-hud.md`; the lobby list before team assignment uses neutral `text`.

**Recommendation:** Variant A, with `bg_scrim` always on. It keeps decision d.2, and all visual prompts stay valid.

### Q4. The operator scene

Sketch: the centre third of the hub (x 640–1280 in design units) shows the local player's model holding the primary weapon of the selected class, lit by our own lights, over a darkened, blurred background.

| Option | How | Facts | Cost |
| --- | --- | --- | --- |
| **A. `DModelPanel` in the centre** (recommended) | A `PWOperator` panel wraps `DModelPanel` (it owns a `ClientsideModel` and renders it in the panel's `Paint` with `cam.Start3D`). Lighting through `SetAmbientLight` / `SetDirectionalLight`; idle pose by `LookupSequence` of a passive idle; the weapon world model attached with `EF_BONEMERGE` | Independent of the map and of `CalcView` (D2 is open); the same panel serves the gunsmith preview (`08-lobby.md` d.3, T-7.3). Auto-framing maths: `dist = radius / tan(fov / 2) × 1.25`. Attachments on the world model depend on the weapon base (ARC9 draws them itself); to verify at CP-3 | Low: one model and one weapon drawn in a scissor rectangle; nothing networked |
| B. Model in the real world + camera | A `ClientsideModel` placed in the map, a `CalcView` orbit, a `ProjectedTexture` spotlight | The most "alive" look; depends on map geometry (walls), needs the single `CalcView` owner (D2, Phase 9); shadowed projected textures are expensive and share the flashlight limit | High; blocked by D2 |
| C. Static backdrop, no model | A 2D image or a gradient | Cheapest; we have no own art and must not copy; loses the operator that `08-lobby.md` d.3 decided | Lowest; contradicts d.3 |

Background behind A: until D2 lands, the live view of the map with `bg_scrim` and a blur (`pp/blurscreen` material, a few passes); after D2, the blurred orbit over the map from `08-lobby.md` d.3.

**Recommendation:** A. The model shown is the local player's model (`LocalPlayer():GetModel()`, later the `models/` choice from progression), the weapon is the world model of the selected class's primary (later, T-7.3 after CP-3). Before CP-3 the panel shows the player model only.

### Q5. Input: mouse, keyboard, gamepad, button hints

Facts:

1. vgui delivers keys to the focused popup panel through `PANEL:OnKeyCodePressed(code)`; the root panel of the menu (`MakePopup`, keyboard input enabled) receives them.
2. The `KEY` enum includes controller codes: `KEY_XBUTTON_A` 114, `B` 115, `X` 116, `Y` 117, `LEFT_SHOULDER` 118, `RIGHT_SHOULDER` 119, `BACK` 120, `START` 121, d-pad `UP/RIGHT/DOWN/LEFT` 146–149, `LTRIGGER` 154, `RTRIGGER` 155 (wiki `Enums/KEY`). Whether vgui receives them under Proton with Steam Input is **unverified**.
3. GMod has no official controller support. On the Deck, Steam Input applies a layout that turns the controls into keyboard keys and mouse (or into XInput, depending on the chosen template). In practice the Deck's buttons arrive as keys.
4. Esc opens GMod's pause menu. `GM:OnPauseMenuShow()` returning `false` suppresses it, so Esc can mean Back while our menu is open.

Recommended action table (pure, `PW.UI.Input`):

| Action | Keyboard | Gamepad codes | Mouse |
| --- | --- | --- | --- |
| Move focus | arrows, W A S D | d-pad, left stick (`KEY_XSTICK1_*`) | hover |
| Activate | Enter, Space | A | left click |
| Back | Esc, Backspace | B | right click (outside lists) |
| Previous / next tab | Q / E | LB / RB | click the tab |
| Secondary action (screen-defined: Game Setup, Ready) | F | X | button |
| Tertiary action (screen-defined: Pick myself, Kick) | R | Y | button |
| Page up / down in long lists | Page Up / Page Down | LT / RT | wheel |
| Settings | F2 | Start | button |

Button hints (`PWHintBar`): the active screen lists its actions; the hint bar draws them for the **current input device**: the last device used (mouse or keyboard → key caps `[Esc] Back`; a controller code → round badges `(B) Back`). A client setting `pw_ui_hints auto|keyboard|gamepad` forces one, for the Deck user whose buttons arrive as keys. Glyphs are our own: a rectangle with the key name, or a circle with the letter A/B/X/Y; no platform glyph artwork.

**Recommendation:** keyboard navigation is the main path and covers the Deck through Steam Input; controller codes are in the same table at no extra cost; a recommended Steam Input layout (the table above) goes into the player docs (T-10.3). Native gamepad support is verified at the UI checkpoint, not promised.

### Q6. Scaling

Facts:

1. `PW.HUD._Scale(w, h)` returns `sx = w / 1920`, `sy = h / 1080`, `s = min(sx, sy)`; `PW.HUD.X/Y/S` multiply by them.
2. The Deck is 1280×800: `sx = 0.667`, `sy = 0.741`, `s = 0.667`. Stretching menus with `X` and `Y` separately would distort cards; at `s = 0.667`, a 16-unit font becomes 10.7 px, too small on a 7-inch screen.

Rules proposed:

1. Design units are 1920×1080. Sizes (fonts, paddings, card heights) use `S`; positions are **anchored**: the left column to the left edge, the right column to the right edge, the centre fills the rest; vertical blocks anchor to the top (title, tabs, status) and to the bottom (hint bar). On 16:10 the extra height goes to the lists (more cards per page). On 21:9 the extra width goes to the centre (operator).
2. Font ladder in design units: display 64, H1 44, H2 32, body 26, small 22. The minimum is 22 (14.7 px on the Deck).
3. The kit reuses `PW.HUD.S/X/Y` and `PW.HUD.Font` (one implementation; both modules are in the `ui` lane). `PW.HUD.Font` gains a family argument (today `"Roboto"` is hard-coded) and `extended = true`. If the `hud` module is missing, the kit falls back to `min(ScrW() / 1920, ScrH() / 1080)` (global rule 2).
4. Layout maths (`PW.UI.Layout.Columns(w, h)`) is pure and returns rectangles in pixels; tests cover 1920×1080, 1280×800, 2560×1440 and 3440×1440.

**Recommendation:** as above; this is not a user question unless the user wants a UI scale setting (proposed: client setting `pw_ui_scale` 0.8–1.25, default 1).

## 3. Component inventory

States used below: **N** normal, **F** focused (hover and keyboard focus are one state), **S** selected (the chosen value), **P** pressed, **D** disabled (skipped by focus), **L** locked (focusable, lock glyph, reason in the hint bar), **New** badge.

| # | Component | States | Data shown | Source |
| --- | --- | --- | --- | --- |
| 1 | `PWScreenTitle` | N | Screen title (uppercase, display font), thin rule under it in `border` | Router (screen name) |
| 2 | `PWTabBar` | N, F, S (active tab, accent underline), L (feature not available yet), New | Tab labels, Q/E (LB/RB) glyphs at the ends | Router tabs; locked until the feature lane ships the screen |
| 3 | `PWStatusLine` | N, warning | Top centre: phase label, timer, players `3/12` | `pw_phase`, `pw_phase_end` (`PW.Phase`), `player.GetCount()`, `game.MaxPlayers()` |
| 4 | `PWPlayerChip` (later) | N | Top right: own name, level | `LocalPlayer():Nick()`; level from progression (P4) |
| 5 | `PWCardList` | — (container) | A vertical list of `PWCard`; the selected card expands; pager when the list is longer than the column | Screen model |
| 6 | `PWCard` | N, F (edge bar `accent`, `bg_hover`), S (expanded, `bg_raised`), D, L, New | Title; when expanded: description, tags (modes), "fills to N" | Playlists: `PW.PlaylistSummary` (`name`, `summary`, `fill`); Custom row `@custom` |
| 7 | `PWInfoCard` | N, F (if it has an action) | Title + rows of key/value or free text | Screen model (match summary, players) |
| 8 | `PWSummary` | N | Mode icon (own monogram badge), mode name, map name, map thumbnail | `PW.LobbyModel.mode`/`map`, mode `Name`; thumbnail `maps/thumb/<map>.png` if present (to verify), else a placeholder |
| 9 | `PWPlayerList` | — | Sections per team (or one "PARTY" section in `LOBBY`), header with count, "+N bots" row | `player.GetAll()`, `Player:Team()`, `IsBot()`, host marker (`IsListenServerHost()`), `pw_teams`, `bots.fill` |
| 10 | `PWPlayerRow` | N, F (host: actions), D | Name, host marker, team colour edge, ready (later), level (later) | Same |
| 11 | `PWHintBar` | N | Actions of the active screen with key caps or pad badges; a locked node's reason | `PW.UI.Input` + active screen |
| 12 | `PWButton` v1 | N, F, P, D, L; variants primary (accent fill), secondary (outline), danger | Label, optional glyph | Screen model (`canStart`, ...) |
| 13 | `PWPager` | N, D (at the ends) | `19 / 21`, up/down arrows | List model |
| 14 | Form controls v1: `PWToggle`, `PWStepper`, `PWSlider`, `PWEnumSwitch` (`< VALUE >`), `PWMultiSelect`, `PWIdList` | N, F, D (no `canEdit`), changed (dot until applied) | Label, value, description on focus | `PW.UI.BuildForm` over `PW.Settings.GetGroups("match", mode)` |
| 15 | `PWWarningChip` | N | Icon + text | `PW.PlaylistItems.warning`, nav line (`PW.Lobby._NavLine`) |
| 16 | `PWVoteCard` | N, F, S (own vote: accent border + check), D (after the vote ended) | Map thumbnail, map, mode, vote count | `PW.VoteState.options[i]`, `mine` |
| 17 | `PWOperator` | N, empty (model missing) | Player model + weapon | `LocalPlayer():GetModel()`; class weapon later (T-7.3) |
| 18 | `PWBackdrop` | N | Scrim + blur over the live view | — |
| 19 | `PWDialog` | N, F | Title, text, two buttons (confirm / cancel) | Navmesh generation confirm (existing), kick confirm |
| 20 | `PWTimer` (HUD and vote) | N, warning (last 10 s) | `M:SS` | `pw_phase_end - CurTime()` |

## 4. Screen mockups

Grid: one character is 20 design units wide, one line is 40 units tall, so 96 columns × 27 lines is 1920×1080. Left column: x 96–576 (columns 5–28); right column: x 1344–1824 (columns 68–91); hint bar: y 1000–1080. Bracketed numbers `[n]` refer to the data legend under each mockup.

### 4a. Main hub (lobby), PLAY tab

```text
+----------------------------------------------------------------------------------------------+
|    PRIVATE WAR                            [1] LOBBY  -  3/12  -  waiting for host            |
|    ------------                                                                              |
|  [Q]  PLAY      LOADOUT (lock)    PROGRESS (lock)    STORE (lock)  [E]           [2] Player1 |
|  ------------------------------------------------------------------------------------------  |
|    +------------------------+                                     +------------------------+ |
|    |# SHIPMENT 24/7     NEW |  [3]                                | MATCH              [5] | |
|    |  Small map, fast       |                                     |  (TDM) Team Deathmatch | |
|    |  respawns.             |                                     |        on Shipment     | |
|    |  TDM, DOM, KC          |                 [4]                 |  Score limit      75   | |
|    |  fills to 12           |                                     |  Time limit     10:00  | |
|    +------------------------+              .-------.              |  Bots fill        12   | |
|    | FREE FOR ALL           |              | ( o ) |              |  ! Server has 8 slots  | |
|    +------------------------+              |  /|\  |              +------------------------+ |
|    | HARDCORE               |              |  /|=====             +------------------------+ |
|    +------------------------+              |   |   |              | PARTY  3/12        [6] | |
|    | CUSTOM GAME   (gear)   |              |  / \  |              |  (host) Player1        | |
|    +------------------------+              |       |              |         Friend_01      | |
|                                           '-------'               |         Friend_02      | |
|                                        operator + gun             |  + 9 bots              | |
|                                                                   +------------------------+ |
|                                                                                              |
|                                                                    [  START MATCH   ] (host) |
|  [7] [Esc] Back   [Enter] Select   [F] Game setup   [F2] Settings                            |
+----------------------------------------------------------------------------------------------+
```

| # | Element | Data (existing module) |
| --- | --- | --- |
| 1 | Status line | Phase `pw_phase` (`LOBBY`), humans `player.GetCount()` / `game.MaxPlayers()`; "waiting for host" when the local player lacks `pw.match.start` (`canStart` of `pw_lobby_state`) |
| 2 | Player chip | `LocalPlayer():Nick()`; level later (progression, P4) |
| 3 | Playlist cards | `pw_playlist_list` → `PW.PlaylistSummary` (`name`, `summary`, `fill`), selected = `active`; the "CUSTOM GAME" card = `PW.Playlist.CustomRow`; "NEW" = id not in the local seen-set (`data/privatewar/ui_seen.json`); guests see the cards, focus moves, Activate is locked (`canPick`) |
| 4 | Operator | `PWOperator`, local only |
| 5 | Match card | Mode and map from `PW.Lobby._Model` (`mode`, `map`), key settings from `PW.UI.BuildForm` sections (first 3 fields of the mode group plus `bots.fill`), warning from `PW.Playlist._Items(...).warning` (T-8.2 maxplayers) |
| 6 | Party card | `player.GetAll()`: humans listed, host marked (`IsListenServerHost()`), bots collapsed to "+N bots" (current bots, or `bots.fill - humans` before the match) |
| 7 | Hint bar | Actions of the hub; host-only actions are hidden for guests |

Tabs LOADOUT, PROGRESS and STORE are locked until the loadout and progression lanes ship their screens (P4, T-7.4, T-7.5). `design/10-frontend.md` d.1 names them CLASSES, STORE, PROGRESS, SETTINGS: see question 6.

### 4b. Custom game (host lobby)

Opened from the CUSTOM GAME card (Push). The left column lists the lobby actions; host-only entries are locked for guests.

```text
+----------------------------------------------------------------------------------------------+
|    CUSTOM GAME                            [1] LOBBY  -  3/12  -  waiting for host            |
|    ------------                                                                              |
|  [Q]  PLAY      LOADOUT (lock)    PROGRESS (lock)    STORE (lock)  [E]                       |
|  ------------------------------------------------------------------------------------------  |
|    +------------------------+                                     +------------------------+ |
|    |# START MATCH           |  [2]                                | PARTY  3/12   auto [5] | |
|    |  Start Team Deathmatch |                                     |  (host) Player1        | |
|    |  on Shipment.          |                                     |         Friend_01      | |
|    +------------------------+                                     |         Friend_02      | |
|    | MODE & MAP     (lock)  |                                     |  + 9 bots              | |
|    +------------------------+                 [4]                 |  Teams are assigned    | |
|    | GAME SETUP     (lock)  |               operator              |  when the match starts | |
|    +------------------------+                                     +------------------------+ |
|    | ENABLED CONTENT (lock) |                                     +------------------------+ |
|    +------------------------+                                     | NAVMESH            [6] | |
|    | NAVMESH        (lock)  |                                     |  412 areas             | |
|    +------------------------+                                     +------------------------+ |
|                                                                                              |
|    +------------------------+                                                                |
|    | (TDM) TEAM DEATHMATCH  | [3]                                                            |
|    |       Shipment         |                                                                |
|    +------------------------+                                                                |
|  [7] [Esc] Back   [Enter] Select   Locked: only the host can change the match                |
+----------------------------------------------------------------------------------------------+
```

| # | Element | Data |
| --- | --- | --- |
| 1 | Status line | As 4a |
| 2 | Action cards | START MATCH (`canStart`; sends `pw_lobby_start` or `PW.Playlist.SendStart`), MODE & MAP (opens 4c; `canStart`), GAME SETUP (opens the settings form; `canEdit`; guests may open it read-only), ENABLED CONTENT (the toggle list; `canToggle`), NAVMESH (`nav.canGenerate`) |
| 3 | Selection summary | `PW.Lobby._Model`: `mode` (name from the modes registry), `map`; mode icon = own monogram badge |
| 4 | Operator | As 4a |
| 5 | Player list | In `LOBBY`: one PARTY section with "auto" (teams are assigned at the match start, `pw_teams = 0` in `LOBBY`). From `PREMATCH` on (and in a rotation): sections per team from `PW.Teams.GetActive()` and `Player:Team()`, team colour relative to the local player |
| 6 | Navmesh card | `PW.Lobby._NavLine(state.nav)` |
| 7 | Hint bar | A focused locked card shows its reason |

Guests see the same screen; every locked card is focusable and explains itself. The server checks every request again (unchanged).

### 4c. Map picker

Opened from MODE & MAP. The list shows the maps that fit the selected mode; the right side is empty (live view behind the scrim) or shows the map thumbnail when one exists.

```text
+----------------------------------------------------------------------------------------------+
|    MAPS                                    [1] LOBBY  -  3/12                                |
|    -----                                                                                     |
|                                                                                              |
|    MODE  < TEAM DEATHMATCH >   [2]                                                           |
|    +------------------------+-+                                                              |
|    | cs_italy               | |  [3]                                                         |
|    +------------------------+ |                                                              |
|    | de_dust2               | |                                                              |
|    +------------------------+ |                    +----------------------------------+      |
|    |# gm_construct          |#|                    |                                  |      |
|    +------------------------+ |                    |      map thumbnail [5]           |      |
|    | gm_flatgrass           | |                    |      (or placeholder)            |      |
|    +------------------------+ |                    |                                  |      |
|    | ttt_minecraft_b5       | |                    +----------------------------------+      |
|    +------------------------+ |                                                              |
|    | ...                    | |                                                              |
|    +------------------------+-+                                                              |
|           ^    3 / 21    v       [4]                                                         |
|                                                                                              |
|    (TDM) TEAM DEATHMATCH   [6]                                                               |
|          gm_construct                                                                        |
|  [7] [Esc] Back   [Enter] Select   [Q]/[E] Mode   [PgUp]/[PgDn] Page                         |
+----------------------------------------------------------------------------------------------+
```

| # | Element | Data |
| --- | --- | --- |
| 1 | Status line | As 4a |
| 2 | Mode switcher | `PW.Lobby._Model(...).modes`; Q/E (LB/RB) cycle the mode on this screen |
| 3 | Map list | `PW.Lobby._Model(...).maps` (maps that fit the mode via `PW.Lobby._Fits` / `PW.Map.ModeFits`); selected = `map` |
| 4 | Pager | Position of the focused row / total; rows per page from the column height (more rows on 16:10) |
| 5 | Thumbnail | `maps/thumb/<map>.png` if the material exists (to verify in game), else a placeholder with the map name |
| 6 | Summary | Mode + focused map; Activate confirms and pops back to 4b |
| 7 | Hint bar | — |

### 4d. Vote screen

```text
+----------------------------------------------------------------------------------------------+
|    NEXT MATCH                              [1] VOTE  -  0:11                                 |
|    -----------                                                                               |
|                                                                                              |
|                                                                                              |
|    +--------------------------+  +==========================+  +--------------------------+  |
|    |                          |  ||                        ||  |                          |  |
|    |      thumbnail [2]       |  ||       thumbnail        ||  |       thumbnail          |  |
|    |                          |  ||                        ||  |                          |  |
|    +--------------------------+  ++------------------------++  +--------------------------+  |
|    | gm_construct             |  || de_dust2           (v) ||  | cs_italy                 |  |
|    | (KC) Kill Confirmed      |  || (DOM) Domination       ||  | (TDM) Team Deathmatch    |  |
|    |                          |  ||                        ||  |                          |  |
|    | 1 vote                   |  || 2 votes  [3]           ||  | 0 votes                  |  |
|    +--------------------------+  +==========================+  +--------------------------+  |
|                                                                                              |
|                                                                                              |
|      2 of 3 players voted   [4]                                                              |
|                                                                                              |
|                                                                                              |
|  [5] [Esc] Close   [Enter] Vote   [R] Pick myself (host)                                     |
+----------------------------------------------------------------------------------------------+
```

| # | Element | Data |
| --- | --- | --- |
| 1 | Status line | `VOTE`, remaining `pw_phase_end - CurTime()` |
| 2 | Vote cards | `PW.VoteState.options[i]`: `map`, `name` (mode), thumbnail as 4c |
| 3 | Own vote | `mine` (accent border and check); votes count `votes` |
| 4 | Turnout | Sum of `votes` / humans (`PW.Vote.Humans` logic on the client from `player.GetAll()`) |
| 5 | Hint bar | "Pick myself" only with `canPick` (`pw.vote.pick`); it opens 4c in pick mode and sends `pw_vote_pick` |

### 4e. HUD sketch (T-6.2)

The HUD keeps the vanilla health, ammo, crosshair and killfeed (`09-hud.md` d.1). Our match status sits at the top centre.

```text
+----------------------------------------------------------------------------------------------+
|                                 +-----------------------------+                     killfeed |
|                                 |  YOU  52  ====|====  47     |  [1]               (vanilla) |
|                                 |          07:41              |  [2]                         |
|                                 +-----------------------------+                              |
|                                       (A)  (B)  (C)             [3] (Domination element)     |
|                                                                                              |
|                                                                                              |
|                                      MATCH STARTS IN 8          [4] (PREMATCH only)          |
|                                                                                              |
|                                              +                                               |
|                                                                                              |
|                                                                                              |
|  health (vanilla)                                                             ammo (vanilla) |
+----------------------------------------------------------------------------------------------+
```

| # | Element | Data |
| --- | --- | --- |
| 1 | Score bar | `team.GetScore(own team)` first in `team_friendly`, the leading other team in `team_enemy`; FFA: own score vs the leader's frags |
| 2 | Timer | `pw_phase_end - CurTime()` formatted `M:SS` (T-6.2 mandatory test) |
| 3 | Domination points | Drawn by the mode's own `hud/` element (T-6.5), not by this element |
| 4 | Phase message | `PREMATCH` countdown; `POSTMATCH` VICTORY / DEFEAT (T-6.2 mandatory test) |

## 5. Implementation plan for the `ui` lane

Order: kit v1 → hub/lobby rewrite → map picker → vote screen restyle → HUD T-6.2. Each task: tests first (GLuaTest, logic only, in `lua/tests/privatewar/`), drawing goes to the checkpoint. The task ids `U-n` are proposals; the orchestrator maps them onto `TASKS.md` (T-7.1, T-8.1, T-8.2, T-7.7, T-6.2).

| Task | Deliverable | Mandatory test cases (pure unless marked) | Depends on D1 answers |
| --- | --- | --- | --- |
| U-1 Tokens, fonts, scaling (part of T-7.1) | `PW.UI.Style` v1 with every token of the chosen palette; font files in `resource/fonts/` with `resource.AddFile` / `AddWorkshop`; `PW.HUD.Font` with a family argument and `extended = true`; font ladder; fallback chain | Every token named in the spec exists and is a colour; font ladder sizes at 1280×800 are ≥ 14 px; every font name ≤ 31 characters; scale `S` for 1920×1080, 1280×800, 2560×1440, 3440×1440; fallback scale when `PW.HUD` is nil | Q2 (fonts), Q3 (palette), Q6 |
| U-2 Layout, focus, input (part of T-7.1) | `PW.UI.Layout.Columns`, `PW.UI.Focus`, `PW.UI.Input` (pure, shared) | Column rectangles at the four resolutions (anchored left/right, centre fills); focus: down/up in a vertical list, stop at the ends, wrap in the tab bar, skip disabled, stop on locked, cross to the neighbour group by geometry, restore the group's last node, no candidate keeps focus; input: every action has a keyboard key and a controller code, device switches on the last input, `pw_ui_hints` override | Q1, Q5 |
| U-3 Router and root (part of T-7.1) | `PWRoot` popup, tab stacks, Back, `OnPauseMenuShow` suppression while open, `screens/` kind (kind file added by the orchestrator) | Push/Pop/Replace; Back at a tab root in `LOBBY` stays; tab switch keeps each tab's stack; a locked tab cannot be entered; a screen whose build errors is skipped through `PW.Call` and the others work | Q1 |
| U-4 Components v1 | Classes of section 3 (1–3, 5–15, 18–20) with models | Card list: the expanded card is the selected one; pager maths (`page`, `pages`, rows per page from height); player list model: humans listed, bots collapsed to "+N", host first, team sections from `PREMATCH`, one PARTY section in `LOBBY`; tab model: locked and "NEW" (seen-set); form controls: existing T-7.2 cases still pass (one control per setting, widget per type, values through the validated path) | Q3 (states' colours) only for drawing; models are independent |
| CP-UI1 (proposed checkpoint) | User looks at the kit on the Deck (1280×800) and at 1920×1080 | — | — |
| U-5 Hub and custom game rewrite (T-8.1, T-8.2) | `lobby_ui` screens 4a and 4b on the kit; old v0 frame removed | Hub model from playlist state + lobby state + players: guest sees Start / Mode & Map / Game Setup locked with a reason, host sees them enabled; summary = mode name + map; maxplayers warning when `bots.fill` exceeds slots (T-8.2 mandatory); "NEW" badge from the seen-set; existing `lobby_ui.lua` cases still pass | Q4 (operator placeholder until T-7.3), Q6 (tab names) |
| U-6 Map picker (part of T-8.2) | Screen 4c | Map list = maps that fit the mode; selection kept when it still fits, else the first; pager position for the focused row; thumbnail path from the map name; mode cycling with Q/E | — |
| U-7 Vote restyle (part of T-7.7) | Screen 4d on `PWVoteCard`; "Pick myself" opens 4c in pick mode | Card model: one card per option, own vote marked, votes, turnout; timer formatting; `canPick` hides the action; existing `vote.lua` cases still pass | Q3 only for drawing |
| U-8 HUD match status (T-6.2) | `hud/match_status.lua` and phase messages replacing `phase_label.lua` | Timer formatting from `pw_phase_end` (T-6.2 mandatory); victory/defeat decision (T-6.2 mandatory); score order: own team first, leader second, FFA uses frags | Q2, Q3 for drawing only |
| U-9 Operator scene (T-7.3) | `PWOperator` with lights and idle pose; weapon after CP-3 | Framing distance from bounds and FOV; model fallback when the model path is invalid (`models/error.mdl` rejected) | Q4 |

Lane notes:

1. `lua/privatewar/kinds/screens.lua` belongs to the core lane: the orchestrator adds it before U-3.
2. Data that does not exist yet and is not invented here: ready flag, player level, mode short names for icons. Each needs a contract change through the orchestrator (see questions 7 and 8).

## 6. Questions for the user

1. **Widget kit.** Extend the current vgui kit (own painting from tokens, pure layout and focus logic, vgui only for structure, scroll and text entry), or switch to immediate-mode panels? Recommendation: extend the vgui kit.
2. **Fonts.** Fira Sans Condensed (headings) + Fira Sans (body), OFL 1.1, Cyrillic included; or Barlow Condensed + Barlow (named in the visual prompts, no Cyrillic); or Oswald + Inter? Recommendation: Fira, because Cyrillic nicknames must render.
3. **Palette.** Variant A "Field green" (keeps d.2 colours, adds the missing tokens, scrim always on) or Variant B "Graphite and hazard yellow" (changes the d.2 accent)? Recommendation: A.
4. **Operator scene.** `DModelPanel` in the centre with our own lights over the blurred live view (now), or a model in the real map with an orbit camera (after D2), or no model? Recommendation: `DModelPanel` now; revisit after D2.
5. **Input.** Keyboard navigation as the main path (it covers the Deck through Steam Input), controller codes in the same action table, hints that follow the last device with an override setting; native gamepad verified at the checkpoint but not promised. Agree? Recommendation: yes.
6. **Hub tabs.** `10-frontend.md` d.1 lists PLAY, CLASSES, STORE, PROGRESS, SETTINGS. Rename to PLAY / LOADOUT / PROGRESS / STORE, with CLASSES shown as LOADOUT and SETTINGS moved to a hint-bar action (F2 / Start)? Recommendation: yes (needs a change of d.1 wording).
7. **Ready flag and player level in the party card.** Add them now (a new lobby message and a contract change) or leave them until progression (P4)? Recommendation: leave until P4; v1 shows name and host marker only.
8. **Mode icons.** Own monogram badges ("TDM", "DOM", "KC") from an optional `MODE.Short` field (contract change through the orchestrator, fallback: initials of `Name`)? Recommendation: yes.
9. **Checkpoint.** Add a checkpoint CP-UI1 after the kit v1 (U-1 to U-4), before rewriting the screens? Recommendation: yes, one look on the Deck saves rework.

## Sources

- GMod wiki, read 2026-11-07: `https://wiki.facepunch.com/gmod/surface.CreateFont`, `https://wiki.facepunch.com/gmod/Structures/FontData`, `https://wiki.facepunch.com/gmod/resource.AddFile`, `https://wiki.facepunch.com/gmod/Enums/KEY`.
- Font licences and subsets: `https://github.com/google/fonts` `ofl/<family>/METADATA.pb` (fields `license`, `subsets`, `repository_url`), read 2026-11-07.
- GMod wiki: `https://wiki.facepunch.com/gmod/GM:OnPauseMenuShow`.
- Prior research: [`20-ui-tooling.md`](20-ui-tooling.md) (Mantle/RNDX, scaling helper; its DHTML recommendation is superseded).
- Contrast ratios: WCAG 2 relative-luminance formula, computed locally.
