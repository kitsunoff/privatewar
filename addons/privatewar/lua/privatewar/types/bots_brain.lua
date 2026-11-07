---@meta
-- Types of the bots_brain module (T-5.9; 07-bots.md d.4, d.5; docs/api/bots-blackboard.md "bot_behaviors") and of the
-- bot_behaviors kind. Code: lua/privatewar/modules/bots_brain/ (shared.lua: the pure selection; sh_stack.lua: the
-- per-bot state, the Action stack and the ctx; init.lua: the scheduler glue).

---A rank: a bucket name ("survival" > "combat" > "objective" > "roam") or a number (higher wins). nil, false or a
---value of 0 or less: the behaviour is not a candidate now.
---@alias PW.BotRank "survival"|"combat"|"objective"|"roam"|number|false|nil

---What Update returns (built with PW.Bot.Continue, ChangeTo, SuspendFor, Done).
---@class PW.BotTransition
---@field kind "continue"|"change"|"suspend"|"done"
---@field id? string the behaviour to change to or to suspend for
---@field reason? string shown in the debug overlay

---A behaviour (class table BEHAVIOR in lua/privatewar/bot_behaviors/<id>.lua). Methods are called through PW.Call
---on the shared definition: an error disables the behaviour until the map changes. Per-run data lives in ctx.state.
---@class PW.BotBehavior: PW.Entity
---@field Modes? string[] mode ids it runs in; nil = every mode
---@field Interval? number seconds between two evaluations of Rank and Weight (default 1, minimum 0.1)
---@field MinRun? number seconds the behaviour runs before a candidate of the same or a lower bucket replaces it
---@field Cooldown? number seconds after it ends before it is a candidate again
---@field Rank fun(self: PW.BotBehavior, bot: Player, ctx: PW.BotBrainCtx): PW.BotRank
---@field Weight fun(self: PW.BotBehavior, bot: Player, ctx: PW.BotBrainCtx): number?
---@field Update fun(self: PW.BotBehavior, bot: Player, ctx: PW.BotBrainCtx): PW.BotTransition?
---@field OnStart? fun(self: PW.BotBehavior, bot: Player, ctx: PW.BotBrainCtx)
---@field OnEnd? fun(self: PW.BotBehavior, bot: Player, ctx: PW.BotBrainCtx)
---@field OnSuspend? fun(self: PW.BotBehavior, bot: Player, ctx: PW.BotBrainCtx)
---@field OnResume? fun(self: PW.BotBehavior, bot: Player, ctx: PW.BotBrainCtx)

---Class table inside a bot_behaviors/ file.
---@type PW.BotBehavior
BEHAVIOR = nil

---One scored option of the selection (plain data).
---@class PW.BotCandidateScore
---@field id string
---@field rank number
---@field weight number

---The running behaviour as the selection sees it.
---@class PW.BotCurrentScore
---@field id string
---@field rank number
---@field weight number
---@field locked? boolean inside its minimum run time

---Options of the selection.
---@class PW.BotChooseOpts
---@field screen number keep the options of the best bucket whose weight is at least screen * best
---@field bonus number commitment: the running behaviour's weight is multiplied by it
---@field random fun(): number uniform in [0, 1)

---One frame of the Action stack.
---@class PW.BotFrame
---@field id string
---@field def PW.BotBehavior
---@field state table per-run data of the behaviour (ctx.state during its frame methods)
---@field since number time the frame started
---@field rank number its rank when it started (inherited from the frame that started it by a transition)
---@field weight number
---@field via "select"|"transition"
---@field reason string

---The last evaluation of a behaviour.
---@class PW.BotEval
---@field at number
---@field rank? number nil = not a candidate
---@field weight number

---Per-bot state of the brain (plain data).
---@class PW.BotBrainState
---@field stack PW.BotFrame[] bottom first; the top runs
---@field evals table<string, PW.BotEval>
---@field cooldowns table<string, number> time before which a behaviour is not a candidate
---@field sighted? table<any, true> the enemies visible on the previous tick (the sight nudge, brain decision 9)
---@field legsOf? string the top frame that owns the legs fields of the intent (brain decision 10, T-11.6)
---@field ctx PW.BotBrainCtx

---Engine calls of the ctx helpers (tests inject fakes).
---@class PW.BotBrainApi
---@field setGoal? fun(bot: any, point: Vector, radius: number, priority: string): boolean, string?
---@field clearGoal? fun(bot: any)
---@field searchPlan? fun(bot: any, ent: any): Vector[]?

---Facts of one brain tick.
---@class PW.BotBrainEnv
---@field bot any the bot (a Player in the glue)
---@field board PW.BotBoard
---@field behaviors PW.BotBehavior[] enabled behaviours
---@field random fun(): number
---@field mode? string id of the active mode (for BEHAVIOR.Modes)
---@field screen? number default PW.BotBrain.Defaults.screen
---@field bonus? number default PW.BotBrain.Defaults.bonus
---@field api? PW.BotBrainApi

---The context given to every behaviour method. One table per bot, refreshed every brain tick.
---@class PW.BotBrainCtx
---@field bot any
---@field board PW.BotBoard
---@field now number
---@field running? string id of the running behaviour (the top of the stack)
---@field state? table the frame's per-run data; set only during OnStart, Update, OnEnd, OnSuspend and OnResume
---@field order? PW.BotOrder board.order
---@field contacts PW.BotContact[] board.contacts or an empty list
---@field memory table<Entity, PW.BotContact> board.memory or an empty table
---@field goal? PW.BotGoal board.goal
---@field target? Entity board.target
---@field _api PW.BotBrainApi
---@field Intent fun(self: PW.BotBrainCtx): PW.BotIntent the board's intent, created when missing
---@field SetGoal fun(self: PW.BotBrainCtx, point: Vector, radius: number, priority: string): boolean, string?
---@field ClearGoal fun(self: PW.BotBrainCtx)
---@field GoalStatus fun(self: PW.BotBrainCtx): string? status of the current goal, nil without one
---@field SetTarget fun(self: PW.BotBrainCtx, ent: Entity?) writes board.target and intent.target (the aim reads them)
---@field Contact fun(self: PW.BotBrainCtx, ent: any): PW.BotContact? the memory entry of an entity
---@field SearchPlan fun(self: PW.BotBrainCtx, ent: any?): Vector[]? the 5 search points of a lost contact

---Debug data of the brain (board.debug.brain).
---@class PW.BotBrainDebug
---@field scores table<string, { rank: number?, weight: number }> the last evaluation of every behaviour
---@field stack string[] ids, bottom first
---@field reason string why the running behaviour runs

---The brain (T-5.9). Shared: the pure selection and the stack; server: the glue.
---@class PW.BotBrainLib
---@field Buckets table<string, number> bucket name to rank value
---@field Defaults { screen: number, bonus: number, interval: number, minInterval: number, maxDepth: integer }
---Pure: the number of a rank, nil when it is not a candidate.
---@field RankValue fun(rank: any): number?
---Pure: the effective re-evaluation interval of a behaviour (default and minimum applied).
---@field IntervalOf fun(def: PW.BotBehavior): number
---Pure: the options of the best bucket that pass the screen (weight >= screen * best weight of that bucket).
---@field Screen fun(cands: PW.BotCandidateScore[], screen: number): PW.BotCandidateScore[]
---Pure: weighted-random pick over options (weights > 0); nil for an empty list.
---@field Pick fun(options: PW.BotCandidateScore[], random: fun(): number): PW.BotCandidateScore?
---Pure: dual-utility selection. Returns the id to run (nil: nothing) and the reason.
---@field Choose fun(cands: PW.BotCandidateScore[], cur: PW.BotCurrentScore?, opts: PW.BotChooseOpts): string?, string
---@field Continue fun(): PW.BotTransition
---@field ChangeTo fun(id: string, reason?: string): PW.BotTransition
---@field SuspendFor fun(id: string, reason?: string): PW.BotTransition
---@field Done fun(reason?: string): PW.BotTransition
---A fresh per-bot state.
---@field NewState fun(): PW.BotBrainState
---One brain tick: evaluate, select, switch, Update the top, apply its transition, write board.behavior and debug.
---@field Think fun(state: PW.BotBrainState, env: PW.BotBrainEnv, now: number)
---Ends every frame top first (death, kick, the bot is no longer managed); clears board.behavior.
---@field Stop fun(state: PW.BotBrainState, env: PW.BotBrainEnv, now: number, reason: string)
---The ids of the stack, bottom first.
---@field StackIds fun(state: PW.BotBrainState): string[]

---Internal (server): state of the module.
---@class PW.BotBrainStore
---@field states table<Player, PW.BotBrainState> weak keys
---@field registered table<Player, string> scheduler id per bot (weak keys)

---@class PW.BotBoard
---@field behavior? { id: string, reason: string } the running behaviour (writer: brain)

---@class PW.BotLib
---@field Continue? fun(): PW.BotTransition
---@field ChangeTo? fun(id: string, reason?: string): PW.BotTransition
---@field SuspendFor? fun(id: string, reason?: string): PW.BotTransition
---@field Done? fun(reason?: string): PW.BotTransition

---@class PW
---@field BotBrain? PW.BotBrainLib
---@field _BotBrain PW.BotBrainStore internal (server)
---The bot_behaviors kind (lua/privatewar/kinds/bot_behaviors.lua).
---@field BotBehaviors? PW.Registry
