---@meta
-- Types of weapon adapters and of the adapter lookup (T-3.1; 04-weapons.md d.1; docs/api/adapter.md).
-- Code: lua/privatewar/kinds/weapon_adapters.lua (the kind), lua/privatewar/modules/weapons_core/ (lookup, defaults).

---@alias PW.WeaponKind "gun"|"melee"|"throwable"|"launcher"|"other"
---@alias PW.SlotId string
---@alias PW.OptionId string
---@alias PW.Build table<PW.SlotId, PW.OptionId|false>

---@class PW.WeaponInfo
---@field class string
---@field name string
---@field kind PW.WeaponKind
---@field category? string
---@field slot integer 1 primary, 2 secondary, 3 equipment

---All fields optional; the core shows "-" for nil.
---@class PW.Stats
---@field damageNear? number
---@field damageFar? number
---@field rangeNear? number
---@field rangeFar? number
---@field rpm? number
---@field magazine? integer
---@field adsTime? number
---@field moveMult? number
---@field pellets? integer
---@field recoil? number base recoil, the base's own unit (compared only within one category)
---@field spread? number base spread, the base's own unit
---@field sprintToFire? number seconds

---@class PW.Slot
---@field id PW.SlotId
---@field name string
---@field parent? PW.SlotId
---@field cosmetic boolean
---@field default? PW.OptionId

---@class PW.Option
---@field id PW.OptionId
---@field name string
---@field icon? IMaterial client only
---@field cosmetic boolean

---@class PW.FireInfo
---@field kind "auto"|"semi"|"burst"|"safe"
---@field burst integer
---@field rpm number
---@field adsKey integer
---@field projectileSpeed? number
---@field projectileGravity? number

---@class PW.Recoil
---@field pitch number
---@field yaw number
---@field affectsBotAim boolean

---@class PW.InputRules
---@field releaseBetweenShots boolean
---@field reloadTap boolean
---@field reloadTapMax number
---@field forbidWithAttack integer
---@field forbidWithReload integer
---@field noSprintWhileFiring boolean
---@field sprintToFire number
---@field reselectEveryTick boolean

---A weapon adapter: an entity of the kind weapon_adapters (docs/api/adapter.md). Required: IsAvailable, Claims,
---ListWeapons. Every other method is optional: PW.Adapters.Call falls back to PW.Adapters.Defaults.
---@class PW.Adapter : PW.Entity
---@field Priority? number higher wins when several adapters claim a class; default 0
---@field IsAvailable fun(self: PW.Adapter): boolean
---@field Claims fun(self: PW.Adapter, class: string, swep: table?): boolean
---@field ListWeapons fun(self: PW.Adapter): PW.WeaponInfo[]
---@field GetBaseStats? fun(self: PW.Adapter, class: string): PW.Stats
---@field GetLiveStats? fun(self: PW.Adapter, wep: Weapon): PW.Stats
---@field PreviewBuildStats? fun(self: PW.Adapter, class: string, build: PW.Build): PW.Stats?
---@field GetIcon? fun(self: PW.Adapter, class: string): IMaterial?
---@field GetSlots? fun(self: PW.Adapter, class: string, build: PW.Build?): PW.Slot[]
---@field GetOptions? fun(self: PW.Adapter, class: string, slot: PW.SlotId): PW.Option[]
---Exact selected metadata, equivalent to a cosmetic GetSlots(class, nil) slot OR a cosmetic offered GetOptions entry.
---Nil delegates to legacy discovery. This is not membership validation, ownership, cost or a player permission.
---@field IsSelectionCosmetic? fun(self: PW.Adapter, class: string, slot: PW.SlotId, option: PW.OptionId): boolean?
---@field GetOptionStats? fun(self: PW.Adapter, class: string, slot: PW.SlotId, option: PW.OptionId): PW.OptionStats?
---@field GetOptionSetKey? fun(self: PW.Adapter): string
---@field Validate? fun(self: PW.Adapter, class: string, build: PW.Build): PW.Build, table<PW.SlotId, string>
---@field Apply? fun(self: PW.Adapter, wep: Weapon, build: PW.Build): PW.Build
---@field SetCustomizationLocked? fun(self: PW.Adapter, locked: boolean)
---@field SuppressDefaultAmmo? fun(self: PW.Adapter, wep: Weapon)
---@field GetAmmoType? fun(self: PW.Adapter, wep: Weapon): integer
---@field IsReloading? fun(self: PW.Adapter, wep: Weapon): boolean
---@field IsAiming? fun(self: PW.Adapter, wep: Weapon): boolean
---@field GetClip? fun(self: PW.Adapter, wep: Weapon): integer, integer
---@field CanFireNow? fun(self: PW.Adapter, wep: Weapon): boolean
---@field PrepareForBot? fun(self: PW.Adapter, ply: Player, wep: Weapon)
---@field GetFireInfo? fun(self: PW.Adapter, wep: Weapon): PW.FireInfo
---@field GetRecoil? fun(self: PW.Adapter, wep: Weapon): PW.Recoil
---@field GetInputRules? fun(self: PW.Adapter, wep: Weapon): PW.InputRules
---@field BotAction? fun(self: PW.Adapter, ply: Player, wep: Weapon, action: string, arg: any): boolean
---@field IsHeadshot? fun(self: PW.Adapter, dmginfo: CTakeDamageInfo): boolean?
---@field GetDisplayName? fun(self: PW.Adapter, wep: Weapon): string
---@field InstallStatMods? fun(self: PW.Adapter, wep: Weapon)
---@field RefreshStatMods? fun(self: PW.Adapter, wep: Weapon)
---@field SupportedStatMods? fun(self: PW.Adapter): table<string, boolean>

---Class table inside a weapon_adapters/ file.
---@type PW.Adapter
ADAPTER = nil

---Internal: the lookup cache of this realm.
---@class PW.AdapterStore
---@field registry? PW.Registry the registry the cache was built for
---@field cache table<string, PW.Adapter|false> adapter by class, false = no adapter claims the class
---@field logged table<string, true> adapter ids that already got their one "default used" log line
---@field log PW.LogFn

---Calls a method of an adapter and returns its results (PW.Call by default).
---@alias PW.AdapterCallFn fun(adapter: PW.Adapter, method: string, ...: any): any

---Adapter lookup and method defaults (04-weapons.md d.1; docs/api/adapter.md "Lookup").
---@class PW.AdaptersLib
---The adapter for a weapon entity or a SWEP class: among the enabled adapters of PW.WeaponAdapters whose
---IsAvailable() is not false and whose Claims(class, swepTable) is true, the highest Priority wins; equal
---Priority: the lowest id. nil when none claims. Cached per class; see Invalidate.
---@field For fun(weaponOrClass: Weapon|string): PW.Adapter?
---Calls an adapter method through PW.Call; a method the adapter lacks (or whose call failed and disabled it) is
---answered by PW.Adapters.Defaults[method].
---@field Call fun(adapter: PW.Adapter, method: string, ...: any): any
---For + Call; the defaults are used for a class no adapter claims, with a nil adapter replaced by an empty one.
---@field CallFor fun(weaponOrClass: Weapon|string, method: string, ...: any): any
---Forgets every cached lookup (reload, PW_WeaponsLoaded, phase change).
---@field Invalidate fun()
---The defaults of the optional methods: Defaults.<Method>(adapter, ...) with the arguments of the method.
---@field Defaults table<string, function>
---Internal: a fresh store (tests swap PW._WeaponAdapters).
---@field _NewStore fun(opts?: { log?: PW.LogFn }): PW.AdapterStore
---Internal, pure over the list: the winner among adapters for a class (see For). swep may be nil.
---@field _Pick fun(list: PW.Adapter[], class: string, swep: table?, call?: PW.AdapterCallFn): PW.Adapter?
---Internal: cached lookup of a class in a registry.
---@field _Find fun(store: PW.AdapterStore, registry: PW.Registry, class: string, swep: table?): PW.Adapter?
---Internal, pure: Stats from a SWEP's Primary table (Damage, RPM, ClipSize); every field optional.
---@field _StatsFromPrimary fun(primary: table?): PW.Stats

---@class PW
---@field Adapters PW.AdaptersLib
---@field _WeaponAdapters PW.AdapterStore internal
---The weapon_adapters kind (lua/privatewar/kinds/weapon_adapters.lua).
---@field WeaponAdapters PW.Registry
