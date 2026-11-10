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
---@field owner PW.ObjectiveFrameState frame ownership token
---@field intent PW.BotIntent exact intent table used by this visit
---@field baseline table<string, any>
---@field values table<string, any>
---@field owned table<string, boolean>
---@field goal? PW.BotGoal exact goal created by this visit
---@field look? Vector exact objective look target
---@field initialGoal? PW.BotGoal inherited goal, never adopted merely by cleanup
---@field initialLook? any inherited aim target
---@field ending? boolean recursive cleanup guard

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

---@class PW.BotBoard
---@field _behaviorOwner? table internal output ownership token, changed on active frame callbacks
