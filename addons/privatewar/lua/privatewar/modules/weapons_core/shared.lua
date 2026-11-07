-- Weapons core module (T-3.1; 04-weapons.md d.1; docs/api/adapter.md "Lookup"). Shared. Owns the adapter lookup:
-- PW.Adapters.For(weaponOrClass) picks the adapter of a class, PW.Adapters.Call calls an adapter method through
-- PW.Call and answers a missing method with the default of PW.Adapters.Defaults. Pure rules over plain data
-- (_Pick, _StatsFromPrimary); the engine calls (weapons.GetStored, entity:GetClass, the registry of the kind) stay
-- in thin wrappers.
--
-- Decisions of the lane agent (adapter.md "Open in design"):
--   1. Lookup name: PW.Adapters.For. Tie rule: the lowest adapter id wins (deterministic, independent of order).
--   2. IsAvailable() is evaluated lazily at the first lookup of a class, and again after every cache flush
--      (PW_RegistriesLoaded, PW_WeaponsLoaded, a phase change): after InitPostEntity every base is mounted.

MODULE.Name = "Weapons core"

local lib = (rawget(PW, "Adapters") or {}) --[[@as PW.AdaptersLib]]
PW.Adapters = lib

---@param opts? { log?: PW.LogFn }
---@return PW.AdapterStore
function lib._NewStore(opts)
    return {
        cache = {},
        logged = {},
        log = (opts ~= nil and opts.log) or function(message) print("[PW] " .. message) end
    }
end

PW._WeaponAdapters = PW._WeaponAdapters or lib._NewStore()

---The PW.Call of the core, looked up on every call so a test can swap it.
---@param adapter PW.Adapter
---@param method string
---@param ... any
---@return any
local function coreCall(adapter, method, ...)
    return PW.Call(adapter, method, ...)
end

---@param adapter PW.Adapter
---@param call PW.AdapterCallFn
---@return boolean
local function isAvailable(adapter, call)
    if not isfunction(adapter.IsAvailable) then return true end
    return call(adapter, "IsAvailable") and true or false
end

---@param adapter PW.Adapter
---@return number
local function priorityOf(adapter)
    local priority = adapter.Priority --[[@as any]]
    if isnumber(priority) then return priority --[[@as number]] end
    return 0
end

---@param adapter PW.Adapter
---@return string
local function idOf(adapter)
    return tostring(adapter.ClassName)
end

---Does a beat b: higher Priority, then the lower id.
---@param a PW.Adapter
---@param b PW.Adapter
---@return boolean
local function beats(a, b)
    local pa, pb = priorityOf(a), priorityOf(b)
    if pa ~= pb then return pa > pb end
    return idOf(a) < idOf(b)
end

---@param list PW.Adapter[]
---@param class string
---@param swep table?
---@param call? PW.AdapterCallFn
---@return PW.Adapter?
function lib._Pick(list, class, swep, call)
    local run = call or coreCall
    ---@type PW.Adapter?
    local best = nil
    for _, adapter in ipairs(list) do
        local contender = best == nil or beats(adapter, best)
        if contender and isAvailable(adapter, run) and run(adapter, "Claims", class, swep) then
            best = adapter
        end
    end
    return best
end

---A cached adapter is usable while it is still valid (a failed call or an enable snapshot invalidates it).
---@param adapter PW.Adapter
---@return boolean
local function stillValid(adapter)
    return not isfunction(adapter.IsValid) or adapter:IsValid()
end

---@param store PW.AdapterStore
---@param registry PW.Registry
---@param class string
---@param swep table?
---@return PW.Adapter?
function lib._Find(store, registry, class, swep)
    if store.registry ~= registry then
        store.registry = registry
        store.cache = {}
    end
    local cached = store.cache[class]
    if cached == false then return nil end
    if cached ~= nil and stillValid(cached) then return cached end
    local found = lib._Pick(registry.GetEnabledList() --[[@as PW.Adapter[] ]], class, swep)
    store.cache[class] = found or false
    return found
end

---@param weaponOrClass Weapon|string
---@return string?
local function classOf(weaponOrClass)
    local any = weaponOrClass --[[@as any]]
    if isstring(any) then return any --[[@as string]] end
    local wep = any --[[@as Weapon]]
    if (istable(wep) or isentity(wep)) and isfunction(wep.GetClass) and IsValid(wep) then
        return wep:GetClass()
    end
    return nil
end

---@param weaponOrClass Weapon|string
---@return PW.Adapter?
function lib.For(weaponOrClass)
    local class = classOf(weaponOrClass)
    local registry = rawget(PW, "WeaponAdapters") --[[@as PW.Registry?]]
    if class == nil or registry == nil then return nil end
    return lib._Find(PW._WeaponAdapters, registry, class, weapons.GetStored(class))
end

function lib.Invalidate()
    PW._WeaponAdapters.cache = {}
end

---Defaults (docs/api/adapter.md): Defaults.<Method>(adapter, ...) with the arguments of the method. Each is
---safe for a plain weapon, one that lacks Primary, an owner, or a clip.
---@type table<string, function>
lib.Defaults = {}
local defaults = lib.Defaults

---@param wep table<string, any>
---@return table
local function primaryOf(wep)
    local primary = wep.Primary --[[@as any]]
    if istable(primary) then return primary end
    return {}
end

---@param value any
---@return number?
local function positive(value)
    if isnumber(value) and value > 0 then return value end
    return nil
end

---@param primary table?
---@return PW.Stats
function lib._StatsFromPrimary(primary)
    local source = primary or {}
    local damage = positive(source.Damage)
    local clip = positive(source.ClipSize)
    return {
        damageNear = damage,
        damageFar = damage,
        rpm = positive(source.RPM),
        magazine = clip ~= nil and math.floor(clip) or nil,
        pellets = positive(source.NumShots)
    }
end

---@param self PW.Adapter
---@param class string
---@return PW.Stats
function defaults.GetBaseStats(self, class)
    local swep = weapons.GetStored(class)
    return lib._StatsFromPrimary(swep ~= nil and primaryOf(swep) or nil)
end

---@param self PW.Adapter
---@param wep Weapon
---@return PW.Stats
function defaults.GetLiveStats(self, wep)
    return lib.Call(self, "GetBaseStats", wep:GetClass())
end

function defaults.PreviewBuildStats() return nil end

---@param self PW.Adapter
---@param class string
---@return IMaterial?
function defaults.GetIcon(self, class)
    if not CLIENT then return nil end
    local material = Material("entities/" .. class .. ".png")
    return material
end

function defaults.GetSlots() return {} end
function defaults.GetOptions() return {} end

---Identity: the build is returned as given, nothing rejected.
---@param self PW.Adapter
---@param _class string
---@param build PW.Build
---@return PW.Build, table<PW.SlotId, string>
function defaults.Validate(self, _class, build)
    return build, {}
end

---No gunsmith: nothing sticks.
---@return PW.Build
function defaults.Apply() return {} end

---@param self PW.Adapter
---@param _locked boolean
function defaults.SetCustomizationLocked(self, _locked)
    local store = PW._WeaponAdapters
    local id = idOf(self)
    if store.logged[id] then return end
    store.logged[id] = true
    store.log(string.format("weapon adapter %q has no SetCustomizationLocked; its customization stays as it is", id))
end

function defaults.SuppressDefaultAmmo() end

---@param self PW.Adapter
---@param wep Weapon
---@return integer
function defaults.GetAmmoType(self, wep)
    return wep:GetPrimaryAmmoType()
end

function defaults.IsReloading() return false end

---@param self PW.Adapter
---@param wep Weapon
---@return boolean
function defaults.IsAiming(self, wep)
    local owner = wep:GetOwner() --[[@as Player]]
    if not IsValid(owner) then return false end
    return owner:KeyDown(IN_ATTACK2) and true or false
end

---@param self PW.Adapter
---@param wep Weapon
---@return integer clip, integer capacity
function defaults.GetClip(self, wep)
    return wep:Clip1(), wep:GetMaxClip1()
end

---A weapon without a magazine (Clip1 < 0, melee and some HL2 weapons) is not blocked by the clip.
---@param self PW.Adapter
---@param wep Weapon
---@return boolean
function defaults.CanFireNow(self, wep)
    local clip = lib.Call(self, "GetClip", wep)
    return wep:GetNextPrimaryFire() <= CurTime() and clip ~= 0
end

function defaults.PrepareForBot() end

---@param self PW.Adapter
---@param wep Weapon
---@return PW.FireInfo
function defaults.GetFireInfo(self, wep)
    local primary = primaryOf(wep --[[@as table<string, any>]])
    local delay = positive(primary.Delay)
    return {
        kind = primary.Automatic and "auto" or "semi",
        burst = 1,
        rpm = positive(primary.RPM) or (delay ~= nil and 60 / delay) or 600,
        adsKey = IN_ATTACK2
    }
end

---@return PW.Recoil
function defaults.GetRecoil()
    return { pitch = 0, yaw = 0, affectsBotAim = false }
end

---Conservative (adapter.md "Open in design" item 7): release between shots, plain IN_RELOAD, never IN_USE with
---attack or reload, no sprint while firing, the core rules of notes/08 section 6.1.
---@return PW.InputRules
function defaults.GetInputRules()
    return {
        releaseBetweenShots = true,
        reloadTap = false,
        reloadTapMax = 0.3,
        forbidWithAttack = IN_USE,
        forbidWithReload = IN_USE,
        noSprintWhileFiring = true,
        sprintToFire = 0.25,
        reselectEveryTick = true
    }
end

function defaults.BotAction() return false end
function defaults.IsHeadshot() return nil end

---@param self PW.Adapter
---@param wep Weapon
---@return string
function defaults.GetDisplayName(self, wep)
    local printName = (wep --[[@as table<string, any>]]).PrintName
    local name = isstring(printName) and printName or wep:GetClass()
    if CLIENT then return language.GetPhrase(name) end
    return name
end

function defaults.InstallStatMods() end
function defaults.RefreshStatMods() end
function defaults.SupportedStatMods() return {} end

---@param adapter PW.Adapter
---@param method string
---@param ... any
---@return any
function lib.Call(adapter, method, ...)
    if isfunction(adapter[method]) then
        local results = { PW.Call(adapter, method, ...) }
        local failed = isfunction(adapter.IsValid) and not adapter:IsValid()
        if not failed then return unpack(results, 1, table.maxn(results)) end
    end
    local fallback = defaults[method]
    if fallback == nil then return nil end
    return fallback(adapter, ...)
end

---@param weaponOrClass Weapon|string
---@param method string
---@param ... any
---@return any
function lib.CallFor(weaponOrClass, method, ...)
    local adapter = lib.For(weaponOrClass)
    if adapter == nil then adapter = { ClassName = "none" } --[[@as any]] end
    return lib.Call(adapter, method, ...)
end

-- The cache follows the registry identity and adapter validity on its own; these hooks also drop it when the set
-- of available adapters can have changed: every boot and reload, the end of the weapon phase (all bases are
-- mounted), and a phase change (the enable snapshot is taken on entering PREMATCH).
function MODULE:PW_RegistriesLoaded() lib.Invalidate() end
function MODULE:PW_WeaponsLoaded() lib.Invalidate() end
function MODULE:PW_PhaseChange() lib.Invalidate() end
function MODULE:PW_PhaseChanged() lib.Invalidate() end
