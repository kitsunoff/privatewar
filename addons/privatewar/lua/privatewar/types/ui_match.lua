---@meta
-- Types of the in-match menus (T-7.6; 10-frontend.md d.1, d.7): the death class picker and the pause menu.
-- Source: lua/privatewar/modules/ui_kit/sh_match.lua (pure, shared) and cl_match.lua (client glue); screens
-- lua/privatewar/screens/match_pause.lua and match_classes.lua.

---@alias PW.UIPauseItemId "resume"|"class"|"settings"|"lobby"|"leave"|"gmod"

---One entry of the pause menu.
---@class PW.UIPauseItem
---@field id PW.UIPauseItemId
---@field label string
---@field variant? "primary"|"secondary"|"danger"
---@field locked boolean focusable, does nothing; reason in the hint bar
---@field reason? string a lock reason (PW.UI.LockReason text or key)
---@field confirm? string text of the confirmation dialog (items that end or leave the match)

---What the pause items depend on.
---@class PW.UIPauseFacts
---@field phase PW.PhaseName
---@field canAbort boolean the local player may end the match (pw_abort; the server checks again)
---@field classes boolean the loadout module and its class state are present
---@field host boolean the local player is the listen server host (leaving closes the server)

---What Escape (or gamepad Start) should do.
---"pause": open the pause menu; "root": one of our menus is open, it handles Back; "leave": the lobby hub is open at
---its root screen, Escape opens the leave dialog (through the root's Back); "engine": the GMod menu.
---@alias PW.UIEscapeResult "pause"|"root"|"leave"|"engine"

---Where Back lands in an open root.
---@class PW.UIRootBackFacts
---@field phase PW.PhaseName
---@field rootId? string the kind of the open root (PWRoot.rootId)
---@field depth? integer the screen stack depth of the active tab (1: the tab's root screen)

---The leave dialog of the lobby (PW.UIDialogSpec with a third button).
---@class PW.UILobbyLeaveSpec
---@field title string
---@field text string the host is warned that leaving closes the server for everyone
---@field confirm string
---@field alt string
---@field cancel string

---@class PW.UIEscapeFacts
---@field phase PW.PhaseName
---@field enabled boolean ui_kit valid and the client setting pausemenu on
---@field rootOpen boolean a PWRoot is open
---@field gameUI boolean the GMod menu is already shown
---@field bypass boolean Shift is held, or the GMod MENU item asked for the engine menu
---@field rootId? string the kind of the open root (PWRoot.rootId)
---@field depth? integer the screen stack depth of the open root's active tab
---@field modal? boolean the open root shows a modal dialog (Back cancels it)

---@class PW.UIDeathFacts
---@field alive boolean the local player is alive
---@field phase PW.PhaseName
---@field enabled boolean ui_kit valid, the loadout module present and the client setting deathpicker on
---@field open boolean the death picker is open
---@field otherRoot boolean another PWRoot (the pause menu, the lobby) is open

---@class PW.UIDeathMemory
---@field alive? boolean the last sample (nil before the first)

---@alias PW.UIChooseResult "sent"|"current"|"locked"|"unknown"

---@class PW.UIMatchLib
---Phases in which Escape opens the pause menu.
---@field PausePhases table<string, true>
---@field LeaveHostText string
---@field LeaveGuestText string
---@field LobbyText string
---@field LobbyGuestText string
---Cards of the human class picker (custom classes then visible presets, stable within each category) and the current
---class (nil when none). The current card carries the badge CURRENT; an unavailable one is locked with its reason.
---@field ClassCards fun(state?: PW.LoadoutClassState): PW.UICard[], string?
---Asks for a class: an available class other than the current one is sent through send(ref).
---@field Choose fun(state?: PW.LoadoutClassState, ref: string, send: fun(ref: string)): PW.UIChooseResult
---The pause menu items for a phase and the local player's privileges, in display order.
---@field PauseItems fun(facts: PW.UIPauseFacts): PW.UIPauseItem[]
---What Escape does now.
---@field Escape fun(facts: PW.UIEscapeFacts): PW.UIEscapeResult
---What Back (Esc, Backspace, gamepad B) does in an open root without a modal: "leave" at the root screen of the
---lobby hub (LOBBY, root "hub", depth 1), else "router" (pop a pushed screen, or the router's own rule).
---@field RootBack fun(facts: PW.UIRootBackFacts): "leave"|"router"
---The leave dialog of the lobby: LEAVE GAME, GMOD MENU, CANCEL.
---@field LobbyLeave fun(host: boolean): PW.UILobbyLeaveSpec
---@field NewDeathMemory fun(): PW.UIDeathMemory
---One sample of the death watcher: "open" on a death in LIVE, "close" on respawn or when LIVE ends, else nil.
---@field DeathStep fun(memory: PW.UIDeathMemory, facts: PW.UIDeathFacts): "open"|"close"|nil

---@class PW.UIRootOptions
---@field id? string the kind of root ("hub" by default); OpenRoot replaces an open root of another kind
---@field tabs? string[] the router tab set (default the hub tabs)
---@field compact? boolean no backdrop, title, status or tab bar: the content is a panel at the right edge
---@field onClose? fun() called when the root is removed

---@class PW.UILib
---@field Match? PW.UIMatchLib
---Client (cl_match.lua): opens the pause menu (a PWRoot with the tabs MATCH and LOADOUT).
---@field OpenPause? fun(): boolean
---Client: opens the compact class picker (a PWRoot over the tab CLASS). The pause menu pushes the same screen.
---@field OpenClassPicker? fun(): boolean
---Client: shows the GMod menu (the Escape fallback); closes the open root unless keepRoot.
---@field ShowGameMenu? fun(keepRoot?: boolean)
---Client: opens the lobby's leave dialog in the open root (Back at the lobby hub root).
---@field OpenLobbyLeave? fun()
