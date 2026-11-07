---@meta
-- Types of the router (U-3, notes/16-frontend-d1-proposal.md Q1; 10-frontend.md d.1, d.8).
-- Source: lua/privatewar/modules/ui_kit/ (sh_router.lua: pure stacks and tabs; cl_root.lua: PWRoot). Pure and shared.

---A screen of the screens kind. Build(ctx) returns the view (a panel on the client; any non-nil value in tests);
---nil, or an error, makes the router skip the screen.
---@class PW.Screen : PW.Entity
---Id of its tab: a hub tab ("play", "loadout", "progress", "store") or an in-match one ("match", "class").
---@field Tab string
---@field Build fun(self: PW.Screen, ctx: table): any
---@field Root? boolean root screen of its tab (the lowest Order wins)
---@field Order? number among root candidates (default 100)
---@field Title? string
---Actions of the hint bar while the screen is on top (default: Select, Back). Actions the router and the focus
---graph do not use reach the view's OnAction(action).
---@field Hints? PW.UIHintEntry[]
---The screen uses Q and E itself: the router does not cycle the tabs, the keys reach the view's OnAction.
---@field OwnsTabKeys? boolean

---@class PW.UIRouterTab
---@field id string
---@field label string
---@field locked boolean
---@field reason? string why it is locked ("soon" when no root screen is registered, "error" after a failed Build)
---@field root? PW.Screen

---@class PW.UIRouterModel
---@field tabs PW.UIRouterTab[]
---@field tabById table<string, PW.UIRouterTab>
---@field stacks table<string, PW.Screen[]> one stack per tab, root first
---@field screens table<string, PW.Screen> by ClassName, for Push by id
---@field active string id of the current tab

---@alias PW.UIBackResult "pop"|"stay"|"close"
---@alias PW.UIRouterResult "tab"|"pop"|"stay"|"close"

---@class PW.UIRouterLib
---@field TabOrder string[]
---@field TabLabels table<string, string>
---New model from the screens list (registry enabled list) over a tab set (default TabOrder, the hub tabs). Tabs
---without a root screen start locked.
---@field New fun(screens: PW.Screen[], tabs?: string[]): PW.UIRouterModel
---@field Top fun(model: PW.UIRouterModel): PW.Screen?
---Depth of the active tab's stack.
---@field Depth fun(model: PW.UIRouterModel): integer
---Push a screen (table or ClassName) on the active tab. False when it is unknown or the tab is empty.
---@field Push fun(model: PW.UIRouterModel, screen: PW.Screen|string): boolean
---Pop the active tab's stack; the root is never popped. False when nothing was popped.
---@field Pop fun(model: PW.UIRouterModel): boolean
---Replace the top screen of the active tab.
---@field Replace fun(model: PW.UIRouterModel, screen: PW.Screen|string): boolean
---Switch to a tab by id. False for an unknown or locked tab; stacks are kept.
---@field SwitchTab fun(model: PW.UIRouterModel, id: string): boolean
---Switch to the next (delta 1) or previous (-1) unlocked tab, wrapping. False when there is no other tab.
---@field Cycle fun(model: PW.UIRouterModel, delta: integer): boolean
---Lock or unlock a tab; locking the active tab moves to the first unlocked one.
---@field SetLocked fun(model: PW.UIRouterModel, id: string, locked: boolean, reason?: string)
---Back: pops above the root; at a root stays in LOBBY and asks to close the root in any other phase.
---@field Back fun(model: PW.UIRouterModel, phase: PW.PhaseName): PW.UIBackResult
---Router result of an input action (tab_prev, tab_next, back); nil when the router does not handle it.
---@field Act fun(model: PW.UIRouterModel, action: string, phase: PW.PhaseName): PW.UIRouterResult?
---Builds the top screen through PW.Call. A screen whose Build fails is dropped (a root locks its tab) and the next
---one is tried. Returns the view and its screen; nil when nothing can be built.
---@field Build fun(model: PW.UIRouterModel, ctx: table): any, PW.Screen?

---@class PW.UILib
---@field Router? PW.UIRouterLib
---Client only (cl_root.lua): opens the root panel (one at a time) and builds the first screen.
---@field OpenRoot? fun(opts?: PW.UIRootOptions): Panel
---@field CloseRoot? fun()
---@field RootOpen? fun(): boolean

---Class table inside a screens/ file.
---@type PW.Screen
SCREEN = nil
