---@meta

---@class PW.UIBoardLine
---@field header boolean
---@field title string
---@field score string
---@field place string
---@field kills string
---@field deaths string
---@field me boolean
---@field bot boolean
---@field relation PW.UIBoardRelation

---@class PW.UIBoardLib
---@field Lines fun(sections: PW.UIBoardSection[]): PW.UIBoardLine[]
---@field Height fun(lines: PW.UIBoardLine[]): number design units
---@field Fit fun(text: string, width: number, measure: fun(text: string): number): string UTF-8 safe, layout only

---@class PWMatchBoard : Panel
---@field SetSections fun(self: PWMatchBoard, sections: PW.UIBoardSection[], label?: string)
---@field GetContentHeight fun(self: PWMatchBoard): number pixels at the current scale
---@field SetViewport fun(self: PWMatchBoard, viewport: Panel) culls offscreen rows

---@class PW.UIScoreboardFacts
---@field phase string
---@field enabled boolean
---@field playerValid boolean
---@field gameUI boolean
---@field focused boolean
---@field rootId? string nil or class picker may coexist; other roots win

---@class PW.UIScoreboardLayout : PW.UIRect
---@field boardY number relative to the panel
---@field boardH number

---@class PW.UIScoreboardData
---@field sections PW.UIBoardSection[]
---@field map string
---@field timer string
---@field scoreLabel? string
---@field note? string optional mode-owned public information
---@field gamepad? boolean native controller invocation (hint auto mode)

---@class PWLiveScoreboard : Panel
---@field Update fun(self: PWLiveScoreboard, data: PW.UIScoreboardData)
---@field Scroll fun(self: PWLiveScoreboard, delta: number)
---@field GetViewportHeight fun(self: PWLiveScoreboard): number

---@class PW.UIScoreboardLib
---@field Allowed fun(facts: PW.UIScoreboardFacts): boolean
---@field Sections fun(rows: PW.UIBoardRow[], opts: PW.UIBoardOpts): PW.UIBoardSection[] allowlisted, nonmutating
---@field Layout fun(width: number, height: number, scale: number): PW.UIScoreboardLayout
---@field Scroll fun(code: integer, viewport: number, scale: number): number?
---@field Gather? fun(): PW.UIScoreboardData client, public replicated facts only
---@field Create? fun(): PWLiveScoreboard client renderer
---@field Show? fun(): boolean client, successful custom board only
---@field Hide? fun() client, removes only this overlay
---@field IsOpen? fun(): boolean client
---@field HandleKey? fun(code: integer): boolean client; forwards keys captured by a death-picker root

---Presentation-only notification after gathering public LIVE data. No new networking or secret state.
---@alias PW.ScoreboardGatheredHook fun(data: PW.UIScoreboardData, ownId: integer)

---@class PW.UILib
---@field Board PW.UIBoardLib shared result/live board model
---@field Scoreboard? PW.UIScoreboardLib
