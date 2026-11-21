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

---@class PW.StimAnimation
---@field anim string registered first-person animation name
---@field skin integer local gesture skin

---@alias PW.StimBackend "gcal"|"vmanip"

---@class PW.StimsArcticLib
---@field Anims table<string, PW.StimAnimation>
---@field _PickBackend fun(hasGcal: boolean, hasVManip: boolean, gcalHas: boolean, vmanipHas: boolean): PW.StimBackend?
---@field _AnimFor fun(itemId: string, anims: table<string, string>|table<string, PW.StimAnimation>): string?
---@field _ShouldSwap fun(current: string?): boolean
---@field _VialOriginal? string server's original value, retained across registry reloads
---@field _MissingWarned? boolean client diagnostic latch, retained until map change

---@class PW
---@field StimsArctic? PW.StimsArcticLib only present when the optional integration is mounted
