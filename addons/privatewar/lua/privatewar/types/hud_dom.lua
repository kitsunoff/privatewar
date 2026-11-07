---@meta
-- Types of the Domination points element (T-6.5, 09-hud.md d.2). Source: lua/privatewar/modules/dom_flags/sh_hud.lua
-- (pure rules), lua/privatewar/hud/dom.lua (the element).

---One flag as the client reads it from the flag entity's network vars.
---@class PW.DomFlagView
---@field letter string
---@field value number the capture scalar in [-100, 100]
---@field owner integer 0 = nobody, else the owning team index
---@field contested boolean both teams inside with equal counts (published by the mode)

---What to draw for one flag, relative to the local team.
---@class PW.DomFlagDisplay
---@field letter string
---@field relation "friendly"|"enemy"|"neutral" the owner relative to the local team
---@field token string style token of the owner colour
---@field lean "friendly"|"enemy"|"none" the side the capture scalar points to
---@field leanToken string style token of the lean colour
---@field progress number 0..1, the distance of the scalar from 0
---@field capturing boolean the scalar is in flux (not untouched, not settled at the owner's end)
---@field contested boolean

---@class PW.DomFlagsHudConfig
---@field top number design units, the top edge of the row
---@field tile number design units, the side of one letter tile
---@field gap number design units between tiles
---@field bar number design units, the height of the progress bar

---@class PW.DomFlagsLib
---Pure: whether the element is visible given the number of flags that exist (they exist only in Domination).
---@field _Visible fun(flagCount: integer): boolean
---Pure: fills out with the display state of a flag for the local team (1 or 2; anything else reads team 1 as friendly).
---@field _Display fun(flag: PW.DomFlagView, team: integer, out: PW.DomFlagDisplay)
---Pure: a new display record (neutral, no progress) for the caller to reuse with _Display.
---@field _NewDisplay fun(letter?: string): PW.DomFlagDisplay
---Pure: sorts the first count displays by letter in place.
---@field _OrderDisplays fun(list: PW.DomFlagDisplay[], count: integer)
---Element layout constants.
---@field Hud PW.DomFlagsHudConfig

---@class PW.DomMode
---Internal, pure: both teams inside with equal counts (the point does not move because of a tie).
---@field _Contested fun(plus: integer, minus: integer): boolean
