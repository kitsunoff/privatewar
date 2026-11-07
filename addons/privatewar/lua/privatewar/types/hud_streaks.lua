---@meta
-- Types of the killstreak HUD element (T-4.6 redesign: three squares and a progress bar; 05-loadout.md d.9).
-- Source: lua/privatewar/modules/hud/sh_streaks.lua (pure rules), lua/privatewar/hud/streaks.lua (the element).

---The state of one streak square: "locked" (the counter is below its cost and none is held: dim), "spent" (the
---counter passed its cost but none is held, it was used: dim), "ready" (held in the inventory, not selected: lit)
---and "selected" (held and selected for the use key: highlighted).
---@alias PW.StreakSquareState "locked"|"spent"|"ready"|"selected"

---One square of the streak element, cheapest first (index 1 is the bottom square).
---@class PW.StreakSquare
---@field id string
---@field cost integer
---@field state PW.StreakSquareState
---@field held integer copies of the streak in the inventory

---What the squares are built from: the client's NW2 values and the selection.
---@class PW.StreakView
---@field set PW.StreakSetEntry[] the streak set (any order)
---@field progress number the counter
---@field inventory string[] held ids, oldest first
---@field selected integer the selected inventory index (PW.Streaks.Selected)

---What the key hints are built from.
---@class PW.StreakHintKeys
---@field hints string the Button hints setting ("auto", "keyboard", "gamepad")
---@field pad boolean the gamepad d-pad setting is on
---@field use string the keyboard key of the use action ("5")
---@field next string the keyboard key of the next action ("6")

---Layout of the streak element in design units (1920x1080).
---@class PW.StreakHudConfig
---@field right number right edge of the squares
---@field bottom number bottom edge of the lowest square
---@field size number side of a square
---@field gap number vertical gap between squares
---@field bar number width of the progress bar
---@field barGap number gap between the bar and the squares
---@field max integer squares drawn at most (the three streak slots)
---@field short table<string, string> short labels of known streak ids

---@class PW.HudLib
---Layout of the streak element.
---@field Streaks PW.StreakHudConfig
---Pure: fills out[1..count] with the squares of the set (cheapest first by cost, then id; at most Streaks.max) and
---their states; returns the count. Entries of `out` are reused; entries past the count are cleared.
---@field _StreakSquares fun(view: PW.StreakView, out: PW.StreakSquare[]): integer
---Pure: the distance from the bottom edge of the lowest square to the centre of square `index`.
---@field _StreakAnchor fun(index: integer, size: number, gap: number): number
---Pure: how far the bar is filled (0..1). The bar runs from the bottom edge of the lowest square (counter 0) to the
---centre of the top square; it reaches the centre of a square exactly at that square's cost and is linear between
---two squares. Past the last cost it stays full (the counter does not loop). `cfg` gives size and gap.
---@field _StreakFill fun(squares: PW.StreakSquare[], count: integer, progress: number, cfg: PW.StreakHudConfig): number
---Pure: the key hint of a square: the use key on the selected one, the next key on the other held ones, "" else.
---Hints "gamepad" with the d-pad on gives the d-pad glyph (PW.UI.Gamepad.Glyph), otherwise the keyboard key.
---@field _StreakHint fun(state: PW.StreakSquareState, keys: PW.StreakHintKeys): string
---Pure: the short label of a streak: the known abbreviation of the id, else the first 4 letters of the name.
---@field _StreakShort fun(id: string, name: string?): string
---Pure: the selected inventory id when no square shows it (a streak earned before a class change), else nil.
---@field _StreakOrphan fun(squares: PW.StreakSquare[], count: integer, view: PW.StreakView): string?
