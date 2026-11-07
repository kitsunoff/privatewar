---@meta
-- Types of Domination (T-2.4; 02-modes.md d.5, d.7; 03-mapdata.md d.2, d.4, d.6). Source: the mode
-- lua/privatewar/modes/dom.lua and the flag module lua/privatewar/modules/dom_flags/ (shared.lua: API, pure presence
-- rules and the scripted entity pw_dom_flag; init.lua: server glue; cl_init.lua: the flag markers).

---One flag of the running match (server, plain data). value is the signed capture scalar in [-100, 100]: +100 is
---held by team 1, -100 by team 2.
---@class PW.DomFlagState
---@field letter string
---@field pos Vector
---@field value number
---@field owner integer 0 = nobody, else the owning team index (1 or 2)
---@field ent? PW.DomFlag the networked entity (nil when it could not be created)

---One flag as read from MAP.Modes.dom.flags: a letter and a bare Vector (03-mapdata.md d.2, d.5).
---@class PW.DomFlagSpot
---@field letter string
---@field pos Vector

---One player as plain data for the presence pass.
---@class PW.DomPresenceInfo
---@field who any the player (handed back in members)
---@field team integer
---@field pos Vector

---Who stands on one flag: counts and members by team id.
---@class PW.DomPresence
---@field counts table<integer, integer>
---@field members table<integer, any[]>

---The flag entity (class pw_dom_flag): data only, not solid, no trigger, invisible to the engine (EF_NODRAW),
---TRANSMIT_ALWAYS; clients draw a marker from its network vars.
---@class PW.DomFlag : ENT
local domFlag = {}

---The flag letter ("A"). Network var.
---@return string
function domFlag:GetLetter() end

---@param _ string
function domFlag:SetLetter(_) end

---The capture scalar in [-100, 100]. Network var.
---@return number
function domFlag:GetValue() end

---@param _ number
function domFlag:SetValue(_) end

---The owning team index, 0 = nobody. Network var.
---@return integer
function domFlag:GetOwnerTeam() end

---@param _ integer
function domFlag:SetOwnerTeam(_) end

---True while both teams stand in the point with equal counts (published by the mode). Network var.
---@return boolean
function domFlag:GetContested() end

---@param _ boolean
function domFlag:SetContested(_) end

---Domination flags (module dom_flags). The module knows nothing about capture or scoring: it owns the networked
---flag entities and the presence pass; the mode moves the scalar and scores.
---@class PW.DomFlagsLib
---Entity class of the flag.
---@field Class string
---Horizontal capture radius around a flag (units).
---@field Radius number
---How far above a flag a player still counts (units).
---@field Above number
---How far below a flag a player still counts (units).
---@field Below number
---Server: spawns a flag entity. Returns nil when the entity could not be created.
---@field Spawn? fun(letter: string, pos: Vector): PW.DomFlag?
---Server: removes every flag (match end).
---@field RemoveAll? fun()
---The flags alive now in spawn order (server: spawned; client: networked). A copy.
---@field GetAll fun(): PW.DomFlag[]
---Pure: whether pos is inside the capture cylinder of a flag at center.
---@field _Inside fun(center: Vector, pos: Vector): boolean
---Plain data of the players that may hold a flag: valid, alive, not observers.
---@field _Infos fun(players: Player[]): PW.DomPresenceInfo[]
---Pure: per flag position, the counts and members by team of the players inside it.
---@field _Presence fun(points: Vector[], infos: PW.DomPresenceInfo[]): PW.DomPresence[]
---Internal: the flag list (server and client).
---@field _Flags PW.DomFlag[]
---Internal: per-realm parts of the entity, called by its methods.
---@field _Init? fun(flag: PW.DomFlag)
---@field _Forget fun(flag: PW.DomFlag)

---The stored Domination mode (tests and the glue read its pure functions from the table).
---@class PW.DomMode : PW.Mode
---@field Base string
---@field MapData boolean
---@field _StartedAt? number CurTime() at which LIVE began, nil outside a match
---@field _Flags? PW.DomFlagState[] the flags of this match, nil outside a match
---@field _Scores? table<integer, integer> team score by team index in this match, nil outside a match
---@field _LastStep? number CurTime() of the last capture step
---@field _NextStep? number CurTime() of the next capture step
---@field _NextTick? number CurTime() of the next score tick
---@field _ScoreKey string prefix of the NW2 globals of the team scores (pw_dom_score_<team>)
---@field StepEvery number seconds between two capture steps (the presence pass rate)
---@field TickPoints integer team points per held flag per score tick
---Server, overridable in tests: the players the presence pass reads (default player.GetAll()).
---@field _Players fun(): Player[]
---Team score in this match (shared: the NW2 global).
---@field GetScore fun(index: integer): integer
---Returns true, or false and a reason: at least 2 flags, every flag a Vector (03-mapdata.md d.6).
---@field ValidateMapData fun(self: PW.DomMode, data: table): boolean, string?
---Internal, pure: the scalar after dt seconds with plus players of team 1 and minus players of team 2 inside.
---@field _Step fun(value: number, plus: integer, minus: integer, rate: number, dt: number): number
---Internal, pure: the owner after a step: team 1 at +100, team 2 at -100, else unchanged.
---@field _Owner fun(value: number, owner: integer): integer
---Internal, pure: adds points per held flag to scores; returns the set of team indexes that changed.
---@field _Hold fun(flags: { owner: integer }[], scores: table<integer, integer>, points: integer): table<integer, true>
---Internal, pure: the flags of map data sorted by letter (invalid entries skipped).
---@field _ParseFlags fun(data: table?): PW.DomFlagSpot[]
---Internal, pure: standings of teams 1..n by score.
---@field _Standings fun(scores: table<integer, integer>, n: integer): PW.Standing[]

---@class PW
---@field DomFlags? PW.DomFlagsLib the dom_flags module (nil when the module is missing)
