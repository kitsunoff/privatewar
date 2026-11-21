---@meta

---@alias PW.StimEffect "heal"|"armor"|"speed"

---@class PW.StimMarks
---@field heal number CurTime deadline, or 0 when inactive
---@field armor number CurTime deadline, or 0 when inactive
---@field speed number CurTime deadline, or 0 when inactive

---@class PW.StimsLib
---@field Param fun(item: PW.EquipmentItem|PW.Instance, field: string, settingId: string): any
---@field _Ticks fun(amount: number, duration: number, step: number): number[]
---@field _Step fun(current: number, add: number, cap: number): number
---@field _EffectLines fun(now: number, marks: PW.StimMarks): string[]
---@field _WireItems string[] fixed server/client order of the built-in stim notification indices
---@field Played? fun(owner: Player, item: PW.EquipmentItem|PW.Instance) server presentation for an accepted use
---@field Mark? fun(owner: Player, key: PW.StimEffect, untilTime: number) server active-effect deadline, zero clears

---@class PW.EquipmentItem
---@field Sound? string stock injection sound
---@field Amount? number health or armor total override
---@field Time? number effect duration override in seconds
---@field Mult? number walk and run multiplier override
---@field Max? number armor cap override
---@field UseTime? number injection delay override in seconds

---@class PW
---@field Stims? PW.StimsLib

---Client-only notification after the server accepts a built-in stim use.
---@alias PW.StimInjectedNotification fun(itemId: string)
