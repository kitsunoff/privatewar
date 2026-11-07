-- Weapons catalogue module (T-3.3; 04-weapons.md d.3; 06-progression.md d.2; docs/api/adapter.md "Weapon
-- catalogue"). Shared. Fills the weapons kind with what the adapters list, next to the declarative files of
-- lua/privatewar/weapons/. Pure rules over plain data (_Entries, _Fill); the registry and PW.Call stay in thin
-- wrappers.
--
-- Decisions of the lane agent:
--   1. ListWeapons has one generic caller: this module. In PW_RegisterWeapons it calls ListWeapons of every
--      enabled, available adapter, highest Priority first (ties: lowest id), and registers each entry with
--      reg.Register(entry, class, { soft = true }). The fields taken from PW.WeaponInfo: Name, Category, Kind,
--      Slot. An integration module still curates with its own soft registration (Attachments, Camos, Unlock...).
--   2. Order independence. A soft registration only fills missing fields of an existing entry, but a later plain
--      registration of the same class replaces the entry (01-extensibility.md d.12), and the soft fields would be
--      lost. So during the phase the module keeps what it filled (the "fills") and, on PW_PreRegister of a weapons
--      entry, adds the missing fields to the incoming table. The fills live from PW_RegisterWeapons to
--      PW_WeaponsLoaded; a registration after the phase replaces, as the core says.

MODULE.Name = "Weapons catalogue"

local lib = (rawget(PW, "WeaponsCatalog") or {}) --[[@as PW.WeaponsCatalogLib]]
PW.WeaponsCatalog = lib

---@type PW.WeaponsCatalogStore
PW._WeaponsCatalog = PW._WeaponsCatalog or { fills = {} }

---@param adapter PW.Adapter
---@return number
local function priorityOf(adapter)
    local priority = adapter.Priority --[[@as any]]
    if isnumber(priority) then return priority --[[@as number]] end
    return 0
end

---Does a come before b: higher Priority, then the lower id.
---@param a PW.Adapter
---@param b PW.Adapter
---@return boolean
local function before(a, b)
    local pa, pb = priorityOf(a), priorityOf(b)
    if pa ~= pb then return pa > pb end
    return tostring(a.ClassName) < tostring(b.ClassName)
end

---The fields of an entry that a PW.WeaponInfo gives; nil when it has no class.
---@param weaponInfo PW.WeaponInfo
---@return table<string, any>?
function lib._EntryFromInfo(weaponInfo)
    if not istable(weaponInfo) or not isstring(weaponInfo.class) then return nil end
    ---@type table<string, any>
    local entry = {}
    if isstring(weaponInfo.name) then entry.Name = weaponInfo.name end
    if isstring(weaponInfo.category) then entry.Category = weaponInfo.category end
    if isstring(weaponInfo.kind) then entry.Kind = weaponInfo.kind end
    if isnumber(weaponInfo.slot) then entry.Slot = weaponInfo.slot end
    return entry
end

---Pure: entries by class from lists in priority order; the first list that gives a field wins it.
---@param lists PW.WeaponInfo[][]
---@return table<string, table<string, any>>
function lib._Entries(lists)
    ---@type table<string, table<string, any>>
    local entries = {}
    for _, list in ipairs(lists) do
        for _, weaponInfo in ipairs(list) do
            local entry = lib._EntryFromInfo(weaponInfo)
            if entry ~= nil then
                local class = weaponInfo.class
                entries[class] = entries[class] or {}
                lib._Fill(entries[class], entry)
            end
        end
    end
    return entries
end

---Pure: copies into target every field of source that target lacks; nested tables are merged per key. Values
---are copied, so target never aliases source.
---@param target table<any, any>
---@param source table<any, any>
function lib._Fill(target, source)
    for key, value in pairs(source) do
        local existing = target[key]
        if existing == nil then
            target[key] = istable(value) and table.Copy(value) or value
        elseif istable(existing) and istable(value) then
            lib._Fill(existing, value)
        end
    end
end

---@param adapter PW.Adapter
---@param call PW.AdapterCallFn
---@return PW.WeaponInfo[]?
local function listOf(adapter, call)
    if isfunction(adapter.IsAvailable) and not call(adapter, "IsAvailable") then return nil end
    local list = call(adapter, "ListWeapons")
    if not istable(list) then return nil end
    return list --[[@as PW.WeaponInfo[] ]]
end

---The lists of the available adapters, highest Priority first.
---@param adapters PW.Adapter[]
---@param call PW.AdapterCallFn
---@return PW.WeaponInfo[][]
function lib._Lists(adapters, call)
    ---@type PW.Adapter[]
    local sorted = {}
    for index, adapter in ipairs(adapters) do sorted[index] = adapter end
    table.sort(sorted, before)
    ---@type PW.WeaponInfo[][]
    local lists = {}
    for _, adapter in ipairs(sorted) do
        local list = listOf(adapter, call)
        if list ~= nil then lists[#lists + 1] = list end
    end
    return lists
end

---@param adapter PW.Adapter
---@param method string
---@param ... any
---@return any
local function coreCall(adapter, method, ...)
    return PW.Call(adapter, method, ...)
end

---@return PW.Adapter[]
local function enabledAdapters()
    local registry = rawget(PW, "WeaponAdapters") --[[@as PW.Registry?]]
    if registry == nil then return {} end
    return registry.GetEnabledList() --[[@as PW.Adapter[] ]]
end

---Registers every listed weapon softly in reg and remembers the fills for the rest of the phase.
---@param reg PW.Registry
---@param adapters? PW.Adapter[] default: the enabled weapon adapters
---@param call? PW.AdapterCallFn default: PW.Call
---@return integer registered
function lib.Populate(reg, adapters, call)
    local entries = lib._Entries(lib._Lists(adapters or enabledAdapters(), call or coreCall))
    PW._WeaponsCatalog.fills = entries
    ---@type string[]
    local classes = table.GetKeys(entries) --[[@as string[] ]]
    table.sort(classes)
    for _, class in ipairs(classes) do
        reg.Register(table.Copy(entries[class]), class, { soft = true })
    end
    return #classes
end

---Forgets the fills (end of the phase, tests).
function lib._Release()
    PW._WeaponsCatalog.fills = {}
end

---The enabled entries of a category, sorted by class.
---@param category string
---@param registry? PW.Registry default: PW.Weapons
---@return PW.Weapon[]
function lib.GetByCategory(category, registry)
    local source = registry or rawget(PW, "Weapons") --[[@as PW.Registry?]]
    ---@type PW.Weapon[]
    local result = {}
    if source == nil then return result end
    for _, entity in ipairs(source.GetEnabledList()) do
        ---@cast entity PW.Weapon
        if entity.Category == category then result[#result + 1] = entity end
    end
    return result
end

function MODULE:PW_RegisterWeapons(reg)
    lib.Populate(reg)
end

function MODULE:PW_WeaponsLoaded()
    lib._Release()
end

---A plain registration of a weapon during the phase keeps the fields the adapters gave (see decision 2).
function MODULE:PW_PreRegister(kind, id, tbl)
    if kind ~= "weapons" then return end
    local fill = PW._WeaponsCatalog.fills[id]
    if fill ~= nil then lib._Fill(tbl, fill) end
end
