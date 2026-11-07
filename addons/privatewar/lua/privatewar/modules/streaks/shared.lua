-- Streaks module (T-4.6; 05-loadout.md d.9, d.10). Shared and pure: the three streak slots of the loadout, the
-- settings, the earning rules (kills or score, reset on death, persist, no chaining), the inventory, the keys and
-- the wire. The reveal rules are sh_reveal.lua; server state, earning hooks and activation are init.lua and
-- sv_reveal.lua; keys and the radar data are cl_init.lua; the streaks themselves are lua/privatewar/streaks/.
--
-- Wire (client -> server, "pw_streak_use", through PW.Net.Receive: LIVE only, rate-limited): one UInt(WireBits),
-- the 1-based inventory index of the streak to activate. Progress, inventory and the streak set reach the client as
-- NW2 values of the player ("pw_streak_n", "pw_streak_inv", "pw_streak_set"), written only when they change.
--
-- Decisions of the lane agent:
--   1. Slots streak1..streak3 (kind streaks, no filter), declared here like the equipment slots; defaults UAV,
--      Counter-UAV, Airstrike (the loadout module's Default and the class presets).
--   2. Kills mode counts the score event "kill"; score mode adds the points of every score event (PW_ScoreEvent).
--   3. A streak is earned when the counter crosses its cost; the counter does not loop after the last streak.
--   4. Kills and points scored while a streak deals damage (PW.Streaks.StreakDamage) are streak kills.
--   5. Keys: 5 activates the selected streak, 6 selects the next one; console commands pw_streak, pw_streak_next.
--   6. The inventory keeps at most MaxInventory streaks (the oldest is dropped); it lives for the match.

MODULE.Name = "Streaks"

MODULE.Settings = {
    earn = { type = "enum", options = { "kills", "score" }, default = "kills", label = "Earn killstreaks by" },
    persist = { type = "bool", default = false, label = "Keep the streak counter after death" },
    chain = { type = "bool", default = false, label = "Streak kills count toward streaks" }
}

local lib = (rawget(PW, "Streaks") or {}) --[[@as PW.StreaksLib]]
PW.Streaks = lib

lib.Slots = { "streak1", "streak2", "streak3" }
lib.Defaults = { streak1 = "uav", streak2 = "counter_uav", streak3 = "airstrike" }
lib.Keys = {
    use = { command = "pw_streak", convar = "pw_key_streak", default = "5" },
    next = { command = "pw_streak_next", convar = "pw_key_streak_next", default = "6" }
}
lib.WireBits = 4
lib.MaxInventory = 15
lib.DefaultDuration = 10
lib.ScorePerKill = 100
lib.NetName = "pw_streak_use"
lib.ProgressKey, lib.InventoryKey, lib.SetKey = "pw_streak_n", "pw_streak_inv", "pw_streak_set"

if SERVER then AddCSLuaFile("privatewar/modules/streaks/sh_reveal.lua") end
include("privatewar/modules/streaks/sh_reveal.lua")

function lib._Cost(def, earn)
    local kills = math.max(1, math.floor(tonumber(def.Kills) or 1))
    if earn ~= "score" then return kills end
    local score = tonumber(def.Score)
    if score ~= nil and score > 0 then return math.floor(score) end
    return kills * lib.ScorePerKill
end

function lib._Set(loadout, lookup, earn)
    ---@type PW.StreakSetEntry[]
    local set = {}
    ---@type table<string, true>
    local seen = {}
    for _, slot in ipairs(lib.Slots) do
        local id = loadout[slot] --[[@as any]]
        local def = isstring(id) and not seen[id] and lookup(id) or nil
        if def ~= nil then
            seen[id] = true
            set[#set + 1] = { id = id, cost = lib._Cost(def, earn) }
        end
    end
    table.sort(set, function(a, b)
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.id < b.id
    end)
    return set
end

function lib._Gain(earn, eventId, points)
    if earn == "score" then return math.max(0, tonumber(points) or 0) end
    if eventId == "kill" then return 1 end
    return 0
end

function lib._Counts(chain, fromStreak)
    return chain == true or not fromStreak
end

function lib._Crossed(set, before, after)
    ---@type string[]
    local ids = {}
    for _, entry in ipairs(set) do
        if before < entry.cost and entry.cost <= after then ids[#ids + 1] = entry.id end
    end
    return ids
end

function lib._AfterDeath(progress, persist)
    if persist then return progress end
    return 0
end

function lib._NextGoal(set, progress)
    for _, entry in ipairs(set) do
        if entry.cost > progress then return entry end
    end
    return nil
end

function lib._Push(inventory, id, max)
    inventory[#inventory + 1] = id
    while #inventory > max do table.remove(inventory, 1) end
    return inventory
end

function lib._Find(inventory, id)
    for index, value in ipairs(inventory) do
        if value == id then return index end
    end
    return nil
end

function lib._Select(selected, count, step)
    if count < 1 then return 1 end
    local index = (math.floor(tonumber(selected) or 1) - 1 + (step or 0)) % count
    return index + 1
end

function lib._EncodeInventory(inventory)
    return table.concat(inventory, ",")
end

function lib._DecodeInventory(text)
    ---@type string[]
    local list = {}
    for id in string.gmatch(text or "", "[^,]+") do list[#list + 1] = id end
    return list
end

function lib._EncodeSet(set)
    ---@type string[]
    local parts = {}
    for i, entry in ipairs(set) do parts[i] = entry.id .. ":" .. entry.cost end
    return table.concat(parts, ",")
end

function lib._DecodeSet(text)
    ---@type PW.StreakSetEntry[]
    local set = {}
    for part in string.gmatch(text or "", "[^,]+") do
        local id, cost = string.match(part, "^([%w_]+):(%d+)$")
        if id ~= nil then set[#set + 1] = { id = id, cost = tonumber(cost) --[[@as integer]] } end
    end
    return set
end

function lib._KeyAction(button, codes)
    if button == nil or button == KEY_NONE then return nil end
    if codes.use == button then return "use" end
    if codes.next == button then return "next" end
    return nil
end

function lib._DeclareSlots()
    local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    if loadout == nil then return end
    for _, slot in ipairs(lib.Slots) do
        loadout.DeclareSlot(slot, { kind = "streaks", label = "#pw.slot." .. slot })
    end
end

lib._DeclareSlots()

function MODULE:PW_RegistriesLoaded()
    lib._DeclareSlots()
end

if CLIENT then
    function lib.Progress(ply)
        return ply:GetNW2Int(lib.ProgressKey, 0)
    end

    function lib.Inventory(ply)
        return lib._DecodeInventory(ply:GetNW2String(lib.InventoryKey, ""))
    end

    function lib.Set(ply)
        return lib._DecodeSet(ply:GetNW2String(lib.SetKey, ""))
    end
end
