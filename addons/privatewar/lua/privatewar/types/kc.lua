---@meta
-- Types of Kill Confirmed (T-2.5; 02-modes.md d.5, d.7; 01-extensibility.md d.17). Source: the mode
-- lua/privatewar/modes/kc.lua and the tag module lua/privatewar/modules/kc_tags/ (shared.lua: API, pure rules and
-- the scripted entity pw_kc_tag; init.lua: server glue; cl_init.lua: drawing).

---Plain facts about one touch of a tag, for the pure verdict.
---@class PW.KCTouchInfo
---@field player boolean the toucher is a valid player
---@field alive boolean the toucher is alive and not an observer (spectator)
---@field enemy boolean PW.IsEnemy(toucher, victim)

---What a pickup does: an enemy of the victim confirms the kill, a teammate (or the victim) denies it.
---@alias PW.KCVerdict "confirm"|"deny"

---The tag entity (class pw_kc_tag): data only, invisible to the engine (EF_NODRAW), not solid, a trigger,
---TRANSMIT_ALWAYS; clients draw it from its network vars.
---@class PW.KCTag : ENT
---@field _PWVictim? any internal (server): the victim as given to Spawn (a player, or a stand-in in tests)
---@field _PWCollected? boolean internal (server): picked up or expired; no second pickup
local kcTag = {}

---The dead player (NULL for a victim that is not an entity). Network var.
---@return Entity
function kcTag:GetVictim() end

---@param _ Entity the victim
function kcTag:SetVictim(_) end

---CurTime() at which the tag expires, 0 = never. Network var.
---@return number
function kcTag:GetExpireAt() end

---@param _ number the expiry time
function kcTag:SetExpireAt(_) end

---Kill Confirmed tags (module kc_tags). The module knows nothing about scoring: a pickup fires the notification
---PW_KCTagCollected(collector, victim, verdict) and the active mode scores there.
---@class PW.KCTagsLib
---Entity class of the tag.
---@field Class string
---Most tags alive at once; spawning one more removes the oldest (TRANSMIT_ALWAYS needs a hard cap).
---@field MaxTags integer
---How far below the victim (units) a tag is snapped to the ground.
---@field GroundTrace number
---Pickup box of a tag around its origin (on the ground).
---@field Mins Vector
---@field Maxs Vector
---Server: spawns a tag at pos for victim with a lifetime in seconds (0 = until picked up or the match ends).
---Returns the tag, or nil when the entity could not be created.
---@field Spawn? fun(pos: Vector, victim: any, lifetime: number): PW.KCTag?
---Server: spawns a tag on the ground under a dead player (Spawn at the snapped position).
---@field Drop? fun(victim: Player, lifetime: number): PW.KCTag?
---Server: the ground under pos (within GroundTrace), or pos itself when nothing is below.
---@field _Ground? fun(pos: Vector): Vector
---Server: removes every tag (match end).
---@field RemoveAll? fun()
---The tags alive now, oldest first (server: spawned and not collected; client: networked). A copy.
---@field GetAll fun(): PW.KCTag[]
---Internal, pure: the verdict of one touch, nil when the toucher picks nothing up.
---@field _Verdict fun(info: PW.KCTouchInfo): PW.KCVerdict?
---Internal, pure: CurTime() of expiry for a tag spawned at now with a lifetime (0 = never, returns 0).
---@field _ExpireAt fun(now: number, lifetime: number): number
---Internal, pure: whether a tag with expiry time at (0 = never) has expired at now.
---@field _Expired fun(at: number, now: number): boolean
---Internal, pure: how many of the oldest tags to remove before one more is spawned with count tags alive.
---@field _Evict fun(count: integer, max: integer): integer
---Internal: the tag list (server and client).
---@field _Tags PW.KCTag[]
---Internal: per-realm parts of the entity, called by its methods.
---@field _Init? fun(tag: PW.KCTag)
---@field _Touch? fun(tag: PW.KCTag, other: any): PW.KCVerdict?
---@field _Think? fun(tag: PW.KCTag): boolean?
---@field _Forget fun(tag: PW.KCTag)

---The stored Kill Confirmed mode (tests and the glue read its pure functions from the table).
---@class PW.KCMode : PW.Mode
---@field Base string
---@field _StartedAt? number CurTime() at which LIVE began, nil outside a match
---@field _Confirms? table<integer, integer> confirms by team index in this match, nil outside a match
---@field _ConfirmsKey string prefix of the NW2 globals of the confirms (pw_kc_confirms_<team>)
---Confirms of a team in this match (shared: the NW2 global).
---@field GetConfirms fun(index: integer): integer
---Internal, pure: counts a verdict (a confirm for team index, nil = no team) and returns the score event id.
---@field _Apply fun(confirms: table<integer, integer>, verdict: PW.KCVerdict, index: integer?): string
---Internal, pure: the team index 1..n of a team id, else nil.
---@field _TeamIndex fun(teamId: integer, n: integer): integer?
---Internal, pure: standings of teams 1..n by confirms.
---@field _Standings fun(confirms: table<integer, integer>, n: integer): PW.Standing[]
---@field PW_PlayerKilled fun(self: PW.KCMode, victim: Player, attacker: Entity, dmg: CTakeDamageInfo)
---@field PW_KCTagCollected fun(self: PW.KCMode, collector: Player, victim: any, verdict: PW.KCVerdict)

---@class PW
---@field KCTags? PW.KCTagsLib the kc_tags module (nil when the module is missing)
