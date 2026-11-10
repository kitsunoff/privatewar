---@meta
-- Optional movement planner. The active fight frame remains the sole movement owner.

---@class PW.CombatMoveInput
---@field now number
---@field target any recognized contact identity, never a hidden live position
---@field visible boolean
---@field grounded boolean alive, grounded ordinary walking movement
---@field nav boolean an active goal or another movement owner has precedence
---@field speed number human movement command magnitude
---@field left boolean hull corridor and ground support are safe on the left
---@field right boolean hull corridor and ground support are safe on the right
---@field sliding boolean the detected addon's public GetSliding result

---@class PW.CombatMovePlan
---@field side integer -1 left, +1 right, 0 stopped
---@field untilAt number end of this short leg, CurTime
---@field target any contact identity
---@field drive? Vector exact owned direct-drive value
---@field slideAt? number exact owned slide request, when verified and eligible
---@field releaseGoal? PW.BotGoal exact inherited hunt goal; the Action alone may release it on acquisition

---@class PW.BotCombatMovementLib
---Pure planning, without engine or blackboard writes.
---@field Plan fun(f:PW.CombatMoveInput,p:PW.CombatMovePlan?,a:number,b:number):PW.CombatMovePlan
---@field Release fun(intent: PW.BotIntent, plan: PW.CombatMovePlan?) exact-value cleanup only
---@field Safe? fun(bot:Player,side:integer,distance:number,direction?:Vector):boolean bounded hull/ground wrapper

---@class PW
---@field BotCombatMovement? PW.BotCombatMovementLib
