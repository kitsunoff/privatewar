---@meta
-- Types of the score module (T-2.1, 06-progression.md d.3). Source: lua/privatewar/modules/score/ (shared.lua: API,
-- pure rules and reading; init.lua: server glue) and lua/privatewar/kinds/score_events.lua.

---One score event: class table inside a score_events/ file. Data only.
---@class PW.ScoreEvent : PW.Entity
---@field Name string display text, a localisation key ("#pw.score.kill")
---@field Points number match score; also streak progress in the "score" streak mode
---@field XP? number XP; nil means the same as the final points (after PW_ScoreValue)
---@field Medal? boolean true: popup with icon and sound
---@field Currency? number optional meta currency; default is 10 % of XP

---Options of PW.Score.Award.
---@class PW.ScoreOpts
---@field weapon? Weapon the weapon of the event; weapon XP comes only from events awarded with one

---Internal (server): scores of the current match. Player scores are kept by player; team scores by team index.
---@class PW.ScoreStore
---@field players table<Player, integer>
---@field teams table<integer, integer>
---@field log PW.LogFn

---Award over an explicit store and registry: true, points, xp or false.
---@alias PW.ScoreAwardFn fun(store: PW.ScoreStore, reg: PW.Registry?, ply: Player, id: string,
---opts?: PW.ScoreOpts): boolean, number?, number?

---Score module (06-progression.md d.3).
---@class PW.ScoreLib
---Server. Awards an event: resolves the points (EVENT.Points, then the question PW_ScoreValue(ply, eventId, points):
---a number answer replaces the points), adds them to the player and, in a team mode, to the player's team, fires the
---notification PW_ScoreEvent(ply, eventId, points, xp, weapon) and then PW_ScoreChanged(ply, score, delta, team,
---teamScore). XP is EVENT.XP, or the final points when EVENT.XP is nil (a PW_ScoreValue answer never changes an
---explicit EVENT.XP). An unknown or disabled event id, or an invalid player, is rejected: one log line, returns false.
---On success returns true, points, xp.
---@field Award fun(ply: Player, eventId: string, opts?: PW.ScoreOpts): boolean, number?, number?
---Match score of a player (0 if none). The server reads its store, a client the NW2 value.
---@field Get fun(ply: Player): integer
---Match score of a team by index 1..N (0 if none). The server reads its store, a client the NW2 global.
---@field GetTeam fun(index: integer): integer
---Internal, pure: points and XP of an event after the PW_ScoreValue answer: a number answer replaces the points,
---anything else keeps EVENT.Points; XP is EVENT.XP or the final points.
---@field _Resolve fun(event: PW.ScoreEvent, answer: any): number, number
---Internal, pure: adds points to a player and, for a team index (nil = none), to the team; returns the new player
---score and team score (nil without a team).
---@field _Add fun(store: PW.ScoreStore, ply: Player, team: integer?, points: number): integer, integer?
---Internal: Award over an explicit store and score_events registry (tests inject their own).
---@field _Award PW.ScoreAwardFn
---Internal: zeroes the store and the published NW2 values of every score in it.
---@field _Reset fun(store: PW.ScoreStore)
---Internal: a fresh store (tests swap PW._Score); log defaults to print("[PW] " .. message).
---@field _NewStore fun(log?: PW.LogFn): PW.ScoreStore
---Internal: NW2 key of the player score and prefix of the team score globals.
---@field _PlayerKey string
---@field _TeamKey string

---@class PW
---@field Score? PW.ScoreLib the score module (nil when the module is missing)
---@field _Score PW.ScoreStore internal

---Class table inside a score_events/ file.
---@type PW.ScoreEvent
EVENT = nil
