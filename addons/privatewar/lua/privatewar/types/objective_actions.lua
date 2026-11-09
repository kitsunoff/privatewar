---@meta

---A registered handler; immutable definition, mutable state passed separately for each bot and visit.
---@class PW.ObjectiveAction: PW.Entity
---@field Motion? string built-in movement strategy: zone, guard, or absent for a touch approach
---@field Update fun(self: PW.ObjectiveAction, bot: Player, ctx: PW.BotBrainCtx, target: PW.BotObjective,
---    state: table): PW.BotTransition returns Continue or Done; never decides a mode verdict
---@field OnStart? fun(self: PW.ObjectiveAction, bot: Player, ctx: PW.BotBrainCtx,
---    target: PW.BotObjective, state: table)
---@field OnEnd? fun(self: PW.ObjectiveAction, bot: Player, ctx: PW.BotBrainCtx, target: PW.BotObjective, state: table)

---@type PW.ObjectiveAction
OBJECTIVEACTION = nil

---@class PW.ObjectiveVisit
---@field id string
---@field action string
---@field revision? integer
---@field handler PW.ObjectiveAction
---@field target PW.BotObjective
---@field state table<string, any>

---@class PW.ObjectiveFrameState
---@field visit? PW.ObjectiveVisit
---@field id? string
---@field action? string
---@field revision? integer

---@class PW.BotObjectivesLib
---@field RunAction fun(ctx: PW.BotBrainCtx, target: PW.BotObjective): PW.BotTransition
---@field EndAction fun(ctx: PW.BotBrainCtx) idempotent, runner-owned cleanup, even after handler failure
---@field ValidateGoal fun(ctx: PW.BotBrainCtx, target: PW.BotObjective): boolean clears unsafe projected goals

---@class PW
---@field ObjectiveActions? PW.Registry
