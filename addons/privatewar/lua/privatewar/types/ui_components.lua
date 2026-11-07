---@meta
-- Types of the kit v1 component models (U-4, notes/16-frontend-d1-proposal.md §3; 10-frontend.md d.3, d.9, d.10).
-- Source: lua/privatewar/modules/ui_kit/ (sh_models.lua, sh_players.lua: pure; cl_*.lua: the vgui classes).

---One card of a card list (playlist, lobby action, ...).
---@class PW.UICard
---@field id string
---@field title string
---@field text? string description shown while expanded
---@field tags? string tag line shown while expanded (modes, ...)
---@field footer? string small line at the bottom while expanded ("fills to 12")
---@field badge? string short text at the right edge of the title (glyph-free, e.g. "x2")
---@field new? boolean shows the "NEW" badge
---@field locked? boolean focusable, not selectable; shows the lock glyph
---@field reason? string why it is locked (hint bar)
---@field lockText? string short text drawn left of the lock glyph of a locked card ("LV 12"; T-7.4)
---@field disabled? boolean skipped by focus, not selectable

---A card with its state in the list.
---@class PW.UICardView
---@field id string
---@field card PW.UICard
---@field selected boolean
---@field expanded boolean the selected card is the expanded one
---@field new boolean
---@field locked boolean
---@field disabled boolean
---@field reason? string

---@class PW.UICardsLib
---Card states for a selection: the selected card (if it exists) is the only expanded one.
---@field View fun(cards: PW.UICard[], selected?: string): PW.UICardView[]
---Id of the expanded card: the selected one when it is in the list, else nil.
---@field Expanded fun(cards: PW.UICard[], selected?: string): string?
---New selection after activating id: id when it exists and is neither locked nor disabled, else current.
---@field Select fun(cards: PW.UICard[], current?: string, id: string): string?

---@class PW.UIPagerState
---@field page integer 1-based page of the focused row
---@field pages integer at least 1
---@field first integer first row index of the page
---@field last integer last row index of the page (0 for an empty list)
---@field atStart boolean
---@field atEnd boolean

---@class PW.UIPagerLib
---Rows that fit a height: floor((height + gap) / (rowHeight + gap)), at least 1.
---@field RowsPerPage fun(height: number, rowHeight: number, gap?: number): integer
---Page of the focused row (index clamped to the list) and the row range of that page.
---@field State fun(count: integer, perPage: integer, index: integer): PW.UIPagerState

---@class PW.UISeenLib
---True when the key is not in the seen-set.
---@field IsNew fun(seen: table<string, true>, key: string): boolean
---Adds the key; true when it was new.
---@field Mark fun(seen: table<string, true>, key: string): boolean

---One tab of the tab bar.
---@class PW.UITabItem
---@field id string
---@field label string
---@field active boolean
---@field locked boolean
---@field reason? string
---@field new boolean unlocked and not in the seen-set

---@class PW.UITabsLib
---Key of a tab in the seen-set ("tab:<id>").
---@field SeenKey fun(id: string): string
---Tab bar items from the router tabs, the active id and the seen-set.
---@field Items fun(tabs: PW.UIRouterTab[], active: string, seen: table<string, true>): PW.UITabItem[]

---A player as the player list sees it (plain data; client glue fills it from player.GetAll()).
---@class PW.UIPlayerInfo
---@field name string
---@field bot? boolean
---@field host? boolean listen server host
---@field team? integer

---@class PW.UIPlayerListOptions
---@field phase PW.PhaseName
---@field teams? { id: integer, name: string }[] active teams in display order (PW.Teams.GetActive)
---@field localTeam? integer team of the local player; colours are relative to it
---@field maxPlayers? integer
---@field botsFill? integer bots.fill target: before the match the bot row shows fill - humans

---@alias PW.UITeamRelation "friendly"|"enemy"|"neutral"

---One section of the player list: humans listed, bots collapsed.
---@class PW.UIPlayerSection
---@field id string "party", "players" or "team<id>"
---@field title string
---@field relation PW.UITeamRelation
---@field rows PW.UIPlayerInfo[] humans, host first, then by name
---@field humans integer
---@field capacity? integer max players (PARTY only)
---@field bots integer
---@field botsText? string "+N bots" (nil when there are none)

---@class PW.UIStatusInfo
---@field phase string
---@field remaining? number seconds left in the phase (nil or negative: no timer)
---@field humans integer
---@field maxPlayers integer
---@field note? string "waiting for host"

---@class PW.UIStatus
---@field text string
---@field warning boolean the timer is in its last 10 seconds

---One action of the hint bar.
---@class PW.UIHintEntry
---@field action string input action (PW.UI.Input.Actions)
---@field label string

---A hint ready to draw.
---@class PW.UIHintItem
---@field label string
---@field cap string key cap or pad badge text
---@field device "keyboard"|"controller"

---@class PW.UIModeLike
---@field Name? string
---@field Short? string

---@class PW.UILib
---@field Cards? PW.UICardsLib
---@field Pager? PW.UIPagerLib
---@field Seen? PW.UISeenLib
---@field Tabs? PW.UITabsLib
---Pure: player list sections (LOBBY: one PARTY section; later phases: one section per team).
---@field PlayerList fun(players: PW.UIPlayerInfo[], opts: PW.UIPlayerListOptions): PW.UIPlayerSection[]
---Pure: badge text of a mode: MODE.Short (upper case), else the initials of Name (at most 3), else "?".
---@field Monogram fun(mode: PW.UIModeLike): string
---Pure: seconds as M:SS (rounded up, never negative).
---@field FormatTime fun(seconds: number): string
---Pure: the top status line.
---@field Status fun(info: PW.UIStatusInfo): PW.UIStatus
---Pure: the text of a lock reason ("soon" -> "Coming soon", "error", "locked"); other text is returned as is.
---@field LockReason fun(reason?: string): string
---Pure: hint bar items for the current device (override: the ui_kit hints setting).
---@field Hints fun(state: PW.UIInputState, entries: PW.UIHintEntry[], override?: string): PW.UIHintItem[]
