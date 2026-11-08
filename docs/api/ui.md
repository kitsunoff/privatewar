# UI modules API: widget kit, HUD, lobby screen and vote screen

Status: added after T-1.19 (2026-11-06). Both are modules, not core: `lua/privatewar/modules/ui_kit/`
(`shared.lua`, `cl_init.lua`) and `lua/privatewar/modules/lobby_ui/` (`shared.lua`, `init.lua`, `cl_init.lua`).
Types: `lua/privatewar/types/ui.lua`, `lua/privatewar/types/lobby.lua`. Source decisions: `design/10-frontend.md`
d.2, `design/08-lobby.md` d.3, `design/00-core.md` d.5, d.7, `design/01-extensibility.md` d.11, d.17.

Kit v1 (style tokens, layout, focus, input, router; U-1 to U-3) was added on 2026-11-07: see "Kit v1". The component set
(U-4) and the dev showcase were added later the same day: see "Components (U-4)".

Extended on 2026-11-07 after T-6.1 (the `hud` kind and module), T-2.6 (the playlist part of the lobby), T-2.12 (the navmesh
part of the lobby) and T-2.13 (the vote screen): see "HUD (`hud`)", "Lobby screen" and "Vote screen (`vote`)". The code
wins over any description here.

Extended on 2026-11-07 after U-5 (the hub and the custom game screen replace the old single-screen lobby) and U-9 (the
operator model): see "Lobby screen" (the client and "Screens (U-5)") and "Operator (U-9)".

Extended after U-6 (the map picker and `SCREEN.OwnsTabKeys`), U-7 (the vote overlay and `PWVoteCard`), T-8.3 (entry
hints) and T-8.4 (the HUD element `spectating`): see "Map picker (U-6)", "Entry hints (T-8.3)", "Vote screen (`vote`)" and
"Built-in element `spectating`".

Extended after T-4.5 (the HUD element `equipment`) and T-4.7 (the LOADOUT tab screen `loadout_classes`): see "Built-in
element `equipment`" and "Screen `loadout_classes` (T-4.7)".

Extended after T-11.9 (operators): the OPERATOR button of `loadout_classes`, the screen `loadout_operator` and
`PWOperator:ShowLocal()`, see `operators.md` "UI".

Extended after T-7.5 (store and progress), T-7.4 (class, editor and gunsmith screens) and T-7.7 (postmatch summary): see
"Store and progress (T-7.5)", "Classes, editor and gunsmith screens (T-4.7, T-7.4)" and "Postmatch summary (T-7.7)".

The UI is Lua only, built on derma primitives. Styling (fonts, colour tokens, input) was decided as D1 (2026-11-07):
see "Kit v1" below.

## Availability

- `PW.UI` exists only when the `ui_kit` module is loaded, `PW.Lobby` only when `lobby_ui` is loaded; otherwise they
  are `nil`. `PW.Lobby.Open` prints `[PW] lobby: the ui_kit module is missing or disabled` and does nothing without `PW.UI`.
- The lobby screen reads `PW.UI` at runtime; `ui_kit` does not depend on `lobby_ui`. The lobby requires `ui_kit` to be
  enabled: with `ui_kit` missing or disabled the screen does not open (`[PW] lobby: the ui_kit module is missing or
  disabled`).

## Widget kit (`ui_kit`)

### Pure functions (shared)

| Function | Contract |
| --- | --- |
| `PW.UI.WidgetFor(def) -> PW.UIWidget` | The widget that edits a setting definition (rule below) |
| `PW.UI.BuildForm(groups, titles?) -> PW.UIFormSection[]` | Settings groups (`PW.Settings.GetGroups`, `core.md` "Settings") to form sections, one section per group in order, one control per field in the group's order. `titles` maps an owner id to a section heading; default: the owner id |
| `PW.UI.ToWire(control, value) -> string` | The text form of a value for `pw_settings_match` / `pw_settings_server` (`PW.Settings.Format`) |

Widget per setting type:

| Type | Condition | Widget |
| --- | --- | --- |
| `int`, `float` | both `min` and `max` set | `slider` |
| `int`, `float` | otherwise | `number` |
| `bool` | — | `checkbox` |
| `enum` | — | `combo` |
| `set` | with `options` | `multiselect` |
| `set` | without `options` | `idlist` (comma-separated ids) |

A control (`PW.UIFormControl`) carries `id` (full setting id), `def`, `widget`, `label`, `value`; for `int` and
`float` also `min`, `max` and `decimals` (`0` for `int`, `2` for `float`); for `enum` and `set` with options a copy
of `options`. A section (`PW.UIFormSection`) carries `owner`, `ownerKind` (`"modes"` or `"modules"`), `title` and
`controls`.

### Widgets (client)

vgui classes, registered by `ui_kit/cl_init.lua`:

| Class | Base | Contract |
| --- | --- | --- |
| `PWPanel` | `DPanel` | Box with background and border; `SetTitle(text)` adds or updates a title docked on top |
| `PWButton` | `DButton` | Flat button. `SetPrimary(bool)` and `SetSelected(bool)` paint it in the accent colour |
| `PWList` | `DScrollPanel` | `SetItems(items, selected?)`: one selectable row (`PWButton`) per `{ id, label }`; a click calls `OnSelect(id)` |
| `PWSettingsForm` | `DScrollPanel` | `SetSections(sections, editable)`: a heading per section and one widget per control; with `editable = false` the widgets are disabled. `OnChange(control, value)` is called once a control has stayed unchanged for 0.3 s (`idlist` reports on Enter). No sections: the text "No settings for this mode." |

### Style

`PW.UI.Style` (`PW.UIStyle`) is the single place for colours and fonts. Kit widgets read it at paint time, so
restyling is one table. Since U-1 it holds the colour tokens of "Kit v1" and the old v0 names as aliases (`bg`,
`hover`, `textMuted`, `fontTitle`, `fontBody`, `pad`, plus `border`, `accent`, `text`).

## Kit v1

Decisions: `design/10-frontend.md` d.3 to d.13; option analysis and token tables: `notes/16-frontend-d1-proposal.md`.
Code: `lua/privatewar/modules/ui_kit/` (`sh_style.lua`, `sh_layout.lua`, `sh_focus.lua`, `sh_input.lua`, `sh_router.lua`
shared and pure; `cl_init.lua`, `cl_root.lua` client glue). Types: `lua/privatewar/types/ui.lua`, `ui_focus.lua`,
`ui_router.lua`, `ui_components.lua`. The component set is U-4, see "Components (U-4)"; the real screens are not built
yet (`TASKS.md` "UI rework", U-5 to U-9).

### Style tokens and fonts (U-1)

Shared (`sh_style.lua`, loaded by `shared.lua`), so the server-side test runner covers it.

- Tokens of the palette "Field green", as cached `Color` objects in `PW.UI.Style`: `bg_scrim` (alpha 0.55), `bg_panel`
  (0.72), `bg_raised` (0.85), `bg_hover`, `bg_selected`, `border`, `border_strong`, `text`, `text_muted`,
  `text_disabled`, `accent`, `on_accent`, `positive`, `negative`, `warning`, `team_friendly`, `team_enemy`,
  `badge_new`. Aliases of the v0 kit: `bg` = `bg_panel`, `hover` = `bg_hover`, `textMuted` = `text_muted`;
  `fontTitle` is the font name of the `h2` step, `fontBody` of `body`; `pad` is 8.
- The table is filled in place, so widgets holding a reference see a reload.
- `PW.UI.DesignWidth`, `DesignHeight` (1920, 1080), `PW.UI.MinFontSize` (22 design units, 14.7 px at 1280x800).
- `PW.UI.FontFamilies` (`heading` and `body`, both `"Roboto"` until D4; the only place a family name is written) and
  `PW.UI.FontSteps`, the ladder in design units: `title` 64 (weight 700), `h1` 44 (700), `h2` 32 (700), `body` 26
  (500), `small` 22 (500), `hint` 22 (400).

| Function | Contract |
| --- | --- |
| `PW.UI.FontName(id) -> string` | The engine font name of a step: `"PW_UI_<id>"` |
| `PW.UI.ScaleFor(width, height) -> number` | The uniform scale, the smaller axis over 1920x1080 (`PW.HUD._Scale` when the `hud` module is loaded, so there is one implementation) |
| `PW.UI.FontPixels(design, scale) -> integer` | Design size to pixels, clamped to 4..255 (engine limit) |
| `PW.UI.FontData(step, scale)` | `surface.CreateFont` data of one step (`extended = true` for Cyrillic, antialiased) |
| `PW.UI.FontLadder(width, height)` | The data of the whole ladder, in the order of `FontSteps` |

Client (`cl_init.lua`): `PW.UI.RefreshFonts() -> boolean` (creates the ladder fonts again when `ScrW()` or `ScrH()`
changed; also on `OnScreenSizeChanged`), `PW.UI.S(value)` (design units to pixels at the current resolution,
`PW.HUD.S` when present) and `PW.UI.Font(id)` (the font name of a step, creating the ladder first when needed).

### Layout (U-2)

`PW.UI.Layout.Columns(w, h, spec, S?) -> PW.UIColumns` (pure): rectangles in pixels for a screen of `w` x `h`. `spec`
(`PW.UIColumnsSpec`, all in design units): `margin` (outer horizontal), `left` and `right` (column widths; a missing
one means no such column), `gap`, `top` and `bottom` (height reserved for the title or tabs and for the hint bar). The
result has `centre` (always), `left` and `right` (when asked), each `{ x, y, w, h }`. `S` maps design units to pixels;
the default is the uniform `min(w / 1920, h / 1080)`, rounded.

### Focus (U-2)

`PW.UI.Focus` (pure, no vgui): a graph over plain node data. A node is `{ id, group, rect, disabled?, locked? }`; a group
is `{ axis = "vertical"|"horizontal" (default vertical), wrap? }` (wrap is for the tab bar).

| Function | Contract |
| --- | --- |
| `PW.UI.Focus.New(nodes, groups?) -> PW.UIFocusModel` | Builds the model (`nodes`, `byId`, `groups`, `last`) |
| `PW.UI.Focus.Set(model, id)` | Records `id` as the last focused node of its group |
| `PW.UI.Focus.Move(model, current, dir) -> id` | `dir` is `"up"`, `"down"`, `"left"` or `"right"`. Inside a group along its axis (stops at the ends, wraps when `wrap`); otherwise across groups by geometry (the sideways offset counts double) restoring the last node of the target group. Disabled nodes are skipped; a locked node is focusable. Returns `current` when there is no candidate |
| `PW.UI.Focus.Activatable(model, id) -> boolean` | The node exists, is not disabled and not locked |
| `PW.UI.Focus.Apply(model, current, action) -> id, event` | A direction action gives `"move"`; `"accept"` gives `"accept"` or `"locked"`; any other action name is returned as the event |

### Input (U-2)

`PW.UI.Input` (pure): one table of actions, keyboard keys and controller codes side by side. The keyboard is the main
path (the Deck reaches it through Steam Input); native gamepad is verified at the checkpoint.

| Action | Keyboard | Controller |
| --- | --- | --- |
| `up`, `down`, `left`, `right` | arrows, W A S D | D-pad, left stick |
| `accept` | Enter, Space | A |
| `back` | Esc, Backspace | B |
| `tab_prev`, `tab_next` | Q, E | LB, RB |
| `secondary`, `tertiary` | F, R | X, Y |
| `page_up`, `page_down` | PgUp, PgDn | LT, RT |
| `settings` | F2 | Start |

| Function | Contract |
| --- | --- |
| `PW.UI.Input.Actions` | The table `action -> { keyboard, controller, cap, pad }` (key codes and the two hint labels) |
| `PW.UI.Input.New() -> state` | `{ device = "keyboard" }` |
| `PW.UI.Input.ActionOf(code) -> string?` | The action of a key or controller code, or `nil` |
| `PW.UI.Input.Press(state, code) -> string?` | Records the device of the press and returns the action; `nil` for an unbound code (device unchanged) |
| `PW.UI.Input.NoteMouse(state)` | Records that the mouse was used |
| `PW.UI.Input.Device(state)` | `"keyboard"`, `"mouse"` or `"controller"` |
| `PW.UI.Input.Hint(state, action, override?) -> { device, label }` | The key cap or pad badge label; `override` is `"auto"` (follow the last device, default), `"keyboard"` or `"gamepad"` |

Client setting `pw_ui_kit_hints` (module `ui_kit`, setting `hints`; enum `auto`, `keyboard`, `gamepad`; default `auto`):
forces the hint device. The ConVar is named after the module, not `pw_ui_hints`.

### Gamepad buttons in a match

`PW.UI.Gamepad` (pure, `ui_kit/sh_gamepad.lua`; glue `cl_gamepad.lua`; types `types/ui_gamepad.lua`): d-pad buttons for
killstreaks and equipment. The design names no pad buttons (`design/10-frontend.md` d.7); the d-pad is a
recommendation, because the GMod controller defaults (`cfg/360controller.cfg`) bind it to sandbox tools only, while
triggers, face buttons and bumpers are fire, aim, jump, reload, use, flashlight and weapon switch.

| Button | Action | Console command | HUD glyph |
| --- | --- | --- | --- |
| D-pad up | `streak` (activate the selected streak) | `pw_streak` | `D-UP` |
| D-pad right | `streak_next` (select the next streak) | `pw_streak_next` | `D-RIGHT` |
| D-pad left | `tactical` | `pw_tactical` | `D-LEFT` |
| D-pad down | `lethal` | `pw_lethal` | `D-DOWN` |

| Function | Contract |
| --- | --- |
| `PW.UI.Gamepad.Action(code, facts) -> action?` | Facts: `phase`, `rootOpen`, `enabled`. An action only in `LIVE`, with no `PWRoot` open and the setting on |
| `PW.UI.Gamepad.Command(action) -> string?` | The console command of the action (owned by the streaks and equipment modules) |
| `PW.UI.Gamepad.Glyph(action, hints, enabled) -> string?` | The HUD glyph when `hints` is `"gamepad"` and the buttons are on; `nil` means the keyboard key |
| `PW.UI.Gamepad.HudGlyph(action) -> string?` | Client. `Glyph` for the current ConVars; the streak and equipment HUD lines use it |

The glue (`PlayerButtonDown`, local player, first prediction) runs the command with `RunConsoleCommand`; the module
then checks the inventory and the server checks the rest. While a button acts, its engine bind is swallowed
(`PlayerBindPress`). Client setting `pw_ui_kit_gamepad` (module `ui_kit`, setting `gamepad`, bool, default on, shown on
the Personal settings screen) turns the buttons and their HUD glyphs off. Engine input is not covered by the tests
(the local manual checklist (not published), section 36).

### Kind `screens` and `SCREEN` (U-3)

Kind `screens` (`lua/privatewar/kinds/screens.lua`): folder `screens/`, class table `SCREEN`, one file per screen in
`lua/privatewar/screens/` (the folder is empty in the game; the only screen is the dev showcase, see "Dev showcase"). `Subscribe = "never"`
(`01-extensibility.md` d.18): the router calls `Build` through `PW.Call`, so an error disables the screen only. The
enable ConVar is `pw_screen_<id>_enabled`. `Required = { Build = "function", Tab = "string" }`.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `Tab` | string | yes | The tab the screen belongs to: a hub tab (`"play"`, `"loadout"`, `"progress"`, `"store"`) or an in-match one (`"match"`, `"class"`, T-7.6) |
| `Build` | `function(self, ctx) -> view` | yes | Builds the screen. A `nil` result or an error makes the router skip the screen. `ctx` (client): `parent` (the content panel), `root` (the `PWRoot`), `router` (the model) and `SetFocus(model, id)` (the screen gives the focus model and the initial focus id to the root) |
| `Root` | boolean | no | The screen is the root of its tab. Among the roots of a tab the lowest `Order` wins, ties by id |
| `Order` | number | no | Among root candidates; default `100` |
| `Title` | string | no | Display title (shown by the root's `PWScreenTitle`; the tab label when absent) |
| `Hints` | `PW.UIHintEntry[]` | no | Hint bar entries (`{ action, label }`) while the screen is on top; default `Select` and `Back` (U-4) |
| `OwnsTabKeys` | boolean | no | The screen uses Q and E itself (U-6). While it is on top the router does not cycle the tabs (`Act` returns `nil` for `tab_next` and `tab_prev`), and the keys reach the view's `OnAction(action)` as `tab_prev` and `tab_next`. Default `false` |

The returned view may be a table with `OnAccept(id)`; the root calls it when `accept` activates the focused node. A view
(panel or table) may also have `OnAction(action)`: the root calls it for the actions the screen owns (`secondary`,
`tertiary`, `settings`, ...) after the focused panel declined them (U-4).

### Router (U-3)

`PW.UI.Router` (shared, pure: plain screen tables, no vgui). One stack of screens per tab, the root first. The tabs are
fixed (design d.8): `PW.UI.Router.TabOrder = { "play", "loadout", "progress", "store" }` with the labels `PLAY`,
`LOADOUT`, `PROGRESS`, `STORE` (`TabLabels`, which also has `MATCH` and `CLASS` for the in-match roots, T-7.6). SETTINGS is a hint-bar action, not a tab. A tab without a root screen is
locked (reason `"soon"`). The model is `PW.UIRouterModel`: `tabs`, `tabById`, `stacks`, `screens` (by `ClassName`) and
`active`; the first unlocked tab is active.

| Function | Contract |
| --- | --- |
| `New(screens, tabs?) -> model` | The model from the enabled list of the `screens` registry. `tabs` is an ordered list of tab ids and replaces `TabOrder` (T-7.6: the pause menu uses `{ "match", "loadout" }`, the death picker `{ "class" }`); a tab id without a root screen is locked with the reason `"soon"` |
| `Top(model) -> screen?` | The top screen of the active tab; `nil` when that tab is locked |
| `Depth(model) -> integer` | The depth of the active tab's stack |
| `Push(model, screen)` | Pushes a screen (a table or a `ClassName`) on the active tab; `false` when it is unknown or the tab is empty |
| `Pop(model)` | Pops the active tab's stack; the root is never popped; `false` when nothing was popped |
| `Replace(model, screen)` | Replaces the top screen of the active tab |
| `SwitchTab(model, id)` | `false` for an unknown or locked tab; every stack is kept |
| `Cycle(model, delta)` | The next (`1`) or previous (`-1`) unlocked tab, wrapping; `false` when there is no other |
| `SetLocked(model, id, locked, reason?)` | Locks or unlocks a tab; locking the active tab moves to the first unlocked one |
| `Back(model, phase) -> "pop"\|"stay"\|"close"` | Pops above the root; at a root it stays in `LOBBY` and asks to close in any other phase |
| `Act(model, action, phase) -> "tab"\|"pop"\|"stay"\|"close"\|nil` | `tab_next` and `tab_prev` cycle (`"tab"` or `"stay"`), unless the top screen has `OwnsTabKeys` (then `nil`); `back` is `Back`; any other action is not handled (`nil`) |
| `Build(model, ctx) -> view, screen` | Builds the top screen through `PW.Call`. A screen whose `Build` fails is popped (a root locks its tab with reason `"error"`) and the next one is tried; `nil` when nothing builds |

### Root panel `PWRoot` and `pw_ui_root` (U-3)

Client (`cl_root.lua`, thin glue). `PWRoot` (base `EditablePanel`) is the full-screen popup that hosts the router. It
paints the scrim (`bg_scrim`) and a plain tab strip (the tab bar of U-4 draws the active tab in `text`, an open one in
`text_muted`, a locked one in `text_disabled`), turns key presses into input actions, gives them to the router first and
to the focus graph second, and rebuilds the top screen after a tab switch or a pop. A mouse click on an open tab
switches to it; a click on a locked tab does nothing. A `close` result removes the panel. Since U-4 the strip is the
real frame: `PWRoot` holds `PWScreenTitle`, `PWStatusLine`, `PWTabBar` and `PWHintBar` (see "Components (U-4)"), and
`PW.UI.CurrentRoot() -> PWRoot?` returns the open root. The seen-set (the NEW marks of tabs) is stored in
`data/privatewar/ui_seen.json` (`PW.UI.SeenSet()`, `PW.UI.SaveSeen()`).

| Function or command | Contract |
| --- | --- |
| `PW.UI.OpenRoot(opts?) -> Panel` | Opens the root (one at a time) and builds the first screen. `opts` is `PW.UIRootOptions`, see "In-match menus (T-7.6)". An open root of the same `id` is returned; an open root of another `id` is closed first and replaced |
| `PW.UI.CloseRoot()` | Closes it (calls the root's `onClose`) |
| `PW.UI.RootOpen() -> boolean` | Whether it is open |
| `pw_ui_root` | Client command: opens the root, or closes it when it is open (router development) |

- While the root is open the engine pause menu is suppressed: the Escape hook (`OnPauseMenuShow`, in `cl_match.lua`)
  runs `Back` and returns `false`; a second Back in the same frame is ignored (Escape can reach both the panel and the
  hook). Shift+Escape is the exception: the hook leaves the GMod menu alone and the root ignores that key press.
- Back (Esc, Backspace, gamepad B) at the root screen of the lobby hub opens the leave dialog, see "Leaving from the
  lobby".
- With no screen registered every tab is locked and the root is empty; in `LOBBY` Back stays, so only `pw_ui_root`
  closes it.

## In-match menus (T-7.6)

Decisions: `design/10-frontend.md` d.1 and d.7, `design/05-loadout.md` d.12, `design/00-core.md` "abort and return to
lobby". Code: `ui_kit/sh_match.lua` (pure, shared, so the server-side test runner covers it), `ui_kit/cl_match.lua`
(client glue: engine hooks, the death watcher, commands), the screens `screens/match_pause.lua` and
`screens/match_classes.lua`, types `types/ui_match.lua`. The client decides nothing: the server repairs and checks every class
pick and every abort again.

### Root options

`PW.UI.OpenRoot(opts)` takes `PW.UIRootOptions`:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string? | The kind of root; default `"hub"`. The pause menu is `"pause"`, the death picker `"class"` |
| `tabs` | `string[]?` | The router tab set (`Router.New(screens, tabs)`); default the hub tabs |
| `compact` | boolean? | No backdrop blur, title, status line or tab bar. The content is a 640-unit panel at the right edge, 320 units from the top (below the killfeed), over a plain scrim |
| `onClose` | `fun()?` | Called once when the root is removed |

Only one root exists. Opening a root of the same `id` returns the open one; opening another `id` removes the open root
first (so the lobby replaces a pause menu left open, and the pause menu replaces the death picker). `PWRoot.rootId` and
`PWRoot.compact` hold the options. `PW.UI.CurrentRoot()` returns the open root.

### Screen `match_pause`

`Tab = "match"`, `Root = true`, `Title = "Match menu"`. Left column: one `PWButton` per item of
`PW.UI.Match.PauseItems(facts)`; an item the player may not use is locked with its reason. Centre: a `PWInfoCard` with the
map and the current class name. Escape on it resumes (a root outside `LOBBY` closes on Back).

| Item | Action | Locked when |
| --- | --- | --- |
| `RESUME` | Closes the menu | never |
| `CHANGE CLASS` | Pushes `match_classes` on the MATCH tab; Back returns to the menu | `Classes are not available` (no loadout module); `The match is over` (any phase but `PREMATCH` and `LIVE`) |
| `SETTINGS` | Pushes `settings` on the MATCH tab (personal settings, `PW.UI.Settings.Open(model, "client")`); Back returns to the menu | never (since T-7.2) |
| `RETURN TO LOBBY` | A dialog, then `pw_abort`; the menu closes | `Only the host can end the match` (not the host and not a superadmin); the server checks `pw.match.abort` again |
| `LEAVE GAME` | A dialog, then the engine `disconnect`; for the host the text warns that the server closes for everyone | never |
| `GMOD MENU` | `PW.UI.ShowGameMenu()` | never |

The pause menu has two tabs, `MATCH` and `LOADOUT` (Q/E). The LOADOUT tab is the existing `loadout_classes` screen.

### Screen `match_classes`

`Tab = "class"`, `Root = true`, `Title = "Choose class"`, hints `Use class` and `Close`. A `PWCardList` of the cards from
`PW.UI.Match.ClassCards(state)`: the presets, then the custom classes; the current class (the selected ref of
`PW.Loadout.GetClassState()`) has the badge `CURRENT` and the text `In use from your next spawn.`; an unavailable class is
locked with the badge `N/A`, the reason as text and `Not available: <reason>` as the tooltip.
`PW.UI.Match.Choose(state, ref, send) -> "sent"|"current"|"locked"|"unknown"` sends the pick (`PW.Loadout.SendPick`) only
for an available class that is not the current one. The new class applies from the next spawn. After `sent` or `current`
the screen leaves: back to the pause menu when it was pushed there, else the compact root closes. In the compact root the
screen draws its own heading `CHOOSE CLASS` and a note (`Used from your next spawn`, or `Waiting for the server` before
the first state); when no state has arrived it sends the class upload once more.

### Opening and closing

| Trigger | Result |
| --- | --- |
| Escape (`OnPauseMenuShow`) | `PW.UI.Match.Escape(facts)` decides: `"pause"` opens the pause menu (the hook returns `false`), `"root"` and `"leave"` give Back to the open root (the hook returns `false`; at the lobby hub root that Back opens the leave dialog), `"engine"` leaves the GMod menu alone |
| Gamepad Start (`PlayerButtonDown`, `KEY_XBUTTON_START`, local player, first prediction) | Opens the pause menu when `Escape` says `"pause"`. Inside a root Start stays the root's `settings` action |
| The local player dies in `LIVE` | The death watcher (a 0.1 s timer) opens the compact class picker. It stays closed once dismissed until the next death |
| The player respawns, or `LIVE` ends | The watcher closes the picker. Respawn is automatic, so the picker never delays it |
| The phase changes while the pause menu is open | Rebuilt inside `PREMATCH`, `LIVE` and `POSTMATCH` (the items depend on the phase), closed in any other phase (`VOTE`, `LOBBY`) |

The picker opens only when no other root is open (`otherRoot`), `ui_kit` and the loadout module are valid and the
setting `deathpicker` is on. `PW.UI.Match.PausePhases = { PREMATCH, LIVE, POSTMATCH }`.

### Escape fallbacks (the GMod menu)

`Match.Escape` answers `"engine"` (the GMod menu opens as usual) when any of these holds, checked in this order:

1. Shift is held (Shift+Escape), or the `GMOD MENU` item asked for it a moment ago (`bypass`, a 0.5 s window set by
   `PW.UI.ShowGameMenu()`), or the GMod menu is already visible;
2. the client setting `pw_ui_kit_pausemenu` is 0, or `ui_kit` is not valid;
3. the phase is not `PREMATCH`, `LIVE` or `POSTMATCH` (the lobby and the vote have their own roots).

With one of our roots open Escape means Back: `"root"`, or `"leave"` in `LOBBY` at the root screen (depth 1) of the
`"hub"` root with no dialog open. Rule 1 is checked first, so Shift+Escape opens the GMod menu over an open root too. A pause menu that cannot be built (no screen built, a `Build`
error) is removed and Escape falls through to the GMod menu.

### Client settings and commands

| Name | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `pw_ui_kit_pausemenu` | ConVar (module `ui_kit`, setting `pausemenu`, client, bool) | 1 | Escape opens the match menu. 0 gives Escape back to the GMod menu entirely |
| `pw_ui_kit_deathpicker` | ConVar (setting `deathpicker`, client, bool) | 1 | The class picker opens by itself on death in `LIVE` |
| `pw_ui_pause` | Client command | | Opens the match menu, or closes it when it is open |
| `pw_ui_classpick` | Client command | | Opens the compact class picker, or closes it when it is open (it opens by itself on death) |

| Function | Contract |
| --- | --- |
| `PW.UI.Match.ClassCards(state?) -> PW.UICard[], string?` | Pure. The picker cards and the current ref |
| `PW.UI.Match.Choose(state?, ref, send) -> string` | Pure. See above |
| `PW.UI.Match.PauseItems(facts) -> PW.UIPauseItem[]` | Pure. Facts: `phase`, `canAbort`, `classes`, `host`. Items carry `id`, `label`, `locked`, `reason?`, `variant?`, `confirm?` (the dialog text) |
| `PW.UI.Match.Escape(facts) -> "pause"\|"root"\|"leave"\|"engine"` | Pure. Facts: `phase`, `enabled`, `rootOpen`, `gameUI`, `bypass`, and for an open root `rootId?`, `depth?` (stack depth of the active tab), `modal?` |
| `PW.UI.Match.RootBack(facts) -> "leave"\|"router"` | Pure. Back in an open root without a dialog: `"leave"` in `LOBBY` at depth 1 of the `"hub"` root, else `"router"` (the router's Back). Facts: `phase`, `rootId?`, `depth?` |
| `PW.UI.Match.LobbyLeave(host) -> PW.UILobbyLeaveSpec` | Pure. The leave dialog: title `Leave game`, buttons `LEAVE GAME`, `GMOD MENU`, `CANCEL`; text `LeaveHostText` for the host, `LobbyGuestText` for a guest |
| `PW.UI.Match.NewDeathMemory()`, `DeathStep(memory, facts) -> "open"\|"close"\|nil` | Pure. One sample of the death watcher |
| `PW.UI.OpenPause()`, `PW.UI.OpenClassPicker() -> boolean` | Client. `false` and nothing left open when no screen could be built (the picker also needs the loadout module) |
| `PW.UI.ShowGameMenu(keepRoot?)` | Client. Shows the GMod menu; closes the open root unless `keepRoot` |
| `PW.UI.OpenLobbyLeave()` | Client. Opens the leave dialog of the lobby in the open root |

Escape and gamepad Start are engine input and are not covered by the tests (the local manual checklist (not published), section 29).

### Leaving from the lobby

Back at the root screen of the lobby hub (Esc, Backspace, gamepad B; `Match.RootBack` says `"leave"`) opens a
`PWDialog` titled `Leave game`:

| Button | Action |
| --- | --- |
| `LEAVE GAME` (focused first) | The engine `disconnect`. The host's text warns: `You are the host: leaving closes the server for everyone.` A guest reads `You leave the server. You can join again while it runs.` |
| `GMOD MENU` | `PW.UI.ShowGameMenu(true)`: the GMod menu over the lobby, which stays open |
| `CANCEL` | Closes the dialog; Esc or B does the same |

A pushed screen (custom game, map picker, settings) keeps Back. Shift+Escape opens the GMod menu directly. Quitting
Garry's Mod is not offered: `quit` and `exit` are blocked commands for `RunConsoleCommand`, `Player:ConCommand` and
`game.ConsoleCommand` (GMod wiki, "Blocked ConCommands"); the GMod menu has its own Quit. Manual checks:
the local manual checklist (not published), section 37.

## Components (U-4)

Decisions: `design/10-frontend.md` d.9, d.10, d.12; proposal and item numbers: `notes/16-frontend-d1-proposal.md` §3.
Code: pure and shared `ui_kit/sh_models.lua` and `sh_players.lua` (covered by the server-side test runner), client
glue `cl_paint.lua` (helpers), `cl_components.lua`, `cl_cards.lua`, `cl_players.lua`, `cl_form.lua`, `cl_settings.lua`.
Types: `lua/privatewar/types/ui_components.lua`, `ui_widgets.lua`. A vgui class only draws what its model returns.

### Models (shared, pure)

| Function | Contract |
| --- | --- |
| `PW.UI.Cards.View(list, selected) -> PW.UICardView[]` | Card states: only the selected card (when it is in the list) is `expanded` |
| `PW.UI.Cards.Expanded(list, selected) -> string?` | The id of the expanded card, or `nil` |
| `PW.UI.Cards.Select(list, current, id) -> string?` | `id` when the card exists and is neither `locked` nor `disabled`, else `current` |
| `PW.UI.Pager.RowsPerPage(height, rowHeight, gap?) -> integer` | Rows that fit a column (at least 1) |
| `PW.UI.Pager.State(count, perPage, index) -> PW.UIPagerState` | `page`, `pages`, `first`, `last`, `atStart`, `atEnd` of the page holding row `index` |
| `PW.UI.Seen.IsNew(seen, key)`, `PW.UI.Seen.Mark(seen, key) -> boolean` | The seen-set is a `table<string, true>`; `Mark` returns `true` when the key was new |
| `PW.UI.Tabs.SeenKey(id)`, `PW.UI.Tabs.Items(tabs, active, seen) -> PW.UITabItem[]` | `"tab:<id>"`; tab bar items (a tab is `new` when unlocked and not seen) |
| `PW.UI.PlayerList(players, opts) -> PW.UIPlayerSection[]` | In `LOBBY` one `PARTY` section (neutral, with `capacity` and the bots row `max(bots, botsFill - humans)`); from `PREMATCH` one section per active team, coloured `friendly`/`enemy` relative to `localTeam`; without teams one `PLAYERS` section. Humans: host first, then by name; bots collapse to `"+N bot(s)"` in `botsText` |
| `PW.UI.Monogram(mode) -> string` | The mode badge text: `mode.Short` upper-cased; else the initials of up to three words of `Name`; else `"?"` |
| `PW.UI.FormatTime(seconds) -> string` | `M:SS`, rounded up, never negative |
| `PW.UI.Status(info) -> PW.UIStatus` | The status line, `PHASE  ·  M:SS  ·  N/M  ·  note` (timer only when `remaining >= 0`); `warning` while the timer shows 10 s or less |
| `PW.UI.Hints(state, entries, override?) -> PW.UIHintItem[]` | Hint bar entries with the key cap or pad badge of the current device (`PW.UI.Input.Hint`); actions unknown to `Input.Actions` are dropped |
| `PW.UI.LockReason(reason?) -> string` | Display text of a lock reason: `soon` "Coming soon", `error` "Unavailable: the screen failed to load", `locked` (default) "Locked"; any other reason is returned as is |

`PW.UICard` fields: `id`, `title`, `text`, `tags`, `footer` (the last three show while expanded), `badge`, `new`,
`locked` (focusable, not selectable, `reason` goes to the hint bar), `disabled` (skipped by focus).

### Classes (client)

All are registered with `vgui.Register`; the buttons derive from `PWButton`. Every interactive one is a focus node
(`PW.UI.Focusable(panel, group, id?)`); a panel may define `PWAct(action)` (handles an action) and `PWOnFocus()`.

| Class | Role |
| --- | --- |
| `PWScreenTitle` | Screen title with a rule (`SetText`) |
| `PWTab`, `PWTabBar` | Tab strip with Q/E key caps and the NEW mark (`SetItems`, `OnSelect(id)`) |
| `PWStatusLine` | `PW.UI.Status` of the live phase on the right (`SetInfo`, `SetNote`) |
| `PWHintBar` | Bottom hint bar (`SetEntries`, `SetReason`: the reason of a focused locked node) |
| `PWWarningChip` | Warning chip (`SetText`) |
| `PWBackdrop` | Blurred backdrop (also `PW.UI.Draw.Backdrop`) |
| `PWTimer` | `M:SS` countdown, warning colour in the last 10 s (`SetEndTime`) |
| `PWDialog` | Modal confirm/cancel dialog over a blurred backdrop; opened with `PW.UI.OpenDialog(spec)` (`title`, `text`, `confirm`, `cancel?`, `onConfirm?`, `onCancel?`, and an optional third button `alt?` with `onAlt?`, placed between cancel and confirm). Back closes it as cancel and focus returns to the opener |
| `PWCard`, `PWCardList`, `PWPager`, `PWPagerArrow` | The card column: `SetCards(cards, selected)`, `OnSelect(id)`, paging from the column height (PgUp/PgDn) |
| `PWInfoCard`, `PWSummary` | Key/value card with an optional warning (`SetTitle`, `SetRows`, `SetText`, `SetWarning`); the mode summary with the monogram (`SetSelection(mode, map)`) |
| `PWPlayerList`, `PWPlayerRow`, `PWPlayerLine` | The player list over `PW.UI.PlayerList` (`SetSections`, `SetNote`; the host carries a HOST marker) |
| `PWToggle`, `PWSlider`, `PWSwitch` | Form controls: checkbox, slider (mouse drag; left/right), `< VALUE >` combo or number; Enter toggles or cycles |
| `PWMultiSelect` | A toggle per option of a `set` setting (`cl_settings.lua`) |
| `PWSettingsForm` | The settings form (since v0), restyled with the controls above; `OnChange` still fires after 0.3 s |
| `PWOperator` | The local player's model in an idle pose (a `DModelPanel`), see "Operator (U-9)" |
| `PWVoteCard` | One vote option as a tall card (`SetCard(PW.VoteCard)`), a focusable `PWButton`: see "Vote screen (`vote`)" |

`PWButton` (v0) gained `SetVariant("primary"|"secondary"|"danger")`, `SetEnabled(false)` (skipped by focus) and
`SetLocked(locked, reason)` (stays focusable, shows the reason in the hint bar, does nothing on accept). `PWRoot` gained
`Act(action)`, `OpenModal(panel, first)` and `CloseModal()`. Helpers in `PW.UI.Draw`: `Px`, `Rect`, `Outline`,
`EdgeBar`, `Lock`, `Badge`, `KeyCap`, `Backdrop`, `Wrap`, `Fit`; `PW.UI.SetLocked(panel, locked, reason?)`.

### Dev showcase

`addons/privatewar-dev/lua/privatewar/screens/dev_kit.lua` (dev addon, never shipped): the screen `dev_kit`, tab `play`,
`Root = true`, `Order = 900` (a real PLAY root wins), title "Kit showcase". It shows every component on fake data (cards,
buttons of each variant, the dialog, the settings form through `PW.UI.BuildForm`, the MATCH card, the party list, the
timer); `tertiary` (R) previews the team sections. The form prints `[PW] dev_kit: <id> = <value>`. Open it with
`pw_ui_root`. Dev command `pw_dev_kit_act <action>` gives an input action to the open root (screenshots through the
bridge). Checks: the local manual checklist (not published) CP-UI1.

## HUD (`hud`)

Kind `hud` (`lua/privatewar/kinds/hud.lua`) and module `hud` (`lua/privatewar/modules/hud/`: `shared.lua` the pure selection and
the paint loop, `cl_init.lua` the engine part), T-6.1. Types: `lua/privatewar/types/hud.lua`. Source decisions:
`design/09-hud.md` d.1, d.3; `design/01-extensibility.md` d.12, d.16.

### Kind `hud` and `HUDELEMENT`

Folder `hud/`, class table `HUDELEMENT`, one file per element in `lua/privatewar/hud/`. `Subscribe = "never"`
(`01-extensibility.md` d.18): an element never subscribes to `PW_*` hooks; the single `HUDPaint` of the module draws it.
`Required = { Draw = "function" }`. The per-element enable ConVar `pw_hudelement_<id>_enabled` follows from `Global`
(`core.md` "Enable ConVars"). The registry accessor is `PW.Hud` (`PW.Registry`; see "Two names" below).

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `Draw` | `function(self)` | yes | Draws the element in 1920x1080 design units (`PW.HUD.X`, `Y`, `S` map them to pixels). Called through `PW.Call` inside the single `HUDPaint`, so an error disables the element and the others still draw. It must not allocate: cache fonts, materials and colours |
| `Order` | number | no | Draw order, ascending; ties are broken by the element id. Default `100` |
| `Phases` | `PW.PhaseName[]` | no | The phases in which the element is drawn. `nil` means every phase, `LOBBY` included |
| `ShouldDraw` | `function(self) -> boolean` | no | Extra visibility check, called through `PW.Call` every frame whose phase matches. A falsy result hides the element for that frame |

### The paint loop

- One `HUDPaint` listener of the `hud` module (`PW.HookFor`, so it stops while the module is disabled) runs
  `PW.HUD._Paint(state, registry, phase, flags)` over `PW.Hud` with the networked phase (`PW.Phase.GetPhase()`).
- `PW.HUD._Select(elements, phase, flags, out) -> count` (pure) puts the elements that match the phase into `out`, ordered by
  `Order` then id, and clears the entries past the count. `flags.hidden` selects nothing. `PW.HUD._Scale(width, height) ->
  sx, sy, s` (pure) gives the stretch per axis and the uniform scale `min(sx, sy)` against `PW.HUD.DesignWidth` x
  `DesignHeight` (1920 x 1080). `PW.HUD._NewState()` creates the loop state.
- The ordered list is cached and rebuilt only when the phase, the registry or the validity of an element changed (an element
  that a ConVar or an error disabled marks the cache stale). A frame allocates nothing in the loop.
- Elements are taken from `registry.GetEnabledList()`.

### `PW.HUD` (client part)

| Function | Contract |
| --- | --- |
| `PW.HUD.DesignWidth`, `DesignHeight` | shared; `1920`, `1080` |
| `PW.HUD.X(value)`, `Y(value)` | Design units to pixels along one axis (stretch: `value * ScrW() / 1920`, `value * ScrH() / 1080`) |
| `PW.HUD.S(value)` | Design units to pixels with the uniform scale (`min(sx, sy)`), for sizes that must stay square or keep the aspect |
| `PW.HUD.Refresh() -> boolean` | Recomputes the scale and re-creates the fonts when `ScrW()` or `ScrH()` changed since the last call; returns `true` when it did. The paint loop calls it every frame |
| `PW.HUD.Font(id, size, weight?) -> string` | The font name `"PW_HUD_<id>"` for a size in design units (the kit's body family, Roboto fallback, antialiased and extended for Cyrillic, default weight 500), created on the first call and re-created on a resolution change. The size of the first call is kept for a given `id` |
| `PW.HUD.Hidden` | Legacy additional hide list, empty by default. Health/battery and ammo replacement is conditional, not stored here; crosshair, killfeed and Tab remain native (`09-hud.md` d.1 and revision 2026-11-08) |

The functions `X`, `Y`, `S`, `Refresh`, `Font` and `Hidden` exist on the client only.

### ConVar `pw_hud`

Client ConVar, archived, default `1`, range 0..1, `Draw the Private War HUD overlay (0 hides it)`. At `0` the loop selects no
element and restores native health/ammo. Conditional replacement also stops when the module or corresponding element is
missing, disabled, not visible or has failed. No crosshair, killfeed or scoreboard replacement is introduced.

### Player vitals and weapon (T-11.11)

User-approved `09-hud.md` revision 2026-11-08 replaces native health/ammo only. Elements `vitals` (`Order = 25`) and
`weapon` (`Order = 26`) run through the existing registry/`PW.Call` paint loop, in `LIVE` only. Both require a valid,
alive, non-observing local player (including the join-in-progress spectator flag). No observed player's data is used.

- Bottom left: nickname above three continuous armor segments of 50 each, above health. Armor presentation clamps
  to 0..150; health is health / actual maximum, clamped to 0..1, with invalid/non-positive maximum giving 0.
  No numerical health/armor, portrait or gameplay changes.
- Bottom right: localized active weapon name, then `CLIP / RESERVE` for primary ammo. Zero magazine and zero reserve
  remain `0`; no primary ammo means name only; a negative/invalid clip with primary ammo shows `- / RESERVE`.
  Names are measured, ellipsized and cached without splitting UTF-8. Colors use `PW.UI.Style` with cached fallbacks;
  fonts use the existing body-family indirection and extended Cyrillic rendering.
- Sizes use uniform scale and positions anchor to their own screen edge. At 1920x1080 the bottom edge is 1016,
  margin 40, vitals width 300, weapon width 360; nickname/name top 950, armor top 982, health top 1000. The weapon's
  ammo top is 984. This leaves the grenade equipment (lowest baseline 900) above and the XP strip below intact.
- Weapon sampling runs in the module's `Think`, outside `HUDPaint`, through `PW.Adapters.CallFor` (`GetClip`,
  `GetAmmoType`, `GetDisplayName`), with engine primary-ammo/name fallback when the adapter module is absent.
  The element checks player and weapon identity again before drawing, so switches cannot show a previous snapshot.
- `CHudHealth`/`CHudBattery` are hidden only for active `vitals`; `CHudAmmo`/`CHudSecondaryAmmo` only for active
  `weapon`. Suppression requires a successful previous draw and current validity/visibility; errors fail open on the
  next native panel query. The first frame can retain vanilla until a custom draw succeeds.

Shared pure helpers (`PW.HUD`, types `types/hud_player.lua`): `_HealthFraction(health, maximum)`,
`_ArmorSegments(armor, out)` (always three fractions), `_PlayerVisible(phase, valid, alive, spectating)`,
`_PlayerLayout(width, height, out)`, `_FitText(text, width, measure)`, `_WeaponModel(valid, name, clip, ammoType,
reserve, out)`, `_WeaponName(adapterName, engineName, class, localize)`, `_WeaponReady(state, player, weapon, visible)`
and `_NativeHidden(name, registry, phase, active)`. Output tables are reused; ammo text changes only with its values.
Client helpers: `PlayerVisible()` and `WeaponState` (current owner/weapon identity, name, optional clip/reserve and text).
`HUDELEMENT._HudPainted` records whether its last eligible draw completed without disabling the element.

### Two names: `PW.Hud` and `PW.HUD`

`PW.Hud` is the registry of the kind `hud` (the loader names the accessor of a kind by its folder in PascalCase,
`core.md` "Namespace"): `Get`, `GetList`, `GetEnabledList` and the other registry functions. `PW.HUD` is the library of
the module `hud` above. The names differ only in case; a script that wants the elements uses `PW.Hud`, one that scales
a coordinate uses `PW.HUD`. `PW.HUD` is `nil` when the module is missing.

### Built-in element `phase_label`

`lua/privatewar/hud/phase_label.lua` proves the pipeline: `Order = 10`, `Phases = { "PREMATCH", "LIVE", "POSTMATCH",
"VOTE" }`. It draws the name of the current phase at the top centre (design position 960, 24; font `phase`, 28 units, weight
700) in the `PW.UI.Style.text` colour (white when `ui_kit` is off). It is temporary: T-6.2 and `U-8` replace it with the real
match status (`TASKS.md`).

Mandatory cases (`TASKS.md` T-6.1): the element registry order and visibility by phase; an element that errors is disabled
without breaking the others.

### Match status (element `match_status`, T-6.2, U-8, T-11.5)

`hud/match_status.lua` (`Order = 10`, phases `PREMATCH`, `LIVE`, `POSTMATCH`); rules in `modules/hud/sh_status.lua`
(timer, verdict, score order) and `modules/hud/sh_scorebars.lua` (bars), both pure and shared. Source:
`design/09-hud.md` d.2 and the revision of 2026-11-07, item 3.

- **Position:** the top left, under the radar (the radar stays in the corner). The bars start at the radar's left edge,
  `gap` units under the radar disc. A dark `bg_panel` box (8 units of padding) sits behind the bars, the numbers and
  the timer.
- **Rows:** one horizontal bar per team in the team colour relative to the local player (`team_friendly` for the own
  team, `team_enemy` for the others), the own team on top, the others by score (ties to the lower index), at most
  `maxRows`. A spectator sees the teams in index order with team 1 friendly. FFA shows two rows: you (friendly) and
  the leader (enemy colour), or you and second place when you lead; a tie for the lead is not leading. Alone in FFA:
  one row. An FFA spectator sees the top two.
- **Bar:** filled by `score / limit`, clamped to 0..1, from the left. The fill eases toward the target
  (`_ScoreEase`, rate `ease`) and never overshoots. A semi-transparent L outline (opacity `outline`) marks the full
  length, which is the score limit: a line under the bar along the full length and a vertical tick at its right end
  rising `tick` units above the bar.
- **Number:** the score right of the bar, in the row colour, font step `body`.
- **No limit** (`limit` 0): no bars and no outline; the numbers move to the left edge and the timer follows them.
- **Timer:** right of the numbers, vertically centred on the rows, font step `h2`, `text` colour; `M:SS` from
  `pw_mode_ends` in `LIVE` and from `pw_phase_end` in `POSTMATCH` (`_TimerEnd`, `_Remaining`, `_FormatTime`). Without
  an end time no timer is drawn.
- **Phase messages** stay centred at design `(960, 330)`: the `POSTMATCH` banner (`VICTORY`, `DEFEAT`, `DRAW` or `MATCH OVER`, step `title`); the
  bars and the timer stay visible in `POSTMATCH`. Nothing is drawn in `PREMATCH`: the start countdown is the
  lobby's START button (T-11.10, "Match flow in the lobby"; the former "Match starts in N" message is gone).
- **Sources (NW2 only, no net messages):** the score key prefix `pw_hud_score` and the score limit `pw_hud_limit`
  published by `match_rules` (`modes.md`, "Match rules"), the team count `pw_teams` (`LIVE`) or `pw_result_teams`
  (`POSTMATCH`), the team scores `<prefix><index>` and the FFA kills `pw_kills` on each player. Round modes show the
  rounds won against `RoundsToWin`.
- A frame allocates nothing: the row, layout and rectangle tables are reused, a score text is rebuilt only when that
  row's score changes and the timer text once per second.

Values in `PW.HUD.ScoreBars` (design units, 1920x1080, scaled with the uniform scale `S`; the left edge follows the
radar's `X`):

| Value | Default | Meaning |
| --- | --- | --- |
| `gap` | 16 | Space between the radar disc and the first row |
| `width` | 220 | Full bar length (the score limit); the radar diameter |
| `bar` | 12 | Bar thickness |
| `pitch` | 30 | Row height |
| `line`, `tick` | 2, 4 | Outline thickness; how far the end tick rises above the bar |
| `outline` | 0.35 | Outline opacity |
| `numberGap`, `numberWidth` | 10, 56 | Space between bar and number; room for the number |
| `timerGap`, `timerWidth` | 14, 80 | Space before the timer; room for it (the right edge of the panel) |
| `maxRows` | 4 | Rows at most (team modes with more teams) |
| `ease` | 10 | Fill ease rate (1/s) |

At 1920x1080 the block spans x 40..420 and y 276..336 for two rows (radar 40..260); at 1280x720 and 1280x800 it scales
down with the radar and stays in the left 40 % and the upper half of the screen, clear of the Domination tiles (top
centre) and the killfeed (top right).

Pure functions (`PW.HUD`): `_ScoreRows(scores, count, own, ffa, limit, out) -> n`, `_ScoreFraction(score, limit) ->
number?`, `_ScoreEase(current, target, dt, rate)`, `_ScoreLayout(width, height, rows, limited, out)` (pixels:
`x`, `top`, `barWidth`, `barHeight`, `pitch`, `line`, `tick`, `numberX`, `timerX`, `timerY`, `right`, `bottom`),
`_ScoreBarRects(layout, slot, fraction, out)` (fill, outline line and tick rectangles, number centre); and from U-8
`_Remaining`, `_FormatTime`, `_TimerEnd`, `_PrematchText`, `_Verdict`, `_Lead`. Types: `PW.ScoreRow`,
`PW.ScoreLayout`, `PW.ScoreBarRects`, `PW.ScoreBarsConfig` in `types/hud.lua`.

Mandatory cases: `TASKS.md` T-6.2, U-8 and T-11.5 (`lua/tests/privatewar/hud_match_status.lua`,
`hud_scorebars.lua`).

### Score popups and medals (element `popups`, T-6.4)

`hud/popups.lua` (`Order = 30`, phase `LIVE`); rules in `modules/hud/sh_popups.lua` (pure, shared). Source:
`design/09-hud.md` d.2.

- Net message `pw_score_popup`, server to the owner of the award only (humans only, no message for a bot or for 0 points):
  `String` event id, `UInt(16)` points. It is sent by the `score` module (`modes.md`, "Score module") for every award.
- An event is a medal popup when it has `Medal = true` and its id is in `PW.Medals.Ids`; every other event, including
  `headshot` (which has `Medal = true` but is not announced by the medals module), is a normal popup. The `pw_medal`
  message is not used by the HUD (`medals.md`).
- Text: `EVENT.Name`, a `#` key resolved with `language.GetPhrase`; with no language entry the id is humanised
  (`first_blood` becomes `First Blood`).
- Timings in `PW.HUD` (seconds, count):

| Value | Default | Meaning |
| --- | --- | --- |
| `PopupMergeWindow` | 1.5 | A popup of the same event within this time of the previous one merges (`+100 Kill` and `+100 Kill` become `+200 Kill`) and restarts its life |
| `PopupHold` | 1.2 | Time at full opacity |
| `PopupFade` | 0.6 | Fade out after the hold |
| `PopupMax` | 4 | Popups stacked at once (the newest on top, right of and below the crosshair) |
| `MedalDuration` | 2.5 | One medal on screen (large, above the crosshair, with the sound `buttons/bell1.wav`) |
| `MedalFadeIn`, `MedalFadeOut` | 0.2, 0.5 | Fade in and out inside the duration |
| `MedalMax` | 6 | Queue length; medals show one after another, a medal past the limit is dropped |

Pure functions: `PW.HUD._PopupNew`, `_PopupAdd`, `_PopupAlpha`, `_PopupPrune`, `_MedalNew`, `_MedalAdd`, `_MedalCurrent`,
`_MedalAlpha`, `_PopupText`, `_PopupKind`, `_LevelUpAdd`, `_LevelUpScale`.

The element draws in `LIVE` and `POSTMATCH` (a level-up or medal from the last award of a match shows before the match
ends). The medal queue (`PW._HudMedals`) also carries the LEVEL UP popup of the element `progression` (next section).

### Bottom XP bar and LEVEL UP (element `progression`)

`hud/progression.lua` (`Order = 15`, phases `PREMATCH`, `LIVE`, `POSTMATCH`); rules in `modules/hud/sh_xpbar.lua` (bar
and detection) and `modules/hud/sh_popups.lua` (the LEVEL UP queue entry), pure and shared. Source: `design/09-hud.md`
d.2, `design/06-progression.md` d.1. Types: `types/hud_xpbar.lua`, `types/hud_popups.lua`.

Layout (design units, 1920x1080): a bar `6` high (at least 2 pixels), `10` above the bottom edge, from `64` to `1856`
across; the shown level is centred in the left `64` units, the next level (or `MAX` at the cap) in the right `64`, font
`xpbar_level` (24, weight 800). Colours: track `bg_panel`, fill `accent`, numbers `text`. The custom vitals and weapon
end at y `1016`, the streak lines at `830` and the equipment lines at `900` (right side), leaving the XP strip clear at
1920x1080, 1280x720 and 1280x800. Native health/ammo remain the fallback when the replacements are inactive.

Bar (`PW.HUD._XpBarStep(bar, level, fraction, dt, animate)`, state `_XpBarNew()`, kept in `PW._HudXpBar`):

- the fill is `PW.Progression._Fraction(pw_xpin, pw_xpneed)` of the NW2 level;
- a higher fill at the same level eases toward it: exponential approach at `XpBarRate` (5 per s), at least
  `XpBarMinSpeed` (0.25 of the bar per s), no overshoot;
- a higher level fills the shown level to full, shows it full for one frame, then wraps to the new level at 0 and eases
  to the remainder; a jump of several levels makes one wrap straight to the final level;
- the first value, a lower level, a lower fill at the same level and any change while the bar is not armed snap.

Level-up detection (`PW.HUD._LevelWatch(watch, source, level, now) -> level?`, state `_LevelWatchNew()`, kept in
`PW._HudLevelWatch`): the source is the last decoded `pw_progression_levels` table (`PW.Progression._Local.levels`, a new
table per message). The first message is the baseline and never fires (join, first sync; a map change reloads the client
Lua, so the next map starts with a new baseline). A later message with a higher player level fires once with that
level; the same level (the `PREMATCH` resend, a weapon level-up) or a lower one (a reset, which moves the baseline down)
does not fire. `PW.HUD._XpBarAnimate(watch, now)` arms the bar animation `XpBarSettle` (1 s) after the baseline, so the
NW2 jump of the join upload snaps even when it arrives after the message.

LEVEL UP popup (`PW.HUD._LevelUpAdd(state, level)`): an entry `{ kind = "levelup", name = "LEVEL UP", label = "LEVEL
<n>", level = n }` appended to the medal queue, so it shows after the medals already waiting and never overlaps one. It
ignores `MedalMax`. Several level-ups in a row show the final level once: a LEVEL UP still waiting takes the newer
level; one already showing gets a new entry after it. It lasts `MedalDuration` (2.5 s) with the medal fade: the title
(`title` font, `accent`) and the level (`h2`, `text`) centred at design y 250, scaled around the centre from
`LevelUpScaleFrom` (1.6) down to 1 over `LevelUpPop` (0.3 s, ease out, `_LevelUpScale(age)`), with the sound
`items/suitchargeok1.wav`. Layout (`PW.HUD._LevelUpLayout(facts, out)`, pure, no allocation): from the measured text
sizes, the two lines are drawn unscaled at their on-screen positions (`LevelUpGap` 6 design units apart) and the model
matrix scales around the block centre, which is moved so the box at `LevelUpScaleFrom` stays `LevelUpMargin` (16) from
the screen edges. The surface clip rect applies before the model matrix, so text drawn around (0, 0) was clipped
(T-11.10); clipping is also switched off while the popup draws.

### Radar (element `radar`, T-6.6)

`hud/radar.lua` (`Order = 28`, phase `LIVE`, hidden while the local player is dead); rules in `modules/hud/sh_radar.lua`
(pure, shared). Source: `design/09-hud.md` d.2. It is a disc in the top-left corner, rotated with the view: the local
player is a white arrow in the centre pointing up.

Values in `PW.HUD.Radar` (design units unless noted):

| Value | Default | Meaning |
| --- | --- | --- |
| `range` | 2000 | World units from the centre to the edge; farther dots are drawn on the edge (smaller) |
| `radius` | 110 | Disc radius |
| `left`, `top` | 40, 40 | Corner offset |
| `life` | 3.5 | UAV blip life (s): the blip fades out over it |
| `period` | 3 | UAV refresh interval (s): the sweep turns once per period |
| `dot` | 8 | Dot size |
| `noise` | 48 | Specks per frame in the jammed state |

Data sources:

- Teammates: every living, non-dormant player the client knows with `not PW.IsEnemy(me, ply)`, always drawn (nobody in
  FFA). Dormant players are not drawn.
- Enemies: only the revealed blips `PW.Streaks.Blips()` (`{ index, pos, ends }`, see `streaks.md`). An enemy the client
  happens to know is never drawn, and shots that are not suppressed are not shown.
- `PW.Streaks.Jammed()`: a hostile Counter-UAV.

States (`PW.HUD._RadarState(jammed, blipCount)`):

| State | Condition | Look |
| --- | --- | --- |
| `normal` | not jammed and no live blips | neutral rim, teammates only |
| `uav` | not jammed and at least one live blip | accent rim, a sweep line with a trail, enemy blips fading over `life` |
| `jammed` | `Jammed()` | warning rim, noise specks, no enemy blips even from an own UAV |

The `uav` state is inferred from live blips, not from a flag: with every enemy dead there are no blips, so no sweep is
shown. Other pure functions: `_RadarProject`, `_RadarFade`, `_RadarSweep`, `_RadarDots`.

## Domination points (element `dom`, T-6.5)

Source: `design/09-hud.md` d.2; code `hud/dom.lua` (drawing) and `modules/dom_flags/sh_hud.lua` (pure rules, config in
`PW.DomFlags.Hud`). Phase `LIVE`, order 12.

A row of letter tiles (A, B, C, sorted by letter) at the top centre (the match status moved to the top left in T-11.5;
the tiles kept their position). Layout values in design units
(1920x1080): `top` 100, `tile` 56, `gap` 12, `bar` 6; the capture bar sits 3 units under its tile.

- Owner colour of a tile (`PW.DomFlags._Display(flag, team, out)`): `team_friendly` for a flag of the local team,
  `team_enemy` for the other team, `text_muted` (grey) while nobody owns it. A local team outside 1..2 (spectator)
  reads team 1 as friendly.
- Capture bar: width is `min(1, |value| / 100)`, in the colour of the side the scalar leans to (`lean`). It is drawn at
  full strength while a capture is in flux and dimmed once settled (the owner's end, or no change at all, `capturing`).
  A flag being retaken keeps the owner colour on the tile while the bar shows the attacker colour.
- Contested pulse: when the flag entity's `Contested` network var is true (`modes.md`, equal counts of both teams) a
  warning rim pulses around the tile (`sin(CurTime() * 8)`); the bar does not move in that state.
- Local highlight: the tile of the flag the local player stands in (`_Inside`, alive only) gets an `accent` rim.
- Visibility: `PW.DomFlags._Visible(flagCount)` is true when at least one flag exists. The client does not know the
  active mode, so existence of the flags decides: no row in `LOBBY`, FFA, TDM or KC, and none outside `LIVE`. `pw_hud 0`
  hides it as every element.

Everything comes from data the client already has (flag network vars, the local position and team), so no hidden enemy
positions are shown. A frame allocates nothing (`_NewDisplay` tables are reused). Other pure functions:
`_OrderDisplays`.

## Lobby screen (`lobby_ui`)

The host picks a mode and a map, edits Game Setup (the `match` settings) and starts the match; players with the
toggle privilege switch enable flags for the next match. The client never decides anything: the server checks
privilege, phase and values again.

### Privileges

Declared by `lobby_ui/init.lua` with `PW.Privilege` (`core.md` "Privileges"):

| Privilege | Field | Default | Allows |
| --- | --- | --- | --- |
| `pw.match.start` | `PW.Lobby.StartPrivilege` | `superadmin` | Starting a match from the lobby |
| `pw.entities.toggle` | `PW.Lobby.TogglePrivilege` | `superadmin` | Changing enable flags (`design/01-extensibility.md` d.11) |

Game Setup edits use the core privilege `pw.settings.change` and the core message `pw_settings_match`.

### Net messages

Client to server, all through `PW.Net.Receive` (`core.md` "Client messages"):

| Message | Who | Phases | Rate | maxLen | Payload |
| --- | --- | --- | --- | --- | --- |
| `pw_lobby_request` | any | `LOBBY`, `PREMATCH` | 4 per s | 16 bytes | none; answered with `pw_lobby_state` |
| `pw_lobby_start` | `pw.match.start` | `LOBBY` | 2 per s | 256 bytes | `WriteString(mode id)`, `WriteString(map)` |
| `pw_lobby_enable` | `pw.entities.toggle` | any | 10 per s | 256 bytes | `WriteString(kind id)`, `WriteString(entity id)`, `WriteBool(enabled)` |

Server to client: `pw_lobby_state`, sent to one player in answer to `pw_lobby_request` and after that player's
accepted `pw_lobby_enable`. Explicit writes, no `net.WriteTable` (DESIGN.md global rule 4), in this order:

1. `WriteString(map)`: the current map.
2. `WriteUInt(n, 12)`, then `n` times `WriteString(map name)`: installed maps.
3. `WriteUInt(n, 8)`, then per mode:
   1. `WriteString(mode id)`;
   2. `WriteUInt(k, 10)`, then `k` times `WriteString(full setting id)`, `WriteString(value in text form)`: every
      field of `PW.Settings.GetGroups("match", mode)` (the mode's group, then the enabled modules' groups), values
      pending or default (`PW.Settings.Format`).
4. `WriteBool(canStart)`, `WriteBool(canEdit)`, `WriteBool(canToggle)`: `pw.match.start`, `pw.settings.change`,
   `pw.entities.toggle` of the receiving player.
5. `WriteUInt(n, 12)`, then per toggle `WriteString(kind id)`, `WriteString(entity id)`, `WriteBool(enabled)`;
   `n = 0` unless `canToggle`.
6. The navmesh block of the `navgen` module (T-2.12), appended last: `WriteBool(present)`, where `present` is `false` when
   the module is missing or disabled; if `true`: `WriteUInt(areas, 24)` (navmesh areas of the current map, 0 = none),
   `WriteBool(generating)`, `WriteBool(canGenerate)`, `WriteBool(fastDefault)`, `WriteString(result)`. Source:
   `PW.NavGen.LobbyInfo(ply)` (`PW.LobbyNav`, `map.md`).

- Every count is capped at `2^bits - 1`; items past the cap are not sent. `areas` is capped the same way (24 bits).
- The server sends the state again to every human when a generation starts and when its result is known
  (`PW.NavGen`, `map.md`), so open screens update the navmesh line.
- Names, setting definitions and groups are not sent: the client rebuilds them from its own registries. A mode the
  client does not know is skipped; a module group with no sent value (a module disabled on the server) is dropped;
  values are parsed back from their text form.
- Maps: `maps/*.bsp` on the `GAME` path, names of 1 to 64 letters, digits, `_` and `-`, unique, sorted.
- Modes: the startable modes (below), sorted by id.
- Toggles: every listed (resolved, non-abstract) entity of every registry except `kinds`, sorted by kind and id;
  `enabled` is the current value of its enable ConVar (a missing ConVar reads as on).

### Start validation

`pw_lobby_start` (server, after the `PW.Net.Receive` checks) is refused first, with one log line (`lobby start from <nick>
refused: navmesh generation running (<mode> on <map>)`), while a navmesh generation runs (`PW.NavGen.IsGenerating()`,
`map.md`): the engine reloads the map when the generation ends, so a match started meanwhile would be lost. Otherwise it
accepts the request only if:

1. The mode is startable: it is in `PW.Modes.GetEnabledList()` (the enable snapshot of the current match) and its
   enable ConVar (`PW.Enable.ConVarName("modes", id)`) is on now. `PW.Match.Start` itself does not check the flag
   (`core.md` "Enable ConVars").
2. The map name is valid (as above) and `maps/<map>.bsp` exists on the `GAME` path.
3. The mode is offered on the map: `PW.Map.ModeFits(mode, map)` (`map.md`; `PW.Lobby._Fits`). A mode without `MapData`
   always fits; the refusal reason is `mode not offered on this map`.

Then it calls `PW.Match.Start(mode, map)` (`core.md` "Phases and match"; another map goes through "Map change").
Accepted and refused requests are logged with one line each (`lobby start by <nick>: <mode> on <map>`,
`lobby start from <nick> refused: <reason> (<mode> on <map>)`).

`pw_lobby_enable` is accepted only for a listed entity of a registry other than `kinds`, with a boolean value, and
only if the entity's enable ConVar exists. It sets the ConVar; the change takes effect at the next match
(`core.md` "Enable ConVars").

### Client

The lobby is the kit's `PWRoot` (`PW.UI.OpenRoot`): the PLAY tab root is the hub (`screens/lobby_hub.lua`), the custom
game screen (`screens/lobby_custom.lua`) is pushed on it ("Screens (U-5)"). `lobby_ui/cl_init.lua` keeps the data the
screens read, sends the requests and opens and closes the root; it decides nothing.

- The root opens by itself when `PW_PhaseChanged` reports `LOBBY` or `PREMATCH` (T-11.10: the START button counts
  down) and closes on any other phase. F1 (the `gm_showhelp` bind, caught in `PlayerBindPress`) and the console command
  `pw_lobby` toggle it: an open root closes, a closed one opens only in `LOBBY` or `PREMATCH`. In `LIVE` F1 is not
  caught and does not open it.
- A watch timer (every 0.25 s) closes the root as soon as `PW.Lobby._ShouldShow(phase, active, kit)` stops holding
  (phase left `LOBBY` and `PREMATCH`, `lobby_ui` or `ui_kit` disabled) and redraws the open screen when the player
  count changes (the PARTY list) or the START countdown label changes (once per second).
- A disabled `lobby_ui` (`pw_module_lobby_ui_enabled 0`, applied from the next match; the client reads it from the
  enable snapshot, `core.md` "Enable ConVars") does not open: `pw_lobby`, F1 and `PW_PhaseChanged` do nothing, an open
  screen closes in its next watch tick, `pw_lobby_state` is ignored, and the three server messages are dropped as
  `disabled` before their handlers run (`PW.Net.Receive` `owner`, `core.md` "Client messages"). The same holds while
  `ui_kit` is disabled.
- `PW.Lobby._ShouldShow` (true in `LOBBY` with the module and `ui_kit` valid) and
  `PW.Lobby._ShouldRequest(open, waiting)` are internal pure rules.
- On open the client sends `pw_lobby_request` and `pw_playlist_request` (the second only with the `playlists` module)
  and redraws from the answers: each `pw_lobby_state` and each `pw_playlist_list` calls the open screen's `PWRefresh`.
  Until the lobby answer arrives the client resends the request every `PW.Lobby.RetryEvery` (2) seconds, only while the
  root is open; the retry stops when `pw_lobby_state` arrives or the root closes. Until it arrives the hub shows
  "Waiting for the server" and every action is locked.
- The client's own mode and map choice (`PW.Lobby.Select`) is not sent anywhere: it only feeds `pw_lobby_start` when
  START MATCH is used. The maps offered for the selected mode are only those where it fits (`PW.Lobby._Fits` over the
  client's registries and `PW.Map.ModeFits`); the server checks again.
- A Game Setup change is sent as `pw_settings_match` (`PW.UI.ToWire`) and also applied to the client's own copy of the
  state; an enable toggle is sent as `pw_lobby_enable`.
- `PW.Lobby.Input()` collects what the models need: the state, the selection, the fits, the playlist state, the players
  (`PW.UI.CollectPlayers`), `game.MaxPlayers()`, the seen-set and the mode's `Short`.
- NEW badges: a playlist card is `new` until its key (`playlist:<id>`) is in the seen-set; all listed playlists are
  marked seen when the lobby is closed (once), and the set is saved to `data/privatewar/ui_seen.json`.
- Console command `pw_lobby_act <action>` gives an input action (`down`, `accept`, `secondary`, `tertiary`, `back`, ...)
  to the open root (`PWRoot:Act`). It is for driving the screen from the dev bridge (`client pw_lobby_act secondary`,
  `scripts/deck/snap.sh`); without an open root or an argument it does nothing.
- After `pw_reload` an open root is closed and opened again one tick later, so it runs the new code.

#### Playlists (T-2.6)

- The left column of the hub lists the playlists as cards (`PW.Playlist._Items` data, `modes.md`), then the Custom game
  card (`@custom`). The selected card is expanded; without an active playlist it is Custom. A card carries the playlist
  summary and, when the playlist fills bots, the footer `Fills to N with bots`.
- On open the client also sends `pw_playlist_request` and redraws when `pw_playlist_list` arrives
  (`PW.Playlist.OnChange`). Selecting a card sends `pw_playlist_pick` (`""` for Custom) only for a player with
  `canStart`; the cards are locked for everyone else ("Only the host can pick the playlist"). Another player's pick is
  not shown until the screen is opened again (the answer goes to the picker only).
- With an active playlist START reads `START PLAYLIST` and sends `pw_playlist_start` (the server samples mode and map,
  applies the playlist settings and starts); otherwise `START MATCH` sends `pw_lobby_start` with the chosen mode and map.

#### Navmesh (T-2.12)

- The NAVMESH action of the custom game screen (present only with the `navgen` block) shows the navmesh line
  (`PW.Lobby._NavLine`): `Generating the navmesh: the game stutters and the map reloads when it is done.` while
  `generating`; else the stored `result` text; else `No navmesh: bots and dynamic spawns unavailable.` for 0 areas; else
  `Navmesh: <n> areas.`
- A player for whom `canGenerate` is `true` can press GENERATE NAVMESH: a dialog with the warning of `03-mapdata.md` d.8
  (from about a minute to over an hour on huge maps, heavy stutter, large maps can crash, the map reloads by itself, the
  file is saved on the host computer) and a fast mode toggle that starts on when `fastDefault` (the host is the only
  human). GENERATE sends `pw_navgen_start` (`WriteBool(fast)`, `WriteBool(false)`, `map.md`). For everyone else the
  button is locked ("Only the host can generate the navmesh").
- While `generating` START is locked ("A navmesh is being generated: the map reloads when it is done") and the server
  also refuses `pw_lobby_start` and `pw_playlist_start` ("Start validation", `modes.md`).

### Screens (U-5)

Decisions: `design/10-frontend.md` d.8 to d.10, `design/08-lobby.md` d.2, d.3, `notes/16-frontend-d1-proposal.md` §4a and
§4b. Thin glue (`SCREEN.Tab = "play"`, kind `screens`, "Kind `screens` and `SCREEN`") over two pure and shared models in
`lobby_ui/sh_hub.lua` (covered by the server-side test runner); types in `lua/privatewar/types/lobby_hub.lua`. Actions a
player may not use are never hidden: they are locked (focusable, the reason in the hint bar), and the server checks every
request again.

| Function | Contract |
| --- | --- |
| `PW.Lobby._Hub(input) -> PW.LobbyHub` | The hub model from a `PW.LobbyHubInput` (`state`, `selection`, `fits`, `playlists`, `players`, `maxPlayers`, `seen`, `shortOf`). `cards`: playlist cards then Custom (locked with the playlist reason without `canStart`); `selected`: the active playlist id or `@custom`; `start` (a `PW.LobbyAction` with `label` `START MATCH` or `START PLAYLIST` and `request` `{ playlist }` or `{ mode, map }`); `modeMap`, `setup`; `summary` (monogram, mode, map); `rows` (the MATCH card: up to 3 fields of each mode settings group and `Bots fill`, or `Playlist` and `Bots fill` with an active playlist); `warning`; `party`; `note`; `model` |
| `PW.Lobby._Custom(input) -> PW.LobbyCustom` | The hub model plus the custom game screen: `actions` (start, modemap, setup, `content`, and `navmesh` with the navgen block), `modeCards`/`modeSelected`, `mapCards`/`mapSelected`, `sections` (Game Setup of the selected mode), `canEdit`, `canToggle`, `toggles`, `nav`, `navLine` |
| `PW.Lobby._SlotWarning(fill, maxPlayers) -> string?` | `Bots fill to <fill> players, the server has <maxPlayers> slots` when `fill > maxPlayers`, else `nil` (shown as the warning of the MATCH card) |
| `PW.Lobby._SeenKey(id) -> string` | `"playlist:<id>"`, the seen-set key of a playlist |
| `PW.Lobby._ShowValue(def, value) -> string` | A setting value as text for the MATCH card (`On`/`Off`, upper-cased enums and sets, `None` for an empty set) |

Lock reasons (the text in the hint bar): `Waiting for the server` (no state yet), `Only the host can start the match`,
`Only the host can pick the mode and the map`, `Only the host can change Game Setup`, `Only the host and superadmins can
switch content`, `Only the host can generate the navmesh`, `Only the host can pick the playlist`, `A navmesh is being
generated: the map reloads when it is done`, `No mode is offered on any installed map` (START with no usable mode and map
and no playlist). The status line carries the note `waiting for host` for a player who cannot start.

**The hub** (`lobby_hub`, `Root = true`, `Order = 10`, title "Private War"). Left: `PWCardList` of the playlists and the
Custom game card. Centre: `PWOperator`. Right: `PWSummary`, the MATCH `PWInfoCard` (with the slot warning), the PARTY
`PWPlayerList` (note "Teams are assigned when the match starts."; host first with HOST, then `+N bots`), and at the
bottom GAME SETUP (secondary button, `PW.Lobby.OpenCustom("setup")`) and START (primary). Hints: Select (Enter), Game
setup (F), and Start match (R) for a player who may start. Esc on the hub opens the leave dialog in `LOBBY` ("Leaving from the lobby"; the router itself stays, "Router
(U-3)"). Selecting the Custom game card, even when it is already selected, sends `pw_playlist_pick ""` (the active
playlist resets to Custom) and opens the custom screen on its mode and map section.

**The custom game screen** (`lobby_custom`, pushed from the hub, title "Custom game"). Left: the actions as cards (START
MATCH, MODE & MAP, GAME SETUP, ENABLED CONTENT, NAVMESH) and the summary. Centre: the section of the selected action:
MODE & MAP is a summary card (`Selected`: mode and map) and the button CHOOSE MODE & MAP, which opens the map picker (selecting
the action opens the picker at once; see "Map picker (U-6)"), GAME SETUP is the generated form
(`PW.UI.BuildForm`, read only without `canEdit`), ENABLED CONTENT is one checkbox per entity grouped by kind ("applies at
the next match"; locked without `canToggle`), NAVMESH is the navmesh line, the fast mode toggle and GENERATE NAVMESH.
Right: the MATCH card and PARTY. START is a command, not a section: it sends the start request and keeps the section.
Guests see the same screen with every action locked and Game Setup read only. Esc goes back to the hub. The centre is
rebuilt only when its key (section, selected mode, `canEdit`, `canToggle`, toggle count, navmesh line) changes, so the
focus survives refreshes.

Internal client helpers (not contract): `PW.Lobby.OpenCustom(section)`, `TakeSection()`, `SetCards(list, cards,
selected)` (updates the card panels in place when the ids are the same), `Refocus()`, `SetFrame(note, hints)` (the status
note and hint bar of the open root), `SendPick`, `SendStart`, `SendSetting`, `SendToggle`, `SendNavGen`.

### Map picker (U-6)

Decisions: `design/10-frontend.md` d.3, `notes/16-frontend-d1-proposal.md` §4c. Screen `map_picker` (`screens/map_picker.lua`,
tab `play`, title "Mode & map", `OwnsTabKeys = true`, hints Select, Previous mode, Next mode, Back) over the pure and shared
`lobby_ui/sh_picker.lua`. Pushed from the custom game screen. Left: the mode strip (the key caps show the keys; a click on
its left or right half cycles) and the paged list of the maps the mode is offered on; centre: a large preview of the focused
map and the summary (mode monogram, mode, map).

- Q and E cycle the mode; the map list follows, and the map selection is kept when it still fits the new mode, else the first
  fitting map.
- The preview follows the focus: `maps/thumb/<map>.png` (looked up once per path), else a placeholder with the map name and
  `NO PREVIEW`.
- Enter on a map selects it (`PW.Lobby.Select({ mode, map })`) and goes back; Esc goes back without changes. The focus opens
  on the selected map; the lobby's current map carries the badge `CURRENT`.
- A guest (no `canStart`) sees the cards locked with the reason `Only the host can pick the mode and the map`. In pick mode
  nothing is locked.

| Function | Contract |
| --- | --- |
| `PW.Lobby.OpenPicker(opts?)` | Client. Pushes `map_picker` on the active tab of the open root. `opts` (`PW.LobbyPickerOpts`): `mode?`, `map?` (the start values; default the lobby selection), `input?` (a state source, default `PW.Lobby.Input`) and `pick?` (**pick mode**) |
| `PW.Lobby.TakePicker() -> PW.LobbyPickerOpts` | Client. The options given to `OpenPicker`, once (the screen reads them in `Build`) |
| `PW.Lobby.ClosePicker()` | Client. Pops the picker |
| `PW.Lobby._Picker(input, pick) -> PW.LobbyPicker` | Pure. What the screen draws: `modes`, `mode`, `modeName`, `maps`, `map`, `cards`, `focusIndex`, `thumb`, `summary`; `ready = false` before the lobby state arrives |
| `PW.Lobby._PickerStep(input, pick, action) -> PW.LobbyPick?` | Pure. For `tab_prev` or `tab_next`, the next mode with the kept map; `nil` for any other action or without a state |
| `PW.Lobby._PickerMaps(state, modeId, fits?) -> string[]` | Pure. The maps a mode is offered on (all without a `fits` test; none for an unknown mode) |
| `PW.Lobby._PickerKeep(maps, wanted) -> string?`, `_PickerCycle(ids, current, delta) -> string?`, `_PickerPage(count, perPage, index)`, `_ThumbPath(map) -> string?` | Pure helpers: the kept map, the wrapping next id, the pager state with its `n / N` text, `maps/thumb/<map>.png` (`nil` for an invalid map name) |

**Pick mode** (`opts.pick = function(mode, map)`): Enter calls the callback with the picker's mode and the focused map and
leaves the lobby selection alone, then goes back. The vote's "Pick myself" uses it.

### Entry hints (T-8.3)

Decisions: `design/08-lobby.md` d.2. Pure and shared `lobby_ui/sh_entry.lua`; the hub shows the hint as an info card under
the MATCH card and hides the card without a hint.

`PW.Lobby._Entry(facts) -> PW.EntryHints` with `facts = { singlePlayer, maxPlayers, host, p2p? }` (the client reads
`game.SinglePlayer()`, `game.MaxPlayers()`, `LocalPlayer():IsListenServerHost()` and the ConVar `p2p_enabled`; `p2p` is `nil`
when the engine does not expose it). The result is `{ hints, startReason? }`, at most one hint, in this order:

1. `singlePlayer` or `maxPlayers <= 1`: the hint `listen` ("Needs a listen server", `blocking = true`) and `startReason`
   (Start is locked with it, and it wins over every other reason).
2. The local player is the host and `p2p == false`: the hint `p2p` ("Friends cannot join yet", `blocking = false`); Start stays
   open (solo play is not affected).
3. Otherwise no hint (also for a guest, and with P2P on or unknown).

`PW.Lobby.EntryText` holds the texts (`listenTitle`, `listenText`, `listenReason`, `p2pTitle`, `p2pText`). The hub model
`PW.Lobby._Hub(input)` takes the facts as `input.entry` and returns the first hint as `hint`.

### Match flow in the lobby (T-11.10)

Pure rules in `lobby_ui/sh_flow.lua` (shared), types in `lua/privatewar/types/lobby.lua`:

| Function | Result |
| --- | --- |
| `PW.Lobby._ScreenFor(phase) -> "lobby"\|"postmatch"\|"vote"\|nil` | `LOBBY` and `PREMATCH` the lobby, `POSTMATCH` the summary, `VOTE` the vote overlay, `LIVE` none |
| `PW.Lobby._ShouldShow(phase, active, kit) -> boolean` | `_ScreenFor(phase) == "lobby"` and both modules valid |
| `PW.Lobby._StartButton(facts) -> { label, reason, seconds }?` | An announced map change: `MAP CHANGE N…`; else `PREMATCH`: `STARTING N…` (N = seconds left, rounded up, never below 0); else `nil` (the normal button) |
| `PW.Lobby._ApplyFlow(start, facts?) -> start` | Applies the override to the start action: `label` and `title`, `locked` with the reason, `countdown = true` |
| `PW.Lobby._MapTitle(map, name?) -> string` | The map data name when it differs from the file name, else the file name without a short prefix (`gm_`, `de_`) and underscores, upper case |
| `PW.Lobby._MapChangePopup(facts) -> PW.LobbyPopup?` | `{ title = "MAP CHANGE", map, mode, seconds, line = "Loading in N…" }`; `nil` without an announced change |

- `PW.Lobby.Input()` carries `flow` (`PW.LobbyFlowFacts`: phase, phase end, `CurTime()`, announced change time) and
  `PW.Lobby._Hub` applies `_ApplyFlow` to its start action, so the hub and the custom game screen show the same label.
- The hub's START button uses the `PWButton` variant `countdown` while it counts down: `bg_raised` fill, `accent` ink
  and outline (`PW.Lobby.CountdownColours`), no lock glyph, never clickable.
- The map change popup (`lobby_ui/cl_flow.lua`) paints in `PostRenderVGUI`, above every root: a dimmed screen and a
  centred card with the title, the map (`title` font), the mode name (from the modes registry) and the seconds left.
- `pw_lobby_request` and `pw_playlist_request` are accepted in `PREMATCH` too, so a lobby that opens after a map change
  gets its state.

### Known limits

- The pending Game Setup values come to the client only with `pw_lobby_state`, that is when the screen opens (and
  after the player's own accepted toggle). Changes made by another player while the screen is open are not shown.
- The `kinds` registry cannot be toggled from the lobby.
- After `pw_reload` a remote client may keep running the old `cl_init.lua` until the map changes or it reconnects
  (`core.md` "Hot reload"). On a client that does reload, an open screen is rebuilt with the new code.
- Internal: every `PW.Lobby._*` name, `PW._Lobby` (server store with injectable engine calls) and `PW.Lobby._View`
  (client screen state).

### Built-in element `hitmarker`

`lua/privatewar/hud/hitmarker.lua` (T-6.3; `09-hud.md` d.2), `Order = 20`, `Phases = { "LIVE" }`. An X of four diagonal strokes
around the crosshair that fades out linearly in `PW.Hitmarker.Duration` (0.25 s). The kind sets the look: `hit` white (token
`text`), `headshot` gold (`warning`), `kill` red (`negative`) and larger. A frame allocates nothing. `pw_hud 0` hides it.

Module `hitmarker` (`lua/privatewar/modules/hitmarker/`, global `PW.Hitmarker`): the server reads `PostEntityTakeDamage`; only a
human attacker is told, never for self-damage, and never a bot. The hits of one tick are merged (the strongest kind wins), so a
shotgun blast or an explosion is one marker. A kill is a victim that died; a headshot is `HITGROUP_HEAD` without a kill; damage
of 0 or less gives nothing.

Net message `pw_hitmarker` (server to the attacker): one `UInt(2)` kind: `1` hit, `2` headshot, `3` kill (`0` is unused). A new
message replaces the running marker and restarts the fade. No sound.

### Built-in element `spectating`

`lua/privatewar/hud/spectating.lua` (T-8.4; `08-lobby.md` d.4), `Order = 30`, no `Phases` (every phase). `ShouldDraw` is true while
the local player's NW2 bool `PW.Jip.NetBool` (`pw_spectating`, `modes.md` "Join in progress") is set, so the element causes no
network traffic. It draws the notice `PW.Jip.Notice` (`Spectating — you join next match`) at the bottom centre (design position
960, 940; font `h2` of `ui_kit`) on a `bg_panel` plate in the `text` colour. Without `PW.Jip` it draws nothing.

### Built-in element `equipment`

`lua/privatewar/hud/equipment.lua` (T-4.5; `05-loadout.md` d.11), `Order = 30`, `Phases = { "LIVE" }`. One line per held
equipment slot at the bottom right (design position: right edge 1880, lowest baseline 900, 30 units per line), above the
custom weapon panel (or native ammo fallback): the key hint in brackets, the item name and the uses left, for example
`[G] FRAG x1`. The key is the value
of the slot's client ConVar (`pw_key_lethal`, `pw_key_tactical`), so a rebind shows at once. An empty slot is not drawn; a
spent one (count 0) is drawn in `text_muted`. The data are the player's NW2 values (`equipment.md`), so the element causes
no traffic; the text of a slot is rebuilt only when its item, count or key changes. Nothing is drawn for a dead player.
`pw_hud 0` hides it.

## Screen `loadout_classes` (T-4.7)

`lua/privatewar/screens/loadout_classes.lua` (`05-loadout.md` d.12 and d.13; `10-frontend.md` d.3). `Tab = "loadout"`,
`Root = true`, `Order = 10`, `Title = "Classes"`, hints `Use class` (accept) and `Back`. It is the only screen of the
LOADOUT tab, so the tab is unlocked (without a root screen the router locks a tab with the reason `"soon"`). The data
and the net messages are in `loadout.md` "Classes"; this section is the screen.

- **Layout.** `PW.UI.Layout.Columns` with a 96-unit margin: a `PWCardList` of the classes in the left column (560 units),
  a `PWInfoCard` with the contents in the centre column.
- **Cards.** `PW.Loadout._ClassCards(state)`: the presets first, then the player's custom classes. Badge `N/A` for an
  unavailable class, else `IN USE` for the class the server holds as the pick; the card text is the reason, else
  `Removed: <list>`; the tag is `Preset` or `Custom class`.
- **Details.** The title is the class name; the rows come from `PW.Loadout._ClassRows(entry)` (slot name in capitals and
  the item names, one `<SLOT> ATTACHMENTS` row per build). Text `Removed by the server: <list>` when repair removed
  anything; a warning `Not available: <reason>` for an unavailable class (budget, attachment cap, empty after repair, a
  `PW_ValidateLoadout` rejection). Before the first state arrives it reads `Waiting for the server`; with no card
  selected, `No class selected` and `Pick a class on the left. It is used from your next spawn.`
- **Selecting.** Activating a card (click or accept) shows its details; when the class is available the screen also asks the
  server to use it (`PW.Loadout.SendPick(ref)`). The server answers with a new state, which redraws the screen through the
  view's `PWRefresh`. The pick applies from the next spawn.
- **Lost upload.** When the screen opens before any state has arrived, it sends the upload once more.

- **OPERATOR** (T-11.9). A second-row button next to NEW CLASS opens the operator picker `loadout_operator`
  (`operators.md`, "UI").

The screen decides nothing: the server repairs, checks and answers; the screen only draws the state. Editing classes is the
class editor (T-4.8, T-7.4).

## Store and progress (T-7.5)

Decisions: `design/06-progression.md` d.6, `design/10-frontend.md` d.1. Code: pure and shared `ui_kit/sh_store.lua`
(`PW.UI.Store`) and `ui_kit/sh_progress.lua` (`PW.UI.Progress`, loaded after the store: it reuses the number format and the
kind labels), both covered by the server-side test runner; client glue `ui_kit/cl_store.lua`. The data are
`PW.Economy.GetStore`, the progression wallet and file, the NW2 level values and the registries. The client decides
nothing: the server quotes every purchase again.

### `PW.UI.Store` (shared, pure)

| Function or value | Contract |
| --- | --- |
| `Currency`, `RequestTimeout`, `KindOrder` | `"CR"`; 5 seconds; `{ "models", "cards", "camos" }` (the permanent kinds listed first) |
| `FormatNumber(n)`, `PriceText(price)` | `12,345` and `12,345 CR`. The postmatch screen has its own `Postmatch.Number` with the same output |
| `KindLabel(kind, plural?)` | A display name (`Model`, `Calling cards`); an unknown kind is capitalised |
| `SecondsToRotation(now, period)` | Seconds to the next UTC midnight (`"daily"`) or the next UTC Monday (`"weekly"`) |
| `CountdownText(seconds)` | `3d 4h`, `5h 07m` or `12m 03s` |
| `OfferState(offer, facts)` | `"pending"`, `"owned"`, `"unlocked"`, `"funds"` or `"buyable"`, in the order the server's quote checks. A bundle is owned by its own key or when every item is owned. `facts` is `{ currency, owned(key), unlocked(kind, id), pending? }` |
| `OfferCards(offers, facts)` | One `PW.UICard` per offer: the badge is the price, `OWNED`, `UNLOCKED` or `...`; the footer is the state text. Cards are never locked: only BUY is |
| `Sections(view, facts, now)` | `featured` and `weekly` (with `countdown` and a note when empty), then one `kind:<kind>` section per permanent kind (`KindOrder` first, others by name). The Camos section exists only when camo offers exist |
| `SectionCards(sections)` | The left-hand list: the countdown as the badge for the rotations, the offer count for the kinds |
| `BuyButton(offer, state, currency)` | `{ label, locked, reason? }`; `funds` gives `Not enough credits: <price> needed, <held> held` |
| `NewPurchase()`, `Request(purchase, offer, state, send, now)`, `OnResult(purchase, result, name)`, `ResultText(result, name)`, `Expire(purchase, now)` | The Buy flow: one request in flight, a text for every answer (`Bought ...`, `Not enough credits ...`, `... has left the rotation`), `No answer from the server` after `RequestTimeout` |
| `Preview(kind, entity)` | `{ type = "model", path }` for a model, `{ type = "material", path }` for a calling card, else `nil` |
| `ItemViews(offer, lookup, facts)`, `ItemCards(items)` | The items of a bundle (`owned`, `unlocked` or `locked`; a camo id is `<weapon>:<camo>`) and their cards |
| `RotationOf(view, key)`, `BundleRows(offer, items, rotation, now)` | The channel of a bundle; the info rows `PRICE`, `RARITY`, `ITEMS`, `LEAVES IN` |

### `PW.UI.Progress` (shared, pure)

| Function | Contract |
| --- | --- |
| `LevelView(level, into, need)` | `{ title = "LEVEL n", xpText, fraction, maxed }` |
| `NextUnlocks(catalogue, level, limit?)` | Entities of every registry with a numeric (or `{ level = N }`) `Unlock` above the level, `Hidden` excluded; closest level first, ties by name, then kind, then id; cut to `limit` (the screen uses 8) |
| `UnlockRows(unlocks)` | `{ "LV n", "<name> (<kind>)" }` rows |
| `Weapons(weapons, xp, levelOf)` | Every registry weapon plus every class that has XP, highest level first; `levelOf(xp)` returns level, into, need |
| `WeaponCards(rows)` | Cards with `LV n`, the XP to the next level and the total XP |
| `SummaryRows(summary, nameOf?)` | The rows of the last match (`XP`, `LEVEL a > b`, weapon level gains, `MEDALS`); `nil` without a summary |

The weapon level on the PROGRESS screen is computed on the client from the XP in the local progression file.

### Client (`cl_store.lua`)

| Function | Contract |
| --- | --- |
| `Store.LiveCatalogue()`, `LiveLookup()`, `LiveFacts()` | The registries (enabled entities by `ClassName`) and the local player's balance, purchases and unlocks |
| `Store.OpenBundle(key)`, `TakeBundle()` | Pushes `store_bundle`; the details screen reads the key back |
| `Store.Buy(offer)`, `ConfirmBuy(offer, done?)` | Sends `PW.Economy.RequestBuy`; the confirm dialog shows the price and the balance after the purchase |
| `Store.Tick()` | Expires a purchase with no answer |
| `Store.UpdateCards(list, cards, selected)` | Refreshes a `PWCardList` in place when the card ids did not change (the focus survives) |

The hook `PW_EconomyResult` stores the answer and redraws the open screen through the view's `PWRefresh`. The purchase
state is kept across a reload of the file.

New vgui classes:

| Class | Contract |
| --- | --- |
| `PWStorePreview` | `SetPreview(preview, title, subtitle)`: a model through `PWOperator`, a card through its material, else the text `NO PREVIEW`; a title strip at the bottom |
| `PWProgressBar` | `SetProgress(fraction, label)`: an accent bar with a centred label |

### Store and progress screens

| Id | Tab | Role |
| --- | --- | --- |
| `store_home` | `store` (root, order 10) | Left: the balance and the sections. Centre: the offers of the selected section. Right: preview, details, DETAILS (bundles) and BUY. The countdowns and the balance refresh every second; a new UTC day rebuilds the sections without reopening |
| `store_bundle` | `store` | Items of the bundle with `OWNED` and `UNLOCKED`, a preview switch, the bundle rows with `LEAVES IN`, BUY. Esc returns to the store |
| `progress_home` | `progress` (root, order 10) | The level card and bar, next unlocks, the weapon levels, `LAST MATCH` after a match |

Keys and bindings:

- `store_home`: `accept` selects; `secondary` (F, X) opens the bundle details (Enter on a selected bundle card does the
  same); `tertiary` (R, Y) is BUY, which opens a confirm dialog (Esc cancels). `back` leaves.
- `store_bundle`: `accept` previews the selected item; `tertiary` buys the bundle; `back` returns.
- `progress_home`: `accept` shows details; `back` leaves.
- With the economy module off the store shows `The economy module is off`.

No new commands.

## Classes, editor and gunsmith screens (T-4.7, T-7.4)

Decisions: `design/05-loadout.md` d.2 to d.5, d.12, d.13, d.15; `design/10-frontend.md` d.1. Code: module `loadout_ui`
(`PW.LoadoutUI`): pure and shared `sh_names.lua`, `sh_editor.lua`, `sh_gunsmith.lua` (covered by the server-side test
runner), client glue `cl_init.lua` and the shared look `cl_widgets.lua`. The server repairs and checks every uploaded
class again; its answer is final. The `loadout_classes` screen is described in "Screen `loadout_classes` (T-4.7)"; T-7.4
adds the actions to it.

### Pure API

Names and save flow (`sh_names.lua`):

| Function | Contract |
| --- | --- |
| `NameMax` | The class name limit (`PW.Loadout.ClassNameMax`, 32 bytes) |
| `ValidateName(name, others)` | `clean, nil` or `nil, reason`. Rules: trimmed, not empty, within the limit, no control characters, unique case-insensitively among `others` |
| `FreeName(base, others)` | A free name: the base, then `base 2`, `base 3`; an empty base becomes `Class` |
| `ToFile(classes)` | The `classes.json` shape: `{ version = 1, classes = { { name, loadout } } }` |
| `_Save(classes, draft, io)` | Replaces the draft's class, then `io.write(file)` and `io.upload()`; returns the new list |
| `UploadDelay(now, last, gap)` | Seconds still to wait before the next upload |
| `SaveResult(state, ref, answered)` | `{ status, title, lines }` from the server's class state: `waiting`, `missing`, `unavailable`, `repaired`, `accepted` |
| `PickAfterDelete(selected, deleted, fallback)` | The ref to select after deleting class `deleted`: `fallback` when the pick was that class, a shifted `custom:k` for a later one, `nil` when nothing changes |
| `ClassActions(ref, count, max)` | `EDIT`, `COPY`, `RENAME`, `DELETE`, `NEW CLASS` with `locked` and `reason` (a preset cannot be edited, renamed or deleted; NEW and COPY lock at the `loadout.classes` limit) |

Editor (`sh_editor.lua`):

| Function | Contract |
| --- | --- |
| `SlotLabel(slot, index)` | The row label in capitals; `#n` is added for a slot with more than one place (for example `PERK 1 #2`) |
| `LockText(entity)` | `text, reason`: `LV n`, `STORE` or `LOCKED` |
| `Editor(input)` | `{ rows, slots, cost, meter, check? }` over the effective slot set (a perk such as Greed adds rows). Row order: weapons, equipment, perks by group, wildcards, streaks, other kinds after |
| `Options(input, row, slots)` | The choices of a row, `NONE` first. An option carries `locked`, `reason` and `lockText` (`PICKED`, `BANNED`, `LV n`, `STORE`, `LOCKED`) |
| `Budget(cost, budget)` | `{ cost, budget, state, text, fraction }`, state `ok`, `full`, `over` or `unlimited` |
| `Normalize(input, value)`, `SetItem(input, rowId, id)` | Drops what the effective slots no longer hold; sets or clears one place (`<slot>#<n>`). A new first weapon drops that weapon's build |

Gunsmith (`sh_gunsmith.lua`):

| Function | Contract |
| --- | --- |
| `Gunsmith(input)` | `{ gunsmith, title, slots, count, cap, levelCount, levelLimit, countText, over, problems, note }`. `gunsmith = false` (no slots) gives the "no gunsmith" note. Options carry `lockText` `LV n`, `FULL` or `BANNED` |
| `SetOption(build, slotId, option)` | Returns a copy of the build with one slot set or cleared |

### Client glue (`cl_init.lua`)

| Function | Contract |
| --- | --- |
| `MaxClasses()`, `ReadClasses()`, `WriteClasses(classes)` | The `loadout.classes` setting (default 10); `privatewar/classes.json` in `DATA`; write and upload |
| `LiveInput(value)`, `LiveGunsmith(draft)` | The inputs of the pure models from the registries, the progression and the lobby's match settings (budget, limits, bans; defaults when there are none) |
| `Draft` | The class being edited, shared by the editor and the gunsmith: `{ index, name, loadout, dirty, saved, focusName?, weaponSlot?, navigating? }` |
| `Edit(index, focusName?)`, `OpenGunsmith(slotId)` | Fill the draft and push `loadout_editor` or `loadout_gunsmith` |
| `Create(base, value)`, `Delete(index)` | Create a class at once (NEW and COPY); delete one and move the pick |
| `SaveDraft()`, `DraftResult()` | Write the file and upload (uploads at least 2.1 s apart); the `SaveResult` of the server's answer |

Edits are a draft: SAVE, or leaving the editor or gunsmith with unsaved changes, writes `classes.json` and uploads the
whole list.

### Widgets (`cl_widgets.lua`)

These are helpers, not vgui classes: `RowButton(parent, group, id)` (a focusable slot row; set `pwLabel`, `pwValue`,
`pwSide`, `pwProblem`, `pwChosen`), `PaintMeter(w, h, title, text, fraction, state, note?)` and `FocusLater(panel)`.

### Card field `lockText`

`PW.UICard.lockText` (`ui_kit/cl_cards.lua`): the text drawn next to the lock icon of a locked card (`LV 12`, `STORE`,
`BANNED`). A locked card with `lockText` reserves a taller collapsed area for it.

### Class screens

| Id | Tab | Role |
| --- | --- | --- |
| `loadout_classes` | `loadout` (root) | Hints: `accept` Use class, `secondary` Edit or copy (edit for a custom class, copy for a preset), `tertiary` New class. Action buttons EDIT, COPY, RENAME, DELETE (with a confirm dialog), NEW CLASS |
| `loadout_editor` | `loadout` | A name field (RENAME focuses it; Enter applies), the budget meter, a row per slot item, the option list with `lockText`, the server's answer after SAVE. `secondary` opens the gunsmith, `tertiary` saves, `back` leaves and saves |
| `loadout_gunsmith` | `loadout` | Slots and options, the attachment counter against the limit, problems. `tertiary` saves, `back` leaves and saves |

No new commands.

## Postmatch summary (T-7.7)

Decisions: `design/08-lobby.md` d.4, d.5; `design/10-frontend.md` d.1 POSTMATCH. Code: pure and shared
`ui_kit/sh_postmatch.lua` (`PW.UI.Postmatch`, covered by the server-side test runner), client glue
`ui_kit/cl_postmatch.lua`, screen `screens/postmatch.lua`.

### `PW.UI.Postmatch` (shared, pure)

| Function or value | Contract |
| --- | --- |
| `RootId`, `Tab`, `Titles`, `Tokens` | `"postmatch"`, `"summary"`; the banner texts (`VICTORY`, `DEFEAT`, `DRAW`, `MATCH OVER`) and the style token of each |
| `Ordinal(n)`, `Number(n)` | `1ST`, `12TH`; `12,345`. `Number` duplicates `Store.FormatNumber` (it also handles negatives) |
| `Placement(rows, ownId)` | `place, total` by kills, spectators excluded; ties share a place; `nil, total` when the player is not listed |
| `Result(facts)` | The banner: kind, title, token and detail text (team score `own : best other`, or `NTH OF M` in FFA). In FFA only the winner gets VICTORY |
| `Board(rows, opts)` | Sections: teams by score (own row flagged, bots tagged), or one `PLAYERS` section for FFA. Rows are sorted by score (kills in FFA), then the other keys, then name, then id |
| `LevelSteps(input, needOf)` | The bar segments from the level before to the level after, the start computed backwards from the XP curve |
| `BarAt(steps, elapsed, timing)` | `{ level, fraction, levelUps, done }`; each step lasts `min(stepTime, maxTime / steps)`, so the animation takes at most `maxTime` after `delay` (the screen uses 0.9, 5 and 0.6 s) |
| `Medals(list, order, nameOf?)` | Sorted by count, then by the `PW.Medals.Ids` order, then id; the name falls back to the id (no language file yet) |
| `Weapons(list, nameOf?)` | Weapon level gains, biggest gain first, then name |
| `Earned(start, now)` | The currency earned since the baseline, never below 0 |
| `Decide(event, facts)` | `"open"`, `"close"`, `"refresh"` or `nil` from the event (`phase`, `summary`, `tick`) and the facts (phase, enabled, open, otherRoot, dismissed) |

Client (`cl_postmatch.lua`): `Postmatch.Gather()` builds the data from the engine; `EarnedNow()`; `Pause()` opens the
pause menu from the summary; `PW.UI.OpenPostmatch()` opens the root. Deaths count from the moment the match went LIVE
(the engine counter is not reset between matches) and the currency is the wallet difference since LIVE; both baselines
are taken at the `LIVE` phase.

Additive presentation extensions (API 1): `PW_PostmatchGathered(data: PW.UIPostmatchData, ownId: integer)`
is a client notification exactly once at the end of every Gather, including progression-disabled and
summary-pending paths. Listeners return nothing and may replace presentation result/sections/subtitle or
metric fields from authoritative received data; they do not award score, XP or currency. Missing/disabled
listeners preserve ordinary presentation. `data.scoreLabel` is optional; nil keeps the `SCORE` column label.

An extension receiving late authoritative data may notify `PW_PostmatchDataChanged()`. The client rebuilds
only an enabled, currently open POSTMATCH root. It never opens a dismissed root, replaces another root,
rebuilds outside POSTMATCH, or gathers every frame. Integration tests execute the actual client Gather
and event handlers in an isolated engine boundary: `ui_postmatch_extension.lua`.

### Behaviour

- The root (kind `postmatch`, one tab SUMMARY) opens at the `POSTMATCH` phase (replacing a pause menu or class picker)
  and when `PW_ProgressionSummary` arrives; any other phase closes it, so the vote overlay takes over at VOTE. A player
  who joins during POSTMATCH sees the summary without the XP part.
- Esc closes it and it stays closed until POSTMATCH ends; the next Esc opens the pause menu. Start (F2) opens the pause
  menu; closing that menu brings the summary back.
- A 0.25 s timer applies `Decide` again to catch missed events and reloads.

### Screen `postmatch`

`Tab = "summary"`, `Root = true`. Hints: `down` Scroll, `accept` Skip (ends the XP animation), `settings` Match menu,
`back` Close. Up and Down scroll the board; PgUp and PgDn scroll a page. The tab bar holds the single tab SUMMARY and the
Q/E hints are shown with it. Layout: the result banner, the scoreboard, the level bar with a `LEVEL UP` badge, the
currency earned, weapon levels and medals.

### Command

| Command | Contract |
| --- | --- |
| `pw_ui_postmatch` | Closes the summary when it is open; in POSTMATCH opens it again (also after a dismissal) |

## Settings screen (T-7.2)

Decisions: `design/10-frontend.md` d.1 and d.8, `design/01-extensibility.md` d.17. Code: pure and shared
`ui_kit/sh_forms.lua` (`PW.UI.Settings`, covered by the server-side test runner), client glue `screens/settings.lua`,
types `types/ui_settings.lua`. The Game Setup form of the lobby stays in `screens/lobby_custom.lua` (PLAY > Custom
game). The server validates and clamps every value again and checks the privilege and the phase; the client only
decides what the player can try.

### `PW.UI.Settings`

| Function | Contract |
| --- | --- |
| `Model(scope, groups, opts) -> PW.UISettingsModel` | The form model of one scope (`client`, `server` or `match`): one section per owner (rows from `PW.UI.BuildForm`), values clamped through the core validation, `editable` and `reason` from `Editable`, `target` from `Target`. `opts` is `{ titles?, facts }` |
| `Clamp(def, value) -> stored?, note?` | `PW.Settings._Validate` of one value: the stored value (`note` is `"clamped"` when it was clamped), or `nil` and the reason when the value is invalid |
| `Editable(scope, facts) -> boolean, reason?` | `client`: always. `server`: needs the privilege (`facts.canChange`). `match`: needs the privilege and `facts.phase == "LOBBY"`. The reason is one of `Reasons` |
| `Target(scope) -> target` | `"local"` (`PW.Settings.Set`) for `client`, `"pw_settings_server"` for `server`, `"pw_settings_match"` for `match` |
| `Diff(model, edits) -> PW.UISettingsChange[]` | `edits` maps a full id to a value. Returns only valid values whose text form differs from the current one, sorted by id; empty for a read-only model |
| `Apply(model, changes)` | Records written changes as the current values (the diff baseline) |
| `Sections(facts) -> PW.UICard[]` | The three cards: Personal (always usable), Host (locked without the privilege), Enabled content (locked without `canToggle`, or outside `LOBBY`) |
| `Open(model, section) -> boolean` | Pushes the `settings` screen on the active tab and asks for `section` (`client`, `server` or `content`). `false` when the screen is unknown, the tab is empty or the screen is already on top |
| `TakeSection() -> section?` | The section asked for by the last `Open`, read once |
| `Reasons` | `privilege` ("Only the host can change these"), `phase` ("Match settings change in the lobby only"), `content` ("The host turns content on and off in the lobby") |

`PW.UISettingsFacts` is `{ phase, canChange, canToggle? }`.

### Screen `settings`

`Tab = "play"`, `Title = "Settings"`, pushed (not a tab: SETTINGS is a hint-bar action, `10-frontend.md` d.8); Back
returns to the screen below. Left: a `PWCardList` of `Sections`. Centre: the form generated from the schema of the
section's scope. Right: a `PWInfoCard` with what the section changes and, when it is read only, why.

| Section | Content |
| --- | --- |
| Personal (`client`) | The `client` scope settings (for example button hints), saved on this computer through `PW.Settings.Set` and used at once |
| Host (`server`) | The `server` scope settings, sent as `pw_settings_server` (privilege `pw.settings.change`). Groups are headed by the owner's name (BOTS, ECONOMY, LOADOUT, ...). A guest sees the form read only with the reason |
| Enabled content | Not a form: choosing it opens the lobby's toggles (`PW.Lobby.OpenCustom("content")`, Custom game > ENABLED CONTENT). Locked with a reason in a match |

A change is applied without a button: the control reports its value through `OnChange` once it has stayed unchanged for
0.3 s (a slider fires on every pixel), and the screen writes the `Diff` of that one edit. A rejected local value is
printed as `[PW] setting <id> not saved: <note>`.

### Opening

| Trigger | Result |
| --- | --- |
| F2 / Start (action `settings`) on a full-screen root | `PWRoot:Act` calls `Settings.Open(model, "client")` unless a modal is open or the root is compact (the pause menu and the death picker use their own item) |
| Pause menu item `SETTINGS` | The same call on the MATCH tab; Back returns to the pause menu |

No new commands.

## Operator (U-9)

Decisions: `design/10-frontend.md` d.6, `notes/16-frontend-d1-proposal.md` Q4. Code: pure and shared
`ui_kit/sh_operator.lua` (covered by the server-side test runner), client glue `ui_kit/cl_operator.lua`; types
`lua/privatewar/types/ui_operator.lua`. The hub shows it in its centre column. The weapon in hand comes after CP-3
(T-7.3).

| Function | Contract |
| --- | --- |
| `PW.UI.Operator.FramingDistance(mins, maxs, fov, aspect?) -> number` | The camera distance from the model centre at which the bounding sphere fits the view: `radius / tan(fov / 2) * Margin` (`Margin` 1.25; the FOV is horizontal, so for a panel wider than tall the half-tangent is divided by `aspect`) |
| `PW.UI.Operator.Frame(mins, maxs, fov, aspect?) -> PW.UIOperatorFrame` | `{ dist, lookAt, camPos }`: `lookAt` is the centre of the bounds, the camera sits `CameraPitch` (6) degrees above it |
| `PW.UI.Operator.ChooseModel(path, isValid) -> string, boolean` | The wanted model when it is a `models/...mdl` path that is not `models/error.mdl` and passes `isValid`, else `FallbackModel` (`models/player/kleiner.mdl`); the second result says the fallback was used |
| `PW.UI.Operator.ChooseSequence(lookup) -> integer?` | The id of the first sequence of `IdleSequences` (`idle_all_01`, `idle_all_02`, `idle_all`, `idle`) that `lookup` knows (`-1` means unknown), else `nil` |
| `PW.UI.Operator.Lights(style) -> PW.UIOperatorRig` | The light rig from the style tokens: `ambient` and four directional lights: `key` (front, the text colour), `fill` (left, a soft white, 0.7), `rim` (behind, the accent) and `top` (0.6). `ambient` is the text colour at 0.55. `dir` is the `DModelPanel` box direction |

`PWOperator` (client, a `DModelPanel` subclass): the local player's operator (`PW.Operators.LocalModel()` when the
operators module is loaded, T-11.9; else `LocalPlayer():GetModel()`; through `ChooseModel`) in the first known idle sequence, field of view 30, framed from the entity's render bounds and re-framed
when the panel's aspect changes, lit by `Lights` (the default `DModelPanel` lights are switched off). It paints nothing
itself, so the blurred backdrop of `PWRoot` shows around the model. The model sways slowly (14 degrees around a base yaw
of 28, 0.35 rad/s). `SetOperatorModel(path?)` shows another model; `ShowLocal()` shows the local operator again. The preview entity copies the local player's player colour, and its skin and bodygroups while the player wears the same model (a `DModelPanel` entity has no `GetPlayerColor`, so the player colour proxy would tint the model almost black). Not yet verified on the Deck (the local manual checklist (not published), section 12).

## Vote screen (`vote`)

Client part of the module `vote` (`lua/privatewar/modules/vote/`: `cl_init.lua` the overlay, `sh_cards.lua` the pure models;
T-2.13, restyled in U-7; `design/08-lobby.md` d.5, `design/10-frontend.md` VOTE). Messages, rules and the wire format: `modes.md`
"Vote module". The client decides nothing: the server checks every vote and pick again.

It is an **overlay, not a router screen**: a full-screen popup panel of its own (`EditablePanel`, keyboard input on), opened
when `PW_PhaseChanged` reports `VOTE` (and when a `pw_vote_state` arrives while it is closed) and closed on any other phase. It
needs `ui_kit` and the `vote` module valid; otherwise it does not open (a disabled module also drops its messages, `core.md`
"Client messages").

- On open the client sends `pw_vote_request` and redraws on every `pw_vote_state`.
- Layout: the title `VOTE FOR THE NEXT MATCH`, the turnout `N/M voted` (votes over humans) and the timer `m:ss` on the right
  (warning colour in the last 10 s) in the header; one `PWVoteCard` per option in a centred row; the hint bar at the bottom.
- `PWVoteCard` (`ui_kit/cl_vote.lua`, a focusable `PWButton`, data from `PW.Vote._Cards`): the map thumbnail
  (`maps/thumb/<map>.png`, else the map name and `NO PREVIEW`), the mode monogram and name, the map, the vote count, and on the
  card of the own vote a `YOUR VOTE` badge and an accent outline.
- Input: Left and Right move the focus (wrapping); Enter (`accept`) or a click votes (`pw_vote_cast`, the 1-based index); a
  new vote replaces the previous one.
- **Pick myself** (`08-lobby.md` d.5): a secondary button and the hint `Pick myself` (F, `secondary`), only for a player with
  `canPick` (`pw.vote.pick`) **and** when the map picker can run. The picker needs the lobby's mode and map lists, which the
  client has only after the lobby screen has received its state in this session (`PW.Lobby._View.state`). A host who joined
  mid-match and never opened the lobby does not get the button (known limitation). F opens the picker in pick mode
  (`PW.Lobby.OpenPicker({ pick = ... })`, "Map picker (U-6)") on a `PWRoot` over the overlay; Enter sends `pw_vote_pick` (mode
  id, map) and closes the root; Esc returns to the overlay.
- A reload (`pw_reload`) closes an open overlay and opens it again one tick later.

| Function | Contract |
| --- | --- |
| `PW.Vote._Screen(state, opts) -> PW.VoteScreen` | Pure, shared. `opts = { remaining?, humans?, shortOf?, pickReady? }`. The screen model: `title`, `cards`, `turnout`, `timer`, `pick = { visible, label }` (`visible` = `state.canPick` and `pickReady ~= false`) and `hints` (Previous, Next, Vote, and Pick myself when visible) |
| `PW.Vote._Cards(state, opts) -> PW.VoteCard[]` | Pure. One card per option: `index`, `mode`, `modeName`, `map`, `votes`, `badge` (the monogram), `thumb` (path or `nil`), `mine` |
| `PW.Vote._Turnout(state, humans) -> PW.VoteTurnout` | Pure. `{ voted, total, text }`, `text` is `N/M voted` |
| `PW.Vote._Timer(remaining?) -> { text, warning }` | Pure. `m:ss` text; `warning` when the whole seconds left are 10 or fewer; empty text without a time |
