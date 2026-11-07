---@meta
-- Optional generic policies; absent questions preserve ordinary modes.
---@alias PW.LoadoutKindPolicy fun(ply: Player, kind: string): boolean?
---@alias PW.JoinInProgressPolicy fun(ply: Player): boolean?

---@class PW.PerksLib
---@field Revoke? fun(ply: Player) remove owned instances and cached modifiers

---@class PW.EquipmentLib
---@field Revoke? fun(ply: Player) clear items, cooking, held grenade weapons/ammo and pending grants

---@class PW.StreaksLib
---@field EndEffects? fun(ply: Player) remove only this owner's instances/effects, keep unused inventory
---@field Revoke? fun(ply: Player) end effects and clear this owner's counter, inventory and set

---@class PW.JipLib
---@field Admit? fun(ply: Player): boolean release an explicitly admitted spectator without spawning

---@class PW.TeamsLib
---@field PlaceLate? fun(ply: Player): integer? public validated late placement, managed selection or balanced fallback

---@class PW.Mode
---@field BotQuotaPolicy? "continuous"|"rounds" nil: managed teams use rounds; other modes continuous

---@class PW.RevealStoreOptions
---@field reset? fun(recipients: any[]) clear derived client radar before replaying still-active sources

---@class PW.RevealPulse
---@field owner? Player source owner, nil for an unowned public reveal
---@field recipients any[]
---@field blips PW.RevealBlip[]
---@field ends number

---@class PW.RevealStore
---@field reset? fun(recipients: any[]) absent only in a store retained from an older reload
---@field pulses? PW.RevealPulse[] absent only in a store retained from an older reload

---@class PW.StreaksLib
---@field _RemoveEffects? fun(owner: Player) internal owning-module radar/jam cleanup
---@field _ResetEffects? fun() internal clear derived radar/jam state for relationship or round reset
