---@meta
-- Types of the bots_goal module (T-5.6; 07-bots.md d.6; docs/api/bots-blackboard.md "Goal API"). Code:
-- lua/privatewar/modules/bots_goal/ (shared.lua and sh_follow.lua: the pure rules; init.lua: the goal wrapper glue,
-- the per-bot follower tick and the hooks; sv_command.lua: pw_bot_goto).

---@alias PW.BotGoalPriority "hunt"|"guard"|"objective"|"tactical"|"critical"

---moving: a path is being searched or followed; arrived: within the radius; failed: given up (stuck, died, no
---navmesh, the bot cannot be placed on the navmesh); unreachable: the path service proved it unreachable, the point
---is off the navmesh, or it is blacklisted.
---@alias PW.BotGoalStatus "moving"|"arrived"|"failed"|"unreachable"

---The blackboard field `goal` (writer: bots_goal; the request comes only through SetGoal).
---@class PW.BotGoal
---@field point Vector the goal as requested
---@field radius number arrival radius, units
---@field priority PW.BotGoalPriority
---@field status PW.BotGoalStatus
---@field since number CurTime() when the goal was accepted
---@field projected? Vector the point projected on the navmesh (the follower walks there)
---@field reason? string why a goal ended failed or unreachable ("stuck", "died", "blacklisted", ...)
---@field repaths? integer path requests after the first one

---The blackboard field `path` (writer: bots_goal): the waypoints the follower walks.
---@class PW.BotPath
---@field points Vector[] waypoints; the last one is the projected goal (or the end of a partial path)
---@field index integer the waypoint the bot is walking to
---@field partial boolean the path ends short of the goal (the search hit its iteration cap)

---@class PW.BotBoard
---@field goal? PW.BotGoal
---@field path? PW.BotPath

---A blacklist of point keys with a time to live.
---@class PW.BotGoalBlacklist
---@field Add fun(key: string)
---@field Has fun(key: string): boolean false once the entry expired
---@field Clear fun()
---@field Count fun(): integer entries not yet expired

---@alias PW.BotStuckAction "jump"|"crouch"|"back_off"|"side_step"|"repath"|"give_up"

---State of the stuck ladder (plain data).
---@class PW.BotStuckState
---@field level integer 0 = not stuck; else the rung of PW.BotGoal.StuckLadder
---@field anchor? number remaining path length at the start of the current window
---@field anchorTime number
---@field levelSince number time the current rung started
---@field side integer +1 right, -1 left: the side of the next side step (alternates)

---Options of StuckStep.
---@class PW.BotStuckOpts
---@field window? number seconds of one progress window, default 1
---@field minProgress? number units the remaining path length must drop in a window, default 24

---Move and buttons of one stuck rung. forward and side are scales (-1..1) of the run speed.
---@class PW.BotStuckInput
---@field buttons integer
---@field forward number
---@field side number

---Door memory of the follower.
---@class PW.BotDoorState
---@field usedAt? number

---One area step of a path for Waypoints: where the path enters the area and the area centre.
---@class PW.BotGoalStep
---@field entry Vector
---@field center Vector

---Parsed pw_bot_goto arguments.
---@class PW.BotGotoArgs
---@field pattern string bot name pattern ("*" every bot)
---@field mode "here"|"point"|"clear"|"status"
---@field point? Vector
---@field radius number
---@field priority PW.BotGoalPriority

---Internal (server): the follower state of one bot. It is also the bot's id in the scheduler.
---@class PW.BotGoalState
---@field bot Player
---@field handle? PW.NavHandle the running path request
---@field token? table identifies the current request; a callback of an older request is ignored
---@field stuck PW.BotStuckState
---@field door PW.BotDoorState
---@field blacklist PW.BotGoalBlacklist
---@field attempts integer path requests of the current goal
---@field retryAt number
---@field requestedAt number CurTime() of the running request; one pending longer than 5 s is cancelled and retried
---@field added integer IN_* bits this module added to intent.buttons last tick
---@field registered boolean
---@field repathed boolean the "repath" rung already requested a path

---Internal (server): state of the module.
---@class PW.BotGoalStore
---@field states table<Player, PW.BotGoalState> weak keys

---The goal API, wrapper and follower (T-5.6).
---@class PW.BotGoalLib
---Privilege of pw_bot_goto: "pw.bots.debug".
---@field Privilege string
---@field Priorities table<PW.BotGoalPriority, integer> hunt 1 .. critical 5
---@field StuckLadder PW.BotStuckAction[]
---Pure: the rank of a priority name; nil when the name is unknown.
---@field PriorityValue fun(priority: string): integer?
---Pure: what SetGoal does with a request against the current goal: "new" (replace), "same" (the same goal: keep the
---path) or "reject" (a lower priority than an active goal).
---@field Arbitrate fun(current: PW.BotGoal?, point: Vector, radius: number, priority: string): "new"|"same"|"reject"
---Pure: the blacklist key of a point (a 64-unit grid cell).
---@field PointKey fun(point: Vector): string
---Pure: a blacklist with a time to live (seconds) over a clock.
---@field NewBlacklist fun(ttl: number, clock?: fun(): number): PW.BotGoalBlacklist
---Pure: a fresh stuck ladder state.
---@field NewStuck fun(): PW.BotStuckState
---Pure: drops the ladder to level 0 and restarts the window (a new path, a door being opened).
---@field StuckReset fun(state: PW.BotStuckState)
---Pure: feeds the remaining path length at now; once per window a window without progress (the length dropped by
---less than minProgress) climbs one rung, progress resets the ladder. Returns the action of the current rung, nil
---when the bot is not stuck.
---@field StuckStep fun(s: PW.BotStuckState, remaining: number, now: number, o?: PW.BotStuckOpts): PW.BotStuckAction?
---Pure: a new path changes the remaining length: re-anchor the window on it, keep the rung and the window timing.
---@field StuckRestartWindow fun(state: PW.BotStuckState, remaining: number)
---Pure: the path length from pos through points[index..] (0 when the path is done).
---@field Remaining fun(points: Vector[], index: integer, pos: Vector): number
---Pure: move and buttons of a rung (since: seconds on the rung; side: +1 or -1); nil for repath and give_up.
---@field StuckInput fun(action: PW.BotStuckAction?, since: number, side: integer): PW.BotStuckInput?
---Pure: the index of the waypoint to walk to after passing the ones within reach (2D, small height difference)
---and the ones the bot is already past; #points + 1 when the path is done.
---@field Advance fun(points: Vector[], index: integer, pos: Vector, reach: number): integer
---Pure: the point distance units along the path from pos through points[index..].
---@field LookAhead fun(points: Vector[], index: integer, pos: Vector, distance: number): Vector
---Pure: forward and side move values toward target for a view yaw (Source: side > 0 is right).
---@field MoveFor fun(pos: Vector, target: Vector, yaw: number, speed: number): number, number
---Pure: whether pos is within radius of point (2D) and not much above or below it.
---@field Arrived fun(pos: Vector, point: Vector, radius: number): boolean
---Pure: delay before path attempt n (1 = the first, no delay); grows and is capped.
---@field RetryDelay fun(attempt: integer): number
---Pure: the waypoints of a path: each area entry pulled toward its centre, then the final point.
---@field Waypoints fun(steps: PW.BotGoalStep[], final: Vector): Vector[]
---Pure: "use" when a door is ahead and not used recently, "wait" shortly after a use, nil otherwise.
---@field DoorStep fun(state: PW.BotDoorState, now: number, doorAhead: boolean): "use"|"wait"|nil
---Pure: whether an entity class is a door the follower opens with +use.
---@field IsDoorClass fun(class: string): boolean
---Pure: whether the follower writes intent.view (orchestrator rule): false while aim (PW.BotAim, nil-safe) owns the
---view of the bot (OwnsView true), true otherwise.
---@field FollowerOwnsView fun(aim: { OwnsView: (fun(bot: any): boolean)? }?, bot: any): boolean
---Pure: the view from `from` turned toward `to` by at most maxSpeed * dt degrees per axis, yaw the short way round.
---@field TurnToward fun(from: Angle, to: Angle, maxSpeed: number, dt: number): Angle
---Pure: view angles of a ladder climb toward target (pitch up or down, yaw to the target).
---@field LadderView fun(pos: Vector, target: Vector): Angle
---Pure: pw_bot_goto arguments; nil and the usage text when they are not valid.
---@field ParseGotoArgs fun(args: string[]): PW.BotGotoArgs?, string?
---Server: the blackboard of a bot (PW.Bot.Get); tests stub it.
---@field BoardOf? fun(bot: Player): PW.BotBoard?
---Server: the point projected on the nearest navmesh area within 256 units; nil when there is none. Tests stub it.
---@field Project? fun(point: Vector): Vector?
---Server: sets a goal for a managed bot. Returns whether it was accepted and the goal status after the call.
---@field SetGoal? fun(bot: Player, point: Vector, radius: number, priority: PW.BotGoalPriority): boolean, string?
---Server: drops the goal and the path of a bot and stops its legs.
---@field ClearGoal? fun(bot: Player)
---Internal (server): ClearGoal plus the follower state (tests, a kicked bot).
---@field _Drop? fun(bot: Player)
---Internal (server): pw_bot_goto; ply nil is the server console. Returns the number of bots changed.
---@field _Command? fun(ply: Player?, args: string[], out?: fun(line: string)): integer

---@class PW.BotLib
---Server: the goal API of 07 d.6 (installed by bots_goal); same as bot:SetGoal.
---@field SetGoal? fun(bot: Player, point: Vector, radius: number, priority: PW.BotGoalPriority): boolean, string?
---@field ClearGoal? fun(bot: Player)

---@class Player
---Server, managed bots: the goal API of 07 d.6 (installed by bots_goal).
---@field SetGoal? fun(self: Player, point: Vector, radius: number, priority: PW.BotGoalPriority): boolean, string?

---@class PW
---@field BotGoal? PW.BotGoalLib
---@field _BotGoal PW.BotGoalStore internal (server)
