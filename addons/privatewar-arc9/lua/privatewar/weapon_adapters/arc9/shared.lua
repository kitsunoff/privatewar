-- ARC9 weapon adapter (T-3.6; 04-weapons.md d.1, d.2, d.4, d.6; notes/08 sections 2, 5.1 and 6.2; notes/12 section
-- 6.3). Shared part: discovery, catalogue, stats, slots and options, state, bot fire info and input rules, stat
-- modifiers. The server part (Apply, Validate, the lock, ammo, PrepareForBot) is in init.lua. Pure rules live in the
-- module arc9 (PW.Arc9); this file is the thin glue over ARC9's public tables and weapon methods.
--
-- Decisions of the lane agent:
--   1. Priority 100 (04-weapons.md "Registration"): above the fallback sweps (-100) and the default 0.
--   2. Claims every class based on arc9_base; ListWeapons lists those ARC9 itself treats as spawnable (not
--      NotAWeapon, Spawnable, not AdminOnly), with the type from ARC9.SpawnableWeapons or ARC9WeaponCategory.
--   3. Stat modifiers: per-instance <Stat>Hook fields (an affector of ARC9's stat pipeline) wrapping a hook the pack
--      already defines; refresh = DoInvalidateCache. All six keys are supported.
if not PW or PW.API ~= 1 then return end

ADAPTER.Priority = 100

local metresPerUnit = 0.0254

---@return ARC9Lib
local function arc9()
    return rawget(_G, "ARC9") --[[@as ARC9Lib]]
end

---@param name string
---@return table?
local function attTable(name)
    return arc9().GetAttTable(name)
end

---@return boolean
function ADAPTER:IsAvailable()
    return rawget(_G, "ARC9") ~= nil
end

---@param class string
---@param swep table?
---@return boolean
function ADAPTER:Claims(class, swep)
    return swep ~= nil and weapons.IsBasedOn(class, "arc9_base")
end

---@return PW.WeaponInfo[]
function ADAPTER:ListWeapons()
    local spawnable = arc9().SpawnableWeapons or {}
    ---@type PW.WeaponInfo[]
    local result = {}
    for _, stored in ipairs(weapons.GetList() --[[@as table<string, any>[] ]]) do
        local class = stored.ClassName
        if isstring(class) and weapons.IsBasedOn(class, "arc9_base") then
            local swep = weapons.Get(class) --[[@as table<string, any>]]
            if swep.NotAWeapon ~= true and swep.Spawnable == true and swep.AdminOnly ~= true then
                local weptype = spawnable[class] or swep.ARC9WeaponCategory
                result[#result + 1] = PW.Arc9._InfoFrom(swep, isnumber(weptype) and weptype or nil)
            end
        end
    end
    table.sort(result, function(a, b) return a.class < b.class end)
    return result
end

---@param read fun(name: string): any
---@return PW.Stats
local function statsFrom(read)
    ---@param name string
    ---@return number?
    local function number(name)
        local value = read(name)
        if isnumber(value) then return value end
        return nil
    end
    local pellets = math.max(1, math.floor(number("Num") or 1))
    local damageMax, damageMin = number("DamageMax"), number("DamageMin")
    local rangeMin, rangeMax = number("RangeMin"), number("RangeMax")
    local clip = number("ClipSize")
    return {
        damageNear = damageMax ~= nil and damageMax * pellets or nil,
        damageFar = damageMin ~= nil and damageMin * pellets or nil,
        rangeNear = rangeMin ~= nil and rangeMin * metresPerUnit or nil,
        rangeFar = rangeMax ~= nil and rangeMax * metresPerUnit or nil,
        rpm = number("RPM"),
        magazine = clip ~= nil and math.floor(clip) or nil,
        adsTime = number("AimDownSightsTime"),
        moveMult = number("SpeedMult"),
        pellets = pellets,
        recoil = number("Recoil"),
        spread = number("Spread"),
        sprintToFire = number("SprintToFireTime")
    }
end

---@param class string
---@return PW.Stats
function ADAPTER:GetBaseStats(class)
    local swep = weapons.Get(class) --[[@as table<string, any>?]]
    if swep == nil then return {} end
    return statsFrom(function(name) return swep[name] end)
end

---@param wep Weapon
---@return PW.Stats
function ADAPTER:GetLiveStats(wep)
    local gun = wep --[[@as PW.Arc9Weapon]]
    return statsFrom(function(name) return gun:GetProcessedValue(name, true) end)
end

---@param slot PW.Arc9SlotTable
---@return string
local function slotName(slot)
    if isstring(slot.PrintName) then return slot.PrintName --[[@as string]] end
    local category = slot.Category
    if istable(category) then return tostring((category --[[@as string[] ]])[1]) end
    return tostring(category)
end

---A copy of a cached list of flat records, so a caller that changes its list leaves the cache as it was.
---@param list table[]
---@return table[]
local function copyList(list)
    ---@type table[]
    local result = {}
    for i, entry in ipairs(list) do result[i] = table.Copy(entry) end
    return result
end

---@param class string
---@param build PW.Build?
---@return PW.Slot[]
local function slotsOf(class, build)
    ---@type PW.Slot[]
    local result = {}
    local cosmetic = arc9().CosmeticCategories or {}
    for _, found in ipairs(PW.Arc9._FindSlots(PW.Arc9.ClassSlots(class), build, attTable)) do
        local default = found.slot.Installed
        result[#result + 1] = {
            id = found.id,
            name = slotName(found.slot),
            parent = found.parent,
            cosmetic = PW.Arc9._IsCosmetic(found.slot, cosmetic),
            default = isstring(default) and default or nil
        }
    end
    return result
end

---The slots without a build (the loadout checks ask for them per option) are read once per memo revision.
---@param class string
---@param build PW.Build?
---@return PW.Slot[]
function ADAPTER:GetSlots(class, build)
    if build ~= nil then return slotsOf(class, build) end
    local lib = PW.Arc9
    return copyList(lib._Memo(PW._Arc9.memo, lib.Revision(), "slotlist:" .. class, function()
        return slotsOf(class, nil)
    end) --[[@as PW.Slot[] ]])
end

---The slot table of an id; a nested id follows the class defaults installed above it.
---@param class string
---@param id PW.SlotId
---@return PW.Arc9SlotTable?
local function slotTable(class, id)
    local path = PW.Arc9._ParseAddress(id)
    if path == nil then return nil end
    local list = PW.Arc9.ClassSlots(class)
    local slot = nil
    for _, index in ipairs(path) do
        slot = list[index]
        if slot == nil then return nil end
        local installed = slot.Installed
        local att = isstring(installed) and attTable(installed --[[@as string]]) or nil
        list = att ~= nil and istable(att.Attachments) and att.Attachments or {}
    end
    return slot
end

---ARC9's GetAttsForCats walks every registered attachment; the answer per category list is kept per revision.
---@param category string|string[]
---@return string[]
local function attsFor(category)
    local lib = PW.Arc9
    local key = "cats:" .. (istable(category) and table.concat(category --[[@as string[] ]], "\n")
        or tostring(category))
    return lib._Memo(PW._Arc9.memo, lib.Revision(), key, function()
        return arc9().GetAttsForCats(category)
    end) --[[@as string[] ]]
end

---@param class string
---@param id PW.SlotId
---@return PW.Option[]
local function optionsOf(class, id)
    local slot = slotTable(class, id)
    if slot == nil then return {} end
    local cosmetic = arc9().CosmeticCategories or {}
    ---@type PW.Option[]
    local result = {}
    for _, name in ipairs(attsFor(slot.Category or "")) do
        local att = PW.Arc9.Offerable(name)
        if att ~= nil then
            local printName = (att --[[@as table<string, any>]]).PrintName
            result[#result + 1] = {
                id = name,
                name = isstring(printName) and printName or name,
                cosmetic = PW.Arc9._IsCosmetic(att, cosmetic)
            }
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

---Read once per memo revision (the loadout checks ask for the same lists again and again).
---@param class string
---@param id PW.SlotId
---@return PW.Option[]
function ADAPTER:GetOptions(class, id)
    local lib = PW.Arc9
    return copyList(lib._Memo(PW._Arc9.memo, lib.Revision(), "options:" .. class .. "|" .. tostring(id), function()
        return optionsOf(class, id)
    end) --[[@as PW.Option[] ]])
end

---T-11.7: the raw base values of the stats an attachment may add to or override, read once per memo revision.
---@param class string
---@return table<string, any>
local function baseValues(class)
    local lib = PW.Arc9
    return lib._Memo(PW._Arc9.memo, lib.Revision(), "base:" .. class, function()
        local swep = weapons.Get(class) --[[@as table<string, any>?]]
        ---@type table<string, any>
        local values = {}
        if swep == nil then return values end
        for _, parts in pairs(lib.OptionStatKeys) do
            for _, part in ipairs(parts) do values[part[1]] = swep[part[1]] end
        end
        return values
    end) --[[@as table<string, any>]]
end

---T-11.7 (docs/api/adapter.md "Option stats"): the stat changes of an option from its ARC9 attachment table.
---@param class string
---@param _ PW.SlotId
---@param option PW.OptionId
---@return PW.OptionStats?
function ADAPTER:GetOptionStats(class, _, option)
    return PW.Arc9._OptionStats(PW.Arc9.Offerable(option), baseValues(class))
end

---T-11.7: the attachment set (names and count), so a cache of option levels is redone when packs change.
---@return string
function ADAPTER:GetOptionSetKey()
    local lib = PW.Arc9
    return lib._Memo(PW._Arc9.memo, lib.Revision(), "optionsetkey", function()
        ---@type string[]
        local names = {}
        for name in pairs(arc9().Attachments or {}) do names[#names + 1] = tostring(name) end
        table.sort(names)
        return #names .. ":" .. util.CRC(table.concat(names, "\n"))
    end) --[[@as string]]
end

---@param wep Weapon
---@return boolean
function ADAPTER:IsReloading(wep)
    return (wep --[[@as PW.Arc9Weapon]]):GetReloading() and true or false
end

---@param wep Weapon
---@return boolean
function ADAPTER:IsAiming(wep)
    return (wep --[[@as PW.Arc9Weapon]]):GetInSights() and true or false
end

---@param wep Weapon
---@return integer clip, integer capacity
function ADAPTER:GetClip(wep)
    return wep:Clip1(), (wep --[[@as PW.Arc9Weapon]]):GetCapacity()
end

---ARC9 firemode: -1 auto, 0 safe, 1 semi, N an N-round burst (notes/08 section 2.4).
---@param wep Weapon
---@return PW.FireInfo
function ADAPTER:GetFireInfo(wep)
    local gun = wep --[[@as PW.Arc9Weapon]]
    local mode = gun:GetCurrentFiremode()
    local kind = "burst"
    if mode < 0 then kind = "auto" elseif mode == 0 then kind = "safe" elseif mode == 1 then kind = "semi" end
    local rpm = gun:GetProcessedValue("RPM", true)
    return {
        kind = kind,
        burst = mode > 1 and mode or 1,
        rpm = isnumber(rpm) and rpm or 600,
        adsKey = IN_ATTACK2
    }
end

---notes/08 section 6.2: IN_USE or IN_WALK turn a reload into an inspect or block it; semi and burst need IN_ATTACK
---released between shots; ARC9 locks fire while sprinting until SprintToFireTime has passed.
---@param wep Weapon
---@return PW.InputRules
function ADAPTER:GetInputRules(wep)
    local gun = wep --[[@as PW.Arc9Weapon]]
    local sprintToFire = gun:GetProcessedValue("SprintToFireTime", true)
    return {
        releaseBetweenShots = gun:GetCurrentFiremode() >= 0,
        reloadTap = false,
        reloadTapMax = 0.3,
        forbidWithAttack = IN_USE,
        forbidWithReload = bit.bor(IN_USE, IN_WALK),
        noSprintWhileFiring = true,
        sprintToFire = isnumber(sprintToFire) and sprintToFire or 0.25,
        reselectEveryTick = true
    }
end

---@return table<string, boolean>
function ADAPTER:SupportedStatMods()
    ---@type table<string, boolean>
    local keys = {}
    for _, key in pairs(PW.Arc9.StatHooks) do keys[key] = true end
    return keys
end

---The instance hook of one stat: the pack's own hook first (if any), then the owner's multiplier.
---@param packHook any
---@param key PW.StatModKey
---@return fun(wep: Weapon, value: any): any
local function statHook(packHook, key)
    return function(wep, value)
        local changed = isfunction(packHook) and packHook(wep, value) or nil
        local result = changed ~= nil and changed or value
        if not isnumber(result) then return result end
        return result * PW.GetStatMod(wep:GetOwner() --[[@as Player]], key)
    end
end

---@param wep Weapon
function ADAPTER:InstallStatMods(wep)
    local gun = wep --[[@as PW.Arc9Weapon]]
    if gun.pwArc9StatMods then return end
    gun.pwArc9StatMods = true
    local fields = gun --[[@as table<string, any>]]
    for stat, key in pairs(PW.Arc9.StatHooks) do
        fields[stat .. "Hook"] = statHook(fields[stat .. "Hook"], key)
    end
end

---@param wep Weapon
function ADAPTER:RefreshStatMods(wep)
    (wep --[[@as PW.Arc9Weapon]]):DoInvalidateCache()
end
