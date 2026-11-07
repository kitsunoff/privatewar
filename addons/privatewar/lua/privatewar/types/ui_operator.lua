---@meta
-- Types of the operator scene (U-9, T-7.3). Source: lua/privatewar/modules/ui_kit/sh_operator.lua (pure) and
-- cl_operator.lua (PWOperator).

---@class PW.UIOperatorFrame
---@field dist number camera distance from the look-at point
---@field lookAt Vector centre of the model bounds
---@field camPos Vector

---@class PW.UIOperatorLight
---@field name string key, fill, rim or top
---@field dir integer DModelPanel box direction 0..5
---@field colour Color

---@class PW.UIOperatorRig
---@field ambient Color
---@field lights PW.UIOperatorLight[]

---@class PW.UIOperatorLib
---@field FallbackModel string stock player model used when the wanted one is unusable
---@field CameraPitch number degrees the camera sits above the look-at point
---@field IdleSequences string[] idle sequence names, best first
---@field Margin number framing margin factor
---Pure: camera distance at which the bounding sphere of mins..maxs fits a FOV (horizontal, degrees). `aspect` is
---panel width / height; above 1 the vertical FOV limits.
---@field FramingDistance fun(mins: Vector, maxs: Vector, fov: number, aspect?: number): number
---Pure: look-at point and camera position for the bounds.
---@field Frame fun(mins: Vector, maxs: Vector, fov: number, aspect?: number): PW.UIOperatorFrame
---Pure: the wanted model, or the fallback when it is empty, malformed, models/error.mdl or invalid (second result).
---@field ChooseModel fun(path: string?, isValid: fun(path: string): boolean): string, boolean
---Pure: id of the first idle sequence the lookup knows, nil when none.
---@field ChooseSequence fun(lookup: fun(name: string): integer): integer?
---Pure: ambient colour and the key, fill, rim and top lights from the style tokens.
---@field Lights fun(style: PW.UIStyle): PW.UIOperatorRig

---@class PW.UILib
---@field Operator? PW.UIOperatorLib
