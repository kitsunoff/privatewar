---@meta
-- Types of the bots_debug module (T-5.4; 07-bots.md d.11). Code: lua/privatewar/modules/bots_debug/ (shared.lua: the
-- pure snapshot, its wire format and the send step; init.lua: the server glue; cl_init.lua: the overlay).

---The goal of one bot in a snapshot: the point the follower walks to, in whole units.
---@class PW.BotDebugGoal
---@field x integer
---@field y integer
---@field z integer
---@field status string PW.BotGoalStatus ("moving", "arrived", "failed", "unreachable")

---One bot in a snapshot.
---@class PW.BotDebugEntry
---@field index integer entity index of the bot (the client finds the bot with Entity(index))
---@field name string
---@field behavior string running behaviour id, "" when none
---@field reason string why it runs, "" when none
---@field target string name of the target, "" when none
---@field goal? PW.BotDebugGoal
---@field path integer[] flat x, y, z of the remaining waypoints, at most PW.BotDebug.MaxPath points

---What the server sends: the scheduler perf line and the bots.
---@class PW.BotDebugSnapshot
---@field perf string
---@field bots PW.BotDebugEntry[]

---Names an entity (a target) for the overlay.
---@alias PW.BotDebugNamer fun(ent: Entity): string

---Writer of the wire format (net.Write* in the engine, a recorder in tests).
---@class PW.BotDebugWriter
---@field uint fun(value: integer, bits: integer)
---@field int fun(value: integer, bits: integer)
---@field string fun(value: string)
---@field bool fun(value: boolean)

---Reader of the wire format (net.Read* in the engine, a replayer in tests).
---@class PW.BotDebugReader
---@field uint fun(bits: integer): integer
---@field int fun(bits: integer): integer
---@field string fun(): string
---@field bool fun(): boolean

---Everything Step needs from the engine; tests inject their own.
---@class PW.BotDebugDeps
---@field enabled fun(): boolean pw_bot_debug
---@field players fun(): Player[] candidates for the recipients
---@field can fun(ply: Player): boolean the privilege check
---@field bots fun(): Player[] the managed bots
---@field boardOf fun(bot: Player): PW.BotBoard?
---@field nameOf PW.BotDebugNamer
---@field counters fun(): PW.BotSchedulerCounters?
---@field send fun(recipients: Player[], snapshot: PW.BotDebugSnapshot)

---@class PW.BotDebugState
---@field nextAt number time of the next snapshot

---@class PW.BotDebugLib
---@field Privilege string "pw.bots.debug"
---@field Message string the server -> client net message name
---@field Interval number seconds between two snapshots (0.25)
---@field MaxPath integer waypoints per bot on the wire (24)
---@field MaxBots integer bots per snapshot (64)
---Server: whether pw_bot_debug is on.
---@field Enabled? fun(): boolean
---Pure: the one-line scheduler summary shown in the corner.
---@field PerfLine fun(counters: PW.BotSchedulerCounters?): string
---Pure: one bot's entry from its blackboard; nameOf names the target.
---@field BuildEntry fun(index: integer, name: string, board: PW.BotBoard?, nameOf: PW.BotDebugNamer): PW.BotDebugEntry
---Pure: the snapshot of the bots; nil (and no board is read) when enabled is false.
---@field Collect fun(enabled: boolean, deps: PW.BotDebugDeps): PW.BotDebugSnapshot?
---Pure: the players for which can(ply) holds.
---@field Recipients fun(players: Player[], can: fun(ply: Player): boolean): Player[]
---Pure: writes a snapshot with explicit writes (no net.WriteTable).
---@field Encode fun(snapshot: PW.BotDebugSnapshot, writer: PW.BotDebugWriter)
---Pure: reads what Encode wrote.
---@field Decode fun(reader: PW.BotDebugReader): PW.BotDebugSnapshot
---Pure: one tick of the sender. Does nothing (reads no board, builds nothing, sends nothing) while pw_bot_debug is
---off, before the next snapshot is due, or with no privileged client. True when a snapshot was sent.
---@field Step fun(state: PW.BotDebugState, now: number, deps: PW.BotDebugDeps): boolean
---Internal (server): the state of the default sender.
---@field _State? PW.BotDebugState

---@class PW
---@field BotDebug? PW.BotDebugLib
