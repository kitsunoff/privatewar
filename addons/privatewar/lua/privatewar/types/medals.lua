---@meta
-- Types of the medals module (T-4.11, 06-progression.md d.3). Source: lua/privatewar/modules/medals/ (shared.lua:
-- pure detectors and counting; init.lua: server glue; cl_init.lua: the receiver) and lua/privatewar/score_events/.

---Plain facts about one death.
---@class PW.MedalsKill
---@field time number CurTime of the death
---@field attacker any? the killer, nil for the world
---@field victim any
---@field enemy boolean the killer is an enemy of the victim (false for a suicide, a teamkill, the world)

---Plain facts about one damage event between players.
---@class PW.MedalsDamage
---@field attacker any
---@field victim any
---@field time number

---A multi-kill chain of one player.
---@class PW.MedalsChain
---@field count integer
---@field last number

---Detector state of the match.
---@class PW.MedalsState
---@field firstBlood boolean the first kill of the match is taken
---@field chains table<any, PW.MedalsChain> multi-kill chain per player
---@field streaks table<any, integer> kills since the last death per player
---@field lastKiller table<any, any> the enemy who killed a player last, until revenge is taken
---@field damage PW.MedalsDamage[] recent damage between enemies, oldest first

---@alias PW.MedalsAllyFn fun(a: any, b: any): boolean

---Internal (server): the state, the per-match medal counts and the engine edges.
---@class PW.MedalsStore
---@field state PW.MedalsState
---@field counts table<any, table<string, integer>>
---@field isAlly PW.MedalsAllyFn
---@field award fun(ply: any, id: string): boolean
---@field notify fun(name: string, ply: any, id: string)
---@field send fun(ply: any, id: string)

---@class PW.MedalsStoreOpts
---@field isAlly? PW.MedalsAllyFn
---@field award? fun(ply: any, id: string): boolean
---@field notify? fun(name: string, ply: any, id: string)
---@field send? fun(ply: any, id: string)

---@class PW
---@field Medals? PW.MedalsLib the medals module (nil when the module is missing)
---@field _Medals PW.MedalsStore internal

---The last medal a client received.
---@class PW.MedalsLast
---@field id string?
---@field at number

---Medals module. Wire: server to client message "pw_medal", one string, the medal id (the owner only, humans only).
---@class PW.MedalsLib
---Medal ids; each is also the id of a score event with Medal = true.
---@field Ids string[]
---Seconds between two kills of a multi-kill chain.
---@field Window number
---Seconds a damage to a teammate keeps the damager a saviour target.
---@field SaviourWindow number
---Kills without dying per 5-kill streak medal.
---@field StreakStep integer
---Server: medals earned by a player this match, `{ [id] = count }` (a copy; empty when none). Kept through
---POSTMATCH, reset when the match goes LIVE and when the lobby returns. Empty on a client.
---@field Get fun(ply: Player): table<string, integer>
---Client: the last medal received, set by the "pw_medal" message.
---@field Last PW.MedalsLast
---Internal, pure: a fresh detector state.
---@field _NewState fun(): PW.MedalsState
---Internal, pure: forgets everything.
---@field _Reset fun(state: PW.MedalsState)
---Internal, pure: records a damage between enemies.
---@field _OnDamage fun(state: PW.MedalsState, rec: PW.MedalsDamage)
---Internal, pure: runs the detectors for one death; returns the medal ids of the killer, in award order.
---@field _OnKill fun(state: PW.MedalsState, ev: PW.MedalsKill, isAlly: PW.MedalsAllyFn): string[]
---Internal: a store over injected edges.
---@field _NewStore fun(opts?: PW.MedalsStoreOpts): PW.MedalsStore
---Internal: detectors, then count, award, notify and send for each earned medal.
---@field _Kill fun(store: PW.MedalsStore, ev: PW.MedalsKill)
---Internal: the counts of a player (a copy).
---@field _Counts fun(store: PW.MedalsStore, ply: any): table<string, integer>
---Internal: clears the state and the counts of a store.
---@field _ResetStore fun(store: PW.MedalsStore)
