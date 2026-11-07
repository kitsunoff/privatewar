-- ARC9 integration module (T-3.6; 04-weapons.md d.2, d.4, d.6; notes/08 sections 2 and 6.2). Shared. Ships in the
-- separate addon privatewar-arc9 and loads only with the gamemode (it lives under lua/privatewar/, which only the
-- gamemode's loader reads). Owns what is base-specific and not per weapon class: the pure helpers the arc9 adapter
-- uses (catalogue info, slot addresses, build trees) and, on the server, the customization lock (init.lua).
--
-- Decisions of the lane agent:
--   1. Slot ids are address paths "i" or "i.j.k" (top slot i, sub-slot j of the attachment in it), not ARC9's flat
--      address, which shifts whenever another slot gains or loses sub-slots (notes/08 section 2.3).
--   2. A build changes only the slots it names; the other slots keep what the weapon has (the class default after
--      Give). false clears a slot. A slot whose attachment changes loses its old sub-slots.
--   3. Categories: ARC9 pistol, shotgun, smg, ar and sniper map to the same names; rpg and special to "special";
--      melee, grenade and misc have none (adapter.md "Open in design" item 9 keeps the closed list open).
if not PW or PW.API ~= 1 then return end

MODULE.Name = "ARC9 integration"

-- 04-weapons.md d.7: the performance profile, a host setting (Host section of SETTINGS); sh_perf.lua.
MODULE.Settings = {
    perf = {
        scope = "server", type = "enum", default = "deck", options = { "deck", "off" },
        label = "ARC9 performance profile",
        description = "deck (recommended) trades ARC9's visual fidelity and simulated bullet travel for frame " ..
            "time on the Steam Deck: simpler distant models and scopes, fewer effects from other players, " ..
            "hitscan bullets without ricochets. off restores your own ARC9 settings and leaves them alone."
    }
}

local lib = (rawget(PW, "Arc9") or {}) --[[@as PW.Arc9Lib]]
PW.Arc9 = lib

lib.Categories = { [1] = "pistol", [2] = "shotgun", [3] = "smg", [4] = "ar", [5] = "sniper", [6] = "special",
    [9] = "special" }

lib.StatHooks = {
    ReloadTime = "reload_time",
    DeployTime = "draw_time",
    AimDownSightsTime = "ads_time",
    SprintToFireTime = "sprint_to_fire",
    Recoil = "recoil",
    Spread = "spread"
}

-- T-11.7: the ARC9 stats behind each PW.OptionStats field, as { stat, condition, share }. An attachment changes a
-- stat through <stat>Mult<condition>, <stat>Add<condition> and <stat>Override<condition>; the field's multiplier is
-- the product of the stat ratios raised to their shares (the recoil components and the hip-fire spread count less).
lib.OptionStatKeys = {
    damage = { { "DamageMax", "", 0.5 }, { "DamageMin", "", 0.5 } },
    range = { { "RangeMax", "", 0.5 }, { "RangeMin", "", 0.5 } },
    rpm = { { "RPM", "", 1 } },
    recoil = { { "Recoil", "", 1 }, { "RecoilUp", "", 1 / 3 }, { "RecoilSide", "", 1 / 3 },
        { "RecoilKick", "", 1 / 3 } },
    spread = { { "Spread", "", 1 }, { "Spread", "HipFire", 0.5 } },
    adsTime = { { "AimDownSightsTime", "", 1 } },
    sprintToFire = { { "SprintToFireTime", "", 1 } },
    moveSpeed = { { "Speed", "", 1 }, { "Speed", "Sights", 0.5 } },
    reloadTime = { { "ReloadTime", "", 1 } }
}

---@param value any
---@return number?
local function positive(value)
    if isnumber(value) and value > 0 and value < math.huge then return value --[[@as number]] end
    return nil
end

---The ratio new/old of one stat under an attachment; nil when the attachment does not touch it (or only adds to a
---stat whose base value is unknown).
---@param att table<string, any>
---@param base table<string, any>
---@param stat string
---@param condition string
---@return number?
local function statRatio(att, base, stat, condition)
    local old = positive(base[stat])
    local override = positive(att[stat .. "Override" .. condition])
    if override ~= nil and old ~= nil then return override / old end
    local mult = positive(att[stat .. "Mult" .. condition])
    local add = att[stat .. "Add" .. condition]
    if not isnumber(add) or old == nil then add = nil end
    if mult == nil and add == nil then return nil end
    local ratio = mult or 1
    if add ~= nil then ratio = math.max(0.01, (old * ratio + add) / old) end
    return ratio
end

function lib._OptionStats(att, base)
    if not istable(att) then return nil end
    ---@type table<string, number>
    local result = {}
    for field, parts in pairs(lib.OptionStatKeys) do
        local product, touched = 1, false
        for _, part in ipairs(parts) do
            local ratio = statRatio(att, base or {}, part[1], part[2])
            if ratio ~= nil then
                product = product * ratio ^ part[3]
                touched = true
            end
        end
        if touched and product ~= 1 then result[field] = product end
    end
    local clip = (att --[[@as table<string, any>]]).ClipSizeAdd --[[@as any]]
    if isnumber(clip) and clip ~= 0 then result.magazineAdd = clip --[[@as number]] end
    if next(result) == nil then return nil end
    return result --[[@as PW.OptionStats]]
end

-- arc9_atts_nocustomize closes the menu and the arc9_networkweapon receiver (which has no owner check);
-- arc9_free_atts 0 closes the arc9_randomizeatts receiver; anarchy would bypass both checks; loseondie would strip
-- builds on death. The adapter's own server path (Apply) goes through none of them.
lib.LockConVars = {
    arc9_atts_nocustomize = "1",
    arc9_atts_anarchy = "0",
    arc9_free_atts = "0",
    arc9_atts_loseondie = "0"
}

-- 09-hud.md d.1: our overlay on the vanilla health and ammo; ARC9's own HUD (ammo, firemode, hints) is hidden while
-- the gamemode runs. arc9_hud_force_disable is replicated, so the server sets it for every client; the hints are a
-- client ConVar. The crosshair stays ARC9's (09 d.1: "vanilla or the weapon base's").
lib.HudConVars = { arc9_hud_force_disable = "1" }
lib.ClientHudConVars = { arc9_hud_hints = "0" }

-- The first Give of each ARC9 weapon class stalls the server for 0.3 to 0.6 s while its models load (measured on the
-- Steam Deck, docs/perf-report.md "ARC9"); ARC9's startup precache moves that cost to the map load. These are server
-- ConVars (archived and replicated, not client ones), read once by ARC9 about 1 s after its Lua loads on every map
-- load; init.lua sets them when the module loads and again on PW_WeaponsLoaded. When ARC9 had not created them yet
-- at the first point, they take effect from the next map load (ARC9 archives them).
lib.PrecacheConVars = { arc9_precache_wepmodels_onstartup = "1", arc9_precache_attsmodels_onstartup = "1" }

-- The session ConVar swaps of this realm (init.lua on the server, cl_init.lua on the client); kept across a reload.
local kept = rawget(PW, "_Arc9") --[[@as PW.Arc9Store?]]
if kept == nil or kept.hud == nil then
    PW._Arc9 = {
        lock = { on = false, saved = {} }, hud = { on = false, saved = {} }, perf = { on = false, saved = {} },
        memo = { values = {} }
    }
end
-- A store kept from before the perf profile existed (reload) gets its swap.
PW._Arc9.perf = rawget(PW._Arc9, "perf") or { on = false, saved = {} }
-- The memo starts empty on every load: a reload may change how its values are computed.
PW._Arc9.memo = { revision = nil, values = {} }

function lib._SwapConVars(swap, values, on, io)
    if on == swap.on then return end
    for name, value in pairs(values) do
        local current = io.get(name)
        if current ~= nil then
            if on then
                swap.saved[name] = current
                io.set(name, value)
            elseif swap.saved[name] ~= nil then
                io.set(name, swap.saved[name])
            end
        end
    end
    if not on then swap.saved = {} end
    swap.on = on
end

local weaponTypeRpg, weaponTypeMelee, weaponTypePistol = 6, 7, 1

---@param swep table<string, any>
---@param weptype integer?
---@return PW.WeaponKind
local function kindOf(swep, weptype)
    if swep.Throwable == true then return "throwable" end
    if swep.PrimaryBash == true or weptype == weaponTypeMelee then return "melee" end
    if weptype == weaponTypeRpg then return "launcher" end
    return "gun"
end

function lib._InfoFrom(swep, weptype)
    local kind = kindOf(swep, weptype)
    local category = kind ~= "melee" and kind ~= "throwable" and lib.Categories[weptype or 0] or nil
    local slot = 1
    if kind == "melee" or kind == "throwable" then
        slot = 3
    elseif weptype == weaponTypePistol then
        slot = 2
    end
    local printName = swep.PrintName
    return {
        class = swep.ClassName,
        name = isstring(printName) and printName or swep.ClassName,
        kind = kind,
        category = category,
        slot = slot
    }
end

function lib._ParseAddress(id)
    if not isstring(id) then return nil end
    ---@type integer[]
    local path = {}
    for part in string.gmatch(id .. ".", "([^%.]*)%.") do
        local index = tonumber(part)
        if index == nil or index < 1 or index ~= math.floor(index) or not string.match(part, "^%d+$") then
            return nil
        end
        path[#path + 1] = index
    end
    return path
end

function lib._Order(build)
    ---@type { id: PW.SlotId, path: integer[] }[]
    local entries = {}
    for id in pairs(build) do
        local path = lib._ParseAddress(id)
        if path ~= nil then entries[#entries + 1] = { id = id, path = path } end
    end
    table.sort(entries, function(a, b)
        if #a.path ~= #b.path then return #a.path < #b.path end
        for i = 1, #a.path do
            if a.path[i] ~= b.path[i] then return a.path[i] < b.path[i] end
        end
        return false
    end)
    ---@type PW.SlotId[]
    local ids = {}
    for _, entry in ipairs(entries) do ids[#ids + 1] = entry.id end
    return ids
end

---@param slots PW.Arc9SlotTable[]?
---@return PW.Arc9Tree
local function treeOf(slots)
    ---@type PW.Arc9Tree
    local tree = {}
    for i, slot in ipairs(slots or {}) do
        local installed = slot.Installed
        tree[i] = {
            Installed = isstring(installed) and installed or nil,
            ToggleNum = slot.ToggleNum,
            SubAttachments = slot.SubAttachments ~= nil and treeOf(slot.SubAttachments) or nil
        }
    end
    return tree
end
lib._TreeOf = treeOf

---The node at a path, creating missing sibling entries under an installed parent; nil when the path cannot exist.
---@param tree PW.Arc9Tree
---@param path integer[]
---@return PW.Arc9Node?
local function nodeAt(tree, path)
    ---@type PW.Arc9Tree
    local list = tree
    ---@type PW.Arc9Node?
    local node = nil
    for depth, index in ipairs(path) do
        if depth == 1 then
            node = list[index]
            if node == nil then return nil end
        else
            if node == nil or node.Installed == nil then return nil end
            node.SubAttachments = node.SubAttachments or {}
            list = node.SubAttachments --[[@as PW.Arc9Tree]]
            for i = #list + 1, index do list[i] = {} end
            node = list[index]
        end
    end
    return node
end

---Every installed node gets one entry per sub-slot of its attachment (BuildSubAttachments walks them with ipairs).
---@param tree PW.Arc9Tree
---@param subCount fun(att: string): integer
local function padSubSlots(tree, subCount)
    for _, node in ipairs(tree) do
        if node.Installed ~= nil then
            node.SubAttachments = node.SubAttachments or {}
            local subs = node.SubAttachments --[[@as PW.Arc9Tree]]
            for i = #subs + 1, subCount(node.Installed) do subs[i] = {} end
            padSubSlots(subs, subCount)
        end
    end
end

function lib._WithBuild(tree, build, subCount)
    local result = table.Copy(tree) --[[@as PW.Arc9Tree]]
    for _, id in ipairs(lib._Order(build)) do
        -- _Order returns only ids that parse.
        local node = nodeAt(result, lib._ParseAddress(id) --[[@as integer[] ]])
        local option = build[id]
        local wanted = isstring(option) and option or nil
        if node ~= nil and node.Installed ~= wanted then
            node.Installed = wanted
            node.SubAttachments = nil
            node.ToggleNum = nil
        end
    end
    padSubSlots(result, subCount)
    return result
end

function lib._ReadBuild(slots, build)
    ---@type PW.Build
    local result = {}
    for id in pairs(build) do
        local path = lib._ParseAddress(id)
        local list = slots --[[@as PW.Arc9SlotTable[]? ]]
        local slot = nil
        for _, index in ipairs(path or {}) do
            slot = list ~= nil and list[index] or nil
            list = slot ~= nil and slot.SubAttachments or nil
        end
        local installed = slot ~= nil and slot.Installed or nil
        result[id] = (path ~= nil and isstring(installed)) and installed or false
    end
    return result
end

---@param slots PW.Arc9SlotTable[]
---@param prefix string?
---@param build PW.Build?
---@param lookup PW.Arc9AttLookup
---@param found PW.Arc9FoundSlot[]
local function walkSlots(slots, prefix, build, lookup, found)
    for i, slot in ipairs(slots) do
        local id = prefix == nil and tostring(i) or (prefix .. "." .. i)
        if slot.Hidden ~= true then found[#found + 1] = { id = id, parent = prefix, slot = slot } end
        local chosen = build ~= nil and build[id] or nil
        local att = isstring(chosen) and lookup(chosen --[[@as string]]) or nil
        local subs = att ~= nil and att.Attachments or nil
        if istable(subs) then walkSlots(subs --[[@as PW.Arc9SlotTable[] ]], id, build, lookup, found) end
    end
end

function lib._FindSlots(top, build, lookup)
    ---@type PW.Arc9FoundSlot[]
    local found = {}
    walkSlots(top, nil, build, lookup, found)
    return found
end

---@param value any
---@return string[]
local function listOf(value)
    if istable(value) then return value --[[@as string[] ]] end
    if isstring(value) then return { value } end
    return {}
end

function lib._IsCosmetic(tbl, cosmetic)
    if tbl.CosmeticOnly == true then return true end
    for _, category in ipairs(listOf(tbl.Category)) do
        if cosmetic[category] then return true end
    end
    return false
end

function lib._Fits(att, slot)
    local slotCategories = listOf(slot.Category)
    for _, category in ipairs(listOf(att.Category)) do
        if category == "*" or table.HasValue(slotCategories, category) then return true end
    end
    return false
end

-- Thin glue over ARC9's tables, shared by the adapter's realms.

function lib._Memo(memo, revision, key, compute)
    if memo.revision ~= revision then
        memo.revision = revision
        memo.values = {}
    end
    local value = memo.values[key]
    if value == nil then
        value = compute()
        memo.values[key] = value
    end
    return value
end

function lib.Revision()
    local arc9 = rawget(_G, "ARC9") --[[@as ARC9Lib?]]
    if arc9 == nil then return "none" end
    return string.format("%s:%d:%d", tostring(arc9.Attachments), tonumber(arc9.Attachments_Count) or 0,
        table.Count(arc9.Blacklist or {}))
end

-- weapons.Get copies the whole SWEP table with its bases (large for ARC9): the slots are read once per revision.
-- Callers only read the result.
function lib.ClassSlots(class)
    return lib._Memo(PW._Arc9.memo, lib.Revision(), "slots:" .. class, function()
        local swep = weapons.Get(class) --[[@as table<string, any>?]]
        local slots = swep ~= nil and swep.Attachments or nil
        return istable(slots) and slots --[[@as PW.Arc9SlotTable[] ]] or {}
    end) --[[@as PW.Arc9SlotTable[] ]]
end

function lib.Offerable(name)
    local arc9 = rawget(_G, "ARC9") --[[@as ARC9Lib?]]
    if arc9 == nil or arc9.Blacklist[name] then return nil end
    local att = arc9.GetAttTable(name)
    if att == nil or att.AdminOnly == true or att.Ignore == true then return nil end
    return att
end

-- T-11.6 follow-up: a bot's bash with an ARC9 weapon. The adapter starts ARC9's own swing (MeleeAttack) on the
-- server instead of pressing ARC9's melee key, so the refusals of the key path are checked here. The fire cadence
-- (the next primary fire time) does not refuse: a bot shoots until the bash, a player would release the trigger.
function lib._BashRefusal(s)
    if not s.bash then return "no_bash" end
    if s.safe then return "safe" end
    if s.inSights then return "sights" end
    if s.grenadePrimed then return "grenade" end
    if s.bipod then return "bipod" end
    if s.swinging then return "swinging" end
    if s.lastMelee + s.preTime / s.speed + s.postTime > s.now then return "cooldown" end
    if s.reloading and not s.cancelsReload then return "reloading" end
    if s.busy then return "busy" end
    if s.sprintLock then return "sprint" end
    if not s.reach then return "out_of_reach" end
    return nil
end

if SERVER then AddCSLuaFile("privatewar/modules/arc9/sh_perf.lua") end
include("privatewar/modules/arc9/sh_perf.lua")
