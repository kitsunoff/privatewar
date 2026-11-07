---@meta
-- Player vitals and active primary weapon HUD (T-11.11).

---@class PW.PlayerHudLayout
---@field left number
---@field bottom number
---@field width number
---@field nameY number
---@field nameHeight number
---@field armorY number
---@field armorHeight number
---@field armorGap number
---@field healthY number
---@field healthHeight number
---@field weaponX number
---@field weaponRight number
---@field weaponWidth number
---@field weaponNameY number
---@field weaponAmmoY number

---@class PW.HudWeaponModel
---@field name string
---@field clip? integer nil for a clipless or non-ammo weapon
---@field reserve? integer nil without primary ammo
---@field text string cached CLIP / RESERVE; '-' denotes no magazine
---@field player? Player
---@field weapon? Weapon

---@class PW.HudElement
---@field _HudPainted? boolean last Draw completed successfully

---@alias PW.WeaponHudUpdate fun(valid: boolean, name: string, clip: number?, ammoType: number?, reserve: number?,
---out: PW.HudWeaponModel): PW.HudWeaponModel

---@class PW.HudLib
---@field _HealthFraction fun(health: number?, maximum: number?): number
---@field _ArmorSegments fun(armor: number?, out: number[]): number[]
---@field _PlayerVisible fun(phase: PW.PhaseName, valid: boolean, alive: boolean, spectating: boolean): boolean
---@field _PlayerLayout fun(width: number, height: number, out: table): PW.PlayerHudLayout
---@field _FitText fun(text: string, width: number, measure: fun(text: string): number): string
---@field _WeaponModel PW.WeaponHudUpdate
---@field _NativeHidden fun(name: string, registry: PW.Registry?, phase: PW.PhaseName, active: boolean): boolean
---@field PlayerVisible? fun(): boolean client: the living local player, never an observed player
---@field WeaponState? PW.HudWeaponModel client: snapshot collected outside HUDPaint
