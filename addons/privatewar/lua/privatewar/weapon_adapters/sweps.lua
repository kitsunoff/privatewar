-- Fallback weapon adapter (T-3.2; 04-weapons.md d.1; docs/api/adapter.md "Fallback adapter"). An ordinary entity of
-- the kind weapon_adapters that serves plain Lua SWEPs and the HL2 engine weapons, so the game works with no weapon
-- base installed.
--
-- Decisions of the lane agent:
--   1. Priority -100: below the default 0 of an adapter that sets none, so any adapter that claims a class wins.
--   2. Claims: any class with a SWEP table, and the fixed HL2 classes below (engine weapons are not Lua SWEPs:
--      weapons.GetStored returns nil for them, notes/08 section 5).
--   3. ListWeapons: spawnable, not admin-only Lua SWEPs that are not a base (a class used as the Base of another
--      SWEP, or named like "*_base"), plus the HL2 list.
--   4. Stats: Primary.* for SWEPs (PW.Adapters._StatsFromPrimary); fixed gameplay values for HL2 weapons.
-- Every other method is answered by PW.Adapters.Defaults.

ADAPTER.Priority = -100

---Fixed data of the HL2 engine weapons: slot (1 primary, 2 secondary, 3 equipment), kind, category and base stats
---(gameplay values, to be confirmed by the user).
---@type table<string, { slot: integer, kind: PW.WeaponKind, category?: string, name: string, stats: PW.Stats }>
local hl2 = {
    weapon_crowbar = {
        slot = 3, kind = "melee", name = "Crowbar", stats = { damageNear = 25, damageFar = 25, rpm = 120 }
    },
    weapon_stunstick = {
        slot = 3, kind = "melee", name = "Stunstick", stats = { damageNear = 40, damageFar = 40, rpm = 90 }
    },
    weapon_pistol = {
        slot = 2, kind = "gun", category = "pistol", name = "9MM Pistol",
        stats = { damageNear = 8, damageFar = 8, rpm = 400, magazine = 18 }
    },
    weapon_357 = {
        slot = 2, kind = "gun", category = "pistol", name = ".357 Magnum",
        stats = { damageNear = 75, damageFar = 75, rpm = 70, magazine = 6 }
    },
    weapon_smg1 = {
        slot = 1, kind = "gun", category = "smg", name = "SMG",
        stats = { damageNear = 8, damageFar = 8, rpm = 800, magazine = 45 }
    },
    weapon_ar2 = {
        slot = 1, kind = "gun", category = "ar", name = "Pulse Rifle",
        stats = { damageNear = 12, damageFar = 12, rpm = 600, magazine = 30 }
    },
    weapon_shotgun = {
        slot = 1, kind = "gun", category = "shotgun", name = "Shotgun",
        stats = { damageNear = 8, damageFar = 8, rpm = 70, magazine = 6, pellets = 7 }
    },
    weapon_crossbow = {
        slot = 1, kind = "gun", category = "special", name = "Crossbow",
        stats = { damageNear = 100, damageFar = 100, rpm = 40, magazine = 1 }
    },
    weapon_rpg = {
        slot = 1, kind = "launcher", category = "special", name = "RPG Launcher",
        stats = { damageNear = 150, damageFar = 150, rpm = 30, magazine = 1 }
    },
    weapon_frag = {
        slot = 3, kind = "throwable", name = "Frag Grenade", stats = { damageNear = 125, damageFar = 125 }
    },
    weapon_slam = {
        slot = 3, kind = "throwable", name = "S.L.A.M.", stats = { damageNear = 150, damageFar = 150 }
    }
}

---@return boolean
function ADAPTER:IsAvailable() return true end

---@param class string
---@param swep table?
---@return boolean
function ADAPTER:Claims(class, swep)
    return swep ~= nil or hl2[class] ~= nil
end

---@param swep table<string, any>
---@return PW.WeaponKind
local function kindOf(swep)
    local holdType = swep.HoldType
    if holdType == "melee" or holdType == "melee2" or holdType == "knife" or holdType == "fist" then return "melee" end
    if holdType == "grenade" then return "throwable" end
    if holdType == "rpg" then return "launcher" end
    local primary = swep.Primary --[[@as any]]
    if istable(primary) and (isnumber(primary.Damage) or isnumber(primary.ClipSize)) then return "gun" end
    return "other"
end

---GMod slots are 0-based: pistols sit in slot 1; melee, grenades and utility go to equipment.
---@param swep table<string, any>
---@param kind PW.WeaponKind
---@return integer
local function slotOf(swep, kind)
    if kind == "melee" or kind == "throwable" or kind == "other" then return 3 end
    if swep.Slot == 1 then return 2 end
    return 1
end

---The classes that are used as the Base of another SWEP in the list.
---@param list table<string, any>[]
---@return table<string, true>
local function baseClasses(list)
    ---@type table<string, true>
    local bases = {}
    for _, swep in ipairs(list) do
        if isstring(swep.Base) then bases[swep.Base] = true end
    end
    return bases
end

---@param swep table<string, any>
---@param bases table<string, true>
---@return boolean
local function isCandidate(swep, bases)
    local class = swep.ClassName
    if not isstring(class) or swep.Spawnable ~= true or swep.AdminOnly == true then return false end
    return not bases[class] and not string.EndsWith(class, "_base") and class ~= "weapon_base"
end

---Pure over plain data: the catalogue candidates among a list of SWEP tables (weapons.GetList()), then the HL2 list.
---@param list table<string, any>[]
---@return PW.WeaponInfo[]
function ADAPTER:_ListFrom(list)
    ---@type PW.WeaponInfo[]
    local result = {}
    local bases = baseClasses(list)
    for _, swep in ipairs(list) do
        if isCandidate(swep, bases) then
            local kind = kindOf(swep)
            local printName = swep.PrintName
            result[#result + 1] = {
                class = swep.ClassName,
                name = isstring(printName) and printName or swep.ClassName,
                kind = kind,
                slot = slotOf(swep, kind)
            }
        end
    end
    local classes = table.GetKeys(hl2) --[[@as string[] ]]
    table.sort(classes)
    for _, class in ipairs(classes) do
        local info = hl2[class]
        result[#result + 1] = {
            class = class, name = info.name, kind = info.kind, category = info.category, slot = info.slot
        }
    end
    return result
end

---@return PW.WeaponInfo[]
function ADAPTER:ListWeapons()
    return self:_ListFrom(weapons.GetList() --[[@as table<string, any>[] ]])
end

---Pure over plain data: the stats of a class given its SWEP table (nil for an engine weapon).
---@param class string
---@param swep table<string, any>?
---@return PW.Stats
function ADAPTER:_StatsOf(class, swep)
    if swep == nil then
        local info = hl2[class]
        return info ~= nil and table.Copy(info.stats) or {}
    end
    local primary = swep.Primary --[[@as table?]]
    return PW.Adapters._StatsFromPrimary(istable(primary) and primary or nil)
end

---@param class string
---@return PW.Stats
function ADAPTER:GetBaseStats(class)
    return self:_StatsOf(class, weapons.GetStored(class))
end
